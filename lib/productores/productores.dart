import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';
import 'usuarios.dart';

class ProductoresScreen extends StatefulWidget {
  const ProductoresScreen({super.key});

  @override
  State<ProductoresScreen> createState() => _ProductoresScreenState();
}

class _ProductoresScreenState extends State<ProductoresScreen> {
  bool _cargando = true;
  String _userRole = "OPERARIO";
  List<Map<String, dynamic>> _productores = [];
  Map<int, int> _conteoUsuariosPorProd = {};
  String _filtroTexto = "";
  final TextEditingController _searchCtrl = TextEditingController();

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
    _userRole = (prefs.getString('userRole') ?? "OPERARIO").toUpperCase().trim();

    if (!_esAdminOIngeniero) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Acceso exclusivo para Administradores o Ingenieros"),
          ),
        );
      }
      return;
    }

    await _cargarProductores();
  }

  bool get _esAdminOIngeniero =>
      _userRole == 'ADMIN' || _userRole == 'ADM' || _userRole == 'INGENIERO';

  Future<void> _cargarProductores() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final resProds = await db.query(
      'productores',
      orderBy: 'productor ASC',
    );

    // Conteo de usuarios asociados por cada productor
    final resConteo = await db.rawQuery('''
      SELECT cod_productor, COUNT(*) as total 
      FROM usuarios 
      WHERE cod_productor IS NOT NULL 
      GROUP BY cod_productor
    ''');

    final Map<int, int> conteoMap = {};
    for (var row in resConteo) {
      final cp = int.tryParse(row['cod_productor']?.toString() ?? '0') ?? 0;
      final total = int.tryParse(row['total']?.toString() ?? '0') ?? 0;
      if (cp > 0) conteoMap[cp] = total;
    }

    if (!mounted) return;
    setState(() {
      _productores = resProds;
      _conteoUsuariosPorProd = conteoMap;
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

  void _navegarAUsuarios(Map<String, dynamic> prod) {
    final int codProd = int.tryParse(prod['cod_productor']?.toString() ?? '0') ?? 0;
    final String nombreProd = (prod['productor'] ?? 'Establecimiento').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UsuariosScreen(
          codProductor: codProd,
          nombreProductor: nombreProd,
        ),
      ),
    ).then((_) => _cargarProductores());
  }

  void _mostrarModalDetalleYEdicion(Map<String, dynamic> prodOriginal) {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController(text: prodOriginal['productor'] ?? '');
    final cuitCtrl = TextEditingController(text: prodOriginal['cuit'] ?? '');
    final renspaCtrl = TextEditingController(text: prodOriginal['renspa'] ?? '');
    final localidadCtrl = TextEditingController(text: prodOriginal['localidad'] ?? 'Chimpay');
    String estadoSeleccionado =
        (prodOriginal['estado'] ?? 'ACTIVO').toString().trim().toUpperCase();

    bool guardando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.85,
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
                                prodOriginal['productor'] ?? 'Detalle Productor',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16.5,
                                  color: AgroTheme.colorText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Código de Establecimiento: #${prodOriginal['cod_productor']}",
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
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: nombreCtrl,
                              decoration: _inputDecoration(
                                "Razón Social / Productor",
                                Icons.business_outlined,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? "Obligatorio"
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: cuitCtrl,
                                    decoration: _inputDecoration(
                                      "CUIT",
                                      Icons.fingerprint_rounded,
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? "Obligatorio"
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: renspaCtrl,
                                    decoration: _inputDecoration(
                                      "RENSPA",
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: localidadCtrl,
                              decoration: _inputDecoration(
                                "Localidad / Zona",
                                Icons.location_on_outlined,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              "Estado de Habilitación:",
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Text("ACTIVO"),
                                  selected: estadoSeleccionado == "ACTIVO",
                                  selectedColor: const Color(0xFFE8F5E9),
                                  labelStyle: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: estadoSeleccionado == "ACTIVO"
                                        ? const Color(0xFF2E7D32)
                                        : AgroTheme.colorTextSecondary,
                                  ),
                                  backgroundColor: AgroTheme.colorBg,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: estadoSeleccionado == "ACTIVO"
                                          ? const Color(0xFFA5D6A7)
                                          : AgroTheme.colorBorder,
                                    ),
                                  ),
                                  onSelected: (val) {
                                    if (val) {
                                      setModalState(() => estadoSeleccionado = "ACTIVO");
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text("INACTIVO"),
                                  selected: estadoSeleccionado == "INACTIVO",
                                  selectedColor: const Color(0xFFFFEBEE),
                                  labelStyle: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: estadoSeleccionado == "INACTIVO"
                                        ? const Color(0xFFC62828)
                                        : AgroTheme.colorTextSecondary,
                                  ),
                                  backgroundColor: AgroTheme.colorBg,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: estadoSeleccionado == "INACTIVO"
                                          ? const Color(0xFFEF9A9A)
                                          : AgroTheme.colorBorder,
                                    ),
                                  ),
                                  onSelected: (val) {
                                    if (val) {
                                      setModalState(() => estadoSeleccionado = "INACTIVO");
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: SoftButton(
                        onTap: guardando
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => guardando = true);
                                final db = await DatabaseHelper.instance.database;

                                final int codProd = int.parse(
                                    prodOriginal['cod_productor'].toString());

                                final rowActualizada = {
                                  'cod_productor': codProd,
                                  'productor': nombreCtrl.text.trim(),
                                  'cuit': cuitCtrl.text.trim(),
                                  'renspa': renspaCtrl.text.trim(),
                                  'localidad': localidadCtrl.text.trim(),
                                  'estado': estadoSeleccionado,
                                };

                                await db.update(
                                  'productores',
                                  rowActualizada,
                                  where: 'cod_productor = ?',
                                  whereArgs: [codProd],
                                );

                                try {
                                  await Supabase.instance.client
                                      .from('productores')
                                      .upsert(rowActualizada);
                                } catch (e) {
                                  debugPrint("Aviso sync update productor: $e");
                                }

                                if (!mounted) return;
                                Navigator.pop(ctx);
                                await _cargarProductores();

                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: AgroTheme.colorAccent,
                                    content: Text("Establecimiento actualizado"),
                                  ),
                                );
                              },
                        child: Center(
                          child: guardando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Text(
                                  "Guardar Cambios",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
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

  void _mostrarModalNuevoProductor() {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    final cuitCtrl = TextEditingController();
    final renspaCtrl = TextEditingController();
    final localidadCtrl = TextEditingController(text: "Chimpay");
    final correoCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: "1234");
    final operarioCtrl = TextEditingController();

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
                        const Text(
                          "Alta de Productor y Acceso",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                            color: AgroTheme.colorText,
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
                              "DATOS DEL ESTABLECIMIENTO",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: nombreCtrl,
                              decoration: _inputDecoration(
                                "Razón Social / Nombre",
                                Icons.business_outlined,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: cuitCtrl,
                                    decoration: _inputDecoration(
                                      "CUIT",
                                      Icons.fingerprint_rounded,
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? "Obligatorio"
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: renspaCtrl,
                                    decoration: _inputDecoration(
                                      "RENSPA",
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: localidadCtrl,
                              decoration: _inputDecoration(
                                "Localidad / Ubicación",
                                Icons.location_on_outlined,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              "CREDENCIALES DE ACCESO (OPERARIO/PRODUCTOR)",
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
                                "Nombre del Encargado",
                                Icons.person_outline_rounded,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: correoCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDecoration(
                                "Correo Electrónico (Usuario Login)",
                                Icons.mail_outline_rounded,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: passCtrl,
                              decoration: _inputDecoration(
                                "Contraseña de Acceso",
                                Icons.lock_outline_rounded,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: SoftButton(
                        onTap: guardando
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => guardando = true);
                                final db = await DatabaseHelper.instance.database;

                                final int sigProdId = await DatabaseHelper.instance
                                    .obtenerSiguienteId('productores', 'cod_productor');
                                final int sigUserId = await DatabaseHelper.instance
                                    .obtenerSiguienteId('usuarios', 'id');

                                final rowProd = {
                                  'cod_productor': sigProdId,
                                  'productor': nombreCtrl.text.trim(),
                                  'cuit': cuitCtrl.text.trim(),
                                  'renspa': renspaCtrl.text.trim(),
                                  'localidad': localidadCtrl.text.trim(),
                                  'estado': 'ACTIVO',
                                };

                                final rowUser = {
                                  'id': sigUserId,
                                  'correo': correoCtrl.text.trim().toLowerCase(),
                                  'operario': operarioCtrl.text.trim(),
                                  'pass': passCtrl.text.trim(),
                                  'rol': 'PROD-ADMIN',
                                  'estado': 'ACTIVO',
                                  'cod_productor': sigProdId,
                                };

                                await db.insert('productores', rowProd);
                                await db.insert('usuarios', rowUser);

                                try {
                                  await Supabase.instance.client
                                      .from('productores')
                                      .insert(rowProd);
                                  await Supabase.instance.client
                                      .from('usuarios')
                                      .insert(rowUser);
                                } catch (e) {
                                  debugPrint("Aviso sync alta productor: $e");
                                }

                                if (!mounted) return;
                                Navigator.pop(ctx);
                                await _cargarProductores();

                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: AgroTheme.colorAccent,
                                    content: Text("Productor y cuenta creados correctamente"),
                                  ),
                                );
                              },
                        child: Center(
                          child: guardando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Text(
                                  "Registrar Productor",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
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

  InputDecoration _inputDecoration(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontSize: 12.5,
        color: AgroTheme.colorTextSecondary,
      ),
      prefixIcon: Icon(
        icono,
        size: 18,
        color: AgroTheme.colorTextSecondary,
      ),
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
    final bool esDesktop = ancho >= 900;

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
        title: const Text(
          "Gestión de Productores",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AgroTheme.colorText,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    esDesktop ? 28 : 16,
                    14,
                    esDesktop ? 28 : 16,
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
                        hintText: "Buscar por razón social, CUIT, RENSPA o localidad...",
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
                          child: CircularProgressIndicator(
                            color: Color(0xFF1E6B4C),
                          ),
                        )
                      : _productoresFiltrados.isEmpty
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
                                      Icons.agriculture_rounded,
                                      size: 38,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    "No se encontraron productores",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5,
                                      color: AgroTheme.colorText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "Podés incorporar uno nuevo con el botón inferior.",
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AgroTheme.colorTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                esDesktop ? 28 : 16,
                                4,
                                esDesktop ? 28 : 16,
                                80,
                              ),
                              itemCount: _productoresFiltrados.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, idx) {
                                final prod = _productoresFiltrados[idx];
                                return _buildProductorListItem(prod);
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
        onPressed: _mostrarModalNuevoProductor,
        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
        label: const Text(
          "Nuevo Productor",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildProductorListItem(Map<String, dynamic> prod) {
    final String nombre = prod['productor'] ?? 'Sin Nombre';
    final String cuit = prod['cuit'] ?? 'S/D';
    final String renspa = prod['renspa'] ?? 'S/D';
    final String localidad = prod['localidad'] ?? 'S/D';
    final String estado = (prod['estado'] ?? 'ACTIVO').toString().trim().toUpperCase();
    final bool esActivo = estado == 'ACTIVO';
    final int codProd = int.tryParse(prod['cod_productor']?.toString() ?? '0') ?? 0;
    final int cantUsuarios = _conteoUsuariosPorProd[codProd] ?? 0;

    return InkWell(
      // 💡 Al tocar la fila abre la pantalla de usuarios del productor
      onTap: () => _navegarAUsuarios(prod),
      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
          border: Border.all(color: AgroTheme.colorBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x03141E18),
              blurRadius: 4,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: esActivo ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.business_outlined,
                color: esActivo ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                size: 20,
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
                          nombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AgroTheme.colorText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Insignia de usuarios vinculados
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_outline_rounded,
                                size: 12, color: Color(0xFF1565C0)),
                            const SizedBox(width: 3),
                            Text(
                              "$cantUsuarios",
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Estado
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: esActivo ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          estado,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: esActivo ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "CUIT: $cuit  ·  RENSPA: $renspa",
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AgroTheme.colorTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: AgroTheme.colorTextSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            localidad,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AgroTheme.colorTextSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Botón de edición rápida de la razón social / establecimiento
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: AgroTheme.colorTextSecondary),
              tooltip: "Modificar establecimiento",
              onPressed: () => _mostrarModalDetalleYEdicion(prod),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AgroTheme.colorTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}