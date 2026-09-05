import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';
import 'ordenes_generadas.dart';

class AplicaProductorScreen extends StatefulWidget {
  const AplicaProductorScreen({super.key});

  @override
  State<AplicaProductorScreen> createState() => _AplicaProductorScreenState();
}

class _AplicaProductorScreenState extends State<AplicaProductorScreen> {
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;
  String _filtroTexto = "";
  bool _cargando = true;

  List<Map<String, dynamic>> _productores = [];
  Map<int, int> _conteoOrdenes = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 💡 ACA ES LO NUEVO: Carga condicionada según los roles definidos
  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final prefs = await SharedPreferences.getInstance();
    _userRole = (prefs.getString('userRole') ?? "OPE-PROD").toUpperCase();
    _userCodProductor = prefs.getInt('userCodProductor') ?? 0;

    final db = await DatabaseHelper.instance.database;

    List<Map<String, dynamic>> listaProds = [];

    // 1. Segmentación por Rol
    if (_userRole == 'ADMIN' || _userRole == 'INGENIERO' || _userRole == 'OPE-APLI') {
      // ADMIN (Vos), INGENIERO y Aplicador ven la cartera completa de productores
      listaProds = await db.query(
        'productores',
        where: 'estado = ?',
        whereArgs: ['ACTIVO'],
        orderBy: 'productor ASC',
      );
    } else {
      // OPE-PROD solo ve su establecimiento asignado
      listaProds = await db.query(
        'productores',
        where: 'cod_productor = ? AND estado = ?',
        whereArgs: [_userCodProductor, 'ACTIVO'],
      );
    }

    // 2. Conteo de órdenes/recetas confeccionadas para cada productor
    final Map<int, int> mapaConteo = {};
    for (var prod in listaProds) {
      final int cod = prod['cod_productor'] as int;
      final res = await db.rawQuery(
        'SELECT COUNT(DISTINCT cod_orden) as total FROM recetas_aplicaciones WHERE cod_productor = ? AND habilitado = ?',
        [cod, 'ACTIVO'],
      );
      mapaConteo[cod] = (res.first['total'] as int?) ?? 0;
    }

    if (!mounted) return;
    setState(() {
      _productores = listaProds;
      _conteoOrdenes = mapaConteo;
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _productoresFiltrados {
    if (_filtroTexto.isEmpty) return _productores;
    return _productores.where((p) {
      final nombre = (p['productor'] ?? '').toString().toLowerCase();
      final cuit = (p['cuit'] ?? '').toString().toLowerCase();
      final renspa = (p['renspa'] ?? '').toString().toLowerCase();
      final loc = (p['localidad'] ?? '').toString().toLowerCase();
      final query = _filtroTexto.toLowerCase();
      return nombre.contains(query) || cuit.contains(query) || renspa.contains(query) || loc.contains(query);
    }).toList();
  }

  void _navegarAOrdenes(Map<String, dynamic> productor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrdenesGeneradasScreen(
          codProductor: productor['cod_productor'] as int,
          nombreProductor: productor['productor'] ?? 'Productor',
          cuit: productor['cuit'] ?? 'S/D',
          renspa: productor['renspa'] ?? 'S/D',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AppBar(
        backgroundColor: AgroTheme.colorSurface.withOpacity(0.85),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Seleccionar Productor",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AgroTheme.colorText),
            ),
            Text(
              "Rol activo: $_userRole",
              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Barra de Búsqueda Dinámica
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border: Border.all(color: AgroTheme.colorBorder),
                  boxShadow: [
                    BoxShadow(color: const Color(0x06141E18), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _filtroTexto = val),
                  style: const TextStyle(color: AgroTheme.colorText, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Buscar por nombre, CUIT, RENSPA o localidad...",
                    hintStyle: const TextStyle(color: AgroTheme.colorTextSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: AgroTheme.colorTextSecondary, size: 20),
                    suffixIcon: _filtroTexto.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: AgroTheme.colorTextSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _filtroTexto = "");
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            // Listado de Productores
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: AgroTheme.colorAccent))
                  : _productoresFiltrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.person_search_outlined, size: 48, color: AgroTheme.colorTextSecondary),
                              SizedBox(height: 12),
                              Text(
                                "No se encontraron productores",
                                style: TextStyle(fontWeight: FontWeight.w700, color: AgroTheme.colorTextSecondary, fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          itemCount: _productoresFiltrados.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final prod = _productoresFiltrados[index];
                            final codProd = prod['cod_productor'] as int;
                            final ordenesCount = _conteoOrdenes[codProd] ?? 0;

                            return _ProductorCard(
                              productor: prod,
                              totalOrdenes: ordenesCount,
                              onTap: () => _navegarAOrdenes(prod),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 🛠️ ESTO LO MODIFIQUE: Card Interactiva Profesional Apple Soft
// ============================================================================
class _ProductorCard extends StatefulWidget {
  final Map<String, dynamic> productor;
  final int totalOrdenes;
  final VoidCallback onTap;

  const _ProductorCard({
    required this.productor,
    required this.totalOrdenes,
    required this.onTap,
  });

  @override
  State<_ProductorCard> createState() => _ProductorCardState();
}

class _ProductorCardState extends State<_ProductorCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final nombre = widget.productor['productor'] ?? 'Sin Nombre';
    final cuit = widget.productor['cuit'] ?? 'S/D';
    final renspa = widget.productor['renspa'] ?? 'S/D';
    final localidad = widget.productor['localidad'] ?? 'Sin Localidad';

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.identity()..scale(_isPressed ? 0.985 : 1.0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _isPressed ? AgroTheme.colorActiveBg : AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
          border: Border.all(
            color: _isPressed ? AgroTheme.colorActiveBorder : AgroTheme.colorBorder,
            width: 1.2,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(color: const Color(0xFFFBC02D).withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2)),
                ]
              : [
                  BoxShadow(color: const Color(0x06141E18), blurRadius: 10, offset: const Offset(0, 4)),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado de la Card
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AgroTheme.colorAccentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.business_rounded, color: AgroTheme.colorAccentDark, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AgroTheme.colorText),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 13, color: AgroTheme.colorTextSecondary),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    localidad,
                                    style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Badge de Órdenes
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.totalOrdenes > 0 ? AgroTheme.colorAccentSoft : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${widget.totalOrdenes} ${widget.totalOrdenes == 1 ? 'orden' : 'órdenes'}",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: widget.totalOrdenes > 0 ? AgroTheme.colorAccentDark : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AgroTheme.colorBorder),
            const SizedBox(height: 12),

            // Datos Técnicos (CUIT / RENSPA)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoTag("CUIT", cuit),
                _buildInfoTag("RENSPA", renspa),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AgroTheme.colorTextSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTag(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AgroTheme.colorTextSecondary)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AgroTheme.colorText)),
      ],
    );
  }
}