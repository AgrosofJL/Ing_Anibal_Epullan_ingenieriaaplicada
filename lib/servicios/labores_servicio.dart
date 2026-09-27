// AgroSoft J&L · Edición y borrado de labores registradas
// -----------------------------------------------------------------------------
// Ubicación: lib/servicios/labores_servicio.dart
//
// Una "labor" (tirada) son varias filas de aplicaciones_registros (una por
// cuadro/variedad × producto). Cada fila tiene su consumo en insumos_detalles
// (reg_aplic = registro).
//
//  • eliminar(registros)  → borra las filas y sus consumos (vuelve el stock).
//  • actualizar(...)      → cambia fecha / tractorista / máquina / caldo L/Ha
//                           y RECALCULA litros y consumo de cada fila, y el
//                           movimiento de stock correspondiente.
//
// Local: en una transacción. Los triggers de sync dejan todo pendiente
// (borrados en sync_eliminados, cambios con sincronizado = 0) y además se
// intenta aplicar en Supabase en el momento si hay conexión.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import '../aplicaciones/calculo_dosis.dart';
import '../base/base.dart';
import 'conexion.dart';
import 'sync_esquema.dart';

class ServicioLabores {
  static double _n(dynamic v) =>
      double.tryParse('${v ?? ''}'.replaceAll(',', '.').trim()) ?? 0.0;

  static String _ph(int n) => List.filled(n, '?').join(', ');

  /// Borra las filas de labor indicadas y sus consumos de stock.
  /// Devuelve cuánto producto volvió al stock (suma de cantidades).
  static Future<double> eliminar(List<String> registros) async {
    if (registros.isEmpty) return 0.0;
    final db = await DatabaseHelper.instance.database;
    try {
      await SyncEsquema.asegurar(db);
    } catch (_) {}

    double devuelto = 0.0;
    await db.transaction((txn) async {
      for (int i = 0; i < registros.length; i += 400) {
        final lote = registros.sublist(
            i, i + 400 > registros.length ? registros.length : i + 400);
        final r = await txn.rawQuery(
          "SELECT SUM(ABS(cantidad)) AS t FROM insumos_detalles "
          "WHERE UPPER(movimiento) = 'CONSUMO' AND reg_aplic IN (${_ph(lote.length)})",
          lote,
        );
        devuelto += _n(r.first['t']);
        await txn.delete(
          'insumos_detalles',
          where:
              "UPPER(movimiento) = 'CONSUMO' AND reg_aplic IN (${_ph(lote.length)})",
          whereArgs: lote,
        );
        await txn.delete(
          'aplicaciones_registros',
          where: 'registro IN (${_ph(lote.length)})',
          whereArgs: lote,
        );
      }
    });

    // Servidor (si falla, queda en la cola de sincronización)
    try {
      final client = SupabaseService.client;
      for (int i = 0; i < registros.length; i += 200) {
        final lote = registros.sublist(
            i, i + 200 > registros.length ? registros.length : i + 200);
        await client
            .from('insumos_detalles')
            .delete()
            .eq('movimiento', 'CONSUMO')
            .inFilter('reg_aplic', lote);
        await client
            .from('aplicaciones_registros')
            .delete()
            .inFilter('registro', lote);
      }
    } catch (e) {
      debugPrint('Labores: se eliminarán arriba al sincronizar ($e)');
    }
    return devuelto;
  }

  /// Actualiza los datos de una labor y recalcula consumos con el nuevo caldo.
  /// [recetaPorProducto]: filas de recetas_aplicaciones de la orden, para saber
  /// si cada producto es por 100 L o por Ha y su dosis.
  static Future<void> actualizar({
    required List<Map<String, dynamic>> filas,
    required String fecha,
    required String tractorista,
    required String maquina,
    required double caldoHa,
    required List<Map<String, dynamic>> itemsReceta,
  }) async {
    if (filas.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    try {
      await SyncEsquema.asegurar(db);
    } catch (_) {}

    Map<String, dynamic>? recetaDe(Map<String, dynamic> f) {
      final cp = '${f['cod_producto'] ?? ''}';
      final cr = '${f['cod_receta'] ?? ''}';
      for (final it in itemsReceta) {
        if (cr.isNotEmpty && '${it['cod_receta'] ?? ''}' == cr) return it;
      }
      for (final it in itemsReceta) {
        if (cp.isNotEmpty && '${it['cod_producto'] ?? ''}' == cp) return it;
      }
      final pf = '${f['producto'] ?? ''}'.trim().toUpperCase();
      for (final it in itemsReceta) {
        if (pf.isNotEmpty &&
            '${it['producto'] ?? ''}'.trim().toUpperCase() == pf) {
          return it;
        }
      }
      return null;
    }

    final List<Map<String, dynamic>> filasRemotas = [];

    // Producto por producto: total de la tanda (litros = caldoHa × Sup) y
    // reparto de ese total entre sus filas según las Ha de cada una.
    final Map<String, List<Map<String, dynamic>>> porProducto = {};
    final Map<String, Map<String, dynamic>> recetaPorClave = {};
    for (final f in filas) {
      final receta = recetaDe(f) ??
          {
            'dosis_x': 'vol_100',
            'dosis_100': f['dosis_100'],
            'dosis_maq': f['dosis_maq'],
          };
      final clave = '${f['cod_receta'] ?? ''}|${f['cod_producto'] ?? ''}|${f['producto'] ?? ''}';
      porProducto.putIfAbsent(clave, () => []).add(f);
      recetaPorClave[clave] = receta;
    }
    final Map<String, double> consumoPorRegistro = {};
    porProducto.forEach((clave, lista) {
      final has = lista.map((f) => _n(f['sup_aplic'])).toList();
      final double sup = has.fold(0.0, (a, b) => a + b);
      final double total = CalculoDosis.totalProductoTanda(
          recetaPorClave[clave]!, sup, caldoHa * sup);
      final reparto = CalculoDosis.repartirPorHa(total, has);
      for (int i = 0; i < lista.length; i++) {
        consumoPorRegistro['${lista[i]['registro']}'] = reparto[i];
      }
    });

    await db.transaction((txn) async {
      for (final f in filas) {
        final String registro = '${f['registro']}';
        final double sup = _n(f['sup_aplic']);
        final receta = recetaDe(f) ??
            {
              'dosis_x': 'vol_100',
              'dosis_100': f['dosis_100'],
              'dosis_maq': f['dosis_maq'],
            };
        final double dosisMaq = CalculoDosis.dosisMaquina(receta, caldoHa);
        final double consumo = consumoPorRegistro[registro] ?? 0.0;

        final cambios = {
          'fecha': fecha,
          'tractorista': tractorista,
          'pulverizadora': maquina,
          'vol_aplic_ha': caldoHa,
          'litros': sup * caldoHa,
          'dosis_maq': dosisMaq,
          'consumo_prod': consumo,
          'sincronizado': 0,
        };
        await txn.update('aplicaciones_registros', cambios,
            where: 'registro = ?', whereArgs: [registro]);
        filasRemotas.add({...f, ...cambios}..remove('sincronizado'));

        final cons = {
          'cantidad': -consumo,
          'fecha_ingreso': fecha,
          'sincronizado': 0,
        };
        await txn.update('insumos_detalles', cons,
            where: "reg_aplic = ? AND UPPER(movimiento) = 'CONSUMO'",
            whereArgs: [registro]);
      }
    });

    // Servidor (si falla, queda pendiente con sincronizado = 0)
    try {
      final client = SupabaseService.client;
      for (final f in filasRemotas) {
        await client
            .from('aplicaciones_registros')
            .upsert(f, onConflict: 'registro');
      }
      final regs = filasRemotas.map((f) => '${f['registro']}').toList();
      for (int i = 0; i < regs.length; i += 400) {
        final lote =
            regs.sublist(i, i + 400 > regs.length ? regs.length : i + 400);
        if (lote.isEmpty) continue;
        final String whereCons =
            "UPPER(movimiento) = 'CONSUMO' AND reg_aplic IN (${_ph(lote.length)})";
        // Fila completa (upsert por cod_mov): si el consumo nunca había
        // subido, un simple update arriba no lo crearía.
        final cons = await db.query('insumos_detalles',
            where: whereCons, whereArgs: lote);
        if (cons.isNotEmpty) {
          await client.from('insumos_detalles').upsert(
                cons
                    .map((c) =>
                        Map<String, dynamic>.from(c)..remove('sincronizado'))
                    .toList(),
                onConflict: 'cod_mov',
              );
        }
        // Todo subió: se marca sincronizado.
        await db.update(
          'aplicaciones_registros',
          {'sincronizado': 1},
          where: 'registro IN (${_ph(lote.length)})',
          whereArgs: lote,
        );
        await db.update(
          'insumos_detalles',
          {'sincronizado': 1},
          where: whereCons,
          whereArgs: lote,
        );
      }
    } catch (e) {
      debugPrint('Labores: cambios se subirán al sincronizar ($e)');
    }
  }
}
