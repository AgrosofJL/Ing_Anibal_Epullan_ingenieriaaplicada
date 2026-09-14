import 'package:flutter/foundation.dart' show kIsWeb;
import '../base/base.dart';
import 'conexion.dart';

class ServicioSubir {
  static Future<int> subirModificados() async {
    final client = SupabaseService.client; //[cite: 16]
    final db = await DatabaseHelper.instance.database; //[cite: 16]
    int totalSubidos = 0; //[cite: 16]

    // 1. Cabeceras de Órdenes
    final pendOrdenes = await db.query(
      'ordenes_aplicaciones',
      where: 'sincronizado = ?',
      whereArgs: [0],
    ); //[cite: 16]

    for (var reg in pendOrdenes) {
      final payload = Map<String, dynamic>.from(reg); //[cite: 16]
      payload.remove('sincronizado'); //[cite: 16]
      await client.from('ordenes_aplicaciones').upsert(payload, onConflict: 'cod_orden'); //[cite: 16]
      await db.update('ordenes_aplicaciones', {'sincronizado': 1}, where: 'cod_orden = ?', whereArgs: [reg['cod_orden']]); //[cite: 16]
      totalSubidos++; //[cite: 16]
    }

    // 2. Recetas de Aplicaciones (con dosis_x)
    final pendientes = await db.query(
      'recetas_aplicaciones',
      where: 'sincronizado = ?',
      whereArgs: [0],
    ); //[cite: 16]

    for (var reg in pendientes) {
      final payload = Map<String, dynamic>.from(reg); //[cite: 16]
      payload.remove('sincronizado'); //[cite: 16]
      payload.remove('actualizado_el'); //[cite: 16]
      await client.from('recetas_aplicaciones').upsert(payload, onConflict: 'cod_receta'); //[cite: 16]
      await db.update('recetas_aplicaciones', {'sincronizado': 1}, where: 'cod_receta = ?', whereArgs: [reg['cod_receta']]); //[cite: 16]
      totalSubidos++; //[cite: 16]
    }

    // 3. Fenología
    final pendFenologia = await db.query('lecturas_fenologia', where: 'sincronizado = ?', whereArgs: [0]); //[cite: 16]
    for (var reg in pendFenologia) {
      final payload = Map<String, dynamic>.from(reg)..remove('sincronizado'); //[cite: 16]
      await client.from('lecturas_fenologia').upsert(payload, onConflict: 'id,id_reg'); //[cite: 16]
      await db.update('lecturas_fenologia', {'sincronizado': 1}, where: 'id = ? AND id_reg = ?', whereArgs: [reg['id'], reg['id_reg']]); //[cite: 16]
      totalSubidos++; //[cite: 16]
    }

    // 4. Trampas
    final pendTrampas = await db.query('lecturas_trampas', where: 'sincronizado = ?', whereArgs: [0]); //[cite: 16]
    for (var reg in pendTrampas) {
      final payload = Map<String, dynamic>.from(reg)..remove('sincronizado'); //[cite: 16]
      await client.from('lecturas_trampas').upsert(payload, onConflict: 'id,id_reg'); //[cite: 16]
      await db.update('lecturas_trampas', {'sincronizado': 1}, where: 'id = ? AND id_reg = ?', whereArgs: [reg['id'], reg['id_reg']]); //[cite: 16]
      totalSubidos++; //[cite: 16]
    }

    // 5. Aplicaciones Registros
    final pendAplicacionesReg = await db.query('aplicaciones_registros', where: 'sincronizado = ?', whereArgs: [0]); //[cite: 16]
    for (var reg in pendAplicacionesReg) {
      final payload = Map<String, dynamic>.from(reg)..remove('sincronizado'); //[cite: 16]
      await client.from('aplicaciones_registros').upsert(payload, onConflict: 'registro'); //[cite: 16]
      await db.update('aplicaciones_registros', {'sincronizado': 1}, where: 'registro = ?', whereArgs: [reg['registro']]); //[cite: 16]
      totalSubidos++; //[cite: 16]
    }

    // 6. Insumos Detalles
    final pendInsumosDetalles = await db.query('insumos_detalles', where: 'sincronizado = ?', whereArgs: [0]); //[cite: 16]
    for (var reg in pendInsumosDetalles) {
      final payload = Map<String, dynamic>.from(reg)..remove('sincronizado'); //[cite: 16]
      await client.from('insumos_detalles').upsert(payload, onConflict: 'cod_mov'); //[cite: 16]
      await db.update('insumos_detalles', {'sincronizado': 1}, where: 'cod_mov = ?', whereArgs: [reg['cod_mov']]); //[cite: 16]
      totalSubidos++; //[cite: 16]
    }

    return totalSubidos; //[cite: 16]
  }
}