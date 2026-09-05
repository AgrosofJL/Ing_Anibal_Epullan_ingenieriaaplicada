import 'package:flutter/foundation.dart';
import 'bajar.dart';
import 'sincronizar_evidencias.dart';
import 'subir.dart';

class ServicioSincronizacion {
  static final ValueNotifier<bool> estaSincronizando = ValueNotifier<bool>(false);
  static final ValueNotifier<String> estadoMensaje = ValueNotifier<String>('');

  static Future<void> sincronizarEnSegundoPlano() async {
    if (estaSincronizando.value) return;

    estaSincronizando.value = true;

    try {
      // 💡 ACA ES LO NUEVO: 1. Sube imágenes a los buckets y actualiza SQLite con URL pública
      estadoMensaje.value = 'Subiendo fotos y evidencias...';
      await ServicioEvidencias.sincronizarFotosPendientes();

      // 2. Sube los registros de tablas modificadas (ahora con la URL pública de la foto)
      estadoMensaje.value = 'Subiendo modificaciones...';
      await ServicioSubir.subirModificados();

      // 3. Baja por bloques paginados
      estadoMensaje.value = 'Descargando datos...';
      await ServicioBajar.bajarIncremental();

      estadoMensaje.value = 'Sincronizado';
    } catch (e) {
      estadoMensaje.value = 'Error al sincronizar';
      debugPrint('Error en sync: $e');
    } finally {
      estaSincronizando.value = false;
    }
  }
}