import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';

class InventarioPlantacionScreen extends StatefulWidget {
  const InventarioPlantacionScreen({super.key});

  @override
  State<InventarioPlantacionScreen> createState() =>
      _InventarioPlantacionScreenState();
}

class _InventarioPlantacionScreenState extends State<InventarioPlantacionScreen> {
  bool _cargando = true;
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;

  List<Map<String, dynamic>> _productores = [];
  int? _selectedCodProductor;
  String _selectedNombreProductor = "";

  List<Map<String, dynamic>> _inventario = [];
  List<String> _chacrasDisponibles = ["TODAS"];
  String _chacraSeleccionada = "TODAS";

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
    _userCodProductor = prefs.getInt('userCodProductor') ?? 0;

    final db = await DatabaseHelper.instance.database;

    if (_esIngenieroOAdmin) {
      final prods = await db.query(
        'productores',
        where: 'estado = ?',
        whereArgs: ['ACTIVO'],
        orderBy: 'productor ASC',
      );
      _productores = prods;
      if (_productores.isNotEmpty) {
        _selectedCodProductor = _productores.first['cod_productor'] as int;
        _selectedNombreProductor = _productores.first['productor'] ?? '';
      }
    } else {
      _selectedCodProductor = _userCodProductor;
    }

    await _cargarInventario();
  }

  bool get _esIngenieroOAdmin =>
      _userRole == 'INGENIERO' || _userRole == 'ADMIN';

  Future<void> _cargarInventario() async {
    if (_selectedCodProductor == null) return;
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final res = await db.query(
      'inventario_plantacion',
      where: 'cod_productor = ?',
      whereArgs: [_selectedCodProductor],
      orderBy: 'chacra ASC, CAST(cuadro AS INTEGER) ASC, variedad ASC',
    );

    final Set<String> chacras = {"TODAS"};
    for (var i in res) {
      final ch = i['chacra']?.toString();
      if (ch != null && ch.trim().isNotEmpty) {
        chacras.add(ch.trim());
      }
    }

    if (!mounted) return;
    setState(() {
      _inventario = res;
      _chacrasDisponibles = chacras.toList();
      if (!_chacrasDisponibles.contains(_chacraSeleccionada)) {
        _chacraSeleccionada = "TODAS";
      }
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _inventarioFiltrado {
    return _inventario.where((item) {
      final matchChacra = _chacraSeleccionada == "TODAS" ||
          (item['chacra'] ?? '').toString() == _chacraSeleccionada;
      if (!matchChacra) return false;

      if (_filtroTexto.isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final ch = (item['chacra'] ?? '').toString().toLowerCase();
      final cu = (item['cuadro'] ?? '').toString().toLowerCase();
      final va = (item['variedad'] ?? '').toString().toLowerCase();
      final cul = (item['cultivo'] ?? '').toString().toLowerCase();
      final up = (item['up'] ?? '').toString().toLowerCase();
      return ch.contains(q) ||
          cu.contains(q) ||
          va.contains(q) ||
          cul.contains(q) ||
          up.contains(q);
    }).toList();
  }

  double get _superficieTotal {
    double total = 0.0;
    for (var i in _inventarioFiltrado) {
      total += double.tryParse(i['ha']?.toString() ?? '0') ?? 0.0;
    }
    return total;
  }

  int get _plantasTotales {
    int total = 0;
    for (var i in _inventarioFiltrado) {
      total += int.tryParse(i['plantas']?.toString() ?? '0') ?? 0;
    }
    return total;
  }

  double get _densidadPromedio {
    final sup = _superficieTotal;
    if (sup <= 0) return 0.0;
    return _plantasTotales / sup;
  }

  // ==========================================================================
  // 💡 FICHA TÉCNICA DETALLADA DE PARCELA
  // ==========================================================================
  void _mostrarFichaTecnicaParcela(Map<String, dynamic> item) {
    final ha = double.tryParse(item['ha']?.toString() ?? '0') ?? 0.0;
    final ano = item['ano_plantacion'] ?? 'S/D';
    final edad = ano != 'S/D' && int.tryParse(ano.toString()) != null
        ? "${DateTime.now().year - int.parse(ano.toString())} años"
        : "S/D";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: const BoxDecoration(
            color: AgroTheme.colorSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Ficha Técnica · Cuadro ${item['cuadro'] ?? 'S/N'}",
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17.5,
                            color: AgroTheme.colorText),
                      ),
                      Text(
                        "Chacra: ${item['chacra']} · UP: ${item['up'] ?? 'S/D'}",
                        style: const TextStyle(
                            fontSize: 12,
                            color: AgroTheme.colorTextSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
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
                  child: Column(
                    children: [
                      // Resumen Principal
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorBg,
                          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildDetalleDato(
                                "Superficie", "${ha.toStringAsFixed(2)} Ha"),
                            _buildDetalleDato("Variedad", "${item['variedad']}"),
                            _buildDetalleDato("Especie", "${item['cultivo']}"),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Grilla de Datos Agronómicos
                      _buildFilaAtributo(
                          Icons.date_range_rounded, "Año de Plantación", "$ano ($edad)"),
                      _buildFilaAtributo(
                          Icons.forest_rounded, "Cantidad de Plantas", "${item['plantas'] ?? 'S/D'} plantas"),
                      _buildFilaAtributo(
                          Icons.grid_4x4_rounded, "Marco de Plantación", "${item['dist_fila'] ?? '-'}m x ${item['dist_arbol'] ?? '-'}m"),
                      _buildFilaAtributo(
                          Icons.water_drop_outlined, "Sistema de Riego", "${item['sitema_riego'] ?? 'Tradicional / Por goteo'}"),
                      _buildFilaAtributo(
                          Icons.shield_outlined, "Defensa Antigranizo / Helada", "${item['sistema_def'] ?? 'Sin sistema activo'}"),
                      _buildFilaAtributo(
                          Icons.explore_outlined, "Orientación de Filas", "${item['orientacion'] ?? 'Norte - Sur'}"),
                      _buildFilaAtributo(
                          Icons.badge_outlined, "Unidad Productora (UP)", "${item['up'] ?? 'S/D'}"),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetalleDato(String titulo, String valor) {
    return Column(
      children: [
        Text(titulo,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AgroTheme.colorTextSecondary)),
        const SizedBox(height: 3),
        Text(valor,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AgroTheme.colorText)),
      ],
    );
  }

  Widget _buildFilaAtributo(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AgroTheme.colorAccentDark),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AgroTheme.colorTextSecondary)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AgroTheme.colorText)),
        ],
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Inventario de Plantación",
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16.5,
                  color: AgroTheme.colorText),
            ),
            if (_selectedNombreProductor.isNotEmpty)
              Text(
                _selectedNombreProductor,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: AgroTheme.colorTextSecondary,
                    fontWeight: FontWeight.w500),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // =========================================================
            // SELECTOR DE PRODUCTOR (INGENIERO / ADMIN)
            // =========================================================
            if (_esIngenieroOAdmin && _productores.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: AgroTheme.colorSurface,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorBg,
                    borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                    border: Border.all(color: AgroTheme.colorBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedCodProductor,
                      isExpanded: true,
                      style: const TextStyle(
                          fontFamily: 'Roboto',
                          color: AgroTheme.colorText,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5),
                      items: _productores.map((p) {
                        return DropdownMenuItem<int>(
                          value: p['cod_productor'] as int,
                          child: Text(
                              "${p['productor']} (CUIT: ${p['cuit'] ?? 'S/D'})",
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedCodProductor = val;
                            _selectedNombreProductor = _productores.firstWhere(
                                (p) => p['cod_productor'] == val)['productor'];
                          });
                          _cargarInventario();
                        }
                      },
                    ),
                  ),
                ),
              ),

            // =========================================================
            // 💡 BARRA DE KPIs MÉTRICOS (SUP TOTAL | PLANTAS | DENSIDAD)
            // =========================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                  border: Border.all(color: AgroTheme.colorBorder),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0x06141E18),
                        blurRadius: 10,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildKpiItem("Superficie",
                        "${_superficieTotal.toStringAsFixed(1)} Ha", Icons.terrain_rounded),
                    Container(height: 28, width: 1, color: AgroTheme.colorBorder),
                    _buildKpiItem("Plantas",
                        NumberFormat.compact().format(_plantasTotales), Icons.park_outlined),
                    Container(height: 28, width: 1, color: AgroTheme.colorBorder),
                    _buildKpiItem("Densidad",
                        "${_densidadPromedio.toStringAsFixed(0)} Pl/Ha", Icons.scatter_plot_outlined),
                  ],
                ),
              ),
            ),

            // =========================================================
            // FILTRO DE CHACRAS (CHIPS HORIZONTALES)
            // =========================================================
            if (_chacrasDisponibles.length > 1)
              Container(
                height: 38,
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _chacrasDisponibles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final ch = _chacrasDisponibles[idx];
                    final isSelected = _chacraSeleccionada == ch;

                    return ChoiceChip(
                      label: Text(ch == "TODAS" ? "Todas las Chacras" : ch),
                      selected: isSelected,
                      selectedColor: AgroTheme.colorAccentDark,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : AgroTheme.colorText,
                      ),
                      backgroundColor: AgroTheme.colorSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                            color: isSelected
                                ? AgroTheme.colorAccentDark
                                : AgroTheme.colorBorder),
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _chacraSeleccionada = ch);
                        }
                      },
                    );
                  },
                ),
              ),

            // =========================================================
            // BUSCADOR RÁPIDO
            // =========================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border: Border.all(color: AgroTheme.colorBorder),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (val) => setState(() => _filtroTexto = val),
                  style:
                      const TextStyle(color: AgroTheme.colorText, fontSize: 13.5),
                  decoration: const InputDecoration(
                    hintText: "Buscar por cuadro, variedad, cultivo o UP...",
                    hintStyle: TextStyle(
                        color: AgroTheme.colorTextSecondary, fontSize: 12.5),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AgroTheme.colorTextSecondary, size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

            // =========================================================
            // LISTADO DE CUARTELES / PARCELAS
            // =========================================================
            Expanded(
              child: _cargando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AgroTheme.colorAccent))
                  : _inventarioFiltrado.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.park_outlined,
                                  size: 44, color: AgroTheme.colorTextSecondary),
                              SizedBox(height: 12),
                              Text("No se encontraron parcelas registradas.",
                                  style: TextStyle(
                                      color: AgroTheme.colorTextSecondary,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                          itemCount: _inventarioFiltrado.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final item = _inventarioFiltrado[idx];
                            return _ParcelaCard(
                              item: item,
                              onTap: () => _mostrarFichaTecnicaParcela(item),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiItem(String titulo, String valor, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AgroTheme.colorAccentDark),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AgroTheme.colorTextSecondary)),
            Text(valor,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AgroTheme.colorText)),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// 🛠️ TARJETA DE PARCELA (ESTILO APPLE SOFT)
// ============================================================================
class _ParcelaCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _ParcelaCard({
    required this.item,
    required this.onTap,
  });

  @override
  State<_ParcelaCard> createState() => _ParcelaCardState();
}

class _ParcelaCardState extends State<_ParcelaCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ha = double.tryParse(item['ha']?.toString() ?? '0') ?? 0.0;
    final variedad = item['variedad'] ?? 'S/D';
    final cultivo = item['cultivo'] ?? 'General';
    final ano = item['ano_plantacion'] ?? 'S/D';
    final riego = item['sitema_riego'] ?? 'S/D';
    final plantas = item['plantas'] ?? '0';

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.identity()..scale(_isPressed ? 0.985 : 1.0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isPressed ? AgroTheme.colorActiveBg : AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
          border: Border.all(
            color: _isPressed
                ? AgroTheme.colorActiveBorder
                : AgroTheme.colorBorder,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x04141E18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera: Cuadro + Chacra + Superficie
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AgroTheme.colorAccentDark,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        "Cuadro ${item['cuadro'] ?? ''}",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${item['chacra'] ?? ''}",
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AgroTheme.colorText),
                    ),
                  ],
                ),
                Text(
                  "${ha.toStringAsFixed(2)} Ha",
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AgroTheme.colorAccentDark),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Variedad y Cultivo
            Row(
              children: [
                Text(
                  "$variedad ",
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AgroTheme.colorText),
                ),
                Text(
                  "($cultivo)",
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AgroTheme.colorTextSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Grilla de Atributos Compacta
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AgroTheme.colorBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMiniTag("Plantación", "$ano"),
                  _buildMiniTag("Plantas", "$plantas"),
                  _buildMiniTag("Riego", "$riego"),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 13, color: AgroTheme.colorTextSecondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniTag(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: AgroTheme.colorTextSecondary)),
        Text(value,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AgroTheme.colorText)),
      ],
    );
  }
}