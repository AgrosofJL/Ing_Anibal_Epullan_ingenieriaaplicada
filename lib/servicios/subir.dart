import '../base/base.dart';
import 'conexion.dart';

class ServicioSubir {
  static Future<int> subirModificados() async {
    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;
    int totalSubidos = 0;

    // 🛠️ ESTO LO MODIFIQUE: Solo toma los registros pendientes de sincronizar
    final pendientes = await db.query(
      'recetas_aplicaciones',
      where: 'sincronizado = ?',
      whereArgs: [0],
    );

    for (var reg in pendientes) {
      final payload = Map<String, dynamic>.from(reg);
      payload.remove('sincronizado');
      payload.remove('actualizado_el');

      // Modifica en Supabase según la clave primaria cod_receta
      await client.from('recetas_aplicaciones').upsert(
            payload,
            onConflict: 'cod_receta',
          );

      // Marca localmente como subido para no reenviarlo
      await db.update(
        'recetas_aplicaciones',
        {'sincronizado': 1},
        where: 'cod_receta = ?',
        whereArgs: [reg['cod_receta']],
      );
      totalSubidos++;
    }

// 💡 ACA ES LO NUEVO: Subida de lecturas de Fenología
final pendFenologia = await db.query(
  'lecturas_fenologia',
  where: 'sincronizado = ?',
  whereArgs: [0],
);

for (var reg in pendFenologia) {
  final payload = Map<String, dynamic>.from(reg);
  payload.remove('sincronizado');
  await client.from('lecturas_fenologia').upsert(payload, onConflict: 'id, id_reg');
  await db.update('lecturas_fenologia', {'sincronizado': 1}, where: 'id = ? AND id_reg = ?', whereArgs: [reg['id'], reg['id_reg']]);
  totalSubidos++;
}

// 💡 ACA ES LO NUEVO: Subida de lecturas de Trampas
final pendTrampas = await db.query(
  'lecturas_trampas',
  where: 'sincronizado = ?',
  whereArgs: [0],
);

for (var reg in pendTrampas) {
  final payload = Map<String, dynamic>.from(reg);
  payload.remove('sincronizado');
  await client.from('lecturas_trampas').upsert(payload, onConflict: 'id, id_reg');
  await db.update('lecturas_trampas', {'sincronizado': 1}, where: 'id = ? AND id_reg = ?', whereArgs: [reg['id'], reg['id_reg']]);
  totalSubidos++;
}
    return totalSubidos;
  }
}