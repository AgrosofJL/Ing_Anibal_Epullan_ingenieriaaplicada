import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

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

  String _urlIphone = "https://agrosofjl.github.io/Ing_Anibal_Epullan_ingenieriaaplicada/";
  String _urlAndroid = "https://agrosofjl.github.io/Ing_Anibal_Epullan_ingenieriaaplicada/";

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
🌱 *AGROSOFT J&L · ACCESO AL SISTEMA*
Hola *$operario*, acá tenés tu cuenta para ingresar al establecimiento *${widget.nombreProductor}*:

📱 *Plataforma:* ${esIphone ? "iPhone / iPad (Safari PWA)" : "Android (APK)"}
🌐 *Link de Instalación:* $enlaceDescarga

👤 *Usuario / Email:* $correo
🔑 *Contraseña:* $pass
🔰 *Rol:* $rol$detalleDevice
*Pasos de instalación:*
$guiaInstalacion
''';

    Share.share(mensaje, subject: 'Acceso AgroSoft - ${widget.nombreProductor}');
  }

  // ===========================================================================
  // MODAL ALTA / EDICIÓN DE USUARIO
  // ===========================================================================
  void _mostrarModalUsuario({Map<String, dynamic>? usuarioExistente}) {
    final bool esEdicion = usuarioExistente != null;
    final formKey = GlobalKey<FormState>();

    final operarioCtrl = TextEditingController(text: usuarioExistente?['operario'] ?? '');
    final correoCtrl = TextEditingController(text: usuarioExistente?['correo'] ?? '');
    final passCtrl = TextEditingController(text: usuarioExistente?['pass'] ?? '1234');
    final deviceCtrl = TextEditingController(text: usuarioExistente?['device'] ?? '');

    String rolVisual = (usuarioExistente?['rol'] ?? '').toString().contains('ADMIN')
        ? "ADMINISTRADOR"
        : "OPERARIO";
    String estadoSeleccionado = (usuarioExistente?['estado'] ?? 'ACTIVO').toString().toUpperCase();

    // Si ya tiene device asignado o no es edición, predeterminamos según corresponda
    String plataformaSeleccionada = (usuarioExistente?['device'] ?? '').toString().isNotEmpty
        ? "ANDROID"
        : "IPHONE";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.90,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              esEdicion ? "Modificar Usuario" : "Nuevo Usuario de Campo",
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AgroTheme.colorText),
                            ),
                            Text(
                              widget.nombreProductor,
                              style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary),
                            ),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const Divider(color: AgroTheme.colorBorder),
                    const SizedBox(height: 10),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Dispositivo del Usuario (Para envío de app):",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AgroTheme.colorAccentDark)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: plataformaSeleccionada,
                              decoration: _inputDecoration("Plataforma / Teléfono", Icons.phone_iphone_rounded),
                              items: const [
                                DropdownMenuItem(
                                  value: "IPHONE",
                                  child: Row(
                                    children: [
                                      Icon(Icons.apple_rounded, size: 18, color: Colors.black87),
                                      SizedBox(width: 8),
                                      Text("iPhone / iPad (Safari PWA)"),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: "ANDROID",
                                  child: Row(
                                    children: [
                                      Icon(Icons.android_rounded, size: 18, color: Color(0xFF3DDC84)),
                                      SizedBox(width: 8),
                                      Text("Android (Instalador / APK)"),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                setModalState(() {
                                  plataformaSeleccionada = v ?? "IPHONE";
                                  if (plataformaSeleccionada == "IPHONE") {
                                    deviceCtrl.clear();
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 14),

                            // ACA ES LO NUEVO: Campo Device ID exclusivo si elige Android
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
                                          "Device ID (Vinculación Hardware):",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: AgroTheme.colorAccentDark,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () async {
                                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                                            if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                              setModalState(() {
                                                deviceCtrl.text = data.text!.trim();
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Device ID pegado desde portapapeles')),
                                              );
                                            }
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            child: Row(
                                              children: const [
                                                Icon(Icons.paste_rounded, size: 16, color: AgroTheme.colorAccentDark),
                                                SizedBox(width: 4),
                                                Text(
                                                  "Pegar",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: AgroTheme.colorAccentDark,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: deviceCtrl,
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                                      decoration: _inputDecoration("Pegá el identificador recibido", Icons.phonelink_lock_rounded),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      "Si el operario aún no instaló la app, dejalo vacío. Podrás pegarlo al recibirlo.",
                                      style: TextStyle(fontSize: 10.5, color: AgroTheme.colorTextSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            const Text("Datos de Acceso:",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AgroTheme.colorGold)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: operarioCtrl,
                              decoration: _inputDecoration("Nombre y Apellido", Icons.person_outline),
                              validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: correoCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDecoration("Correo Electrónico (Login)", Icons.mail_outline),
                              validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: passCtrl,
                                    decoration: _inputDecoration("Contraseña", Icons.lock_outline),
                                    validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: rolVisual,
                                    decoration: _inputDecoration("Rol", Icons.shield_outlined),
                                    items: const [
                                      DropdownMenuItem(value: "ADMINISTRADOR", child: Text("Admin")),
                                      DropdownMenuItem(value: "OPERARIO", child: Text("Operario")),
                                    ],
                                    onChanged: (v) => setModalState(() => rolVisual = v ?? "OPERARIO"),
                                  ),
                                ),
                              ],
                            ),
                            if (esEdicion) ...[
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                value: estadoSeleccionado,
                                decoration: _inputDecoration("Estado de Acceso", Icons.toggle_on_outlined),
                                items: const [
                                  DropdownMenuItem(value: "ACTIVO", child: Text("ACTIVO")),
                                  DropdownMenuItem(value: "INACTIVO", child: Text("INACTIVO (Bloqueado)")),
                                ],
                                onChanged: (v) => setModalState(() => estadoSeleccionado = v ?? "ACTIVO"),
                              ),
                            ],
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: SoftButton(
                        onTap: () async {
                          if (!formKey.currentState!.validate()) return;
                          final db = await DatabaseHelper.instance.database;

                          final String rolFinal = rolVisual == 'ADMINISTRADOR' ? 'PROD-ADMIN' : 'PROD-OPE';
                          final String finalDevice = plataformaSeleccionada == "ANDROID"
                              ? deviceCtrl.text.trim()
                              : '';

                          if (esEdicion) {
                            final int userId = int.parse(usuarioExistente['id'].toString());
                            final rowUpdate = {
                              'correo': correoCtrl.text.trim(),
                              'operario': operarioCtrl.text.trim(),
                              'device': finalDevice,
                              'pass': passCtrl.text.trim(),
                              'rol': rolFinal,
                              'estado': estadoSeleccionado,
                            };

                            await db.update('usuarios', rowUpdate, where: 'id = ?', whereArgs: [userId]);
                            await _sincronizarRemotoUsuario({
                              'id': userId,
                              'cod_productor': widget.codProductor,
                              ...rowUpdate,
                            });

                            if (mounted) {
                              Navigator.pop(ctx);
                              _cargarUsuarios();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(backgroundColor: AgroTheme.colorAccent, content: Text("Usuario actualizado correctamente.")),
                              );
                            }
                          } else {
                            final int sigUserId = await DatabaseHelper.instance.obtenerSiguienteId('usuarios', 'id');

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

                            if (mounted) {
                              Navigator.pop(ctx);
                              _cargarUsuarios();

                              _compartirCredencialesWhatsApp(
                                operario: rowUser['operario'] as String,
                                correo: rowUser['correo'] as String,
                                pass: rowUser['pass'] as String,
                                rol: rolFinal,
                                plataforma: plataformaSeleccionada,
                                device: finalDevice,
                              );
                            }
                          }
                        },
                        child: Center(
                          child: Text(
                            esEdicion ? "Guardar Cambios" : "Guardar y Enviar Accesos",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: AgroTheme.colorSurface,
      builder: (bCtx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Enviar Acceso a ${u['operario']}",
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AgroTheme.colorText)),
              const SizedBox(height: 6),
              const Text("Elegí el dispositivo que usará para adjuntar el enlace e instrucciones correspondientes:",
                  style: TextStyle(fontSize: 12.5, color: AgroTheme.colorTextSecondary)),
              const SizedBox(height: 18),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AgroTheme.colorBg,
                leading: const Icon(Icons.apple_rounded, size: 28, color: Colors.black87),
                title: const Text("iPhone / iPad (Apple)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text("Envía enlace de Safari PWA (omite Device ID)", style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
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
              const SizedBox(height: 10),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AgroTheme.colorBg,
                leading: const Icon(Icons.android_rounded, size: 28, color: Color(0xFF3DDC84)),
                title: const Text("Android", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(
                  (u['device'] ?? '').toString().isNotEmpty
                      ? "Device ID vinculado: ${u['device']}"
                      : "Envía el instalador APK y guía de vinculación",
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
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

  Future<void> _eliminarUsuario(Map<String, dynamic> u) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("¿Eliminar usuario?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text("Se revocará definitivamente el acceso de ${u['operario']}."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AgroTheme.colorDanger),
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

      _cargarUsuarios();
    }
  }

  InputDecoration _inputDecoration(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12.5, color: AgroTheme.colorTextSecondary),
      prefixIcon: Icon(icono, size: 18, color: AgroTheme.colorTextSecondary),
      filled: true,
      fillColor: AgroTheme.colorBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AppBar(
        backgroundColor: AgroTheme.colorSurface.withOpacity(0.92),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Usuarios de Campo",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText),
            ),
            Text(
              widget.nombreProductor,
              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border: Border.all(color: AgroTheme.colorBorder),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _filtroTexto = v),
                  style: const TextStyle(color: AgroTheme.colorText, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Buscar por nombre, correo, rol o device...",
                    hintStyle: TextStyle(color: AgroTheme.colorTextSecondary, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, color: AgroTheme.colorTextSecondary, size: 20),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: AgroTheme.colorAccent))
                  : _usuariosFiltrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.people_outline_rounded, size: 48, color: AgroTheme.colorTextSecondary),
                              const SizedBox(height: 10),
                              Text(
                                "No hay usuarios registrados para ${widget.nombreProductor}.",
                                style: const TextStyle(color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 85),
                          itemCount: _usuariosFiltrados.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final u = _usuariosFiltrados[idx];
                            final String rol = u['rol'] ?? 'PROD-OPE';
                            final bool esAdmin = rol.contains('ADMIN');
                            final bool activo = (u['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'ACTIVO';
                            final String device = (u['device'] ?? '').toString();

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AgroTheme.colorSurface,
                                borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                                border: Border.all(color: AgroTheme.colorBorder),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x04141E18), blurRadius: 8, offset: Offset(0, 2)),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: (esAdmin ? AgroTheme.colorGold : AgroTheme.colorAccent).withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      esAdmin ? Icons.admin_panel_settings_outlined : Icons.engineering_outlined,
                                      size: 22,
                                      color: esAdmin ? AgroTheme.colorGold : AgroTheme.colorAccentDark,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                u['operario'] ?? 'Sin Nombre',
                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AgroTheme.colorText),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: activo ? AgroTheme.colorAccentSoft : AgroTheme.colorDanger.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                u['estado'] ?? 'ACTIVO',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: activo ? AgroTheme.colorAccentDark : AgroTheme.colorDanger,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text("Usuario: ${u['correo']}", style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary)),
                                        Text("Clave: ${u['pass']}", style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500)),
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AgroTheme.colorBg,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: AgroTheme.colorBorder),
                                              ),
                                              child: Text(
                                                rol,
                                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AgroTheme.colorText),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            if (device.isNotEmpty)
                                              Expanded(
                                                child: Text(
                                                  "ID: $device",
                                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: AgroTheme.colorAccentDark, fontWeight: FontWeight.bold),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              )
                                            else
                                              const Text(
                                                "Web / Safari PWA",
                                                style: TextStyle(fontSize: 10, color: AgroTheme.colorTextSecondary, fontStyle: FontStyle.italic),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.share_outlined, size: 20, color: AgroTheme.colorAccentDark),
                                        tooltip: "Compartir Acceso por WhatsApp",
                                        onPressed: () => _mostrarSelectorReenvio(u),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 18, color: AgroTheme.colorTextSecondary),
                                            tooltip: "Editar",
                                            onPressed: () => _mostrarModalUsuario(usuarioExistente: u),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AgroTheme.colorDanger),
                                            tooltip: "Eliminar",
                                            onPressed: () => _eliminarUsuario(u),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: SoftButton(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        borderRadius: 28,
        onTap: () => _mostrarModalUsuario(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text("Nuevo Usuario", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}