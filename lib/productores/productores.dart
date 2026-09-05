import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'usuarios.dart';
import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

class ProductoresScreen extends StatefulWidget {
  const ProductoresScreen({super.key});

  @override
  State<ProductoresScreen> createState() => _ProductoresScreenState();
}

class _ProductoresScreenState extends State<ProductoresScreen> {
  bool _cargando = true;
  String _userRole = "OPERARIO";
  List<Map<String, dynamic>> _productores = [];
  Map<int, List<Map<String, dynamic>>> _usuariosPorProductor = {};
  String _filtroTexto = "";
  final TextEditingController _searchCtrl = TextEditingController();

  final String _appWebUrl = "https://agrosofjl.github.io/Ing_Anibal_Epullan_ingenieriaaplicada/";

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
    final prefs = await SharedPreferences.getInstance();
    _userRole = (prefs.getString('userRole') ?? "OPERARIO").toUpperCase();

    if (_userRole != 'ADMIN' && _userRole != 'INGENIERO') {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AgroTheme.colorDanger,
            content: Text("Acceso exclusivo para Administradores o Ingenieros"),
          ),
        );
      }
      return;
    }

    await _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final resProd = await db.query(
      'productores',
      orderBy: 'productor ASC',
    );

    final resUsers = await db.query('usuarios');
    final Map<int, List<Map<String, dynamic>>> mapaUsuarios = {};

    for (var u in resUsers) {
      final cp = u['cod_productor'] != null ? int.tryParse(u['cod_productor'].toString()) : null;
      if (cp != null) {
        if (!mapaUsuarios.containsKey(cp)) {
          mapaUsuarios[cp] = [];
        }
        mapaUsuarios[cp]!.add(u);
      }
    }

    if (!mounted) return;
    setState(() {
      _productores = resProd;
      _usuariosPorProductor = mapaUsuarios;
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _productoresFiltrados {
    if (_filtroTexto.isEmpty) return _productores;
    final q = _filtroTexto.toLowerCase();
    return _productores.where((p) {
      final nom = (p['productor'] ?? '').toString().toLowerCase();
      final cuit = (p['cuit'] ?? '').toString().toLowerCase();
      final ren = (p['renspa'] ?? '').toString().toLowerCase();
      final loc = (p['localidad'] ?? '').toString().toLowerCase();
      return nom.contains(q) || cuit.contains(q) || ren.contains(q) || loc.contains(q);
    }).toList();
  }

  // Sincronización transparente con Supabase
  Future<void> _sincronizarRemoto(String tabla, Map<String, dynamic> datos, {String? campoId, dynamic valorId}) async {
    try {
      final supabase = Supabase.instance.client;
      if (campoId != null && valorId != null) {
        await supabase.from(tabla).upsert(datos);
      } else {
        await supabase.from(tabla).insert(datos);
      }
    } catch (e) {
      debugPrint("Aviso sync remoto en $tabla (se conserva local): $e");
    }
  }

  // 💡 ENVÍO DE CREDENCIALES POR WHATSAPP / MENSAJE
  void _compartirAccesoApp({
    required String productor,
    required String operario,
    required String correo,
    required String pass,
    required String rol,
  }) {
    final mensaje = '''
🌱 *AGROSOFT J&L · ACCESO AL SISTEMA DE GESTIÓN*
Hola *$operario*, te compartimos las credenciales de acceso para *$productor*:

🌐 *Enlace de la App:* $_appWebUrl
👤 *Usuario:* $correo
🔑 *Contraseña:* $pass
🔰 *Rol Asignado:* $rol

_Recomendación en iPhone / Safari:_
1. Abrí el enlace en Safari.
2. Tocá el botón compartir (cuadrado con flecha).
3. Seleccioná "Agregar a pantalla de inicio".
''';

    Share.share(mensaje, subject: 'Acceso AgroSoft - $productor');
  }

  // ===========================================================================
  // MODAL ALTA / EDICIÓN DE PRODUCTOR
  // ===========================================================================
  void _mostrarModalProductor({Map<String, dynamic>? productorExistente}) {
    final bool esEdicion = productorExistente != null;
    final formKey = GlobalKey<FormState>();

    final nombreCtrl = TextEditingController(text: productorExistente?['productor'] ?? '');
    final cuitCtrl = TextEditingController(text: productorExistente?['cuit'] ?? '');
    final renspaCtrl = TextEditingController(text: productorExistente?['renspa'] ?? '');
    final localidadCtrl = TextEditingController(text: productorExistente?['localidad'] ?? 'Chimpay');
    String estadoSeleccionado = (productorExistente?['estado'] ?? 'ACTIVO').toString().toUpperCase();

    // Campos de usuario si es creación nueva
    final operarioCtrl = TextEditingController();
    final correoCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: "1234");
    String rolVisual = "ADMINISTRADOR"; // Puede ser ADMINISTRADOR u OPERARIO

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
                        Text(
                          esEdicion ? "Editar Productor" : "Nuevo Productor y Usuario",
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AgroTheme.colorText),
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
                            const Text("Datos del Establecimiento:",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AgroTheme.colorAccentDark)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: nombreCtrl,
                              decoration: _inputDecoration("Razón Social / Productor", Icons.business_outlined),
                              validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: cuitCtrl,
                                    decoration: _inputDecoration("CUIT", Icons.badge_outlined),
                                    validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: renspaCtrl,
                                    decoration: _inputDecoration("RENSPA", Icons.confirmation_number_outlined),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: localidadCtrl,
                                    decoration: _inputDecoration("Localidad", Icons.location_on_outlined),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    value: estadoSeleccionado,
                                    decoration: _inputDecoration("Estado", Icons.toggle_on_outlined),
                                    items: const [
                                      DropdownMenuItem(value: "ACTIVO", child: Text("ACTIVO")),
                                      DropdownMenuItem(value: "INACTIVO", child: Text("INACTIVO")),
                                    ],
                                    onChanged: (v) => setModalState(() => estadoSeleccionado = v ?? "ACTIVO"),
                                  ),
                                ),
                              ],
                            ),

                            if (!esEdicion) ...[
                              const SizedBox(height: 20),
                              const Text("Usuario de Ingreso Inicial:",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AgroTheme.colorGold)),
                              const SizedBox(height: 4),
                              const Text(
                                "El sistema mapea el rol automáticamente con prefijo PROD- para aislar permisos.",
                                style: TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary),
                              ),
                              const SizedBox(height: 10),
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
                                    flex: 3,
                                    child: TextFormField(
                                      controller: passCtrl,
                                      decoration: _inputDecoration("Contraseña", Icons.lock_outline),
                                      validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      value: rolVisual,
                                      decoration: _inputDecoration("Rol", Icons.shield_outlined),
                                      items: const [
                                        DropdownMenuItem(value: "ADMINISTRADOR", child: Text("Admin Prod")),
                                        DropdownMenuItem(value: "OPERARIO", child: Text("Operario")),
                                      ],
                                      onChanged: (v) => setModalState(() => rolVisual = v ?? "ADMINISTRADOR"),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
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

                          if (esEdicion) {
                            final int codP = int.parse(productorExistente['cod_productor'].toString());
                            final Map<String, dynamic> updateData = {
                              'productor': nombreCtrl.text.trim(),
                              'cuit': cuitCtrl.text.trim(),
                              'renspa': renspaCtrl.text.trim(),
                              'localidad': localidadCtrl.text.trim(),
                              'estado': estadoSeleccionado,
                            };

                            await db.update('productores', updateData, where: 'cod_productor = ?', whereArgs: [codP]);
                            await _sincronizarRemoto('productores', {'cod_productor': codP, ...updateData}, campoId: 'cod_productor', valorId: codP);

                            if (mounted) {
                              Navigator.pop(ctx);
                              _cargarDatos();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(backgroundColor: AgroTheme.colorAccent, content: Text('Productor actualizado correctamente')),
                              );
                            }
                          } else {
                            final int sigProdId = await DatabaseHelper.instance.obtenerSiguienteId('productores', 'cod_productor');
                            final int sigUserId = await DatabaseHelper.instance.obtenerSiguienteId('usuarios', 'id');

                            final Map<String, dynamic> rowProd = {
                              'cod_productor': sigProdId,
                              'productor': nombreCtrl.text.trim(),
                              'cuit': cuitCtrl.text.trim(),
                              'renspa': renspaCtrl.text.trim(),
                              'nro_control': 1,
                              'localidad': localidadCtrl.text.trim(),
                              'estado': estadoSeleccionado,
                            };

                            // Mapeo dinámico: ADMIN -> PROD-ADMIN | OPERARIO -> PROD-OPE
                            final String rolFinal = rolVisual == 'ADMINISTRADOR' ? 'PROD-ADMIN' : 'PROD-OPE';

                            final Map<String, dynamic> rowUser = {
                              'id': sigUserId,
                              'correo': correoCtrl.text.trim(),
                              'operario': operarioCtrl.text.trim(),
                              'device': '',
                              'pass': passCtrl.text.trim(),
                              'rol': rolFinal,
                              'estado': 'ACTIVO',
                              'cod_productor': sigProdId,
                            };

                            await db.insert('productores', rowProd);
                            await db.insert('usuarios', rowUser);

                            await _sincronizarRemoto('productores', rowProd, campoId: 'cod_productor', valorId: sigProdId);
                            await _sincronizarRemoto('usuarios', rowUser, campoId: 'id', valorId: sigUserId);

                            if (mounted) {
                              Navigator.pop(ctx);
                              _cargarDatos();

                              // Invitar a compartir inmediatamente por WhatsApp
                              _compartirAccesoApp(
                                productor: rowProd['productor'],
                                operario: rowUser['operario'],
                                correo: rowUser['correo'],
                                pass: rowUser['pass'],
                                rol: rolFinal,
                              );
                            }
                          }
                        },
                        child: Center(
                          child: Text(
                            esEdicion ? "Guardar Modificaciones" : "Guardar y Enviar Accesos",
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

  // ===========================================================================
  // MODAL GESTIÓN DE USUARIOS DEL PRODUCTOR
  // ===========================================================================
  void _mostrarModalUsuariosProductor(Map<String, dynamic> productor) {
    final int codProd = int.parse(productor['cod_productor'].toString());
    final String nombreProd = productor['productor'] ?? 'Productor';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final listaUsuarios = _usuariosPorProductor[codProd] ?? [];

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.all(20),
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
                          Text("Usuarios de Acceso", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AgroTheme.colorText)),
                          Text(nombreProd, style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary)),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.person_add_rounded, color: AgroTheme.colorAccentDark),
                            tooltip: "Agregar Usuario",
                            onPressed: () => _modalCrearUsuarioParaProductor(codProd, nombreProd, () {
                              setSheetState(() {});
                            }),
                          ),
                          IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: AgroTheme.colorBorder),
                  const SizedBox(height: 10),

                  Expanded(
                    child: listaUsuarios.isEmpty
                        ? const Center(
                            child: Text("No hay usuarios creados para este productor.",
                                style: TextStyle(color: AgroTheme.colorTextSecondary, fontSize: 13)),
                          )
                        : ListView.separated(
                            itemCount: listaUsuarios.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, idx) {
                              final u = listaUsuarios[idx];
                              final String rol = u['rol'] ?? 'PROD-OPE';
                              final bool esAdmin = rol.contains('ADMIN');

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AgroTheme.colorBorder),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: (esAdmin ? AgroTheme.colorGold : AgroTheme.colorAccent).withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        esAdmin ? Icons.admin_panel_settings_outlined : Icons.engineering_outlined,
                                        size: 20,
                                        color: esAdmin ? AgroTheme.colorGold : AgroTheme.colorAccentDark,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(u['operario'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          Text("Email: ${u['correo']} · Clave: ${u['pass']}",
                                              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary)),
                                          Container(
                                            margin: const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AgroTheme.colorSurface,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AgroTheme.colorBorder),
                                            ),
                                            child: Text(rol, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.share_outlined, size: 20, color: AgroTheme.colorAccentDark),
                                      tooltip: "Reenviar Datos por WhatsApp",
                                      onPressed: () {
                                        _compartirAccesoApp(
                                          productor: nombreProd,
                                          operario: u['operario'] ?? '',
                                          correo: u['correo'] ?? '',
                                          pass: u['pass'] ?? '',
                                          rol: rol,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AgroTheme.colorDanger),
                                      tooltip: "Eliminar Usuario",
                                      onPressed: () async {
                                        final bool? confirmar = await _dialogoConfirmar("¿Eliminar usuario?", "Se revocará el acceso de ${u['operario']}.");
                                        if (confirmar == true) {
                                          final db = await DatabaseHelper.instance.database;
                                          await db.delete('usuarios', where: 'id = ?', whereArgs: [u['id']]);
                                          try {
                                            await Supabase.instance.client.from('usuarios').delete().eq('id', u['id']);
                                          } catch (_) {}

                                          await _cargarDatos();
                                          setSheetState(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Sub-modal para crear un nuevo usuario dentro de un productor ya existente
  void _modalCrearUsuarioParaProductor(int codProd, String nombreProd, VoidCallback onCreado) {
    final formKey = GlobalKey<FormState>();
    final operarioCtrl = TextEditingController();
    final correoCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: "1234");
    String rolVisual = "OPERARIO";

    showDialog(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (context, setDState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: AgroTheme.colorSurface,
              title: Text("Nuevo Usuario para $nombreProd", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: operarioCtrl,
                      decoration: _inputDecoration("Nombre y Apellido", Icons.person_outline),
                      validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: correoCtrl,
                      decoration: _inputDecoration("Correo / Usuario", Icons.mail_outline),
                      validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passCtrl,
                      decoration: _inputDecoration("Contraseña", Icons.lock_outline),
                      validator: (v) => v == null || v.trim().isEmpty ? "Obligatorio" : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: rolVisual,
                      decoration: _inputDecoration("Rol Interno", Icons.shield_outlined),
                      items: const [
                        DropdownMenuItem(value: "ADMINISTRADOR", child: Text("Admin (PROD-ADMIN)")),
                        DropdownMenuItem(value: "OPERARIO", child: Text("Operario (PROD-OPE)")),
                      ],
                      onChanged: (v) => setDState(() => rolVisual = v ?? "OPERARIO"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("Cancelar")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AgroTheme.colorAccentDark),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final db = await DatabaseHelper.instance.database;
                    final int sigUserId = await DatabaseHelper.instance.obtenerSiguienteId('usuarios', 'id');

                    final String rolFinal = rolVisual == 'ADMINISTRADOR' ? 'PROD-ADMIN' : 'PROD-OPE';
                    final rowUser = {
                      'id': sigUserId,
                      'correo': correoCtrl.text.trim(),
                      'operario': operarioCtrl.text.trim(),
                      'device': '',
                      'pass': passCtrl.text.trim(),
                      'rol': rolFinal,
                      'estado': 'ACTIVO',
                      'cod_productor': codProd,
                    };

                    await db.insert('usuarios', rowUser);
                    await _sincronizarRemoto('usuarios', rowUser, campoId: 'id', valorId: sigUserId);

                    Navigator.pop(dCtx);
                    await _cargarDatos();
                    onCreado();

                    _compartirAccesoApp(
                      productor: nombreProd,
                      operario: rowUser['operario'] as String,
                      correo: rowUser['correo'] as String,
                      pass: rowUser['pass'] as String,
                      rol: rolFinal,
                    );
                  },
                  child: const Text("Crear y Compartir", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool?> _dialogoConfirmar(String titulo, String cuerpo) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(cuerpo),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AgroTheme.colorDanger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text("Confirmar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
        title: const Text(
          "Administración de Productores",
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AgroTheme.colorText),
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
                    hintText: "Buscar por productor, CUIT, RENSPA...",
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
                  : _productoresFiltrados.isEmpty
                      ? const Center(
                          child: Text("No se encontraron productores registrados.",
                              style: TextStyle(color: AgroTheme.colorTextSecondary, fontSize: 14)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 85),
                          itemCount: _productoresFiltrados.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final prod = _productoresFiltrados[idx];
                            final int codP = int.parse(prod['cod_productor'].toString());
                            final int cantUsuarios = (_usuariosPorProductor[codP] ?? []).length;
                            final bool activo = (prod['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'ACTIVO';

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AgroTheme.colorSurface,
                                borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                                border: Border.all(color: AgroTheme.colorBorder),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x04141E18), blurRadius: 8, offset: Offset(0, 2)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          prod['productor'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AgroTheme.colorText),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: activo ? AgroTheme.colorAccentSoft : AgroTheme.colorDanger.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          prod['estado'] ?? 'ACTIVO',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: activo ? AgroTheme.colorAccentDark : AgroTheme.colorDanger,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "CUIT: ${prod['cuit'] ?? 'S/D'}  ·  RENSPA: ${prod['renspa'] ?? 'S/D'}",
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AgroTheme.colorTextSecondary),
                                  ),
                                  Text(
                                    "Localidad: ${prod['localidad'] ?? 'S/D'}",
                                    style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary),
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1, color: AgroTheme.colorBorder),
                                  const SizedBox(height: 8),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      InkWell(
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UsuariosScreen(
          codProductor: int.parse(prod['cod_productor'].toString()),
          nombreProductor: prod['productor'] ?? 'Productor',
        ),
      ),
    ).then((_) => _cargarDatos()); // Recarga al volver para actualizar la cantidad de usuarios
  },
  borderRadius: BorderRadius.circular(8),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    child: Row(
      children: [
        const Icon(Icons.people_alt_outlined, size: 18, color: AgroTheme.colorAccentDark),
        const SizedBox(width: 6),
        Text(
          "$cantUsuarios usuarios asignados",
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AgroTheme.colorAccentDark),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 18, color: AgroTheme.colorAccentDark),
      ],
    ),
  ),
),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 20, color: AgroTheme.colorTextSecondary),
                                            tooltip: "Editar Datos",
                                            onPressed: () => _mostrarModalProductor(productorExistente: prod),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              activo ? Icons.block_flipped : Icons.check_circle_outline,
                                              size: 20,
                                              color: activo ? AgroTheme.colorDanger : AgroTheme.colorAccentDark,
                                            ),
                                            tooltip: activo ? "Desactivar" : "Reactivar",
                                            onPressed: () async {
                                              final String nuevoEst = activo ? 'INACTIVO' : 'ACTIVO';
                                              final bool? conf = await _dialogoConfirmar(
                                                "¿$nuevoEst Productor?",
                                                "El productor pasará a estado $nuevoEst.",
                                              );
                                              if (conf == true) {
                                                final db = await DatabaseHelper.instance.database;
                                                await db.update('productores', {'estado': nuevoEst}, where: 'cod_productor = ?', whereArgs: [codP]);
                                                await _sincronizarRemoto('productores', {'cod_productor': codP, 'estado': nuevoEst}, campoId: 'cod_productor', valorId: codP);
                                                _cargarDatos();
                                              }
                                            },
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
        onTap: () => _mostrarModalProductor(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add_business_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text("Alta Productor", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}