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
      if (kIsWeb) {
        estadoMensaje.value = 'Verificando licencia...';
        await ServicioBajar.verificarLicencia();
        estadoMensaje.value = 'Conectado a la nube';
        return;
      }

      // En Android / iOS / Windows Desktop (SQLite Local):
      estadoMensaje.value = 'Subiendo fotos y evidencias...';
      await ServicioEvidencias.sincronizarFotosPendientes();

      estadoMensaje.value = 'Subiendo modificaciones...';
      await ServicioSubir.subirModificados();

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