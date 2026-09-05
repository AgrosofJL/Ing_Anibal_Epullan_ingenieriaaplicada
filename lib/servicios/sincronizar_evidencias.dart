import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../base/base.dart';
import 'conexion.dart';

class ServicioEvidencias {
  /// Sube las evidencias pendientes de fenología y trampas
  static Future<void> sincronizarFotosPendientes() async {
    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;

    // 1. Evidencias de Fenología
    final pendFeno = await db.rawQuery('''
      SELECT id, id_reg, url_evidencia 
      FROM lecturas_fenologia 
      WHERE url_evidencia IS NOT NULL 
        AND url_evidencia != "" 
        AND url_evidencia NOT LIKE 'http%'
    ''');

    for (var reg in pendFeno) {
      final String rutaLocal = reg['url_evidencia'].toString();
      final file = File(rutaLocal);

      if (await file.exists()) {
        try {
          final nombreArchivo = "${reg['id_reg']}_${DateTime.now().millisecondsSinceEpoch}.jpg";
          
          // Subida al bucket evidencias_fenologia
          await client.storage.from('evidencias_fenologia').upload(
                nombreArchivo,
                file,
                fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
              );

          final urlPublica = client.storage.from('evidencias_fenologia').getPublicUrl(nombreArchivo);

          // Actualizamos SQLite local con la URL remota
          await db.update(
            'lecturas_fenologia',
            {'url_evidencia': urlPublica, 'sincronizado': 0},
            where: 'id = ? AND id_reg = ?',
            whereArgs: [reg['id'], reg['id_reg']],
          );
        } catch (_) {}
      }
    }

    // 2. Evidencias de Trampas
    final pendTrampas = await db.rawQuery('''
      SELECT id, id_reg, url_evidencia 
      FROM lecturas_trampas 
      WHERE url_evidencia IS NOT NULL 
        AND url_evidencia != "" 
        AND url_evidencia NOT LIKE 'http%'
    ''');

    for (var reg in pendTrampas) {
      final String rutaLocal = reg['url_evidencia'].toString();
      final file = File(rutaLocal);

      if (await file.exists()) {
        try {
          final nombreArchivo = "${reg['id_reg']}_${DateTime.now().millisecondsSinceEpoch}.jpg";

          // Subida al bucket evidencias_trampas
          await client.storage.from('evidencias_trampas').upload(
                nombreArchivo,
                file,
                fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
              );

          final urlPublica = client.storage.from('evidencias_trampas').getPublicUrl(nombreArchivo);

          await db.update(
            'lecturas_trampas',
            {'url_evidencia': urlPublica, 'sincronizado': 0},
            where: 'id = ? AND id_reg = ?',
            whereArgs: [reg['id'], reg['id_reg']],
          );
        } catch (_) {}
      }
    }
  }
}