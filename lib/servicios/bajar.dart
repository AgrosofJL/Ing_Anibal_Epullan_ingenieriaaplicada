import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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

  // 💡 2. Descarga diferencial verificando diferencias con lo de arriba
  // 💡 Descarga diferencial para TODAS las plataformas (incluyendo Web con SQLite local)
  static Future<bool> bajarIncremental({BuildContext? context}) async {
    final bool rolCambio = await verificarLicencia(context: context);

    // ❌ ELIMINADO: if (kIsWeb) return rolCambio; -> Ahora la Web sí baja los datos a IndexedDB

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
      // 💡 ACA ES LO NUEVO
      {'nombre': 'ordenes_aplicaciones', 'pk': 'cod_orden'},
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

          final List<Map<String, dynamic>> registrosAbajo = await db.query(
            tabla,
            where: whereClause,
            whereArgs: whereArgs,
            limit: 1,
          );

          bool huboCambio = false;

          if (registrosAbajo.isEmpty) {
            huboCambio = true; // Si no existe localmente, se inserta sí o sí
          } else {
            final Map<String, dynamic> filaAbajo = registrosAbajo.first;

            for (final entrada in filaArriba.entries) {
              final String col = entrada.key;
              final dynamic valArriba = entrada.value;

              if (col == 'sincronizado') continue;

              if (filaAbajo.containsKey(col)) {
                final dynamic valAbajo = filaAbajo[col];
                if (!_sonValoresIguales(valArriba, valAbajo)) {
                  huboCambio = true;
                  break;
                }
              } else {
                huboCambio = true;
                break;
              }
            }
          }

          // 💡 Si hay cambios O si la tabla local estaba completamente vacía, guardamos en lote
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

    return rolCambio;
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