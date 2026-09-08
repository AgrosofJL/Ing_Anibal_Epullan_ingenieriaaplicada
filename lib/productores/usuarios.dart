import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';

class UsuariosScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const UsuariosScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  bool _cargando = true;
  List<Map<String, dynamic>> _usuarios = [];
  String _filtroTexto = "";
  final TextEditingController _searchCtrl = TextEditingController();

  String _urlIphone =
      "https://agrosofjl.github.io/Ing_Anibal_Epullan_ingenieriaaplicada/";
  String _urlAndroid =
      "https://agrosofjl.github.io/Ing_Anibal_Epullan_ingenieriaaplicada/";

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    await _cargarConfiguracionEnlaces();
    await _cargarUsuarios();
  }

  Future<void> _cargarConfiguracionEnlaces() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final res = await db.query('config_app_enlaces');
      for (var row in res) {
        final plat = (row['plataforma'] ?? '').toString().toUpperCase();
        final url = (row['url_instalacion'] ?? '').toString();
        if (plat == 'IPHONE' && url.isNotEmpty) _urlIphone = url;
        if (plat == 'ANDROID' && url.isNotEmpty) _urlAndroid = url;
      }
    } catch (_) {
      try {
        final supabase = Supabase.instance.client;
        final res = await supabase.from('config_app_enlaces').select();
        for (var row in res) {
          final plat = (row['plataforma'] ?? '').toString().toUpperCase();
          final url = (row['url_instalacion'] ?? '').toString();
          if (plat == 'IPHONE' && url.isNotEmpty) _urlIphone = url;
          if (plat == 'ANDROID' && url.isNotEmpty) _urlAndroid = url;
        }
      } catch (_) {}
    }
  }

  Future<void> _cargarUsuarios() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final res = await db.query(
      'usuarios',
      where: 'cod_productor = ?',
      whereArgs: [widget.codProductor],
      orderBy: 'operario ASC',
    );

    if (!mounted) return;
    setState(() {
      _usuarios = res;
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _usuariosFiltrados {
    if (_filtroTexto.isEmpty) return _usuarios;
    final q = _filtroTexto.toLowerCase();
    return _usuarios.where((u) {
      final op = (u['operario'] ?? '').toString().toLowerCase();
      final cor = (u['correo'] ?? '').toString().toLowerCase();
      final rol = (u['rol'] ?? '').toString().toLowerCase();
      final dev = (u['device'] ?? '').toString().toLowerCase();
      return op.contains(q) || cor.contains(q) || rol.contains(q) || dev.contains(q);
    }).toList();
  }

  Future<void> _sincronizarRemotoUsuario(Map<String, dynamic> userRow) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('usuarios').upsert(userRow);
    } catch (e) {
      debugPrint("Aviso sync usuario Supabase: $e");
    }
  }

  // Cambiar estado rápido (Dar de baja / Reactivar)
  Future<void> _alternarEstadoUsuario(Map<String, dynamic> u) async {
    final String estadoActual =
        (u['estado'] ?? 'ACTIVO').toString().trim().toUpperCase();
    final String nuevoEstado = estadoActual == 'ACTIVO' ? 'INACTIVO' : 'ACTIVO';
    final int userId = int.parse(u['id'].toString());

    final db = await DatabaseHelper.instance.database;
    await db.update(
      'usuarios',
      {'estado': nuevoEstado},
      where: 'id = ?',
      whereArgs: [userId],
    );

    final updatedRow = Map<String, dynamic>.from(u);
    updatedRow['estado'] = nuevoEstado;
    await _sincronizarRemotoUsuario(updatedRow);

    await _cargarUsuarios();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: nuevoEstado == 'ACTIVO'
            ? const Color(0xFF2E7D32)
            : const Color(0xFFC62828),
        content: Text(nuevoEstado == 'ACTIVO'
            ? "Usuario reactivado con éxito"
            : "Usuario dado de baja (Acceso bloqueado)"),
      ),
    );
  }

  Future<void> _eliminarUsuario(Map<String, dynamic> u) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AgroTheme.colorSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Eliminar usuario",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text("¿Deseás eliminar de forma definitiva la ficha de ${u['operario']}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('usuarios', where: 'id = ?', whereArgs: [u['id']]);
      try {
        await Supabase.instance.client.from('usuarios').delete().eq('id', u['id']);
      } catch (_) {}

      await _cargarUsuarios();
    }
  }

  void _compartirCredencialesWhatsApp({
    required String operario,
    required String correo,
    required String pass,
    required String rol,
    required String plataforma,
    String? device,
  }) {
    final bool esIphone = plataforma == 'IPHONE';
    final String enlaceDescarga = esIphone ? _urlIphone : _urlAndroid;

    final String guiaInstalacion = esIphone
        ? "1. Abrí el link en *Safari*.\n2. Tocá el botón Compartir (cuadrado con flecha hacia arriba).\n3. Elegí *'Agregar a pantalla de inicio'*."
        : "1. Abrí el link y descargá el archivo instalador APK.\n2. Permití *'Instalar apps de fuentes desconocidas'* si te lo solicita.\n3. Instalá y abrí la aplicación.";

    final String detalleDevice = (!esIphone && device != null && device.isNotEmpty)
        ? "\n📱 *Device ID Registrado:* `$device`\n"
        : "";

    final mensaje = '''
🌱 *AGROSOFT J&L · FICHA DE ACCESO*
Hola *$operario*, acá tenés tu credencial de acceso para el establecimiento *${widget.nombreProductor}*:

📱 *Plataforma:* ${esIphone ? "iPhone / iPad (Safari PWA)" : "Android (APK)"}
🌐 *Link de Instalación:* $enlaceDescarga

👤 *Usuario / Email:* $correo
🔑 *Contraseña:* $pass
🔰 *Rol:* $rol$detalleDevice
*Pasos de instalación:*
$guiaInstalacion
''';

    Share.share(mensaje, subject: 'Ficha de Acceso - ${widget.nombreProductor}');
  }

  void _mostrarModalUsuario({Map<String, dynamic>? usuarioExistente}) {
    final bool esEdicion = usuarioExistente != null;
    final formKey = GlobalKey<FormState>();

    final operarioCtrl =
        TextEditingController(text: usuarioExistente?['operario'] ?? '');
    final correoCtrl =
        TextEditingController(text: usuarioExistente?['correo'] ?? '');
    final passCtrl =
        TextEditingController(text: usuarioExistente?['pass'] ?? '1234');
    final deviceCtrl =
        TextEditingController(text: usuarioExistente?['device'] ?? '');

    String rolVisual = (usuarioExistente?['rol'] ?? '').toString().contains('ADMIN')
        ? "ADMINISTRADOR"
        : "OPERARIO";
    String estadoSeleccionado =
        (usuarioExistente?['estado'] ?? 'ACTIVO').toString().toUpperCase();

    String plataformaSeleccionada =
        (usuarioExistente?['device'] ?? '').toString().isNotEmpty
            ? "ANDROID"
            : "IPHONE";

    bool guardando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.90,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 22,
                right: 22,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                esEdicion ? "Editar Ficha de Personal" : "Alta de Operario / Admin",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16.5,
                                  color: AgroTheme.colorText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.nombreProductor,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AgroTheme.colorTextSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: AgroTheme.colorBorder),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "DISPOSITIVO DE TRABAJO",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.apple_rounded, size: 16),
                                        SizedBox(width: 6),
                                        Text("iPhone (Safari PWA)"),
                                      ],
                                    ),
                                    selected: plataformaSeleccionada == "IPHONE",
                                    selectedColor: const Color(0xFFE8F5E9),
                                    labelStyle: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: plataformaSeleccionada == "IPHONE"
                                          ? const Color(0xFF2E7D32)
                                          : AgroTheme.colorTextSecondary,
                                    ),
                                    backgroundColor: AgroTheme.colorBg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: plataformaSeleccionada == "IPHONE"
                                            ? const Color(0xFFA5D6A7)
                                            : AgroTheme.colorBorder,
                                      ),
                                    ),
                                    onSelected: (val) {
                                      if (val) {
                                        setModalState(() {
                                          plataformaSeleccionada = "IPHONE";
                                          deviceCtrl.clear();
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.android_rounded, size: 16),
                                        SizedBox(width: 6),
                                        Text("Android (APK)"),
                                      ],
                                    ),
                                    selected: plataformaSeleccionada == "ANDROID",
                                    selectedColor: const Color(0xFFE8F5E9),
                                    labelStyle: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: plataformaSeleccionada == "ANDROID"
                                          ? const Color(0xFF2E7D32)
                                          : AgroTheme.colorTextSecondary,
                                    ),
                                    backgroundColor: AgroTheme.colorBg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: plataformaSeleccionada == "ANDROID"
                                            ? const Color(0xFFA5D6A7)
                                            : AgroTheme.colorBorder,
                                      ),
                                    ),
                                    onSelected: (val) {
                                      if (val) {
                                        setModalState(() => plataformaSeleccionada = "ANDROID");
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (plataformaSeleccionada == "ANDROID") ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorBg,
                                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                                  border: Border.all(color: AgroTheme.colorBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          "VINCULACIÓN POR DEVICE ID",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                            color: AgroTheme.colorTextSecondary,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () async {
                                            final data =
                                                await Clipboard.getData(Clipboard.kTextPlain);
                                            if (data?.text != null &&
                                                data!.text!.trim().isNotEmpty) {
                                              setModalState(() {
                                                deviceCtrl.text = data.text!.trim();
                                              });
                                            }
                                          },
                                          child: const Row(
                                            children: [
                                              Icon(Icons.paste_rounded,
                                                  size: 14, color: Color(0xFF2E7D32)),
                                              SizedBox(width: 4),
                                              Text(
                                                "Pegar",
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF2E7D32),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: deviceCtrl,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: _inputDecoration(
                                        "ID de hardware de Android",
                                        Icons.phonelink_lock_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            const Text(
                              "DATOS DE LA CUENTA",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: operarioCtrl,
                              decoration: _inputDecoration(
                                "Nombre y Apellido",
                                Icons.person_outline,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: correoCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDecoration(
                                "Correo Electrónico (Login)",
                                Icons.mail_outline,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: passCtrl,
                                    decoration: _inputDecoration(
                                      "Contraseña",
                                      Icons.lock_outline,
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty ? "Obligatorio" : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: rolVisual,
                                    decoration: _inputDecoration(
                                      "Rol",
                                      Icons.shield_outlined,
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: "ADMINISTRADOR", child: Text("Admin")),
                                      DropdownMenuItem(
                                          value: "OPERARIO", child: Text("Operario")),
                                    ],
                                    onChanged: (v) =>
                                        setModalState(() => rolVisual = v ?? "OPERARIO"),
                                  ),
                                ),
                              ],
                            ),
                            if (esEdicion) ...[
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                value: estadoSeleccionado,
                                decoration: _inputDecoration(
                                  "Estado",
                                  Icons.toggle_on_outlined,
                                ),
                                items: const [
                                  DropdownMenuItem(value: "ACTIVO", child: Text("ACTIVO")),
                                  DropdownMenuItem(
                                      value: "INACTIVO", child: Text("INACTIVO (Bloqueado)")),
                                ],
                                onChanged: (v) =>
                                    setModalState(() => estadoSeleccionado = v ?? "ACTIVO"),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E6B4C),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: guardando
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => guardando = true);
                                final db = await DatabaseHelper.instance.database;

                                final String rolFinal = rolVisual == 'ADMINISTRADOR'
                                    ? 'PROD-ADMIN'
                                    : 'PROD-OPE';
                                final String finalDevice = plataformaSeleccionada == "ANDROID"
                                    ? deviceCtrl.text.trim()
                                    : '';

                                if (esEdicion) {
                                  final int userId =
                                      int.parse(usuarioExistente['id'].toString());
                                  final rowUpdate = {
                                    'correo': correoCtrl.text.trim(),
                                    'operario': operarioCtrl.text.trim(),
                                    'device': finalDevice,
                                    'pass': passCtrl.text.trim(),
                                    'rol': rolFinal,
                                    'estado': estadoSeleccionado,
                                  };

                                  await db.update('usuarios', rowUpdate,
                                      where: 'id = ?', whereArgs: [userId]);
                                  await _sincronizarRemotoUsuario({
                                    'id': userId,
                                    'cod_productor': widget.codProductor,
                                    ...rowUpdate,
                                  });

                                  if (!mounted) return;
                                  Navigator.pop(ctx);
                                  await _cargarUsuarios();
                                } else {
                                  final int sigUserId = await DatabaseHelper.instance
                                      .obtenerSiguienteId('usuarios', 'id');

                                  final rowUser = {
                                    'id': sigUserId,
                                    'correo': correoCtrl.text.trim(),
                                    'operario': operarioCtrl.text.trim(),
                                    'device': finalDevice,
                                    'pass': passCtrl.text.trim(),
                                    'rol': rolFinal,
                                    'estado': 'ACTIVO',
                                    'cod_productor': widget.codProductor,
                                  };

                                  await db.insert('usuarios', rowUser);
                                  await _sincronizarRemotoUsuario(rowUser);

                                  if (!mounted) return;
                                  Navigator.pop(ctx);
                                  await _cargarUsuarios();

                                  _compartirCredencialesWhatsApp(
                                    operario: rowUser['operario'] as String,
                                    correo: rowUser['correo'] as String,
                                    pass: rowUser['pass'] as String,
                                    rol: rolFinal,
                                    plataforma: plataformaSeleccionada,
                                    device: finalDevice,
                                  );
                                }
                              },
                        child: guardando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                esEdicion ? "Guardar Cambios" : "Guardar y Enviar Accesos",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _mostrarSelectorReenvio(Map<String, dynamic> u) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      backgroundColor: AgroTheme.colorSurface,
      builder: (bCtx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Compartir acceso a ${u['operario']}",
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AgroTheme.colorText,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Seleccioná el dispositivo del destinatario para adjuntar la guía e instalador:",
                style: TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary),
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                tileColor: AgroTheme.colorBg,
                leading: const Icon(Icons.apple_rounded, size: 24, color: Colors.black87),
                title: const Text("iPhone / iPad (Apple)",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: const Text("Enlace para Safari PWA",
                    style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  Navigator.pop(bCtx);
                  _compartirCredencialesWhatsApp(
                    operario: u['operario'] ?? '',
                    correo: u['correo'] ?? '',
                    pass: u['pass'] ?? '',
                    rol: u['rol'] ?? 'PROD-OPE',
                    plataforma: 'IPHONE',
                  );
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                tileColor: AgroTheme.colorBg,
                leading: const Icon(Icons.android_rounded,
                    size: 24, color: Color(0xFF2E7D32)),
                title: const Text("Android",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: Text(
                  (u['device'] ?? '').toString().isNotEmpty
                      ? "Device ID vinculado"
                      : "Instalador APK con guía paso a paso",
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  Navigator.pop(bCtx);
                  _compartirCredencialesWhatsApp(
                    operario: u['operario'] ?? '',
                    correo: u['correo'] ?? '',
                    pass: u['pass'] ?? '',
                    rol: u['rol'] ?? 'PROD-OPE',
                    plataforma: 'ANDROID',
                    device: u['device']?.toString(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12.5, color: AgroTheme.colorTextSecondary),
      prefixIcon: Icon(icono, size: 18, color: AgroTheme.colorTextSecondary),
      filled: true,
      fillColor: AgroTheme.colorBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: AgroTheme.colorBorder, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: Color(0xFF1E6B4C), width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double ancho = MediaQuery.of(context).size.width;
    final bool esDesktop = ancho >= 920;

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AppBar(
        backgroundColor: AgroTheme.colorSurface.withOpacity(0.92),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Fichas de Personal",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16.5,
                color: AgroTheme.colorText,
              ),
            ),
            Text(
              widget.nombreProductor,
              style: const TextStyle(
                fontSize: 11.5,
                color: AgroTheme.colorTextSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1150),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    esDesktop ? 24 : 16,
                    14,
                    esDesktop ? 24 : 16,
                    10,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AgroTheme.colorSurface,
                      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                      border: Border.all(color: AgroTheme.colorBorder),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x04141E18),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _filtroTexto = v),
                      style: const TextStyle(color: AgroTheme.colorText, fontSize: 13.5),
                      decoration: const InputDecoration(
                        hintText: "Buscar por nombre, correo, rol o device...",
                        hintStyle: TextStyle(
                            color: AgroTheme.colorTextSecondary, fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: AgroTheme.colorTextSecondary, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _cargando
                      ? const Center(
                          child: CircularProgressIndicator(color: Color(0xFF1E6B4C)),
                        )
                      : _usuariosFiltrados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE8F5E9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.badge_outlined,
                                      size: 38,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    "No hay fichas registradas",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5,
                                      color: AgroTheme.colorText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Creá el primer usuario para ${widget.nombreProductor}.",
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AgroTheme.colorTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : esDesktop
                              ? GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 80),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 520,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    childAspectRatio: 1.85,
                                  ),
                                  itemCount: _usuariosFiltrados.length,
                                  itemBuilder: (context, idx) {
                                    return _buildFichaEmpleadoCard(_usuariosFiltrados[idx]);
                                  },
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                                  itemCount: _usuariosFiltrados.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, idx) {
                                    return _buildFichaEmpleadoCard(_usuariosFiltrados[idx]);
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1E6B4C),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: () => _mostrarModalUsuario(),
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
        label: const Text(
          "Nuevo Usuario",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // 💡 CARD TIPO FICHA DE EMPLEADO (Apple Soft + Colores Pastel Suaves)
  Widget _buildFichaEmpleadoCard(Map<String, dynamic> u) {
    final String operario = (u['operario'] ?? 'Sin Nombre').toString();
    final String correo = (u['correo'] ?? '').toString();
    final String pass = (u['pass'] ?? '').toString();
    final String rol = (u['rol'] ?? 'PROD-OPE').toString();
    final bool esAdmin = rol.contains('ADMIN');
    final String estado = (u['estado'] ?? 'ACTIVO').toString().toUpperCase();
    final bool activo = estado == 'ACTIVO';
    final String device = (u['device'] ?? '').toString().trim();

    // Iniciales para el avatar tipo credencial
    final partes = operario.trim().split(' ');
    String iniciales = partes.isNotEmpty && partes[0].isNotEmpty ? partes[0][0] : "U";
    if (partes.length > 1 && partes[1].isNotEmpty) {
      iniciales += partes[1][0];
    }
    iniciales = iniciales.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AgroTheme.colorSurface,
        borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
        border: Border.all(
          color: activo ? AgroTheme.colorBorder : const Color(0xFFFFCDD2),
          width: 1.1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04141E18),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Encabezado Ficha: Avatar + Nombre + Estado
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: activo
                      ? (esAdmin ? const Color(0xFFFFF8E1) : const Color(0xFFE8F5E9))
                      : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activo
                        ? (esAdmin ? const Color(0xFFFFECB3) : const Color(0xFFC8E6C9))
                        : const Color(0xFFFFCDD2),
                  ),
                ),
                child: Center(
                  child: Text(
                    iniciales,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: activo
                          ? (esAdmin ? const Color(0xFF8A6A1E) : const Color(0xFF2E7D32))
                          : const Color(0xFFC62828),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      operario,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AgroTheme.colorText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: esAdmin
                                ? const Color(0xFFFFF8E1)
                                : const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            rol,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: esAdmin
                                  ? const Color(0xFF8A6A1E)
                                  : const Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: activo
                                ? const Color(0xFFE8F5E9)
                                : const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            estado,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: activo
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFC62828),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Botón de opciones rápidas (Compartir Credencial WhatsApp)
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 19, color: Color(0xFF2E7D32)),
                tooltip: "Enviar credenciales",
                onPressed: () => _mostrarSelectorReenvio(u),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Cuerpo: Credenciales y Device
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AgroTheme.colorBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "Login: $correo",
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AgroTheme.colorTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      "Clave: $pass",
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AgroTheme.colorText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      device.isNotEmpty
                          ? Icons.android_rounded
                          : Icons.apple_rounded,
                      size: 13,
                      color: AgroTheme.colorTextSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        device.isNotEmpty
                            ? "ID Vinculado: $device"
                            : "iPhone (Safari PWA) / Web",
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: device.isNotEmpty ? 'monospace' : null,
                          color: device.isNotEmpty
                              ? const Color(0xFF2E7D32)
                              : AgroTheme.colorTextSecondary,
                          fontWeight: device.isNotEmpty ? FontWeight.w700 : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Barra inferior de acciones: Dar de Baja / Reactivar, Editar y Eliminar
          Row(
            children: [
              // Botón de Estado (Baja / Reactivar)
              Expanded(
                child: InkWell(
                  onTap: () => _alternarEstadoUsuario(u),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6.5),
                    decoration: BoxDecoration(
                      color: activo
                          ? const Color(0xFFFFEBEE)
                          : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: activo
                            ? const Color(0xFFFFCDD2)
                            : const Color(0xFFC8E6C9),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        activo ? "Dar de Baja" : "Reactivar",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: activo
                              ? const Color(0xFFC62828)
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botón Editar
              InkWell(
                onTap: () => _mostrarModalUsuario(usuarioExistente: u),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AgroTheme.colorBorder),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 14, color: AgroTheme.colorText),
                      SizedBox(width: 4),
                      Text(
                        "Editar",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AgroTheme.colorText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Botón Eliminar
              InkWell(
                onTap: () => _eliminarUsuario(u),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6.5),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AgroTheme.colorBorder),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 15,
                    color: Color(0xFFC62828),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}