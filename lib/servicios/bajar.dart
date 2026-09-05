import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../base/base.dart';
import '../main.dart'; // O donde tengas la ruta de LoginScreen o BloqueoScreen
import 'conexion.dart';
import '../loguer.dart';

// Excepción personalizada para atrapar el estado de corte
class LicenciaInactivaException implements Exception {
  final String mensaje;
  LicenciaInactivaException(this.mensaje);

  @override
  String toString() => mensaje;
}

class ServicioBajar {
  static const int _chunkSize = 1000;

  static Future<void> bajarIncremental({BuildContext? context}) async {
    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();

    // ========================================================================
    // 💡 1. CONTROL PREVIO Y DESCARGA DE LA TABLA LICENCIA DESDE SUPABASE
    // ========================================================================
    bool licenciaActivaRemota = false;
    String estadoRemoto = 'INACTIVO';

    try {
      // Consultamos directamente la tabla licencias en Supabase
      final List<dynamic> resLic = await client
          .from('usuarios')
          .select()
          .limit(1);

      if (resLic.isNotEmpty) {
        final Map<String, dynamic> licData = Map<String, dynamic>.from(resLic.first);
        estadoRemoto = (licData['estado'] ?? 'INACTIVO').toString().trim().toUpperCase();
        licenciaActivaRemota = estadoRemoto == 'ACTIVO';

        // Actualizamos o guardamos en SQLite local
        await db.insert(
          'usuarios',
          licData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        // Si no hay fila en la tabla remota, se considera inactiva por seguridad
        estadoRemoto = 'INACTIVO';
        licenciaActivaRemota = false;
      }
    } catch (e) {
      debugPrint("Error verificando licencia remota: $e");
      // Respaldo: si falla la consulta remota, verificamos la copia local de SQLite
      try {
        final List<Map<String, dynamic>> licLocal = await db.query('usuarios', limit: 1);
        if (licLocal.isNotEmpty) {
          estadoRemoto = (licLocal.first['estado'] ?? 'INACTIVO').toString().trim().toUpperCase();
          licenciaActivaRemota = estadoRemoto == 'ACTIVO';
        }
      } catch (_) {}
    }

    // Guardamos la bandera de acceso en preferencias locales
    await prefs.setBool('licencia_activa', licenciaActivaRemota);
    await prefs.setString('licencia_estado', estadoRemoto);

    // ========================================================================
    // 💡 2. SINCRONIZACIÓN DE TABLAS OPERATIVAS
    // ========================================================================
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
      {'nombre': 'lecturas_fenologia', 'pk': 'id'},
      {'nombre': 'lecturas_trampas', 'pk': 'id'},
    ];

    for (final t in tablas) {
      final String tabla = t['nombre']!;

      int from = 0;
      bool hayMas = true;

      while (hayMas) {
        final List<dynamic> data = await client
            .from(tabla)
            .select()
            .range(from, from + _chunkSize - 1);

        if (data.isEmpty) {
          hayMas = false;
          break;
        }

        Batch batch = db.batch();
        for (var row in data) {
          final Map<String, dynamic> item = Map<String, dynamic>.from(row);

          if (tabla == 'catalogo_insumos') {
            if (item.containsKey('principio activo')) {
              item['principio_activo'] = item['principio activo'];
              item.remove('principio activo');
            }
          }

          if (tabla == 'recetas_aplicaciones') {
            item['sincronizado'] = 1;
          }

          batch.insert(
            tabla,
            item,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);

        if (data.length < _chunkSize) {
          hayMas = false;
        } else {
          from += _chunkSize;
        }
      }
    }

    // ========================================================================
    // 💡 3. BLOQUEO INMEDIATO SI NO ESTÁ ACTIVO TRAS SINCRONIZAR
    // ========================================================================
    if (!licenciaActivaRemota) {
      // Inactivamos en SQLite local
      try {
        await db.rawUpdate("UPDATE licencias SET estado = 'INACTIVO'");
      } catch (_) {}

      // Limpiamos la sesión del usuario para forzar salida segura
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
  }

  // 💡 Pantalla/Dialog de Bloqueo Infranqueable
  static void _mostrarBloqueoLicencia(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return WillPopScope(
          onWillPop: () async => false, // Evita salir con botón atrás de Android
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: const Color(0xFF1E293B),
            title: Row(
              children: const [
                Icon(Icons.gavel_rounded, color: Color(0xFFEF4444), size: 28),
                SizedBox(width: 10),
                Text(
                  "Licencia Suspendida",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16.5,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "El estado de la licencia de AgroSoft J&L no se encuentra ACTIVO en el servidor central.",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
                ),
                SizedBox(height: 12),
                Text(
                  "Los datos locales se han actualizado correctamente pero el acceso operativo ha quedado bloqueado. Comuníquese con el soporte técnico o administración para su reactivación.",
                  style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, height: 1.4),
                ),
              ],
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
                  onPressed: () {
                    Navigator.of(ctx).popUntil((route) => route.isFirst);
                  },
                  child: const Text(
                    "Cerrar Sesión",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}