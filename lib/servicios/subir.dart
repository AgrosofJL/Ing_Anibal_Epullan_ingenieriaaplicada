import 'package:flutter/foundation.dart' show kIsWeb;
import '../base/base.dart';
import 'conexion.dart';

class ServicioSubir {
  static Future<int> subirModificados() async {
    // 💡 En Web los datos se persisten en tiempo real en Supabase
    if (kIsWeb) return 0;

    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;
    int totalSubidos = 0;

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

    return totalSubidos;
  }
}