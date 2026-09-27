// AgroSoft J&L · Eliminación en cascada de una orden
// -----------------------------------------------------------------------------
// Ubicación: lib/servicios/eliminar_orden.dart
//
// Al borrar una orden se elimina, en este orden:
//   1. insumos_detalles      → consumos generados por las labores de la orden
//                              (reg_aplic = registro, o reg_consumo = APLICACION_ORDEN_x)
//   2. aplicaciones_registros → labores registradas de la orden
//   3. recetas_aplicaciones   → productos de la receta
//   4. parametros_aplic       → parámetros técnicos
//   5. ordenes_aplicaciones   → cabecera
//
// Localmente se hace en UNA transacción (o se borra todo o nada).
// Los triggers de sync_esquema dejan cada borrado en la cola sync_eliminados,
// así que si no hay conexión se eliminan arriba en la próxima sincronización.
// Además se intenta borrar en Supabase en el momento (si hay conexión).

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';
import 'conexion.dart';
import 'sync_esquema.dart';

class ResumenOrdenABorrar {
  final int recetas;
  final int labores;
  final int consumos;
  final double stockDevuelto; // suma de producto que vuelve al stock

  const ResumenOrdenABorrar({
    required this.recetas,
    required this.labores,
    required this.consumos,
    required this.stockDevuelto,
  });
}

class ServicioEliminarOrden {
  static const String _whereOrden = 'CAST(cod_orden AS INTEGER) = ?';
  static const String _whereOrdenProd =
      'CAST(cod_orden AS INTEGER) = ? AND CAST(cod_productor AS INTEGER) = ?';

  static String _refConsumo(int codOrden) => 'APLICACION_ORDEN_$codOrden';

  /// Registros (ids de labor) de la orden.
  static Future<List<String>> _registros(
      DatabaseExecutor db, int codOrden, int codProductor) async {
    final rows = await db.query(
      'aplicaciones_registros',
      columns: ['registro'],
      where: _whereOrdenProd,
      whereArgs: [codOrden, codProductor],
    );
    return rows
        .map((r) => r['registro']?.toString() ?? '')
        .where((r) => r.isNotEmpty)
        .toList();
  }

  /// Condición SQL para los consumos de la orden: los que generaron sus
  /// labores (reg_aplic) o los marcados con APLICACION_ORDEN_x.
  /// Se usa subconsulta para no chocar con el límite de parámetros de SQLite.
  static String get _whereConsumos =>
      "UPPER(movimiento) = 'CONSUMO' AND CAST(cod_productor AS INTEGER) = ? AND ("
      "reg_consumo = ? OR reg_aplic IN ("
      "SELECT registro FROM aplicaciones_registros WHERE $_whereOrdenProd))";

  static List<Object?> _argsConsumos(int codOrden, int codProductor) =>
      [codProductor, _refConsumo(codOrden), codOrden, codProductor];

  /// Cuenta lo que se va a borrar (para mostrarlo en la confirmación).
  static Future<ResumenOrdenABorrar> resumen(
      int codOrden, int codProductor) async {
    final db = await DatabaseHelper.instance.database;
    final registros = await _registros(db, codOrden, codProductor);

    int contar(List<Map<String, Object?>> r) =>
        int.tryParse(r.first['n']?.toString() ?? '0') ?? 0;

    final rec = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM recetas_aplicaciones WHERE $_whereOrdenProd',
        [codOrden, codProductor]);
    final cons = await db.rawQuery(
        'SELECT COUNT(*) AS n, SUM(ABS(cantidad)) AS total FROM insumos_detalles WHERE $_whereConsumos',
        _argsConsumos(codOrden, codProductor));

    return ResumenOrdenABorrar(
      recetas: contar(rec),
      labores: registros.length,
      consumos: contar(cons),
      stockDevuelto: double.tryParse(cons.first['total']?.toString() ?? '') ?? 0.0,
    );
  }

  /// Borra la orden y todo lo que depende de ella.
  /// Devuelve true si localmente quedó todo eliminado.
  static Future<bool> eliminar(int codOrden, int codProductor) async {
    final db = await DatabaseHelper.instance.database;

    // Asegura los triggers → cada borrado queda en la cola para subir.
    try {
      await SyncEsquema.asegurar(db);
    } catch (e) {
      debugPrint('Aviso preparando triggers: $e');
    }

    List<String> registros = [];

    // ---------------- LOCAL (todo o nada) ----------------
    await db.transaction((txn) async {
      registros = await _registros(txn, codOrden, codProductor);

      // Consumos primero (la subconsulta necesita las labores todavía).
      await txn.delete('insumos_detalles',
          where: _whereConsumos,
          whereArgs: _argsConsumos(codOrden, codProductor));
      await txn.delete('aplicaciones_registros',
          where: _whereOrdenProd, whereArgs: [codOrden, codProductor]);
      await txn.delete('recetas_aplicaciones',
          where: _whereOrdenProd, whereArgs: [codOrden, codProductor]);
      await txn.delete('parametros_aplic',
          where: _whereOrden, whereArgs: [codOrden]);
      await txn.delete('ordenes_aplicaciones',
          where: _whereOrdenProd, whereArgs: [codOrden, codProductor]);
    });

    // ---------------- SERVIDOR (si hay conexión) ----------------
    // Si falla, los borrados siguen en sync_eliminados y se reintentan
    // en la próxima sincronización.
    try {
      final client = SupabaseService.client;

      // 1. Consumos
      await client
          .from('insumos_detalles')
          .delete()
          .eq('cod_productor', codProductor)
          .eq('reg_consumo', _refConsumo(codOrden));
      for (int i = 0; i < registros.length; i += 200) {
        final lote = registros.sublist(
            i, i + 200 > registros.length ? registros.length : i + 200);
        await client
            .from('insumos_detalles')
            .delete()
            .eq('cod_productor', codProductor)
            .eq('movimiento', 'CONSUMO')
            .inFilter('reg_aplic', lote);
      }

      // 2. Labores
      await client
          .from('aplicaciones_registros')
          .delete()
          .eq('cod_orden', codOrden)
          .eq('cod_productor', codProductor);

      // 3. Receta
      await client
          .from('recetas_aplicaciones')
          .delete()
          .eq('cod_orden', codOrden)
          .eq('cod_productor', codProductor);

      // 4. Parámetros
      await client.from('parametros_aplic').delete().eq('cod_orden', codOrden);

      // 5. Cabecera (cod_orden es texto en esta tabla)
      await client
          .from('ordenes_aplicaciones')
          .delete()
          .eq('cod_orden', codOrden.toString());

      // Los borrados que quedaron en la cola se vuelven a mandar en la
      // próxima sincronización; borrar algo ya borrado arriba no hace nada.
    } catch (e) {
      debugPrint('Orden $codOrden: se eliminará en el servidor al sincronizar ($e)');
    }

    return true;
  }
}
