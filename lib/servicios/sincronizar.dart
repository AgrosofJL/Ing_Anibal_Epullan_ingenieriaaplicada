import 'package:flutter/foundation.dart' show debugPrint, ValueNotifier;

import 'bajar.dart';
import 'sincronizar_evidencias.dart';
import 'subir.dart';
import 'sync_esquema.dart';

class ServicioSincronizacion {
  static final ValueNotifier<bool> estaSincronizando = ValueNotifier<bool>(false);
  static final ValueNotifier<String> estadoMensaje = ValueNotifier<String>('');
  static final ValueNotifier<int> versionMenuNotifier = ValueNotifier<int>(0);

  /// Cantidad de cambios locales sin subir (modificados + eliminados).
  /// Útil para mostrar un contador en el botón de sincronizar.
  static final ValueNotifier<int> pendientes = ValueNotifier<int>(0);

  /// Resumen de la última subida (subidos, eliminados arriba, errores).
  static ResultadoSubida? get ultimoResultado => ServicioSubir.ultimoResultado;

  /// Sincronización normal:
  ///  1) prepara la base (triggers / columnas),
  ///  2) borra arriba lo eliminado en el dispositivo,
  ///  3) sube todo lo pendiente (upsert: corrige si ya existe),
  ///  4) baja todas las tablas sin pisar cambios locales pendientes
  ///     y borra localmente lo que se eliminó en el servidor.
  static Future<bool> sincronizarEnSegundoPlano() async {
    if (estaSincronizando.value) return false;

    estaSincronizando.value = true;
    estadoMensaje.value = 'Iniciando sincronización...';

    try {
      try {
        await SyncEsquema.asegurar();
      } catch (e) {
        debugPrint("Aviso preparando esquema de sync: $e");
      }

      // 1. Subir (eliminaciones + modificaciones)
      estadoMensaje.value = 'Subiendo registros locales...';
      try {
        await ServicioSubir.subirModificados(
          onProgreso: (m) => estadoMensaje.value = m,
        );
      } catch (e) {
        debugPrint("Aviso al subir modificados: $e");
      }

      // 2. Bajar
      estadoMensaje.value = 'Descargando datos...';
      final bool rolCambio = await ServicioBajar.bajarIncremental(
        onProgreso: (m) => estadoMensaje.value = m,
      );

      if (rolCambio) {
        versionMenuNotifier.value++;
      }

      await actualizarPendientes();

      final r = ServicioSubir.ultimoResultado;
      estadoMensaje.value = (r != null && r.errores > 0)
          ? 'Sincronizado con ${r.errores} ${r.errores == 1 ? 'error' : 'errores'}'
          : 'Sincronizado';
      // El proceso terminó; los errores puntuales quedan en ultimoResultado
      // y esos registros se reintentan en la próxima sincronización.
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

  /// Sincronización COMPLETA: vuelve a subir todos los registros de este
  /// dispositivo (corrige cualquier diferencia arriba) y después baja todo.
  /// ⚠ Si otro dispositivo modificó los mismos registros, gana este.
  static Future<bool> sincronizarCompleto() async {
    if (estaSincronizando.value) return false;
    try {
      await ServicioSubir.marcarTodoComoPendiente();
    } catch (e) {
      debugPrint("Aviso marcando todo como pendiente: $e");
    }
    return sincronizarEnSegundoPlano();
  }

  static Future<void> actualizarPendientes() async {
    try {
      pendientes.value = await SyncEsquema.contarPendientes();
    } catch (_) {}
  }
}
