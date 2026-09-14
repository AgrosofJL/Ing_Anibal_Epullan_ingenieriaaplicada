import 'package:flutter/foundation.dart' show kIsWeb;
import '../base/base.dart';
import 'conexion.dart';

class ServicioSubir {
  static Future<int> subirModificados() async {
    // 💡 Si la Web utiliza SQLite local vía IndexedDB, puedes remover esta condición si deseas que también suba lotes pendientes.
    if (kIsWeb) return 0;

    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;
    int totalSubidos = 0;

    // 1. Recetas de Aplicaciones
    final pendientes = await db.query(
      'recetas_aplicaciones',
      where: 'sincronizado = ?',
      whereArgs: [0],
    );

    for (var reg in pendientes) {
      final payload = Map<String, dynamic>.from(reg);
      payload.remove('sincronizado');
      payload.remove('actualizado_el');

      await client.from('recetas_aplicaciones').upsert(
            payload,
            onConflict: 'cod_receta',
          );

      await db.update(
        'recetas_aplicaciones',
        {'sincronizado': 1},
        where: 'cod_receta = ?',
        whereArgs: [reg['cod_receta']],
      );
      totalSubidos++;
    }

    // 2. Lecturas de Fenología
    final pendFenologia = await db.query(
      'lecturas_fenologia',
      where: 'sincronizado = ?',
      whereArgs: [0],
    );

    for (var reg in pendFenologia) {
      final payload = Map<String, dynamic>.from(reg);
      payload.remove('sincronizado');
      await client.from('lecturas_fenologia').upsert(payload, onConflict: 'id,id_reg');
      await db.update('lecturas_fenologia', {'sincronizado': 1}, where: 'id = ? AND id_reg = ?', whereArgs: [reg['id'], reg['id_reg']]);
      totalSubidos++;
    }

    // 3. Lecturas de Trampas
    final pendTrampas = await db.query(
      'lecturas_trampas',
      where: 'sincronizado = ?',
      whereArgs: [0],
    );

    for (var reg in pendTrampas) {
      final payload = Map<String, dynamic>.from(reg);
      payload.remove('sincronizado');
      await client.from('lecturas_trampas').upsert(payload, onConflict: 'id,id_reg');
      await db.update('lecturas_trampas', {'sincronizado': 1}, where: 'id = ? AND id_reg = ?', whereArgs: [reg['id'], reg['id_reg']]);
      totalSubidos++;
    }

    // 4. Aplicaciones Registros (Labores reales de campo)
    final pendAplicacionesReg = await db.query(
      'aplicaciones_registros',
      where: 'sincronizado = ?',
      whereArgs: [0],
    );

    for (var reg in pendAplicacionesReg) {
      final payload = Map<String, dynamic>.from(reg);
      payload.remove('sincronizado');
      await client.from('aplicaciones_registros').upsert(
            payload,
            onConflict: 'registro',
          );
      await db.update(
        'aplicaciones_registros',
        {'sincronizado': 1},
        where: 'registro = ?',
        whereArgs: [reg['registro']],
      );
      totalSubidos++;
    }

    // 5. Insumos Detalles (Ingresos, consumos y bajas de stock en galpones)
    final pendInsumosDetalles = await db.query(
      'insumos_detalles',
      where: 'sincronizado = ?',
      whereArgs: [0],
    );

    for (var reg in pendInsumosDetalles) {
      final payload = Map<String, dynamic>.from(reg);
      payload.remove('sincronizado');
      await client.from('insumos_detalles').upsert(
            payload,
            onConflict: 'cod_mov',
          );
      await db.update(
        'insumos_detalles',
        {'sincronizado': 1},
        where: 'cod_mov = ?',
        whereArgs: [reg['cod_mov']],
      );
      totalSubidos++;
    }

// 💡 ACA ES LO NUEVO: Subida de Cabeceras de Órdenes
    final pendOrdenes = await db.query(
      'ordenes_aplicaciones',
      where: 'sincronizado = ?',
      whereArgs: [0],
    );

    for (var reg in pendOrdenes) {
      final payload = Map<String, dynamic>.from(reg);
      payload.remove('sincronizado');
      await client.from('ordenes_aplicaciones').upsert(
            payload,
            onConflict: 'cod_orden',
          );
      await db.update(
        'ordenes_aplicaciones',
        {'sincronizado': 1},
        where: 'cod_orden = ?',
        whereArgs: [reg['cod_orden']],
      );
      totalSubidos++;
    }
    return totalSubidos;
  }
}