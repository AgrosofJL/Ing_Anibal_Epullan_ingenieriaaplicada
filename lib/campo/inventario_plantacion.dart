import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

class InventarioPlantacionScreen extends StatefulWidget {
  const InventarioPlantacionScreen({super.key});

  @override
  State<InventarioPlantacionScreen> createState() =>
      _InventarioPlantacionScreenState();
}

class _InventarioPlantacionScreenState
    extends State<InventarioPlantacionScreen> {
  bool _cargando = true;
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;

  List<Map<String, dynamic>> _productores = [];
  int? _selectedCodProductor;
  String _selectedNombreProductor = "";

  List<Map<String, dynamic>> _inventario = [];
  List<Map<String, dynamic>> _cuadros = [];
  List<String> _chacrasDisponibles = ["TODAS"];
  String _chacraSeleccionada = "TODAS";

  String _filtroTexto = "";
  final TextEditingController _searchCtrl = TextEditingController();

  static const Map<String, List<String>> _cultivosVariedades = {
    'Manzano': [
      'Red Delicious',
      'Gala',
      'Granny Smith',
      'Cripps Pink (Pink Lady)',
      'Fuji',
      'Golden Delicious',
      'Otras Variedades'
    ],
    'Peral': [
      'Williams (Bartlett)',
      'Packham\'s Triumph',
      'D\'Anjou',
      'Abate Fetel',
      'Red Bartlett',
      'Beurré Bosc',
      'Otras Variedades'
    ],
    'Cerezo': [
      'Bing',
      'Lapins',
      'Sweetheart',
      'Santina',
      'Rainier',
      'Brooks',
      'Otras Variedades'
    ],
    'Ciruelo': [
      'Larry Ann',
      'Black Amber',
      'Angeleno',
      'Friar',
      'D\'Agen',
      'Otras Variedades'
    ],
    'Duraznero / Pelón': [
      'Flavorcrest',
      'Red Globe',
      'Caldesi',
      'Artic Snow',
      'Otras Variedades'
    ],
    'Vid': [
      'Malbec',
      'Cabernet Sauvignon',
      'Merlot',
      'Pinot Noir',
      'Torrontés',
      'Chardonnay',
      'Otras Variedades'
    ],
    'Nogal': ['Chandler', 'Franquette', 'Tulare', 'Otras Variedades'],
  };

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
        _selectedNombreProductor =
            (_productores.first['productor'] ?? '').toString();
      }
    } else {
      _selectedCodProductor = _userCodProductor;
      final resP = await db.query(
        'productores',
        where: 'cod_productor = ?',
        whereArgs: [_userCodProductor],
        limit: 1,
      );
      if (resP.isNotEmpty) {
        _selectedNombreProductor = (resP.first['productor'] ?? '').toString();
      }
    }

    await _cargarDatosCompletos();
  }

  bool get _esIngenieroOAdmin =>
      _userRole == 'INGENIERO' || _userRole == 'ADMIN';

  bool get _puedeEditar =>
      _esIngenieroOAdmin || _userRole == 'PROD-ADMIN';

  Future<void> _cargarDatosCompletos() async {
    if (_selectedCodProductor == null) return;
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final resCuadros = await db.query(
      'cuadros',
      where: 'cod_productor = ?',
      whereArgs: [_selectedCodProductor],
      orderBy: 'chacra ASC, CAST(cuadro AS INTEGER) ASC',
    );

    final resInv = await db.query(
      'inventario_plantacion',
      where: 'cod_productor = ?',
      whereArgs: [_selectedCodProductor],
      orderBy: 'chacra ASC, CAST(cuadro AS INTEGER) ASC, variedad ASC',
    );

    final Set<String> chacras = {"TODAS"};
    for (var i in resInv) {
      final ch = i['chacra']?.toString();
      if (ch != null && ch.trim().isNotEmpty) {
        chacras.add(ch.trim());
      }
    }
    for (var c in resCuadros) {
      final ch = c['chacra']?.toString();
      if (ch != null && ch.trim().isNotEmpty) {
        chacras.add(ch.trim());
      }
    }

    if (!mounted) return;
    setState(() {
      _cuadros = resCuadros;
      _inventario = resInv;
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

  Future<void> _sincronizarRemoto(String tabla, Map<String, dynamic> data) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from(tabla).upsert(data);
    } catch (e) {
      debugPrint("Aviso sync remoto en $tabla: $e");
    }
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
        borderSide: const BorderSide(color: AgroTheme.colorAccentDark, width: 1.5),
      ),
    );
  }

  void _mostrarModalNuevoCuadro() {
    final formKey = GlobalKey<FormState>();
    final chacraCtrl = TextEditingController(
        text: _chacraSeleccionada != "TODAS"
            ? _chacraSeleccionada
            : "Chacra Principal");
    final cuadroCtrl = TextEditingController();
    final supCtrl = TextEditingController();
    final ubicacionCtrl = TextEditingController();

    String riegoSeleccionado = "Goteo";
    String defensaSeleccionada = "Ninguna";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final mediaQuery = MediaQuery.of(modalContext);

            return Container(
              height: mediaQuery.size.height * 0.85,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: mediaQuery.viewInsets.bottom + 20,
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
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Alta de Cuadro / Parcela",
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  color: AgroTheme.colorText),
                            ),
                            Text(
                              _selectedNombreProductor,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AgroTheme.colorTextSecondary),
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
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: chacraCtrl,
                              decoration: _inputDecoration(
                                  "Nombre de Chacra / Lote",
                                  Icons.terrain_rounded),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? "Obligatorio"
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: cuadroCtrl,
                                    decoration: _inputDecoration(
                                        "N° de Cuadro", Icons.grid_view_rounded),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? "Obligatorio"
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: supCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _inputDecoration(
                                        "Superficie (Ha)",
                                        Icons.aspect_ratio_rounded),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? "Obligatorio"
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: riegoSeleccionado,
                              decoration: _inputDecoration(
                                  "Sistema de Riego", Icons.water_drop_outlined),
                              items: const [
                                DropdownMenuItem(
                                    value: "Goteo", child: Text("Riego por Goteo")),
                                DropdownMenuItem(
                                    value: "Gravedad / Manto",
                                    child: Text("Gravedad / Manto")),
                                DropdownMenuItem(
                                    value: "Aspersión",
                                    child: Text("Microaspersión / Aspersión")),
                                DropdownMenuItem(
                                    value: "Surco", child: Text("Por Surco")),
                              ],
                              onChanged: (v) => setModalState(
                                  () => riegoSeleccionado = v ?? "Goteo"),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: defensaSeleccionada,
                              decoration: _inputDecoration(
                                  "Defensa Climatológica", Icons.shield_outlined),
                              items: const [
                                DropdownMenuItem(
                                    value: "Ninguna", child: Text("Sin Defensa")),
                                DropdownMenuItem(
                                    value: "Malla Antigranizo",
                                    child: Text("Malla Antigranizo")),
                                DropdownMenuItem(
                                    value: "Riego Subarbóreo (Antihelada)",
                                    child: Text("Riego Subarbóreo (Antihelada)")),
                                DropdownMenuItem(
                                    value: "Riego Supra-arbóreo (Antihelada)",
                                    child: Text("Riego Supra-arbóreo")),
                                DropdownMenuItem(
                                    value: "Calefactores / Molinos",
                                    child:
                                        Text("Calefactores / Molinos de Viento")),
                              ],
                              onChanged: (v) => setModalState(
                                  () => defensaSeleccionada = v ?? "Ninguna"),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: ubicacionCtrl,
                              decoration: _inputDecoration(
                                  "Ubicación / Referencia (Opcional)",
                                  Icons.location_on_outlined),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: SoftButton(
                        onTap: () async {
                          if (!formKey.currentState!.validate()) return;
                          final db = await DatabaseHelper.instance.database;

                          final int sigCodCuadro = await DatabaseHelper.instance
                              .obtenerSiguienteId('cuadros', 'cod_cuadro');

                          final rowCuadro = {
                            'cod_cuadro': sigCodCuadro,
                            'cod_productor': _selectedCodProductor,
                            'productor': _selectedNombreProductor,
                            'chacra': chacraCtrl.text.trim(),
                            'cuadro': cuadroCtrl.text.trim(),
                            'sitema_riego': riegoSeleccionado,
                            'sistema_def': defensaSeleccionada,
                            'ubicacion': ubicacionCtrl.text.trim(),
                            'sup': double.tryParse(
                                    supCtrl.text.trim().replaceAll(',', '.')) ??
                                0.0,
                          };

                          await db.insert('cuadros', rowCuadro);
                          await _sincronizarRemoto('cuadros', rowCuadro);

                          if (!mounted) return;
                          Navigator.pop(ctx);
                          await _cargarDatosCompletos();

                          if (!mounted) return;
                          _mostrarModalNuevaPlantacion(
                              preseleccionCuadro: rowCuadro);
                        },
                        child: const Center(
                          child: Text(
                            "Guardar Cuadro y Asignar Plantación",
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
      },
    );
  }

  void _mostrarModalNuevaPlantacion({Map<String, dynamic>? preseleccionCuadro}) {
    if (_cuadros.isEmpty) {
      _mostrarModalNuevoCuadro();
      return;
    }

    final formKey = GlobalKey<FormState>();

    Map<String, dynamic> cuadroActual = preseleccionCuadro ?? _cuadros.first;
    int codCuadroSeleccionado = cuadroActual['cod_cuadro'] as int;

    String cultivoSeleccionado = _cultivosVariedades.keys.first;
    List<String> listaVariedades = _cultivosVariedades[cultivoSeleccionado]!;
    String variedadSeleccionada = listaVariedades.first;

    final anoCtrl = TextEditingController(text: "${DateTime.now().year - 4}");
    final haCtrl = TextEditingController(text: "${cuadroActual['sup'] ?? ''}");
    final plantasCtrl = TextEditingController();
    final upCtrl = TextEditingController(text: "UP-01");
    final distFilaCtrl = TextEditingController(text: "4.0");
    final distArbolCtrl = TextEditingController(text: "1.5");
    String orientacionSeleccionada = "Norte - Sur";

    void calcularPlantasAuto() {
      final double distF =
          double.tryParse(distFilaCtrl.text.replaceAll(',', '.')) ?? 0.0;
      final double distA =
          double.tryParse(distArbolCtrl.text.replaceAll(',', '.')) ?? 0.0;
      final double ha =
          double.tryParse(haCtrl.text.replaceAll(',', '.')) ?? 0.0;

      if (distF > 0 && distA > 0 && ha > 0) {
        final double marcoM2 = distF * distA;
        final int plantasCalculadas = ((ha * 10000) / marcoM2).round();
        plantasCtrl.text = plantasCalculadas.toString();
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final mediaQuery = MediaQuery.of(modalContext);

            return Container(
              height: mediaQuery.size.height * 0.92,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: mediaQuery.viewInsets.bottom + 20,
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
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Registrar Cuartel de Plantación",
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: AgroTheme.colorText,
                              ),
                            ),
                            Text(
                              "Chacra: ${cuadroActual['chacra']} · Cuadro: ${cuadroActual['cuadro']}",
                              style: const TextStyle(
                                fontSize: 12,
                                color: AgroTheme.colorAccentDark,
                                fontWeight: FontWeight.bold,
                              ),
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
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "1. Seleccionar Cuadro Asignado:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<int>(
                              value: codCuadroSeleccionado,
                              decoration: _inputDecoration(
                                "Cuadro",
                                Icons.grid_view_rounded,
                              ),
                              items: _cuadros.map((c) {
                                return DropdownMenuItem<int>(
                                  value: c['cod_cuadro'] as int,
                                  child: Text(
                                    "${c['chacra']} - Cuadro ${c['cuadro']} (${c['sup'] ?? 0} Ha)",
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setModalState(() {
                                    codCuadroSeleccionado = v;
                                    cuadroActual = _cuadros.firstWhere(
                                      (c) => c['cod_cuadro'] == v,
                                    );
                                    haCtrl.text =
                                        "${cuadroActual['sup'] ?? ''}";
                                    calcularPlantasAuto();
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "2. Cultivo y Variedad Botánica:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: cultivoSeleccionado,
                                    decoration: _inputDecoration(
                                      "Cultivo / Especie",
                                      Icons.eco_outlined,
                                    ),
                                    items: _cultivosVariedades.keys.map((cul) {
                                      return DropdownMenuItem<String>(
                                        value: cul,
                                        child: Text(cul),
                                      );
                                    }).toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setModalState(() {
                                          cultivoSeleccionado = v;
                                          listaVariedades =
                                              _cultivosVariedades[v] ?? [];
                                          variedadSeleccionada =
                                              listaVariedades.first;
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: variedadSeleccionada,
                                    decoration: _inputDecoration(
                                      "Variedad",
                                      Icons.psychology_outlined,
                                    ),
                                    items: listaVariedades.map((vari) {
                                      return DropdownMenuItem<String>(
                                        value: vari,
                                        child: Text(
                                          vari,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (v) => setModalState(
                                      () => variedadSeleccionada =
                                          v ?? listaVariedades.first,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "3. Marco de Plantación y Superficie:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: distFilaCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: _inputDecoration(
                                      "Entre Filas (m)",
                                      Icons.straighten_rounded,
                                    ),
                                    onChanged: (_) => calcularPlantasAuto(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: distArbolCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: _inputDecoration(
                                      "Entre Plantas (m)",
                                      Icons.height_rounded,
                                    ),
                                    onChanged: (_) => calcularPlantasAuto(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: haCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: _inputDecoration(
                                      "Superficie Cuartel (Ha)",
                                      Icons.aspect_ratio_rounded,
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? "Obligatorio"
                                            : null,
                                    onChanged: (_) => calcularPlantasAuto(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: plantasCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration(
                                      "Plantas Totales",
                                      Icons.forest_outlined,
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? "Obligatorio"
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: anoCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration(
                                      "Año Plantación",
                                      Icons.event_note_rounded,
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
                                    controller: upCtrl,
                                    decoration: _inputDecoration(
                                      "Unidad Productora (UP)",
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: orientacionSeleccionada,
                              decoration: _inputDecoration(
                                "Orientación de Filas",
                                Icons.explore_outlined,
                              ),
                              items: const [
                                DropdownMenuItem<String>(
                                  value: "Norte - Sur",
                                  child: Text("Norte - Sur (Recomendada)"),
                                ),
                                DropdownMenuItem<String>(
                                  value: "Este - Oeste",
                                  child: Text("Este - Oeste"),
                                ),
                                DropdownMenuItem<String>(
                                  value: "Nororiente - Surponiente",
                                  child: Text("Diagonal / Otra"),
                                ),
                              ],
                              onChanged: (v) => setModalState(
                                () =>
                                    orientacionSeleccionada = v ?? "Norte - Sur",
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: SoftButton(
                        onTap: () async {
                          if (!formKey.currentState!.validate()) return;
                          final db = await DatabaseHelper.instance.database;

                          final int sigId = await DatabaseHelper.instance
                              .obtenerSiguienteId(
                                  'inventario_plantacion', 'id');

                          final double distF = double.tryParse(
                                  distFilaCtrl.text.replaceAll(',', '.')) ??
                              0.0;
                          final double distA = double.tryParse(
                                  distArbolCtrl.text.replaceAll(',', '.')) ??
                              0.0;

                          final rowInv = {
                            'id': sigId,
                            'cod_productor': _selectedCodProductor,
                            'productor': _selectedNombreProductor,
                            'chacra': cuadroActual['chacra'],
                            'cod_cuadro': codCuadroSeleccionado,
                            'cuadro': cuadroActual['cuadro'],
                            'cultivo': cultivoSeleccionado,
                            'variedad': variedadSeleccionada,
                            'ano_plantacion':
                                int.tryParse(anoCtrl.text.trim()) ??
                                    DateTime.now().year,
                            'ha': double.tryParse(
                                    haCtrl.text.trim().replaceAll(',', '.')) ??
                                0.0,
                            'plantas':
                                int.tryParse(plantasCtrl.text.trim()) ?? 0,
                            'marco_plantacion': (distF * distA).round(),
                            'up': upCtrl.text.trim(),
                            'dist_arbol': distA,
                            'dist_fila': distF,
                            'orientacion': orientacionSeleccionada,
                            'sitema_riego':
                                cuadroActual['sitema_riego'] ?? 'Goteo',
                            'sistema_def':
                                cuadroActual['sistema_def'] ?? 'Ninguna',
                          };

                          await db.insert('inventario_plantacion', rowInv);
                          await _sincronizarRemoto(
                              'inventario_plantacion', rowInv);

                          if (!mounted) return;
                          Navigator.pop(ctx);
                          await _cargarDatosCompletos();

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AgroTheme.colorAccent,
                              content: Text(
                                  "¡Cuartel de plantación registrado con éxito!"),
                            ),
                          );
                        },
                        child: const Center(
                          child: Text(
                            "Guardar Plantación",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
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

  void _mostrarOpcionesCarga() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      backgroundColor: AgroTheme.colorSurface,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Cargar Catastro Agronómico",
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16.5,
                    color: AgroTheme.colorText),
              ),
              const SizedBox(height: 6),
              const Text(
                "Seleccioná qué nivel de detalle deseás dar de alta para el establecimiento:",
                style: TextStyle(
                    fontSize: 12.5, color: AgroTheme.colorTextSecondary),
              ),
              const SizedBox(height: 18),
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                tileColor: AgroTheme.colorBg,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AgroTheme.colorAccentDark.withOpacity(0.12),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.grid_view_rounded,
                      color: AgroTheme.colorAccentDark, size: 22),
                ),
                title: const Text("1. Nuevo Cuadro / Parcela",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text(
                    "Define la parcela madre, riego, defensa y superficie total.",
                    style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarModalNuevoCuadro();
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                tileColor: AgroTheme.colorBg,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AgroTheme.colorGold.withOpacity(0.12),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.park_outlined,
                      color: AgroTheme.colorGold, size: 22),
                ),
                title: const Text("2. Nuevo Cuartel de Plantación",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text(
                    "Asigna especie, variedad, marco y densidad dentro de un cuadro.",
                    style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarModalNuevaPlantacion();
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorBg,
                          borderRadius:
                              BorderRadius.circular(AgroTheme.radiusMd),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildDetalleDato(
                                "Superficie", "${ha.toStringAsFixed(2)} Ha"),
                            _buildDetalleDato(
                                "Variedad", "${item['variedad']}"),
                            _buildDetalleDato("Especie", "${item['cultivo']}"),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFilaAtributo(Icons.date_range_rounded,
                          "Año de Plantación", "$ano ($edad)"),
                      _buildFilaAtributo(Icons.forest_rounded,
                          "Cantidad de Plantas", "${item['plantas'] ?? 'S/D'} plantas"),
                      _buildFilaAtributo(
                          Icons.grid_4x4_rounded,
                          "Marco de Plantación",
                          "${item['dist_fila'] ?? '-'}m x ${item['dist_arbol'] ?? '-'}m"),
                      _buildFilaAtributo(Icons.water_drop_outlined,
                          "Sistema de Riego", "${item['sitema_riego'] ?? 'Goteo'}"),
                      _buildFilaAtributo(
                          Icons.shield_outlined,
                          "Defensa Antigranizo / Helada",
                          "${item['sistema_def'] ?? 'Ninguna'}"),
                      _buildFilaAtributo(Icons.explore_outlined,
                          "Orientación de Filas", "${item['orientacion'] ?? 'Norte - Sur'}"),
                      _buildFilaAtributo(Icons.badge_outlined,
                          "Unidad Productora (UP)", "${item['up'] ?? 'S/D'}"),
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
                            _selectedNombreProductor =
                                (_productores.firstWhere(
                                            (p) => p['cod_productor'] == val)[
                                        'productor'] ??
                                    '')
                                .toString();
                          });
                          _cargarDatosCompletos();
                        }
                      },
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                  border: Border.all(color: AgroTheme.colorBorder),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x06141E18),
                        blurRadius: 10,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildKpiItem(
                        "Superficie",
                        "${_superficieTotal.toStringAsFixed(1)} Ha",
                        Icons.terrain_rounded),
                    Container(
                        height: 28, width: 1, color: AgroTheme.colorBorder),
                    _buildKpiItem(
                        "Plantas",
                        NumberFormat.compact().format(_plantasTotales),
                        Icons.park_outlined),
                    Container(
                        height: 28, width: 1, color: AgroTheme.colorBorder),
                    _buildKpiItem(
                        "Densidad",
                        "${_densidadPromedio.toStringAsFixed(0)} Pl/Ha",
                        Icons.scatter_plot_outlined),
                  ],
                ),
              ),
            ),
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
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
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
                  style: const TextStyle(
                      color: AgroTheme.colorText, fontSize: 13.5),
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
            Expanded(
              child: _cargando
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AgroTheme.colorAccent))
                  : _inventarioFiltrado.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(28.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: AgroTheme.colorAccent.withOpacity(0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                      Icons.nature_people_rounded,
                                      size: 54,
                                      color: AgroTheme.colorAccentDark),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "Sin Plantaciones Registradas",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                      color: AgroTheme.colorText),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  "Tu establecimiento no cuenta aún con cuarteles cargados.\nPodes registrar tu primer cuadro y cuartel de plantación ahora mismo.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AgroTheme.colorTextSecondary,
                                      height: 1.4),
                                ),
                                const SizedBox(height: 24),
                                if (_puedeEditar)
                                  SizedBox(
                                    width: 240,
                                    height: 48,
                                    child: SoftButton(
                                      borderRadius: 24,
                                      onTap: _mostrarOpcionesCarga,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(
                                              Icons.add_circle_outline_rounded,
                                              color: Colors.white,
                                              size: 18),
                                          SizedBox(width: 8),
                                          Text(
                                            "Cargar Mi Primer Cuadro",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 85),
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
      floatingActionButton: _puedeEditar
          ? SoftButton(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              borderRadius: 28,
              onTap: _mostrarOpcionesCarga,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 6),
                  Text(
                    "Cargar Parcela / Plantación",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14),
                  ),
                ],
              ),
            )
          : null,
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
          children: [
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