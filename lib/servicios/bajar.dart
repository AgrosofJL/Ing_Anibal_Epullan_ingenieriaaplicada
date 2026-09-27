import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../base/base.dart';
import 'conexion.dart';
import 'sync_esquema.dart';

class LicenciaInactivaException implements Exception {
  final String mensaje;
  LicenciaInactivaException(this.mensaje);

  @override
  String toString() => mensaje;
}

class ServicioBajar {
  static const int _chunkSize = 1000;

  // 💡 1. Verificación remota de usuario, rol y licencia
  // Retorna true si el rol o contexto del usuario cambió arriba
  static Future<bool> verificarLicencia({BuildContext? context}) async {
    final client = SupabaseService.client;
    final prefs = await SharedPreferences.getInstance();

    final String correoActual = prefs.getString('userEmail') ?? '';
    final String rolActual = (prefs.getString('userRole') ?? 'OPERARIO').toUpperCase().trim();
    final int codProdActual = prefs.getInt('userCodProductor') ?? 0;

    bool licenciaActivaRemota = false;
    String estadoRemoto = 'INACTIVO';
    bool rolModificado = false;

    try {
      dynamic builder = client.from('usuarios').select();
      if (correoActual.isNotEmpty) {
        builder = builder.eq('correo', correoActual);
      }
      final dynamic resLic = await builder.limit(1);

      if (resLic is List && resLic.isNotEmpty) {
        final Map<String, dynamic> licData = Map<String, dynamic>.from(resLic.first as Map);
        estadoRemoto = (licData['estado'] ?? 'INACTIVO').toString().trim().toUpperCase();
        licenciaActivaRemota = estadoRemoto == 'ACTIVO';

        final String nuevoRol = (licData['rol'] ?? 'OPERARIO').toString().toUpperCase().trim();
        final int nuevoCodProd = int.tryParse(licData['cod_productor']?.toString() ?? '0') ?? 0;
        final String nuevoNombre = (licData['operario'] ?? '').toString().trim();

        // Detectar si cambiaron los permisos o el rol arriba
        if (nuevoRol != rolActual || nuevoCodProd != codProdActual) {
          rolModificado = true;
          await prefs.setString('userRole', nuevoRol);
          await prefs.setInt('userCodProductor', nuevoCodProd);
          if (nuevoNombre.isNotEmpty) {
            await prefs.setString('userName', nuevoNombre);
          }
        }

        if (!kIsWeb) {
          final db = await DatabaseHelper.instance.database;
          await db.insert(
            'usuarios',
            licData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } else {
        estadoRemoto = 'INACTIVO';
        licenciaActivaRemota = false;
      }
    } catch (e) {
      debugPrint("Aviso verificando usuario/licencia: $e");
      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          final List<Map<String, dynamic>> licLocal = correoActual.isNotEmpty
              ? await db.query('usuarios', where: 'correo = ?', whereArgs: [correoActual], limit: 1)
              : await db.query('usuarios', limit: 1);

          if (licLocal.isNotEmpty) {
            estadoRemoto = (licLocal.first['estado'] ?? 'INACTIVO').toString().trim().toUpperCase();
            licenciaActivaRemota = estadoRemoto == 'ACTIVO';
          }
        } catch (_) {}
      }
    }

    await prefs.setBool('licencia_activa', licenciaActivaRemota);
    await prefs.setString('licencia_estado', estadoRemoto);

    // Si el usuario quedó INACTIVO, cerramos sesión pero permitimos que la subida ya haya impactado
    if (!licenciaActivaRemota) {
      await prefs.setBool('isLogged', false);
      await prefs.remove('userName');
      await prefs.remove('userRole');

      if (context != null && context.mounted) {
        _mostrarBloqueoLicencia(context);
      }

      throw LicenciaInactivaException(
        "El usuario o licencia se encuentra INACTIVO en el servidor central.",
      );
    }

    return rolModificado;
  }

  static bool _sonValoresIguales(dynamic valorArriba, dynamic valorAbajo) {
    if (valorArriba == null && valorAbajo == null) return true;
    if (valorArriba == null || valorAbajo == null) return false;

    final num? numArriba = num.tryParse(valorArriba.toString().trim());
    final num? numAbajo = num.tryParse(valorAbajo.toString().trim());
    if (numArriba != null && numAbajo != null) {
      return (numArriba - numAbajo).abs() < 0.0001;
    }

    return valorArriba.toString().trim() == valorAbajo.toString().trim();
  }

  // 💡 2. Descarga completa y diferencial de TODAS las tablas (Web y móvil)
  //
  // Reglas:
  //  • Si el registro no existe localmente → se inserta.
  //  • Si existe y es distinto → se reemplaza por el del servidor,
  //    SALVO que tenga cambios locales sin subir (sincronizado = 0).
  //  • Si está en la cola de eliminados → no se vuelve a bajar.
  //  • Reconciliación: si un registro local sincronizado ya no existe en el
  //    servidor (lo borró otro dispositivo), se borra localmente.
  //    Solo se hace si la tabla se descargó completa y sin errores.
  static Future<bool> bajarIncremental({
    BuildContext? context,
    void Function(String)? onProgreso,
  }) async {
    final bool rolCambio = await verificarLicencia(context: context);

    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;

    await SyncEsquema.asegurar(db);

    // Los INSERT OR REPLACE con sincronizado = 1 no disparan los triggers
    // (el borrado implícito del REPLACE no dispara AFTER DELETE con
    // recursive_triggers apagado). La pausa se usa solo en la reconciliación,
    // dentro de una transacción, para no perder cambios del usuario.
    for (final t in SyncConfig.tablas) {
      if (!t.bajar) continue;
      onProgreso?.call('Descargando ${t.nombre}…');
      try {
        await _bajarTabla(db, client, t);
      } catch (e) {
        debugPrint("Aviso al bajar ${t.nombre}: $e");
      }
    }

    return rolCambio;
  }

  static Future<void> _bajarTabla(
    Database db,
    SupabaseClient client,
    TablaSync t,
  ) async {
    final String tabla = t.nombre;
    if (!await SyncEsquema.existeTabla(db, tabla)) return;

    final Set<String> colsLocales = await SyncEsquema.columnas(db, tabla);
    if (!t.pk.every(colsLocales.contains)) return;
    final bool tieneMarca = colsLocales.contains('sincronizado');

    // Estado local completo en memoria (una sola consulta por tabla).
    final List<Map<String, dynamic>> filasLocales = await db.query(tabla);
    final Map<String, Map<String, dynamic>> locales = {
      for (final f in filasLocales) SyncConfig.claveFila(t, f): f,
    };

    final Set<String> clavesRemotas = {};
    bool descargaCompleta = true;
    bool ordenar = true; // orden estable para paginar sin saltear filas
    int from = 0;
    int paginas = 0;

    while (true) {
      List<dynamic> dataRemota = [];
      try {
        dynamic q = client.from(tabla).select();
        if (ordenar) {
          for (final c in t.pk) {
            q = q.order(c, ascending: true);
          }
        }
        final dynamic res = await q.range(from, from + _chunkSize - 1);
        if (res is List) dataRemota = res;
      } catch (e) {
        if (ordenar) {
          // Si no se puede ordenar por la clave, se reintenta sin orden.
          ordenar = false;
          continue;
        }
        debugPrint("Aviso al descargar tabla $tabla: $e");
        descargaCompleta = false;
        break;
      }

      if (dataRemota.isEmpty) break;
      paginas++;

      final List<Map<String, dynamic>> aGrabar = [];
      for (final row in dataRemota) {
        final Map<String, dynamic> filaArriba =
            Map<String, dynamic>.from(row as Map);

        if (tabla == 'catalogo_insumos' &&
            filaArriba.containsKey('principio activo')) {
          filaArriba['principio_activo'] = filaArriba.remove('principio activo');
        }

        // Solo columnas que existen localmente (evita errores de insert).
        filaArriba.removeWhere((k, _) => !colsLocales.contains(k));
        if (t.pk.any((c) => filaArriba[c] == null)) continue;

        final String clave = SyncConfig.claveFila(t, filaArriba);
        clavesRemotas.add(clave);

        final Map<String, dynamic>? filaAbajo = locales[clave];

        bool huboCambio = filaAbajo == null;
        if (!huboCambio) {
          for (final entrada in filaArriba.entries) {
            if (entrada.key == 'sincronizado') continue;
            if (!_sonValoresIguales(entrada.value, filaAbajo[entrada.key])) {
              huboCambio = true;
              break;
            }
          }
        }

        if (huboCambio) {
          if (tieneMarca) filaArriba['sincronizado'] = 1;
          aGrabar.add(filaArriba);
        }
      }

      if (aGrabar.isNotEmpty) {
        // En transacción: las escrituras del usuario esperan, y los pendientes
        // (sincronizado <> 1 o en cola de borrado) se releen justo antes.
        await db.transaction((txn) async {
          final Set<String> protegidas =
              await _clavesProtegidas(txn, t, tieneMarca);
          final Batch batch = txn.batch();
          for (final f in aGrabar) {
            if (protegidas.contains(SyncConfig.claveFila(t, f))) continue;
            batch.insert(tabla, f, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
        });
      }

      // Se avanza por lo recibido y se corta con página vacía: si el servidor
      // limita max_rows por debajo de _chunkSize no se pierden filas.
      from += dataRemota.length;
    }

    // Sin orden estable y con varias páginas no hay garantía de haber
    // recibido todo: en ese caso no se reconcilia.
    if (!ordenar && paginas > 1) descargaCompleta = false;

    // Reconciliación de borrados hechos en el servidor.
    // Protección extra: si arriba no vino nada, no se toca lo local
    // (puede ser un problema de permisos o conexión).
    if (!t.reconciliar || !descargaCompleta || clavesRemotas.isEmpty) return;

    final List<Map<String, dynamic>> aBorrar = [
      for (final e in locales.entries)
        if (!clavesRemotas.contains(e.key)) e.value,
    ];
    if (aBorrar.isEmpty) return;

    int borrados = 0;
    await db.transaction((txn) async {
      final Set<String> protegidas =
          await _clavesProtegidas(txn, t, tieneMarca);
      // Pausa solo dentro de la transacción: no se encolan estos borrados.
      await SyncEsquema.pausar(txn);
      final Batch borrar = txn.batch();
      final where = t.pk.map((c) => '"$c" = ?').join(' AND ');
      for (final f in aBorrar) {
        if (protegidas.contains(SyncConfig.claveFila(t, f))) continue;
        borrar.delete(
          tabla,
          where: tieneMarca ? '$where AND sincronizado = 1' : where,
          whereArgs: t.pk.map((c) => f[c]).toList(),
        );
        borrados++;
      }
      await borrar.commit(noResult: true);
      await SyncEsquema.reanudar(txn);
    });
    if (borrados > 0) {
      debugPrint('Sync: $borrados registros de $tabla ya no existen arriba, borrados localmente');
    }
  }

  /// Claves que la bajada NO debe tocar: filas con cambios locales sin subir
  /// (sincronizado distinto de 1, incluido NULL) y claves en cola de borrado.
  static Future<Set<String>> _clavesProtegidas(
    DatabaseExecutor txn,
    TablaSync t,
    bool tieneMarca,
  ) async {
    final Set<String> r = {};
    if (tieneMarca) {
      final filas = await txn.query(
        t.nombre,
        columns: t.pk,
        where: 'sincronizado IS NOT 1',
      );
      for (final f in filas) {
        r.add(SyncConfig.claveFila(t, f));
      }
    }
    try {
      final cola = await txn.query(
        SyncEsquema.tablaEliminados,
        columns: ['clave'],
        where: 'tabla = ?',
        whereArgs: [t.nombre],
      );
      for (final c in cola) {
        r.add((c['clave']?.toString() ?? '')
            .split('|')
            .map(SyncConfig.claveValor)
            .join('|'));
      }
    } catch (_) {}
    return r;
  }

  static void _mostrarBloqueoLicencia(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: const Color(0xFF1E293B),
            title: const Row(
              children: [
                Icon(Icons.gavel_rounded, color: Color(0xFFEF4444), size: 28),
                SizedBox(width: 10),
                Text(
                  "Acceso Suspendido",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5),
                ),
              ],
            ),
            content: const Text(
              "Tu usuario o establecimiento se encuentra en estado INACTIVO en el servidor central. Se han resguardado los datos pendientes, pero el acceso operativo ha quedado bloqueado.",
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.of(ctx).popUntil((route) => route.isFirst),
                  child: const Text("Cerrar Sesión", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}