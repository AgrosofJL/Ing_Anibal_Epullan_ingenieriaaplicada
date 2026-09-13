import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';
import 'conexion.dart';

class LicenciaInactivaException implements Exception {
  final String mensaje;
  LicenciaInactivaException(this.mensaje);

  @override
  String toString() => mensaje;
}

class ServicioBajar {
  static const int _chunkSize = 1000;

  // 💡 1. Verificación remota de licencia
  static Future<bool> verificarLicencia({BuildContext? context}) async {
    final client = SupabaseService.client;
    final prefs = await SharedPreferences.getInstance();

    bool licenciaActivaRemota = false;
    String estadoRemoto = 'INACTIVO';

    try {
      final dynamic resLic = await client
          .from('usuarios')
          .select()
          .limit(1);

      if (resLic is List && resLic.isNotEmpty) {
        final Map<String, dynamic> licData = Map<String, dynamic>.from(resLic.first as Map);
        estadoRemoto = (licData['estado'] ?? 'INACTIVO').toString().trim().toUpperCase();
        licenciaActivaRemota = estadoRemoto == 'ACTIVO';

        if (!kIsWeb) {
          final db = await DatabaseHelper.instance.database;
          await db.insert(
            'usuarios',
            licData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } catch (e) {
      debugPrint("Aviso verificando licencia remota: $e");
      if (!kIsWeb) {
        try {
          final db = await DatabaseHelper.instance.database;
          final List<Map<String, dynamic>> licLocal = await db.query('usuarios', limit: 1);
          if (licLocal.isNotEmpty) {
            estadoRemoto = (licLocal.first['estado'] ?? 'INACTIVO').toString().trim().toUpperCase();
            licenciaActivaRemota = estadoRemoto == 'ACTIVO';
          }
        } catch (_) {}
      }
    }

    await prefs.setBool('licencia_activa', licenciaActivaRemota);
    await prefs.setString('licencia_estado', estadoRemoto);

    if (!licenciaActivaRemota) {
      await prefs.setBool('isLogged', false);
      await prefs.remove('userName');
      await prefs.remove('userRole');

      if (context != null && context.mounted) {
        _mostrarBloqueoLicencia(context);
      }

      throw LicenciaInactivaException(
        "Sincronización finalizada. Licencia INACTIVA: el sistema ha sido bloqueado.",
      );
    }

    return licenciaActivaRemota;
  }

  // 💡 2. Comparador de igualdad entre valor de arriba (remoto) y valor de abajo (local)
  static bool _sonValoresIguales(dynamic valorArriba, dynamic valorAbajo) {
    if (valorArriba == null && valorAbajo == null) return true;
    if (valorArriba == null || valorAbajo == null) return false;

    // Si ambos son numéricos o texto numérico
    final num? numArriba = num.tryParse(valorArriba.toString().trim());
    final num? numAbajo = num.tryParse(valorAbajo.toString().trim());
    if (numArriba != null && numAbajo != null) {
      return (numArriba - numAbajo).abs() < 0.0001;
    }

    return valorArriba.toString().trim() == valorAbajo.toString().trim();
  }

  // 💡 3. Descarga con verificación diferencial fila por fila
  static Future<void> bajarIncremental({BuildContext? context}) async {
    await verificarLicencia(context: context);

    if (kIsWeb) return;

    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;

    final tablas = [
      {'nombre': 'usuarios', 'pk': 'id'},
      {'nombre': 'rubros_insumos', 'pk': 'codigo'},
      {'nombre': 'productores', 'pk': 'cod_productor'},
      {'nombre': 'motivos_aplicaciones', 'pk': 'cod'},
      {'nombre': 'inventario_plantacion', 'pk': 'id'},
      {'nombre': 'cuadros', 'pk': 'cod_cuadro'},
      {'nombre': 'catalogo_insumos', 'pk': 'ID_Insumos'},
      {'nombre': 'recetas_aplicaciones', 'pk': 'cod_receta'},
      {'nombre': 'fenologia_parametros', 'pk': 'id'},
      {'nombre': 'lecturas_fenologia', 'pk': 'id,id_reg'},
      {'nombre': 'lecturas_trampas', 'pk': 'id,id_reg'},
      {'nombre': 'parametros_aplic', 'pk': 'id'},
      {'nombre': 'config_app_enlaces', 'pk': 'id'},
      {'nombre': 'insumos_detalles', 'pk': 'cod_mov'},
    ];

    for (final t in tablas) {
      final String tabla = t['nombre']!;
      final String pkConfig = t['pk']!;
      final List<String> columnasPk = pkConfig.split(',').map((e) => e.trim()).toList();

      int from = 0;
      bool hayMas = true;

      while (hayMas) {
        List<dynamic> dataRemota = [];
        try {
          final dynamic res = await client
              .from(tabla)
              .select()
              .range(from, from + _chunkSize - 1);

          if (res is List) {
            dataRemota = res;
          }
        } catch (e) {
          debugPrint("Aviso al descargar tabla $tabla: $e");
          hayMas = false;
          break;
        }

        if (dataRemota.isEmpty) {
          hayMas = false;
          break;
        }

        Batch batch = db.batch();
        int insercionesEnLote = 0;

        for (var row in dataRemota) {
          final Map<String, dynamic> filaArriba = Map<String, dynamic>.from(row as Map);

          if (tabla == 'catalogo_insumos') {
            if (filaArriba.containsKey('principio activo')) {
              filaArriba['principio_activo'] = filaArriba['principio activo'];
              filaArriba.remove('principio activo');
            }
          }

          if (tabla == 'recetas_aplicaciones') {
            filaArriba['sincronizado'] = 1;
          }

          // Construcción de la consulta del registro local correspondiente
          String whereClause = '';
          List<dynamic> whereArgs = [];

          if (columnasPk.length == 1) {
            final col = columnasPk.first;
            whereClause = '$col = ?';
            whereArgs = [filaArriba[col]];
          } else {
            whereClause = columnasPk.map((col) => '$col = ?').join(' AND ');
            whereArgs = columnasPk.map((col) => filaArriba[col]).toList();
          }

          // Consultar el estado del registro abajo en SQLite
          final List<Map<String, dynamic>> registrosAbajo = await db.query(
            tabla,
            where: whereClause,
            whereArgs: whereArgs,
            limit: 1,
          );

          bool huboCambio = false;

          if (registrosAbajo.isEmpty) {
            // El registro no existe abajo: es nuevo y debe insertarse
            huboCambio = true;
          } else {
            final Map<String, dynamic> filaAbajo = registrosAbajo.first;

            // Comparar cada columna remota contra la local
            for (final entrada in filaArriba.entries) {
              final String col = entrada.key;
              final dynamic valArriba = entrada.value;

              // Ignorar columnas de control local si existieran
              if (col == 'sincronizado') continue;

              if (filaAbajo.containsKey(col)) {
                final dynamic valAbajo = filaAbajo[col];
                if (!_sonValoresIguales(valArriba, valAbajo)) {
                  huboCambio = true;
                  break;
                }
              } else {
                // Columna nueva agregada arriba
                huboCambio = true;
                break;
              }
            }
          }

          // Si arriba es distinto a abajo, se aplica la actualización
          if (huboCambio) {
            batch.insert(
              tabla,
              filaArriba,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            insercionesEnLote++;
          }
        }

        if (insercionesEnLote > 0) {
          await batch.commit(noResult: true);
        }

        if (dataRemota.length < _chunkSize) {
          hayMas = false;
        } else {
          from += _chunkSize;
        }
      }
    }
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
                  "Licencia Suspendida",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5),
                ),
              ],
            ),
            content: const Text(
              "El estado de la licencia de AgroSoft J&L no se encuentra ACTIVO en el servidor central. Comuníquese con soporte técnico o administración.",
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