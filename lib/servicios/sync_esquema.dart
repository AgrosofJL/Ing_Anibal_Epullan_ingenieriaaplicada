// AgroSoft J&L · Configuración y esquema de sincronización
// -----------------------------------------------------------------------------
// Ubicación: lib/servicios/sync_esquema.dart
//
// • Define en UN solo lugar qué tablas se suben/bajan y cuál es su clave.
// • Crea (de forma idempotente) en la base local:
//     - la columna `sincronizado` donde falte,
//     - la tabla `sync_eliminados` (cola de borrados pendientes de subir),
//     - la tabla `sync_pausa` (apaga los triggers en la reconciliación de bajar),
//     - los triggers:
//         AFTER DELETE → guarda la clave en sync_eliminados
//         AFTER INSERT → si no vino marcado, queda sincronizado = 0
//         AFTER UPDATE → cualquier cambio deja el registro en sincronizado = 0
//
// Llamá a `SyncEsquema.asegurar()` al iniciar la app (después de abrir la base)
// y la sincronización la vuelve a llamar por las dudas (es barato).

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';

class TablaSync {
  final String nombre;

  /// Columnas de la clave primaria (también se usan como onConflict arriba).
  final List<String> pk;

  /// Si los cambios locales se suben al servidor.
  final bool subir;

  /// Si se descarga desde el servidor.
  final bool bajar;

  /// Si se borran localmente los registros que ya no existen arriba.
  final bool reconciliar;

  /// Columnas locales que NO existen arriba y no se deben enviar.
  final List<String> excluirAlSubir;

  /// Renombres de columnas local → remoto al subir.
  final Map<String, String> renombrarAlSubir;

  const TablaSync(
    this.nombre,
    this.pk, {
    this.subir = true,
    this.bajar = true,
    this.reconciliar = true,
    this.excluirAlSubir = const [],
    this.renombrarAlSubir = const {},
  });

  String get onConflict => pk.join(',');
}

class SyncConfig {
  /// Orden pensado para respetar dependencias (maestros → movimientos).
  static const List<TablaSync> tablas = [
    // Solo bajada
    TablaSync('usuarios', ['id'], subir: false, reconciliar: false),
    TablaSync('config_app_enlaces', ['id'], subir: false),

    // Maestros
    TablaSync('rubros_insumos', ['codigo']),
    TablaSync('productores', ['cod_productor']),
    TablaSync('motivos_aplicaciones', ['cod']),
    TablaSync('inventario_plantacion', ['id']),
    TablaSync('cuadros', ['cod_cuadro']),
    TablaSync(
      'catalogo_insumos',
      ['ID_Insumos'],
      renombrarAlSubir: {'principio_activo': 'principio activo'},
    ),
    TablaSync('fenologia_parametros', ['id']),

    // Órdenes y movimientos
    TablaSync('ordenes_aplicaciones', ['cod_orden']),
    TablaSync('recetas_aplicaciones', ['cod_receta'],
        excluirAlSubir: ['actualizado_el']),
    TablaSync('parametros_aplic', ['id']),
    TablaSync('lecturas_fenologia', ['id', 'id_reg']),
    TablaSync('lecturas_trampas', ['id', 'id_reg']),
    TablaSync('aplicaciones_registros', ['registro']),
    TablaSync('insumos_detalles', ['cod_mov']),

    // Presupuestos (cabecera antes que renglones)
    TablaSync('presupuestos', ['cod_presupuesto']),
    TablaSync('presupuestos_items', ['cod_item']),
  ];

  static TablaSync? porNombre(String nombre) {
    for (final t in tablas) {
      if (t.nombre == nombre) return t;
    }
    return null;
  }

  /// Normaliza un valor de clave a texto (5.0 → "5") para que coincida
  /// entre SQLite, Supabase y la cola de eliminados.
  static String claveValor(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      if (v is double && !v.isFinite) return v.toString();
      return v == v.truncate() ? v.truncate().toString() : v.toString();
    }
    final s = v.toString().trim();
    final d = double.tryParse(s);
    if (d != null && d == d.truncate() && s.contains('.')) {
      return d.truncate().toString();
    }
    return s;
  }

  /// Clave compuesta "v1|v2" de una fila.
  static String claveFila(TablaSync t, Map<String, dynamic> fila) =>
      t.pk.map((c) => claveValor(fila[c])).join('|');
}

class SyncEsquema {
  static const String tablaEliminados = 'sync_eliminados';
  static const String tablaPausa = 'sync_pausa';
  static const String _versionTriggers = 'v2';

  static Future<bool> existeTabla(Database db, String tabla) async {
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tabla],
    );
    return r.isNotEmpty;
  }

  static Future<Set<String>> columnas(Database db, String tabla) async {
    final r = await db.rawQuery('PRAGMA table_info("$tabla")');
    return r.map((e) => e['name'].toString()).toSet();
  }

  /// Crea tablas auxiliares, columna `sincronizado` y triggers. Idempotente.
  static Future<void> asegurar([Database? dbParam]) async {
    final db = dbParam ?? await DatabaseHelper.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablaEliminados (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tabla TEXT NOT NULL,
        columnas TEXT NOT NULL,
        clave TEXT NOT NULL,
        eliminado_el TEXT DEFAULT (datetime('now')),
        intentos INTEGER DEFAULT 0,
        ultimo_error TEXT
      )
    ''');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS $tablaPausa (id INTEGER PRIMARY KEY)');
    // Si la app se cerró en medio de una bajada, reactivamos los triggers.
    await db.delete(tablaPausa);

    for (final t in SyncConfig.tablas) {
      if (!t.subir) continue;
      try {
        if (!await existeTabla(db, t.nombre)) continue;
        final cols = await columnas(db, t.nombre);
        if (!t.pk.every(cols.contains)) {
          debugPrint('Sync: ${t.nombre} no tiene la clave ${t.pk}, se omite');
          continue;
        }

        if (!cols.contains('sincronizado')) {
          await db.execute(
              'ALTER TABLE "${t.nombre}" ADD COLUMN sincronizado INTEGER');
          // Lo que ya estaba se considera sincronizado.
          await db.execute(
              'UPDATE "${t.nombre}" SET sincronizado = 1 WHERE sincronizado IS NULL');
        }

        await _crearTriggers(db, t);
      } catch (e) {
        debugPrint('Sync: no se pudo preparar ${t.nombre}: $e');
      }
    }
  }

  static Future<void> _crearTriggers(Database db, TablaSync t) async {
    final String tb = t.nombre;
    final String v = _versionTriggers;
    const String sinPausa = 'NOT EXISTS (SELECT 1 FROM $tablaPausa)';

    String clave(String alias) => t.pk
        .map((c) => 'CAST($alias."$c" AS TEXT)')
        .join(" || '|' || ");
    String pkNoNula(String alias) =>
        t.pk.map((c) => '$alias."$c" IS NOT NULL').join(' AND ');

    // Versiones anteriores de los triggers (si quedaron de pruebas).
    for (final n in ['del', 'reins', 'ins', 'upd']) {
      await db.execute('DROP TRIGGER IF EXISTS trg_sync_${n}_v1_$tb');
    }

    // 1) Borrado local → cola para borrar arriba.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_del_${v}_$tb
      AFTER DELETE ON "$tb"
      FOR EACH ROW WHEN ${pkNoNula('OLD')} AND $sinPausa
      BEGIN
        INSERT INTO $tablaEliminados (tabla, columnas, clave)
        VALUES ('$tb', '${t.pk.join(',')}', ${clave('OLD')});
      END
    ''');

    // 2) Si se vuelve a crear un registro con la misma clave (ej. editar una
    //    orden borra y reinserta), se cancela su borrado pendiente.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_reins_${v}_$tb
      AFTER INSERT ON "$tb"
      FOR EACH ROW WHEN ${pkNoNula('NEW')}
      BEGIN
        DELETE FROM $tablaEliminados
        WHERE tabla = '$tb' AND clave = ${clave('NEW')};
      END
    ''');

    // 3) Insert sin marca de sincronización → pendiente de subir.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_ins_${v}_$tb
      AFTER INSERT ON "$tb"
      FOR EACH ROW WHEN NEW.sincronizado IS NULL AND $sinPausa
      BEGIN
        UPDATE "$tb" SET sincronizado = 0 WHERE rowid = NEW.rowid;
      END
    ''');

    // 4) Cualquier modificación que no toque la marca → pendiente de subir.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_sync_upd_${v}_$tb
      AFTER UPDATE ON "$tb"
      FOR EACH ROW WHEN NEW.sincronizado IS OLD.sincronizado
        AND NEW.sincronizado IS NOT 0 AND $sinPausa
      BEGIN
        UPDATE "$tb" SET sincronizado = 0 WHERE rowid = NEW.rowid;
      END
    ''');
  }

  /// Apaga los triggers. Usar SOLO dentro de una transacción (así las
  /// escrituras del usuario esperan y no quedan sin registrar).
  static Future<void> pausar(DatabaseExecutor db) =>
      db.insert(tablaPausa, {'id': 1},
          conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<void> reanudar(DatabaseExecutor db) => db.delete(tablaPausa);

  /// Registros pendientes de subir (modificados + eliminados).
  static Future<int> contarPendientes([Database? dbParam]) async {
    final db = dbParam ?? await DatabaseHelper.instance.database;
    int total = 0;
    for (final t in SyncConfig.tablas) {
      if (!t.subir) continue;
      try {
        if (!await existeTabla(db, t.nombre)) continue;
        if (!(await columnas(db, t.nombre)).contains('sincronizado')) continue;
        final r = await db.rawQuery(
            'SELECT COUNT(*) AS n FROM "${t.nombre}" WHERE sincronizado = 0 OR sincronizado IS NULL');
        total += int.tryParse(r.first['n']?.toString() ?? '0') ?? 0;
      } catch (_) {}
    }
    try {
      final r =
          await db.rawQuery('SELECT COUNT(*) AS n FROM $tablaEliminados');
      total += int.tryParse(r.first['n']?.toString() ?? '0') ?? 0;
    } catch (_) {}
    return total;
  }
}
