// AgroSoft J&L · Subida de cambios locales al servidor
// -----------------------------------------------------------------------------
// 1) Procesa la cola `sync_eliminados` (lo que se borró en el dispositivo)
//    y lo elimina en Supabase.
// 2) Sube TODAS las tablas configuradas en SyncConfig con registros
//    pendientes (sincronizado = 0), en lotes, con upsert: si ya existe
//    arriba se corrige, si no existe se crea.
// 3) Si una columna local no existe arriba, se detecta y se deja de enviar.
// 4) Si un lote falla, se reintenta registro por registro para que un dato
//    malo no frene al resto (queda pendiente para la próxima).

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import 'conexion.dart';
import 'sync_esquema.dart';

class ResultadoSubida {
  int subidos = 0;
  int eliminadosArriba = 0;
  int errores = 0;
  final List<String> detalleErrores = [];

  int get total => subidos + eliminadosArriba;

  @override
  String toString() =>
      'Subidos: $subidos · Eliminados arriba: $eliminadosArriba · Errores: $errores';
}

class ServicioSubir {
  static const int _tamLote = 200;

  /// Columnas locales que se detectó que no existen en Supabase (por tabla).
  static final Map<String, Set<String>> _columnasFaltantesArriba = {};

  static ResultadoSubida? ultimoResultado;

  /// Compatibilidad con el código existente: devuelve la cantidad procesada.
  static Future<int> subirModificados({void Function(String)? onProgreso}) async {
    final r = await subir(onProgreso: onProgreso);
    return r.total;
  }

  static Future<ResultadoSubida> subir({void Function(String)? onProgreso}) async {
    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;
    final resultado = ResultadoSubida();

    await SyncEsquema.asegurar(db);

    // 1. Eliminaciones primero (así no se borra algo que después se re-sube)
    onProgreso?.call('Eliminando en el servidor…');
    await _procesarEliminaciones(db, client, resultado);

    // 2. Altas y modificaciones, tabla por tabla
    for (final t in SyncConfig.tablas) {
      if (!t.subir) continue;
      try {
        if (!await SyncEsquema.existeTabla(db, t.nombre)) continue;
        final cols = await SyncEsquema.columnas(db, t.nombre);
        if (!cols.contains('sincronizado') || !t.pk.every(cols.contains)) {
          continue;
        }
        onProgreso?.call('Subiendo ${t.nombre}…');
        await _subirTabla(db, client, t, resultado);
      } catch (e) {
        resultado.errores++;
        resultado.detalleErrores.add('${t.nombre}: $e');
        debugPrint('Sync subir ${t.nombre}: $e');
      }
    }

    ultimoResultado = resultado;
    debugPrint('Sync subir → $resultado');
    return resultado;
  }

  // ---------------------------------------------------------------------------
  // ELIMINACIONES
  // ---------------------------------------------------------------------------

  static Future<void> _procesarEliminaciones(
    Database db,
    SupabaseClient client,
    ResultadoSubida resultado,
  ) async {
    List<Map<String, dynamic>> cola = [];
    try {
      cola = await db.query(SyncEsquema.tablaEliminados, orderBy: 'id ASC');
    } catch (_) {
      return;
    }

    for (final e in cola) {
      final int idCola = int.tryParse(e['id']?.toString() ?? '') ?? 0;
      final String tabla = e['tabla']?.toString() ?? '';
      final List<String> columnas = (e['columnas']?.toString() ?? '')
          .split(',')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      final List<String> valores = (e['clave']?.toString() ?? '')
          .split('|')
          .map(SyncConfig.claveValor)
          .toList();

      Future<void> quitarDeCola() => db.delete(SyncEsquema.tablaEliminados,
          where: 'id = ?', whereArgs: [idCola]);

      if (tabla.isEmpty ||
          columnas.isEmpty ||
          columnas.length != valores.length ||
          valores.any((v) => v.isEmpty)) {
        await quitarDeCola();
        continue;
      }

      // Si el registro volvió a existir localmente, no se borra arriba:
      // el upsert lo va a corregir.
      try {
        final existe = await db.query(
          tabla,
          where: columnas.map((c) => '"$c" = ?').join(' AND '),
          whereArgs: valores,
          limit: 1,
        );
        if (existe.isNotEmpty) {
          await quitarDeCola();
          continue;
        }
      } catch (_) {}

      try {
        dynamic q = client.from(tabla).delete();
        for (int i = 0; i < columnas.length; i++) {
          q = q.eq(columnas[i], valores[i]);
        }
        await q;
        await quitarDeCola();
        resultado.eliminadosArriba++;
      } catch (err) {
        resultado.errores++;
        resultado.detalleErrores.add('Eliminar $tabla [${valores.join('|')}]: $err');
        await db.update(
          SyncEsquema.tablaEliminados,
          {
            'intentos': (int.tryParse(e['intentos']?.toString() ?? '0') ?? 0) + 1,
            'ultimo_error': err.toString(),
          },
          where: 'id = ?',
          whereArgs: [idCola],
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ALTAS / MODIFICACIONES
  // ---------------------------------------------------------------------------

  static Future<void> _subirTabla(
    Database db,
    SupabaseClient client,
    TablaSync t,
    ResultadoSubida resultado,
  ) async {
    final pendientes = await db.query(
      t.nombre,
      where: 'sincronizado = 0 OR sincronizado IS NULL',
    );
    if (pendientes.isEmpty) return;

    for (int i = 0; i < pendientes.length; i += _tamLote) {
      final lote = pendientes.sublist(
          i, (i + _tamLote) > pendientes.length ? pendientes.length : i + _tamLote);

      try {
        await _upsert(client, t, lote.map((f) => _payload(t, f)).toList());
        await _marcarSincronizados(db, t, lote);
        resultado.subidos += lote.length;
      } catch (errLote) {
        // El lote falló: se prueba uno por uno para aislar el registro malo.
        for (final fila in lote) {
          try {
            await _upsert(client, t, [_payload(t, fila)]);
            await _marcarSincronizados(db, t, [fila]);
            resultado.subidos++;
          } catch (errFila) {
            resultado.errores++;
            resultado.detalleErrores.add(
                '${t.nombre} [${SyncConfig.claveFila(t, fila)}]: $errFila');
            debugPrint(
                'Sync subir ${t.nombre} [${SyncConfig.claveFila(t, fila)}]: $errFila');
          }
        }
      }
    }
  }

  /// Arma lo que se envía a Supabase (sin columnas locales).
  static Map<String, dynamic> _payload(TablaSync t, Map<String, dynamic> fila) {
    final p = Map<String, dynamic>.from(fila);
    p.remove('sincronizado');
    for (final c in t.excluirAlSubir) {
      p.remove(c);
    }
    t.renombrarAlSubir.forEach((local, remoto) {
      if (p.containsKey(local)) p[remoto] = p.remove(local);
    });
    // Después del renombre: el error de Supabase trae el nombre REMOTO.
    for (final c in _columnasFaltantesArriba[t.nombre] ?? const <String>{}) {
      p.remove(c);
    }
    return p;
  }

  /// Upsert que aprende qué columnas no existen arriba y reintenta sin ellas.
  static Future<void> _upsert(
    SupabaseClient client,
    TablaSync t,
    List<Map<String, dynamic>> filas,
  ) async {
    for (int intento = 0; intento < 10; intento++) {
      try {
        await client.from(t.nombre).upsert(filas, onConflict: t.onConflict);
        return;
      } on PostgrestException catch (e) {
        final m = RegExp(r"Could not find the '([^']+)' column")
            .firstMatch(e.message);
        if (m == null) rethrow;
        final col = m.group(1)!;
        _columnasFaltantesArriba.putIfAbsent(t.nombre, () => <String>{}).add(col);
        debugPrint('Sync: ${t.nombre}.$col no existe en Supabase, se omite');
        for (final f in filas) {
          f.remove(col);
        }
      }
    }
    throw Exception('Demasiadas columnas inexistentes en ${t.nombre}');
  }

  static Future<void> _marcarSincronizados(
    Database db,
    TablaSync t,
    List<Map<String, dynamic>> filas,
  ) async {
    final batch = db.batch();
    for (final f in filas) {
      // Solo se marca si la fila sigue IGUAL a lo que se subió: si el usuario
      // la editó durante la subida, queda pendiente para la próxima.
      final cols = f.keys.where((c) => c != 'sincronizado').toList();
      batch.update(
        t.nombre,
        {'sincronizado': 1},
        where: cols.map((c) => '"$c" IS ?').join(' AND '),
        whereArgs: cols.map((c) => f[c]).toList(),
      );
    }
    await batch.commit(noResult: true);
  }

  /// Marca TODO como pendiente para forzar una subida completa
  /// (corrige en el servidor cualquier diferencia con este dispositivo).
  /// ⚠ Pisa arriba los cambios que otro dispositivo haya hecho sobre los
  /// mismos registros. Usar solo desde el dispositivo "maestro".
  static Future<void> marcarTodoComoPendiente() async {
    final db = await DatabaseHelper.instance.database;
    await SyncEsquema.asegurar(db);
    for (final t in SyncConfig.tablas) {
      if (!t.subir) continue;
      try {
        if (!await SyncEsquema.existeTabla(db, t.nombre)) continue;
        await db.execute('UPDATE "${t.nombre}" SET sincronizado = 0');
      } catch (e) {
        debugPrint('Sync: no se pudo marcar ${t.nombre}: $e');
      }
    }
  }
}
