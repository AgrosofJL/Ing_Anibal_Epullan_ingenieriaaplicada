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

  static Future<void> bajarIncremental({BuildContext? context}) async {
    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();

    final String correoLogueado = (prefs.getString('userCorreo') ?? '').trim().toLowerCase();
    final int idUsuarioLogueado = prefs.getInt('userId') ?? 0;

    bool accesoPermitido = true;
    String motivoCorte = '';

    // ========================================================================
    // 💡 1. TABLAS A SINCRONIZAR (INCLUYE ENLACES Y ESTRUCTURA AGRONÓMICA)
    // ========================================================================
    final tablas = [
      {'nombre': 'config_app_enlaces', 'pk': 'id'},
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
        List<dynamic> data = [];
        try {
          data = await client
              .from(tabla)
              .select()
              .range(from, from + _chunkSize - 1);
        } catch (e) {
          debugPrint("Aviso al bajar tabla $tabla: $e");
          hayMas = false;
          break;
        }

        if (data.isEmpty) {
          hayMas = false;
          break;
        }

        Batch batch = db.batch();
        for (var row in data) {
          final Map<String, dynamic> item = Map<String, dynamic>.from(row);

          // Homogeneización de campos con nombres compuestos
          if (tabla == 'catalogo_insumos') {
            if (item.containsKey('principio activo')) {
              item['principio_activo'] = item['principio activo'];
              item.remove('principio activo');
            }
          }

          if (tabla == 'recetas_aplicaciones') {
            item['sincronizado'] = 1;
          }

          // 💡 ACA ES LO NUEVO: Si el Ingeniero modificó al usuario actual en la nube,
          // actualizamos sus datos en tiempo real en SharedPreferences
          if (tabla == 'usuarios') {
            final String correoFila = (item['correo'] ?? '').toString().trim().toLowerCase();
            final int idFila = int.tryParse(item['id']?.toString() ?? '0') ?? 0;

            final bool esUsuarioActual = (idUsuarioLogueado > 0 && idFila == idUsuarioLogueado) ||
                (correoLogueado.isNotEmpty && correoFila == correoLogueado);

            if (esUsuarioActual) {
              final String estadoUsuario = (item['estado'] ?? 'ACTIVO').toString().trim().toUpperCase();
              final String rolUsuario = (item['rol'] ?? 'OPERARIO').toString().trim().toUpperCase();
              final String operarioNombre = (item['operario'] ?? '').toString();
              final String deviceGuardado = (item['device'] ?? '').toString();
              final int codProd = int.tryParse(item['cod_productor']?.toString() ?? '0') ?? 0;

              // Actualizamos sesión local
              await prefs.setString('userRole', rolUsuario);
              await prefs.setString('userName', operarioNombre);
              await prefs.setString('userDevice', deviceGuardado);
              await prefs.setInt('userCodProductor', codProd);

              if (estadoUsuario != 'ACTIVO') {
                accesoPermitido = false;
                motivoCorte = 'Su usuario ha sido dado de baja o suspendido por el Ingeniero administrador.';
              }
            }
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
    // 💡 2. VERIFICACIÓN DE ESTADO DEL PRODUCTOR VINCULADO
    // ========================================================================
    final int codProductorActual = prefs.getInt('userCodProductor') ?? 0;
    if (codProductorActual > 0) {
      try {
        final resProd = await db.query(
          'productores',
          where: 'cod_productor = ?',
          whereArgs: [codProductorActual],
          limit: 1,
        );
        if (resProd.isNotEmpty) {
          final String estadoProd = (resProd.first['estado'] ?? 'ACTIVO').toString().toUpperCase();
          if (estadoProd != 'ACTIVO') {
            accesoPermitido = false;
            motivoCorte = 'El establecimiento productor asociado a esta cuenta se encuentra INACTIVO.';
          }
        }
      } catch (_) {}
    }

    await prefs.setBool('licencia_activa', accesoPermitido);
    await prefs.setString('licencia_estado', accesoPermitido ? 'ACTIVO' : 'INACTIVO');

    // ========================================================================
    // 💡 3. BLOQUEO INMEDIATO ANTE USUARIO O LICENCIA INACTIVA
    // ========================================================================
    if (!accesoPermitido) {
      await prefs.setBool('isLogged', false);
      await prefs.remove('userName');
      await prefs.remove('userRole');

      if (context != null && context.mounted) {
        _mostrarBloqueoLicencia(context, motivoCorte);
      }

      throw LicenciaInactivaException(
        "Acceso no autorizado: $motivoCorte",
      );
    }
  }

  static void _mostrarBloqueoLicencia(BuildContext context, String detalle) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: const Color(0xFF1E293B),
            title: Row(
              children: const [
                Icon(Icons.lock_person_rounded, color: Color(0xFFEF4444), size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Acceso Restringido",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detalle.isNotEmpty
                      ? detalle
                      : "El estado de su usuario o licencia ha cambiado a INACTIVO en el servidor central.",
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Comuníquese con el Ingeniero administrador de AgroSoft J&L para habilitar nuevamente sus permisos de acceso.",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
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
                    "Entendido, Salir",
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