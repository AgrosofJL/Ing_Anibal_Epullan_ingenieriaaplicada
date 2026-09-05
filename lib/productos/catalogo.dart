import 'package:flutter/material.dart';
import '../base/base.dart';
import '../constantes/tema.dart';

class CatalogoInsumosScreen extends StatefulWidget {
  const CatalogoInsumosScreen({super.key});

  @override
  State<CatalogoInsumosScreen> createState() => _CatalogoInsumosScreenState();
}

class _CatalogoInsumosScreenState extends State<CatalogoInsumosScreen> {
  bool _cargando = true;
  List<Map<String, dynamic>> _insumos = [];
  String _filtroTexto = "";
  String _rubroSeleccionado = "TODOS";
  List<String> _rubrosDisponibles = ["TODOS"];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> lista = await db.rawQuery('''
      SELECT * FROM catalogo_insumos
      WHERE rubro IN (
        SELECT nombre FROM rubros_insumos WHERE macro_rubro = 'PRODUCTOS'
      )
      AND (Mostrar = 1 OR Mostrar IS NULL)
      GROUP BY ID_Insumos
      ORDER BY Descripcion1 ASC
    ''');

    final Set<String> rubrosSet = {"TODOS"};
    for (var i in lista) {
      final r = i['rubro']?.toString();
      if (r != null && r.isNotEmpty) {
        rubrosSet.add(r.toUpperCase());
      }
    }

    if (!mounted) return;
    setState(() {
      _insumos = lista;
      _rubrosDisponibles = rubrosSet.toList()..sort();
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _insumosFiltrados {
    return _insumos.where((item) {
      final matchesRubro = _rubroSeleccionado == "TODOS" ||
          (item['rubro'] ?? '').toString().toUpperCase() == _rubroSeleccionado;

      if (!matchesRubro) return false;

      if (_filtroTexto.isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final nom = (item['Descripcion1'] ?? '').toString().toLowerCase();
      final pa = (item['principio_activo'] ?? '').toString().toLowerCase();
      return nom.contains(q) || pa.contains(q);
    }).toList();
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
          "Catálogo de Insumos",
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: AgroTheme.colorText),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Buscador
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border: Border.all(color: AgroTheme.colorBorder),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0x06141E18),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (val) => setState(() => _filtroTexto = val),
                  style:
                      const TextStyle(color: AgroTheme.colorText, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Buscar por nombre comercial o principio activo...",
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

            // Chips Horizontales de Rubros
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _rubrosDisponibles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final rubro = _rubrosDisponibles[idx];
                  final isSelected = _rubroSeleccionado == rubro;

                  return ChoiceChip(
                    label: Text(rubro),
                    selected: isSelected,
                    selectedColor: AgroTheme.colorAccentDark,
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : AgroTheme.colorText,
                    ),
                    backgroundColor: AgroTheme.colorSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                          color: isSelected
                              ? AgroTheme.colorAccentDark
                              : AgroTheme.colorBorder),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _rubroSeleccionado = rubro);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            // Listado de Productos
            Expanded(
              child: _cargando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AgroTheme.colorAccent))
                  : _insumosFiltrados.isEmpty
                      ? const Center(
                          child: Text("No se encontraron insumos.",
                              style: TextStyle(
                                  color: AgroTheme.colorTextSecondary,
                                  fontSize: 14)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                          itemCount: _insumosFiltrados.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final item = _insumosFiltrados[idx];
                            final rubro = item['rubro'] ?? 'General';
                            final pa = item['principio_activo'] ??
                                item['Descripcion2'] ??
                                'S/D';
                            final tc = item['T_C'] ?? 'S/D';
                            final tri = item['TRI'] ?? 'S/D';
                            final stock = item['stock_real'] ?? 0;

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AgroTheme.colorSurface,
                                borderRadius:
                                    BorderRadius.circular(AgroTheme.radiusLg),
                                border:
                                    Border.all(color: AgroTheme.colorBorder),
                                boxShadow: [
                                  BoxShadow(
                                      color: const Color(0x04141E18),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2)),
                                ],
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
                                          item['Descripcion1'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
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
                                          rubro,
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
                                    "Principio Activo: $pa",
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AgroTheme.colorTextSecondary),
                                  ),
                                  const SizedBox(height: 10),
                                  const Divider(
                                      height: 1, color: AgroTheme.colorBorder),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("T. Carencia: ${tc}d",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: AgroTheme.colorText)),
                                      Text("T. Reingreso: ${tri}hs",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: AgroTheme.colorText)),
                                      Text("Stock: $stock",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  AgroTheme.colorAccentDark)),
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
    );
  }
}