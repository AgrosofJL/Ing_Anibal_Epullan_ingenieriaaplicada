import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

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
    _userRole = (prefs.getString('userRole') ?? "OPERARIO").toUpperCase();

    // Protección de acceso
    if (_userRole != 'ADMIN' && _userRole != 'INGENIERO') {
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

  Future<void> _cargarProductores() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final res = await db.query(
      'productores',
      orderBy: 'productor ASC',
    );

    if (!mounted) return;
    setState(() {
      _productores = res;
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
      return nom.contains(q) || cuit.contains(q) || ren.contains(q);
    }).toList();
  }

  // 💡 Modal para crear un nuevo productor + usuario OPE-PROD
  void _mostrarModalNuevoProductor() {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    final cuitCtrl = TextEditingController();
    final renspaCtrl = TextEditingController();
    final localidadCtrl = TextEditingController(text: "Chimpay");
    final correoCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: "1234");
    final operarioCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
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
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Alta de Productor y Usuario",
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: AgroTheme.colorText),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx)),
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
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AgroTheme.colorAccentDark)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: nombreCtrl,
                          decoration: _inputDecoration("Razón Social / Productor"),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Obligatorio" : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: cuitCtrl,
                                decoration: _inputDecoration("CUIT"),
                                validator: (v) => v == null || v.isEmpty
                                    ? "Obligatorio"
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: renspaCtrl,
                                decoration: _inputDecoration("RENSPA"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: localidadCtrl,
                          decoration: _inputDecoration("Localidad"),
                        ),
                        const SizedBox(height: 18),

                        const Text("Asignar Usuario de Acceso (OPE-PROD):",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AgroTheme.colorGold)),
                        const SizedBox(height: 4),
                        const Text(
                            "Permite que el productor ingrese a su cuenta independiente.",
                            style: TextStyle(
                                fontSize: 11.5,
                                color: AgroTheme.colorTextSecondary)),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: operarioCtrl,
                          decoration: _inputDecoration("Nombre del Operario / Encargado"),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Obligatorio" : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: correoCtrl,
                          decoration:
                              _inputDecoration("Correo Electrónico (Login)"),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Obligatorio" : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: passCtrl,
                          decoration: _inputDecoration("Contraseña"),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Obligatorio" : null,
                        ),
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

                      // Obtener siguiente ID secuencial
                      final int sigProdId = await DatabaseHelper.instance
                          .obtenerSiguienteId('productores', 'cod_productor');
                      final int sigUserId = await DatabaseHelper.instance
                          .obtenerSiguienteId('usuarios', 'id');

                      // 1. Guardar Productor
                      await db.insert('productores', {
                        'cod_productor': sigProdId,
                        'productor': nombreCtrl.text.trim(),
                        'cuit': cuitCtrl.text.trim(),
                        'renspa': renspaCtrl.text.trim(),
                        'localidad': localidadCtrl.text.trim(),
                        'estado': 'ACTIVO',
                      });

                      // 2. Guardar Usuario vinculado con rol OPE-PROD
                      await db.insert('usuarios', {
                        'id': sigUserId,
                        'correo': correoCtrl.text.trim(),
                        'operario': operarioCtrl.text.trim(),
                        'pass': passCtrl.text.trim(),
                        'rol': 'OPE-PROD',
                        'estado': 'ACTIVO',
                        'cod_productor': sigProdId,
                      });

                      if (mounted) {
                        Navigator.pop(ctx);
                        _cargarProductores();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AgroTheme.colorAccent,
                            content: Text(
                                "¡Productor y usuario OPE-PROD creados con éxito!"),
                          ),
                        );
                      }
                    },
                    child: const Center(
                      child: Text(
                        "Guardar Productor y Usuario",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14),
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
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(fontSize: 13, color: AgroTheme.colorTextSecondary),
      filled: true,
      fillColor: AgroTheme.colorBg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: AgroTheme.colorBorder),
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Gestión de Productores",
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: AgroTheme.colorText),
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
                  style:
                      const TextStyle(color: AgroTheme.colorText, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Buscar por nombre, CUIT o RENSPA...",
                    hintStyle: TextStyle(
                        color: AgroTheme.colorTextSecondary, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AgroTheme.colorTextSecondary, size: 20),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _cargando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AgroTheme.colorAccent))
                  : _productoresFiltrados.isEmpty
                      ? const Center(
                          child: Text("No se encontraron productores.",
                              style: TextStyle(
                                  color: AgroTheme.colorTextSecondary,
                                  fontSize: 14)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 80),
                          itemCount: _productoresFiltrados.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final prod = _productoresFiltrados[idx];
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AgroTheme.colorSurface,
                                borderRadius:
                                    BorderRadius.circular(AgroTheme.radiusLg),
                                border:
                                    Border.all(color: AgroTheme.colorBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          prod['productor'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15.5,
                                              color: AgroTheme.colorText),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AgroTheme.colorAccentSoft,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          prod['estado'] ?? 'ACTIVO',
                                          style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color:
                                                  AgroTheme.colorAccentDark),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "CUIT: ${prod['cuit'] ?? 'S/D'}  ·  RENSPA: ${prod['renspa'] ?? 'S/D'}",
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AgroTheme.colorTextSecondary),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Localidad: ${prod['localidad'] ?? 'S/D'}",
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AgroTheme.colorTextSecondary),
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
        onTap: _mostrarModalNuevoProductor,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.person_add_alt_1_rounded,
                color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              "Nuevo Productor",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}