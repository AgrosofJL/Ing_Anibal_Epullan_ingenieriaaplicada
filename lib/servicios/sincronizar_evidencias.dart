import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../base/base.dart';
import 'conexion.dart';

class ServicioEvidencias {
  /// Sube las evidencias pendientes de fenología y trampas
  static Future<void> sincronizarFotosPendientes() async {
    // 💡 En Web / Safari PWA no hay sistema de archivos File local nativo
    if (kIsWeb) {
      return; 
    }

    final client = SupabaseService.client;
    final db = await DatabaseHelper.instance.database;

    // 1. Evidencias de Fenología (Usando db.query parametrizado para evitar comillas SQL)
    final pendFeno = await db.query(
      'lecturas_fenologia',
      columns: ['id', 'id_reg', 'url_evidencia'],
      where: "url_evidencia IS NOT NULL AND url_evidencia != ? AND url_evidencia NOT LIKE ?",
      whereArgs: ['', 'http%'],
    );

    for (var reg in pendFeno) {
      final String rutaLocal = reg['url_evidencia']?.toString() ?? '';
      if (rutaLocal.isEmpty) continue;

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

    // 2. Evidencias de Trampas (Usando db.query parametrizado)
    final pendTrampas = await db.query(
      'lecturas_trampas',
      columns: ['id', 'id_reg', 'url_evidencia'],
      where: "url_evidencia IS NOT NULL AND url_evidencia != ? AND url_evidencia NOT LIKE ?",
      whereArgs: ['', 'http%'],
    );

    for (var reg in pendTrampas) {
      final String rutaLocal = reg['url_evidencia']?.toString() ?? '';
      if (rutaLocal.isEmpty) continue;

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