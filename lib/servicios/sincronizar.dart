import 'package:flutter/foundation.dart' show debugPrint, ValueNotifier;
import 'bajar.dart';
import 'sincronizar_evidencias.dart';
import 'subir.dart';

class ServicioSincronizacion {
  static final ValueNotifier<bool> estaSincronizando = ValueNotifier<bool>(false);
  static final ValueNotifier<String> estadoMensaje = ValueNotifier<String>('');
  static final ValueNotifier<int> versionMenuNotifier = ValueNotifier<int>(0);

  static Future<bool> sincronizarEnSegundoPlano() async {
    if (estaSincronizando.value) return false;

    estaSincronizando.value = true;
    estadoMensaje.value = 'Iniciando sincronización...';

    try {
      // 1. Subir modificaciones pendientes (compatible con Web y móvil)
      estadoMensaje.value = 'Subiendo registros locales...';
      try {
        await ServicioSubir.subirModificados();
      } catch (e) {
        debugPrint("Aviso al subir modificados: $e");
      }

      // 2. Descargar y actualizar datos locales de forma diferencial
      estadoMensaje.value = 'Descargando datos...';
      final bool rolCambio = await ServicioBajar.bajarIncremental();

      if (rolCambio) {
        versionMenuNotifier.value++;
      }

      estadoMensaje.value = 'Sincronizado';
      return true;
    } on LicenciaInactivaException catch (lie) {
      estadoMensaje.value = 'Usuario Inactivo';
      debugPrint("Bloqueo aplicado: $lie");
      return false;
    } catch (e) {
      estadoMensaje.value = 'Error al sincronizar';
      debugPrint('Error general en sync: $e');
      return false;
    } finally {
      estaSincronizando.value = false;
    }
  }
}