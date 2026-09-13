import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, ValueNotifier;
import 'bajar.dart';
import 'sincronizar_evidencias.dart';
import 'subir.dart';

class ServicioSincronizacion {
  static final ValueNotifier<bool> estaSincronizando = ValueNotifier<bool>(false);
  static final ValueNotifier<String> estadoMensaje = ValueNotifier<String>('');

  static Future<bool> sincronizarEnSegundoPlano() async {
    if (estaSincronizando.value) return false;

    estaSincronizando.value = true;
    estadoMensaje.value = 'Iniciando sincronización...';

    try {
      if (kIsWeb) {
        // En Web / Safari PWA solo validamos conexión y licencia con Supabase
        estadoMensaje.value = 'Verificando licencia en la nube...';
        await ServicioBajar.verificarLicencia();
        estadoMensaje.value = 'Conectado y sincronizado';
        return true;
      }

      // En Windows / Android / iOS con SQLite local
      estadoMensaje.value = 'Subiendo evidencias...';
      try {
        await ServicioEvidencias.sincronizarFotosPendientes();
      } catch (e) {
        debugPrint("Aviso al subir evidencias: $e");
      }

      estadoMensaje.value = 'Subiendo registros locales...';
      try {
        await ServicioSubir.subirModificados();
      } catch (e) {
        debugPrint("Aviso al subir modificados: $e");
      }

      estadoMensaje.value = 'Descargando datos...';
      try {
        await ServicioBajar.bajarIncremental();
      } catch (e) {
        debugPrint("Aviso al descargar datos: $e");
      }

      estadoMensaje.value = 'Sincronizado';
      return true;
    } catch (e) {
      estadoMensaje.value = 'Error al sincronizar';
      debugPrint('Error general en sync: $e');
      return false;
    } finally {
      estaSincronizando.value = false;
    }
  }
}