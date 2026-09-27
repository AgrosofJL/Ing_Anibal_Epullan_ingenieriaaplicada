// ignore_for_file: deprecated_member_use

import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/agro_reportes_ui.dart';
import '../widgets/agro_ui.dart';

final NumberFormat _fmtHa = NumberFormat('#,##0.00', 'es');
final NumberFormat _fmtEntero = NumberFormat('#,##0', 'es');

double _haDe(Map<String, dynamic> item) =>
    double.tryParse(item['ha']?.toString() ?? '0') ?? 0.0;

int _plantasDe(Map<String, dynamic> item) =>
    int.tryParse(item['plantas']?.toString() ?? '0') ?? 0;

Color _colorCultivo(String cultivo) {
  final c = cultivo.toLowerCase();
  if (c.contains('manzano')) return const Color(0xFFC62828);
  if (c.contains('peral')) return const Color(0xFF2E7D32);
  if (c.contains('cerezo')) return const Color(0xFFAD1457);
  if (c.contains('ciruelo')) return const Color(0xFF6A1B9A);
  if (c.contains('durazn') || c.contains('pelón')) return const Color(0xFFE65100);
  if (c.contains('vid')) return const Color(0xFF4527A0);
  if (c.contains('nogal')) return const Color(0xFF6D4C41);
  return AgroColors.primario;
}

class InventarioPlantacionScreen extends StatefulWidget {
  /// Productor con el que se abrió la pantalla (opcional). Para ingenieros /
  /// administradores se preselecciona si está en la lista de activos.
  final int? codProductor;
  final String? nombreProductor;

  const InventarioPlantacionScreen({
    super.key,
    this.codProductor,
    this.nombreProductor,
  });

  @override
  State<InventarioPlantacionScreen> createState() =>
      _InventarioPlantacionScreenState();
}

class _InventarioPlantacionScreenState
    extends State<InventarioPlantacionScreen> {
  bool _cargando = true;
  bool _exportando = false;
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;

  List<Map<String, dynamic>> _productores = [];
  int? _selectedCodProductor;
  String _selectedNombreProductor = "";
  Map<String, dynamic>? _productorInfo;

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

  // ============================================================
  // LÓGICA DE DATOS
  // ============================================================

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole =
        (prefs.getString('userRole') ?? "OPERARIO").toUpperCase().trim();
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
        // Si la pantalla se abrió con un productor y está activo, se usa ese;
        // si no, el primero de la lista (comportamiento original).
        Map<String, dynamic> elegido = _productores.first;
        if (widget.codProductor != null) {
          for (final p in _productores) {
            if (p['cod_productor'] == widget.codProductor) {
              elegido = p;
              break;
            }
          }
        }
        _selectedCodProductor = elegido['cod_productor'] as int;
        _selectedNombreProductor = (elegido['productor'] ?? '').toString();
        _productorInfo = elegido;
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
        _productorInfo = resP.first;
      } else if ((widget.nombreProductor ?? '').trim().isNotEmpty) {
        _selectedNombreProductor = widget.nombreProductor!.trim();
      }
    }

    if (!mounted) return;
    if (_selectedCodProductor == null) {
      // Sin productores activos: no queda la pantalla cargando indefinidamente.
      setState(() => _cargando = false);
      return;
    }
    await _cargarDatosCompletos();
  }

  bool get _esIngenieroOAdmin =>
      _userRole == 'INGENIERO' || _userRole == 'ADMIN' || _userRole == 'ADM';

  bool get _puedeEditar => _esIngenieroOAdmin || _userRole == 'PROD-ADMIN';

  Future<void> _cargarDatosCompletos() async {
    if (_selectedCodProductor == null) return;
    if (!mounted) return;
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

  void _cambiarProductor(int cod) {
    if (!_esIngenieroOAdmin) return;
    Map<String, dynamic>? prod;
    for (final p in _productores) {
      if (p['cod_productor'] == cod) {
        prod = p;
        break;
      }
    }
    if (prod == null) return;
    setState(() {
      _selectedCodProductor = cod;
      _selectedNombreProductor = (prod!['productor'] ?? '').toString();
      _productorInfo = prod;
    });
    _cargarDatosCompletos();
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

  bool get _hayFiltros =>
      _chacraSeleccionada != "TODAS" || _filtroTexto.trim().isNotEmpty;

  void _limpiarFiltros() {
    setState(() {
      _searchCtrl.clear();
      _filtroTexto = "";
      _chacraSeleccionada = "TODAS";
    });
  }

  double _superficieDe(List<Map<String, dynamic>> lista) {
    double total = 0.0;
    for (var i in lista) {
      total += _haDe(i);
    }
    return total;
  }

  int _plantasTotalesDe(List<Map<String, dynamic>> lista) {
    int total = 0;
    for (var i in lista) {
      total += _plantasDe(i);
    }
    return total;
  }

  // ============================================================
  // EXPORTACIÓN EXCEL
  // ============================================================

  Future<void> _exportarExcelInventario() async {
    if (_exportando) return;
    final datos = _inventarioFiltrado;
    if (datos.isEmpty) return;

    setState(() => _exportando = true);
    mostrarAgroSnack(context, 'Generando planilla de inventario…',
        duracion: const Duration(milliseconds: 1500));

    try {
      final excel = Excel.createExcel();
      final sheet = excel['Catastro_Plantacion'];
      excel.delete('Sheet1');

      final headerStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#1E6B4C'),
        horizontalAlign: HorizontalAlign.Center,
      );

      final headers = [
        'ID',
        'Chacra',
        'Cuadro',
        'Especie / Cultivo',
        'Variedad',
        'Superficie (Ha)',
        'Año Plantación',
        'Cantidad Plantas',
        'Entre Filas (m)',
        'Entre Plantas (m)',
        'Marco (m²)',
        'Sistema Riego',
        'Defensa',
        'Orientación',
        'UP'
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      int rowIdx = 1;
      for (var row in datos) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
            .value = TextCellValue(row['id']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx))
            .value = TextCellValue(row['chacra']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx))
            .value = TextCellValue(row['cuadro']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx))
            .value = TextCellValue(row['cultivo']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
            .value = TextCellValue(row['variedad']?.toString() ?? '');
        sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx))
                .value =
            DoubleCellValue(double.tryParse(row['ha']?.toString() ?? '0') ?? 0.0);
        sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx))
                .value =
            IntCellValue(
                int.tryParse(row['ano_plantacion']?.toString() ?? '0') ?? 0);
        sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx))
                .value =
            IntCellValue(int.tryParse(row['plantas']?.toString() ?? '0') ?? 0);
        sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx))
                .value =
            DoubleCellValue(
                double.tryParse(row['dist_fila']?.toString() ?? '0') ?? 0.0);
        sheet
                .cell(
                    CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIdx))
                .value =
            DoubleCellValue(
                double.tryParse(row['dist_arbol']?.toString() ?? '0') ?? 0.0);
        sheet
                .cell(CellIndex.indexByColumnRow(
                    columnIndex: 10, rowIndex: rowIdx))
                .value =
            DoubleCellValue(
                double.tryParse(row['marco_plantacion']?.toString() ?? '0') ??
                    0.0);
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIdx))
            .value = TextCellValue(row['sitema_riego']?.toString() ?? '');
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIdx))
            .value = TextCellValue(row['sistema_def']?.toString() ?? '');
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIdx))
            .value = TextCellValue(row['orientacion']?.toString() ?? '');
        sheet
            .cell(
                CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIdx))
            .value = TextCellValue(row['up']?.toString() ?? '');
        rowIdx++;
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) return;

      final Uint8List bytes = Uint8List.fromList(fileBytes);
      final String nombreArchivo =
          'Inventario_${agroNombreArchivo(_selectedNombreProductor)}.xlsx';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.xlsx,
        texto: 'Catastro de Plantación - $_selectedNombreProductor',
        context: context,
      );
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'Error al exportar: $e',
            tipo: AgroSnackTipo.error);
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _sincronizarRemoto(
      String tabla, Map<String, dynamic> data) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from(tabla).upsert(data);
    } catch (e) {
      debugPrint("Aviso sync remoto en $tabla: $e");
    }
  }

  // ============================================================
  // HELPERS DE FORMULARIO
  // ============================================================

  /// Dos campos lado a lado; en pantallas muy angostas se apilan.
  Widget _parCampos(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 12), b],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  Widget _tituloBloque(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(texto.toUpperCase(), style: AgroText.overline),
    );
  }

  // ============================================================
  // SELECTOR DE PRODUCTOR
  // ============================================================

  void _abrirSelectorProductor() {
    if (!_esIngenieroOAdmin || _productores.isEmpty) return;
    String filtro = '';
    final ctrl = TextEditingController();

    mostrarAgroPanel<void>(
      context: context,
      titulo: 'Seleccionar productor',
      subtitulo: '${_productores.length} establecimientos activos',
      icono: Icons.swap_horiz_rounded,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModal) {
            final q = filtro.toLowerCase();
            final lista = _productores.where((p) {
              if (q.isEmpty) return true;
              return (p['productor'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(q) ||
                  (p['cuit'] ?? '').toString().toLowerCase().contains(q) ||
                  (p['localidad'] ?? '').toString().toLowerCase().contains(q);
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AgroSearchField(
                  controller: ctrl,
                  hint: 'Buscar por nombre, CUIT o localidad…',
                  onChanged: (v) => setModal(() => filtro = v),
                ),
                const SizedBox(height: 12),
                if (lista.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Sin coincidencias',
                        textAlign: TextAlign.center,
                        style: AgroText.secundario),
                  ),
                ...lista.map((p) {
                  final cod = p['cod_productor'] as int;
                  final sel = cod == _selectedCodProductor;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AgroCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      borderColor: sel ? AgroColors.primario : null,
                      color: sel ? AgroColors.primarioSoft : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        if (!sel) _cambiarProductor(cod);
                      },
                      child: Row(
                        children: [
                          AgroIconBox(
                            icono: Icons.agriculture_rounded,
                            size: 38,
                            color: sel
                                ? AgroColors.primario
                                : AgroTheme.colorTextSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['productor']?.toString() ?? 'S/N',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AgroTheme.colorText,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'CUIT ${p['cuit'] ?? 'S/D'} · ${p['localidad'] ?? 'Sin localidad'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AgroText.secundario,
                                ),
                              ],
                            ),
                          ),
                          if (sel)
                            const Icon(Icons.check_circle_rounded,
                                color: AgroColors.primario, size: 22),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // ALTA DE CUADRO
  // ============================================================

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
    bool guardando = false;

    mostrarAgroPanel<void>(
      context: context,
      titulo: 'Alta de cuadro / parcela',
      subtitulo: _selectedNombreProductor.isEmpty
          ? 'Parcela madre del establecimiento'
          : _selectedNombreProductor,
      icono: Icons.grid_view_rounded,
      maxWidth: 560,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            Future<void> guardar() async {
              if (guardando) return;
              if (!formKey.currentState!.validate()) return;
              setModalState(() => guardando = true);
              try {
                final db = await DatabaseHelper.instance.database;

                final int sigCodCuadro = await DatabaseHelper.instance
                    .obtenerSiguienteId('cuadros', 'cod_cuadro');

                final Map<String, dynamic> rowCuadro = {
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
                if (ctx.mounted) Navigator.pop(ctx);
                await _cargarDatosCompletos();

                if (!mounted) return;
                mostrarAgroSnack(
                  context,
                  'Cuadro ${rowCuadro['cuadro']} creado. Ahora asigná la plantación.',
                  tipo: AgroSnackTipo.ok,
                );
                _mostrarModalNuevaPlantacion(preseleccionCuadro: rowCuadro);
              } catch (e) {
                if (ctx2.mounted) setModalState(() => guardando = false);
                if (mounted) {
                  mostrarAgroSnack(context, 'No se pudo guardar el cuadro: $e',
                      tipo: AgroSnackTipo.error);
                }
              }
            }

            return Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tituloBloque('Identificación'),
                  TextFormField(
                    controller: chacraCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: agroInputDecoration(
                      label: "Nombre de chacra / lote",
                      icono: Icons.terrain_rounded,
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? "Obligatorio" : null,
                  ),
                  const SizedBox(height: 12),
                  _parCampos(
                    TextFormField(
                      controller: cuadroCtrl,
                      decoration: agroInputDecoration(
                        label: "N° de cuadro",
                        icono: Icons.grid_view_rounded,
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? "Obligatorio" : null,
                    ),
                    TextFormField(
                      controller: supCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: agroInputDecoration(
                        label: "Superficie",
                        icono: Icons.aspect_ratio_rounded,
                        sufijo: 'ha',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? "Obligatorio" : null,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _tituloBloque('Infraestructura'),
                  DropdownButtonFormField<String>(
                    value: riegoSeleccionado,
                    isExpanded: true,
                    decoration: agroInputDecoration(
                      label: "Sistema de riego",
                      icono: Icons.water_drop_outlined,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: "Goteo", child: Text("Riego por Goteo")),
                      DropdownMenuItem(
                          value: "Gravedad / Manto",
                          child: Text("Gravedad / Manto")),
                      DropdownMenuItem(
                          value: "Aspersión",
                          child: Text("Microaspersión / Aspersión")),
                      DropdownMenuItem(value: "Surco", child: Text("Por Surco")),
                    ],
                    onChanged: (v) =>
                        setModalState(() => riegoSeleccionado = v ?? "Goteo"),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: defensaSeleccionada,
                    isExpanded: true,
                    decoration: agroInputDecoration(
                      label: "Defensa climatológica",
                      icono: Icons.shield_outlined,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: "Ninguna", child: Text("Sin Defensa")),
                      DropdownMenuItem(
                          value: "Malla Antigranizo",
                          child: Text("Malla Antigranizo")),
                      DropdownMenuItem(
                          value: "Riego Subarbóreo (Antihelada)",
                          child: Text("Riego Subarbóreo (Antihelada)",
                              overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(
                          value: "Riego Supra-arbóreo (Antihelada)",
                          child: Text("Riego Supra-arbóreo")),
                      DropdownMenuItem(
                          value: "Calefactores / Molinos",
                          child: Text("Calefactores / Molinos de Viento",
                              overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setModalState(
                        () => defensaSeleccionada = v ?? "Ninguna"),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ubicacionCtrl,
                    decoration: agroInputDecoration(
                      label: "Ubicación / referencia",
                      hint: "Opcional",
                      icono: Icons.location_on_outlined,
                    ),
                  ),
                  const SizedBox(height: 22),
                  AgroButton(
                    label: "Guardar cuadro y asignar plantación",
                    icono: Icons.save_rounded,
                    expandido: true,
                    cargando: guardando,
                    onTap: guardar,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // ALTA DE CUARTEL DE PLANTACIÓN
  // ============================================================

  void _mostrarModalNuevaPlantacion(
      {Map<String, dynamic>? preseleccionCuadro}) {
    if (_cuadros.isEmpty) {
      _mostrarModalNuevoCuadro();
      return;
    }

    final formKey = GlobalKey<FormState>();

    Map<String, dynamic> cuadroActual = preseleccionCuadro ?? _cuadros.first;
    int codCuadroSeleccionado = cuadroActual['cod_cuadro'] as int;
    // Asegura que el cuadro preseleccionado exista entre las opciones.
    if (!_cuadros.any((c) => c['cod_cuadro'] == codCuadroSeleccionado)) {
      cuadroActual = _cuadros.first;
      codCuadroSeleccionado = cuadroActual['cod_cuadro'] as int;
    }

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
    bool guardando = false;

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

    mostrarAgroPanel<void>(
      context: context,
      titulo: 'Registrar cuartel de plantación',
      subtitulo: _selectedNombreProductor.isEmpty
          ? 'Especie, variedad, marco y densidad'
          : _selectedNombreProductor,
      icono: Icons.park_outlined,
      maxWidth: 600,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            final double distF =
                double.tryParse(distFilaCtrl.text.replaceAll(',', '.')) ?? 0.0;
            final double distA =
                double.tryParse(distArbolCtrl.text.replaceAll(',', '.')) ??
                    0.0;
            final double haForm =
                double.tryParse(haCtrl.text.replaceAll(',', '.')) ?? 0.0;
            final int plantasForm =
                int.tryParse(plantasCtrl.text.trim()) ?? 0;
            final double marco = distF * distA;
            final double densidad = marco > 0 ? 10000 / marco : 0.0;

            Future<void> guardar() async {
              if (guardando) return;
              if (!formKey.currentState!.validate()) return;
              setModalState(() => guardando = true);
              try {
                final db = await DatabaseHelper.instance.database;

                final int sigId = await DatabaseHelper.instance
                    .obtenerSiguienteId('inventario_plantacion', 'id');

                final double distF = double.tryParse(
                        distFilaCtrl.text.replaceAll(',', '.')) ??
                    0.0;
                final double distA = double.tryParse(
                        distArbolCtrl.text.replaceAll(',', '.')) ??
                    0.0;

                final Map<String, dynamic> rowInv = {
                  'id': sigId,
                  'cod_productor': _selectedCodProductor,
                  'productor': _selectedNombreProductor,
                  'chacra': cuadroActual['chacra'],
                  'cod_cuadro': codCuadroSeleccionado,
                  'cuadro': cuadroActual['cuadro'],
                  'cultivo': cultivoSeleccionado,
                  'variedad': variedadSeleccionada,
                  'ano_plantacion':
                      int.tryParse(anoCtrl.text.trim()) ?? DateTime.now().year,
                  'ha': double.tryParse(
                          haCtrl.text.trim().replaceAll(',', '.')) ??
                      0.0,
                  'plantas': int.tryParse(plantasCtrl.text.trim()) ?? 0,
                  'marco_plantacion': (distF * distA).round(),
                  'up': upCtrl.text.trim(),
                  'dist_arbol': distA,
                  'dist_fila': distF,
                  'orientacion': orientacionSeleccionada,
                  'sitema_riego': cuadroActual['sitema_riego'] ?? 'Goteo',
                  'sistema_def': cuadroActual['sistema_def'] ?? 'Ninguna',
                };

                await db.insert('inventario_plantacion', rowInv);
                await _sincronizarRemoto('inventario_plantacion', rowInv);

                if (!mounted) return;
                if (ctx.mounted) Navigator.pop(ctx);
                await _cargarDatosCompletos();

                if (!mounted) return;
                mostrarAgroSnack(
                  context,
                  "¡Cuartel de plantación registrado con éxito!",
                  tipo: AgroSnackTipo.ok,
                );
              } catch (e) {
                if (ctx2.mounted) setModalState(() => guardando = false);
                if (mounted) {
                  mostrarAgroSnack(
                      context, 'No se pudo guardar la plantación: $e',
                      tipo: AgroSnackTipo.error);
                }
              }
            }

            return Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cuadro destino
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AgroColors.primarioSoft,
                      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 18, color: AgroColors.primario),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Chacra: ${cuadroActual['chacra']} · Cuadro: ${cuadroActual['cuadro']}",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AgroColors.primario,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _tituloBloque('Ubicación y especie'),
                  DropdownButtonFormField<int>(
                    value: codCuadroSeleccionado,
                    isExpanded: true,
                    decoration: agroInputDecoration(
                      label: "Cuadro asignado",
                      icono: Icons.grid_view_rounded,
                    ),
                    items: _cuadros.map((c) {
                      return DropdownMenuItem<int>(
                        value: c['cod_cuadro'] as int,
                        child: Text(
                          "${c['chacra']} - Cuadro ${c['cuadro']} (${c['sup'] ?? 0} Ha)",
                          overflow: TextOverflow.ellipsis,
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
                          haCtrl.text = "${cuadroActual['sup'] ?? ''}";
                          calcularPlantasAuto();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _parCampos(
                    DropdownButtonFormField<String>(
                      value: cultivoSeleccionado,
                      isExpanded: true,
                      decoration: agroInputDecoration(
                        label: "Cultivo",
                        icono: Icons.eco_outlined,
                      ),
                      items: _cultivosVariedades.keys.map((cul) {
                        return DropdownMenuItem<String>(
                          value: cul,
                          child: Text(cul, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() {
                            cultivoSeleccionado = v;
                            listaVariedades = _cultivosVariedades[v] ?? [];
                            variedadSeleccionada = listaVariedades.first;
                          });
                        }
                      },
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>('variedad_$cultivoSeleccionado'),
                      value: variedadSeleccionada,
                      isExpanded: true,
                      decoration: agroInputDecoration(
                        label: "Variedad",
                        icono: Icons.nature_rounded,
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
                        () => variedadSeleccionada = v ?? listaVariedades.first,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _tituloBloque('Marco de plantación'),
                  _parCampos(
                    TextFormField(
                      controller: distFilaCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: agroInputDecoration(
                        label: "Entre filas",
                        icono: Icons.straighten_rounded,
                        sufijo: 'm',
                      ),
                      onChanged: (_) => setModalState(calcularPlantasAuto),
                    ),
                    TextFormField(
                      controller: distArbolCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: agroInputDecoration(
                        label: "Entre plantas",
                        icono: Icons.height_rounded,
                        sufijo: 'm',
                      ),
                      onChanged: (_) => setModalState(calcularPlantasAuto),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _parCampos(
                    TextFormField(
                      controller: haCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: agroInputDecoration(
                        label: "Superficie",
                        icono: Icons.aspect_ratio_rounded,
                        sufijo: 'ha',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? "Obligatorio" : null,
                      onChanged: (_) => setModalState(calcularPlantasAuto),
                    ),
                    TextFormField(
                      controller: plantasCtrl,
                      keyboardType: TextInputType.number,
                      decoration: agroInputDecoration(
                        label: "Total plantas",
                        icono: Icons.forest_outlined,
                        helper: "Se calcula según marco y superficie",
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? "Obligatorio" : null,
                      onChanged: (_) => setModalState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AgroStatGrid(
                    fondo: AgroTheme.colorBg,
                    stats: [
                      AgroStat(
                        label: 'Marco',
                        valor: marco > 0
                            ? '${_fmtHa.format(marco)} m²'
                            : '—',
                        icono: Icons.grid_4x4_rounded,
                      ),
                      AgroStat(
                        label: 'Densidad teórica',
                        valor: densidad > 0
                            ? '${_fmtEntero.format(densidad)} pl/ha'
                            : '—',
                        icono: Icons.scatter_plot_outlined,
                      ),
                      AgroStat(
                        label: 'Densidad real',
                        valor: haForm > 0 && plantasForm > 0
                            ? '${_fmtEntero.format(plantasForm / haForm)} pl/ha'
                            : '—',
                        icono: Icons.forest_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _tituloBloque('Datos complementarios'),
                  _parCampos(
                    TextFormField(
                      controller: anoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: agroInputDecoration(
                        label: "Año de plantación",
                        icono: Icons.event_note_rounded,
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? "Obligatorio" : null,
                    ),
                    TextFormField(
                      controller: upCtrl,
                      decoration: agroInputDecoration(
                        label: "UP (unidad productiva)",
                        icono: Icons.badge_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: orientacionSeleccionada,
                    isExpanded: true,
                    decoration: agroInputDecoration(
                      label: "Orientación de filas",
                      icono: Icons.explore_outlined,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: "Norte - Sur",
                          child: Text("Norte - Sur (Recomendada)")),
                      DropdownMenuItem(
                          value: "Este - Oeste", child: Text("Este - Oeste")),
                      DropdownMenuItem(
                          value: "Diagonal / Otra",
                          child: Text("Diagonal / Otra")),
                    ],
                    onChanged: (v) => setModalState(
                        () => orientacionSeleccionada = v ?? "Norte - Sur"),
                  ),
                  const SizedBox(height: 22),
                  AgroButton(
                    label: "Guardar plantación",
                    icono: Icons.save_rounded,
                    expandido: true,
                    cargando: guardando,
                    onTap: guardar,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // OPCIONES DE CARGA
  // ============================================================

  void _mostrarOpcionesCarga() {
    mostrarAgroPanel<void>(
      context: context,
      titulo: 'Cargar catastro agronómico',
      subtitulo: 'Elegí qué nivel de detalle querés dar de alta',
      icono: Icons.add_business_outlined,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AgroOptionTile(
              icono: Icons.grid_view_rounded,
              titulo: '1. Nuevo cuadro / parcela',
              descripcion:
                  'Define la parcela madre, riego, defensa y superficie total.',
              color: AgroColors.ok,
              onTap: () {
                Navigator.pop(ctx);
                _mostrarModalNuevoCuadro();
              },
            ),
            AgroOptionTile(
              icono: Icons.park_outlined,
              titulo: '2. Nuevo cuartel de plantación',
              descripcion: _cuadros.isEmpty
                  ? 'Primero necesitás un cuadro: se abrirá el alta de cuadro.'
                  : 'Asigna especie, variedad, marco y densidad dentro de un cuadro.',
              color: AgroColors.warn,
              onTap: () {
                Navigator.pop(ctx);
                _mostrarModalNuevaPlantacion();
              },
            ),
            const SizedBox(height: 4),
            Text(
              '${_cuadros.length} ${_cuadros.length == 1 ? 'cuadro cargado' : 'cuadros cargados'} · ${_inventario.length} ${_inventario.length == 1 ? 'cuartel' : 'cuarteles'}',
              textAlign: TextAlign.center,
              style: AgroText.secundario,
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // FICHA TÉCNICA
  // ============================================================

  void _mostrarFichaTecnicaParcela(Map<String, dynamic> item) {
    final ha = _haDe(item);
    final ano = item['ano_plantacion'] ?? 'S/D';
    final edad = ano != 'S/D' && int.tryParse(ano.toString()) != null
        ? "${DateTime.now().year - int.parse(ano.toString())} años"
        : "S/D";
    final plantas = _plantasDe(item);
    final densidad = ha > 0 && plantas > 0 ? plantas / ha : 0.0;
    final cultivo = (item['cultivo'] ?? 'General').toString();

    mostrarAgroPanel<void>(
      context: context,
      titulo: "Ficha técnica · Cuadro ${item['cuadro'] ?? 'S/N'}",
      subtitulo: "Chacra: ${item['chacra'] ?? 'S/D'} · UP: ${item['up'] ?? 'S/D'}",
      icono: Icons.park_outlined,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AgroIconBox(
                  icono: Icons.eco_rounded,
                  color: _colorCultivo(cultivo),
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${item['variedad'] ?? 'S/D'}",
                        style: AgroText.tituloCard,
                      ),
                      Text(cultivo, style: AgroText.secundario),
                    ],
                  ),
                ),
                AgroBadge(
                  texto: '${_fmtHa.format(ha)} ha',
                  grande: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            AgroStatGrid(
              stats: [
                AgroStat(
                  label: 'Superficie',
                  valor: '${ha.toStringAsFixed(2)} Ha',
                  icono: Icons.aspect_ratio_rounded,
                ),
                AgroStat(
                  label: 'Variedad',
                  valor: "${item['variedad']}",
                  icono: Icons.nature_rounded,
                ),
                AgroStat(
                  label: 'Especie',
                  valor: "${item['cultivo']}",
                  icono: Icons.eco_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            AgroKeyValue(
              icono: Icons.date_range_rounded,
              clave: "Año de plantación",
              valor: "$ano ($edad)",
            ),
            AgroKeyValue(
              icono: Icons.forest_rounded,
              clave: "Cantidad de plantas",
              valor: "${item['plantas'] ?? 'S/D'} plantas",
            ),
            AgroKeyValue(
              icono: Icons.scatter_plot_outlined,
              clave: "Densidad",
              valor: densidad > 0
                  ? "${_fmtEntero.format(densidad)} pl/ha"
                  : "S/D",
            ),
            AgroKeyValue(
              icono: Icons.grid_4x4_rounded,
              clave: "Marco de plantación",
              valor:
                  "${item['dist_fila'] ?? '-'}m x ${item['dist_arbol'] ?? '-'}m",
            ),
            AgroKeyValue(
              icono: Icons.water_drop_outlined,
              clave: "Sistema de riego",
              valor: "${item['sitema_riego'] ?? 'Goteo'}",
            ),
            AgroKeyValue(
              icono: Icons.shield_outlined,
              clave: "Defensa antigranizo / helada",
              valor: "${item['sistema_def'] ?? 'Ninguna'}",
            ),
            AgroKeyValue(
              icono: Icons.explore_outlined,
              clave: "Orientación de filas",
              valor: "${item['orientacion'] ?? 'Norte - Sur'}",
            ),
            AgroKeyValue(
              icono: Icons.badge_outlined,
              clave: "Unidad productiva (UP)",
              valor: "${item['up'] ?? 'S/D'}",
            ),
            const SizedBox(height: 16),
            AgroButton(
              label: 'Cerrar',
              tipo: AgroButtonTipo.secundario,
              expandido: true,
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final esMovil = AgroBreakpoints.esMovil(context);
    final filtrado = _inventarioFiltrado;
    final bool puedeCargar = _puedeEditar && _selectedCodProductor != null;

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: "Inventario de plantación",
        subtitulo: _selectedNombreProductor.isNotEmpty
            ? _selectedNombreProductor
            : null,
        acciones: [
          AgroIconButton(
            icono: Icons.table_view_rounded,
            tooltip: _exportando ? "Generando Excel…" : "Exportar a Excel",
            color: AgroColors.ok,
            onTap: filtrado.isEmpty || _exportando || _cargando
                ? null
                : _exportarExcelInventario,
          ),
          const SizedBox(width: 8),
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: "Recargar",
            color: AgroColors.primario,
            onTap: _cargando || _selectedCodProductor == null
                ? null
                : _cargarDatosCompletos,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _cargando
            ? const AgroLoading(mensaje: 'Cargando catastro de plantación…')
            : RefreshIndicator(
                color: AgroColors.primario,
                onRefresh: _cargarDatosCompletos,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 16, bottom: 110),
                  child: AgroContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTarjetaProductor(esMovil),
                        const SizedBox(height: 16),
                        if (_selectedCodProductor == null)
                          const AgroEmptyState(
                            icono: Icons.person_off_outlined,
                            titulo: 'No hay productores activos',
                            mensaje:
                                'Sincronizá los datos o dá de alta un productor para gestionar su plantación.',
                          )
                        else ...[
                          _buildKpis(filtrado),
                          const SizedBox(height: 18),
                          if (_inventario.isNotEmpty) ...[
                            _buildFiltros(),
                            const SizedBox(height: 12),
                            _buildResumenFiltro(filtrado),
                            const SizedBox(height: 6),
                          ],
                          if (_inventario.isEmpty)
                            _buildVacioInicial(puedeCargar)
                          else if (filtrado.isEmpty)
                            AgroEmptyState(
                              icono: Icons.search_off_rounded,
                              titulo: 'Sin resultados',
                              mensaje:
                                  'Ningún cuartel coincide con la chacra o la búsqueda. Probá con otros filtros.',
                              accion: AgroButton(
                                label: 'Limpiar filtros',
                                icono: Icons.filter_alt_off_rounded,
                                tipo: AgroButtonTipo.secundario,
                                onTap: _limpiarFiltros,
                              ),
                            )
                          else
                            _buildListado(filtrado),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButton: puedeCargar && !_cargando
          ? FloatingActionButton.extended(
              onPressed: _mostrarOpcionesCarga,
              backgroundColor: AgroColors.primario,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                esMovil ? "Cargar" : "Cargar parcela / plantación",
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
    );
  }

  Widget _buildTarjetaProductor(bool esMovil) {
    final bool puedeCambiar = _esIngenieroOAdmin && _productores.isNotEmpty;
    final String nombre = _selectedNombreProductor.isNotEmpty
        ? _selectedNombreProductor
        : (_esIngenieroOAdmin ? 'Sin productor seleccionado' : 'Mi establecimiento');
    final String? cuit = _productorInfo?['cuit']?.toString();
    final String? localidad = _productorInfo?['localidad']?.toString();
    final List<String> detalles = [
      if (cuit != null && cuit.isNotEmpty) 'CUIT $cuit',
      if (localidad != null && localidad.isNotEmpty) localidad,
    ];

    return AgroCard(
      onTap: puedeCambiar ? _abrirSelectorProductor : null,
      accentColor: AgroColors.primario,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const AgroIconBox(icono: Icons.agriculture_rounded, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _esIngenieroOAdmin ? 'PRODUCTOR EN GESTIÓN' : 'MI ESTABLECIMIENTO',
                  style: AgroText.overline,
                ),
                const SizedBox(height: 2),
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AgroTheme.colorText,
                  ),
                ),
                if (detalles.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detalles.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgroText.secundario,
                  ),
                ],
              ],
            ),
          ),
          if (puedeCambiar) ...[
            const SizedBox(width: 8),
            if (esMovil)
              const Icon(Icons.unfold_more_rounded,
                  color: AgroTheme.colorTextSecondary)
            else
              const AgroBadge(
                texto: 'Cambiar',
                icono: Icons.swap_horiz_rounded,
                grande: true,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildKpis(List<Map<String, dynamic>> filtrado) {
    final double sup = _superficieDe(filtrado);
    final int plantas = _plantasTotalesDe(filtrado);
    final double densidad = sup > 0 ? plantas / sup : 0.0;
    final int variedades = filtrado
        .map((e) => (e['variedad'] ?? '').toString().trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .length;
    final int cultivos = filtrado
        .map((e) => (e['cultivo'] ?? '').toString().trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .length;

    return AgroKpiGrid(
      maxColumnas: 5,
      anchoMinimo: 150,
      kpis: [
        AgroKpiTile(
          label: 'Superficie',
          valor: '${_fmtHa.format(sup)} ha',
          icono: Icons.terrain_rounded,
          color: AgroColors.primario,
        ),
        AgroKpiTile(
          label: 'Plantas',
          valor: _fmtEntero.format(plantas),
          icono: Icons.forest_outlined,
          color: AgroColors.ok,
        ),
        AgroKpiTile(
          label: 'Densidad media',
          valor: _fmtEntero.format(densidad),
          detalle: 'plantas / ha',
          icono: Icons.scatter_plot_outlined,
          color: AgroColors.info,
        ),
        AgroKpiTile(
          label: 'Cuarteles',
          valor: '${filtrado.length}',
          detalle: '${_cuadros.length} cuadros en total',
          icono: Icons.grid_view_rounded,
          color: AgroColors.warn,
        ),
        AgroKpiTile(
          label: 'Variedades',
          valor: '$variedades',
          detalle: '$cultivos ${cultivos == 1 ? 'especie' : 'especies'}',
          icono: Icons.nature_rounded,
          color: const Color(0xFF6A1B9A),
        ),
      ],
    );
  }

  Widget _buildFiltros() {
    final opcionesChacra =
        _chacrasDisponibles.where((c) => c != "TODAS").toList();

    return LayoutBuilder(
      builder: (context, c) {
        final buscador = AgroSearchField(
          controller: _searchCtrl,
          hint: "Buscar por cuadro, variedad, cultivo o UP…",
          onChanged: (val) => setState(() => _filtroTexto = val),
        );

        final Widget? chips = opcionesChacra.isEmpty
            ? null
            : AgroChipSelector(
                label: 'Chacra',
                opciones: opcionesChacra,
                valor: _chacraSeleccionada == "TODAS"
                    ? null
                    : _chacraSeleccionada,
                textoTodos: 'Todas',
                onChanged: (v) =>
                    setState(() => _chacraSeleccionada = v ?? "TODAS"),
              );

        if (chips != null && c.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(flex: 5, child: buscador),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: chips),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buscador,
            if (chips != null) ...[
              const SizedBox(height: 12),
              chips,
            ],
          ],
        );
      },
    );
  }

  Widget _buildResumenFiltro(List<Map<String, dynamic>> filtrado) {
    final String texto = _hayFiltros
        ? 'Mostrando ${filtrado.length} de ${_inventario.length} cuarteles'
        : '${_inventario.length} ${_inventario.length == 1 ? 'cuartel registrado' : 'cuarteles registrados'}';
    return Row(
      children: [
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AgroText.label,
          ),
        ),
        if (_hayFiltros)
          AgroButton(
            label: 'Limpiar filtros',
            icono: Icons.filter_alt_off_rounded,
            tipo: AgroButtonTipo.texto,
            compacto: true,
            onTap: _limpiarFiltros,
          )
        else
          const SizedBox(height: 38),
      ],
    );
  }

  Widget _buildVacioInicial(bool puedeCargar) {
    final String mensaje = _cuadros.isEmpty
        ? "Este establecimiento no cuenta aún con cuarteles cargados.\nPodés registrar el primer cuadro y su plantación ahora mismo."
        : "Hay ${_cuadros.length} ${_cuadros.length == 1 ? 'cuadro cargado' : 'cuadros cargados'} sin cuarteles de plantación.\nAsigná especie y variedad para completar el catastro.";
    return AgroEmptyState(
      icono: Icons.nature_people_rounded,
      titulo: "Sin plantaciones registradas",
      mensaje: mensaje,
      accion: puedeCargar
          ? AgroButton(
              label: _cuadros.isEmpty
                  ? "Cargar mi primer cuadro"
                  : "Cargar plantación",
              icono: Icons.add_circle_outline_rounded,
              onTap: _mostrarOpcionesCarga,
            )
          : null,
    );
  }

  Widget _buildListado(List<Map<String, dynamic>> filtrado) {
    final Map<String, List<Map<String, dynamic>>> grupos = {};
    for (final it in filtrado) {
      final ch = (it['chacra'] ?? '').toString().trim();
      grupos
          .putIfAbsent(ch.isEmpty ? 'Sin chacra' : ch,
              () => <Map<String, dynamic>>[])
          .add(it);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final int cols = c.maxWidth >= 700 ? 2 : 1;
        const double gap = 12;
        final double w =
            ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in grupos.entries) ...[
              const SizedBox(height: 12),
              _buildHeaderChacra(e.key, e.value),
              const SizedBox(height: 10),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: e.value
                    .map((it) => SizedBox(
                          width: w,
                          child: _CuartelCard(
                            item: it,
                            onTap: () => _mostrarFichaTecnicaParcela(it),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHeaderChacra(String chacra, List<Map<String, dynamic>> items) {
    final double sup = _superficieDe(items);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AgroColors.primarioSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.terrain_rounded,
              size: 17, color: AgroColors.primario),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            chacra,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AgroTheme.colorText,
            ),
          ),
        ),
        const SizedBox(width: 8),
        AgroBadge(
          texto:
              '${_fmtHa.format(sup)} ha · ${items.length} ${items.length == 1 ? 'cuartel' : 'cuarteles'}',
          color: AgroColors.neutral,
          fondo: AgroColors.neutralSoft,
        ),
      ],
    );
  }
}

// ============================================================
// TARJETA DE CUARTEL
// ============================================================

class _CuartelCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _CuartelCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ha = _haDe(item);
    final plantasNum = _plantasDe(item);
    final variedad = (item['variedad'] ?? 'S/D').toString();
    final cultivo = (item['cultivo'] ?? 'General').toString();
    final ano = (item['ano_plantacion'] ?? 'S/D').toString();
    final riego = (item['sitema_riego'] ?? 'S/D').toString();
    final up = (item['up'] ?? '').toString().trim();
    final densidad = ha > 0 && plantasNum > 0 ? plantasNum / ha : 0.0;
    final color = _colorCultivo(cultivo);

    return AgroCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AgroIconBox(icono: Icons.eco_rounded, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variedad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.tituloCard,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      up.isEmpty ? cultivo : '$cultivo · $up',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.secundario,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_fmtHa.format(ha)} ha',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AgroColors.primario,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AgroBadge(texto: 'Cuadro ${item['cuadro'] ?? ''}'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          AgroStatGrid(
            stats: [
              AgroStat(
                label: 'Plantación',
                valor: ano,
                icono: Icons.event_note_rounded,
              ),
              AgroStat(
                label: 'Plantas',
                valor: plantasNum > 0 ? _fmtEntero.format(plantasNum) : '0',
                icono: Icons.forest_outlined,
              ),
              AgroStat(
                label: 'Densidad',
                valor: densidad > 0
                    ? '${_fmtEntero.format(densidad)} pl/ha'
                    : 'S/D',
                icono: Icons.scatter_plot_outlined,
              ),
              AgroStat(
                label: 'Riego',
                valor: riego,
                icono: Icons.water_drop_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
