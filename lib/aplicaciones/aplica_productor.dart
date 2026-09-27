// ignore_for_file: deprecated_member_use

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/agro_ui.dart';
import 'ordenes_generadas.dart';

class AplicaProductorScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const AplicaProductorScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<AplicaProductorScreen> createState() => _AplicaProductorScreenState();
}

class _AplicaProductorScreenState extends State<AplicaProductorScreen> {
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;
  String _filtroTexto = "";
  bool _cargando = true;
  bool _soloConOrdenes = false;
  bool _exportando = false;

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

  // ============================================================
  // LÓGICA
  // ============================================================

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final prefs = await SharedPreferences.getInstance();
    _userRole =
        (prefs.getString('userRole') ?? "OPE-PROD").toUpperCase().trim();
    _userCodProductor = prefs.getInt('userCodProductor') ?? 0;

    final db = await DatabaseHelper.instance.database;

    List<Map<String, dynamic>> listaProds = [];

    if (_userRole == 'ADMIN' ||
        _userRole == 'INGENIERO' ||
        _userRole == 'OPE-APLI') {
      listaProds = await db.query(
        'productores',
        where: 'estado = ?',
        whereArgs: ['ACTIVO'],
        orderBy: 'productor ASC',
      );
    } else {
      listaProds = await db.query(
        'productores',
        where: 'cod_productor = ? AND estado = ?',
        whereArgs: [_userCodProductor, 'ACTIVO'],
      );
    }

    // Una sola consulta agrupada (antes era una consulta por productor).
    final Map<int, int> mapaConteo = {};
    final res = await db.rawQuery(
      'SELECT cod_productor, COUNT(DISTINCT cod_orden) as total '
      'FROM recetas_aplicaciones WHERE habilitado = ? GROUP BY cod_productor',
      ['ACTIVO'],
    );
    for (final r in res) {
      final cod = int.tryParse(r['cod_productor']?.toString() ?? '');
      if (cod != null) {
        mapaConteo[cod] = int.tryParse(r['total']?.toString() ?? '0') ?? 0;
      }
    }

    if (!mounted) return;
    setState(() {
      _productores = listaProds;
      _conteoOrdenes = mapaConteo;
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _productoresFiltrados {
    final query = _filtroTexto.toLowerCase().trim();
    return _productores.where((p) {
      if (_soloConOrdenes) {
        final cod = p['cod_productor'] as int;
        if ((_conteoOrdenes[cod] ?? 0) == 0) return false;
      }
      if (query.isEmpty) return true;
      final nombre = (p['productor'] ?? '').toString().toLowerCase();
      final cuit = (p['cuit'] ?? '').toString().toLowerCase();
      final renspa = (p['renspa'] ?? '').toString().toLowerCase();
      final loc = (p['localidad'] ?? '').toString().toLowerCase();
      return nombre.contains(query) ||
          cuit.contains(query) ||
          renspa.contains(query) ||
          loc.contains(query);
    }).toList();
  }

  // Solo suma los productores visibles para el usuario (el GROUP BY trae todos).
  int get _totalOrdenesActivas => _productores.fold<int>(
      0, (a, p) => a + (_conteoOrdenes[p['cod_productor'] as int] ?? 0));

  int get _productoresConOrdenes => _productores
      .where((p) => (_conteoOrdenes[p['cod_productor'] as int] ?? 0) > 0)
      .length;

  Future<void> _exportarExcelProductores() async {
    setState(() => _exportando = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Productores'];
      excel.delete('Sheet1');

      final headerStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#1E6B4C'),
        horizontalAlign: HorizontalAlign.Center,
      );

      final headers = [
        'Código',
        'Razón Social / Productor',
        'CUIT',
        'RENSPA',
        'Localidad',
        'Estado',
        'Órdenes Activas'
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      int rowIdx = 1;
      for (var p in _productoresFiltrados) {
        final cod = p['cod_productor'] as int;
        final totalOrd = _conteoOrdenes[cod] ?? 0;

        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
            .value = IntCellValue(cod);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx))
            .value = TextCellValue(p['productor']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx))
            .value = TextCellValue(p['cuit']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx))
            .value = TextCellValue(p['renspa']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
            .value = TextCellValue(p['localidad']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx))
            .value = TextCellValue(p['estado']?.toString() ?? 'ACTIVO');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx))
            .value = IntCellValue(totalOrd);
        rowIdx++;
      }

      const nombreArchivo = "Resumen_Productores_AgroSoft.xlsx";

      if (kIsWeb) {
        // En web, el paquete excel dispara la descarga directa en el navegador.
        excel.save(fileName: nombreArchivo);
      } else {
        final fileBytes = excel.save();
        if (fileBytes == null) return;
        // XFile.fromData evita dart:io → compatible con todas las plataformas.
        await Share.shareXFiles(
          [
            XFile.fromData(
              Uint8List.fromList(fileBytes),
              name: nombreArchivo,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            )
          ],
          subject: "Listado de Productores - AgroSoft J&L",
        );
      }
    } catch (e) {
      if (!mounted) return;
      mostrarAgroSnack(context, "Error al exportar Excel: $e",
          tipo: AgroSnackTipo.error);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
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
    ).then((_) => _cargarDatos());
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final esMovil = AgroBreakpoints.esMovil(context);
    final filtrados = _productoresFiltrados;

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: "Órdenes de Aplicación",
        subtitulo: "Elegí un productor · Rol: $_userRole",
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: "Recargar",
            onTap: _cargando ? null : _cargarDatos,
          ),
          const SizedBox(width: 8),
          if (esMovil)
            AgroIconButton(
              icono: Icons.table_view_rounded,
              tooltip: "Exportar listado a Excel",
              color: AgroColors.ok,
              onTap: filtrados.isEmpty || _exportando
                  ? null
                  : _exportarExcelProductores,
            )
          else
            AgroButton(
              label: "Exportar Excel",
              icono: Icons.table_view_rounded,
              tipo: AgroButtonTipo.secundario,
              compacto: true,
              cargando: _exportando,
              onTap: filtrados.isEmpty ? null : _exportarExcelProductores,
            ),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const AgroLoading(mensaje: 'Cargando productores…')
            : RefreshIndicator(
                color: AgroColors.primario,
                onRefresh: _cargarDatos,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: AgroContent(
                        maxWidth: 1180,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 18, bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildResumen(),
                              const SizedBox(height: 14),
                              _buildFiltros(esMovil),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (filtrados.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: AgroEmptyState(
                          icono: Icons.person_search_outlined,
                          titulo: "No se encontraron productores",
                          mensaje: _filtroTexto.isNotEmpty || _soloConOrdenes
                              ? "Probá con otro término de búsqueda o quitá los filtros."
                              : "No hay productores activos asignados a tu usuario.",
                          accion: _filtroTexto.isNotEmpty || _soloConOrdenes
                              ? AgroButton(
                                  label: 'Limpiar filtros',
                                  icono: Icons.filter_alt_off_rounded,
                                  tipo: AgroButtonTipo.secundario,
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() {
                                      _filtroTexto = '';
                                      _soloConOrdenes = false;
                                    });
                                  },
                                )
                              : null,
                        ),
                      )
                    else
                      SliverToBoxAdapter(
                        child: AgroContent(
                          maxWidth: 1180,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 40),
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final cols = c.maxWidth >= 1000
                                    ? 3
                                    : (c.maxWidth >= 640 ? 2 : 1);
                                const gap = 12.0;
                                final w =
                                    ((c.maxWidth - gap * (cols - 1)) / cols)
                                        .floorToDouble();
                                return Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: filtrados.map((prod) {
                                    final codProd =
                                        prod['cod_productor'] as int;
                                    return SizedBox(
                                      width: w,
                                      child: _ProductorCard(
                                        productor: prod,
                                        totalOrdenes:
                                            _conteoOrdenes[codProd] ?? 0,
                                        onTap: () => _navegarAOrdenes(prod),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildResumen() {
    return AgroStatGrid(
      fondo: AgroTheme.colorSurface,
      stats: [
        AgroStat(
          label: 'Productores',
          valor: '${_productores.length}',
          icono: Icons.groups_2_outlined,
        ),
        AgroStat(
          label: 'Con órdenes activas',
          valor: '$_productoresConOrdenes',
          icono: Icons.assignment_turned_in_outlined,
          color: AgroColors.ok,
        ),
        AgroStat(
          label: 'Órdenes activas',
          valor: '$_totalOrdenesActivas',
          icono: Icons.pending_actions_rounded,
          color: AgroColors.warn,
        ),
      ],
    );
  }

  Widget _buildFiltros(bool esMovil) {
    final buscador = AgroSearchField(
      controller: _searchController,
      hint: "Buscar por nombre, CUIT, RENSPA o localidad…",
      onChanged: (val) => setState(() => _filtroTexto = val),
    );

    final filtro = FilterChip(
      label: const Text('Solo con órdenes activas'),
      selected: _soloConOrdenes,
      onSelected: (v) => setState(() => _soloConOrdenes = v),
      showCheckmark: true,
      checkmarkColor: AgroColors.primario,
      selectedColor: AgroColors.primarioSoft,
      backgroundColor: AgroTheme.colorSurface,
      side: BorderSide(
        color: _soloConOrdenes ? AgroColors.primario : AgroTheme.colorBorder,
      ),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: _soloConOrdenes ? AgroColors.primario : AgroTheme.colorText,
      ),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );

    if (esMovil) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [buscador, const SizedBox(height: 10), filtro],
      );
    }
    return Row(
      children: [
        Expanded(child: buscador),
        const SizedBox(width: 12),
        filtro,
      ],
    );
  }
}

// ============================================================
// TARJETA DE PRODUCTOR
// ============================================================

class _ProductorCard extends StatelessWidget {
  final Map<String, dynamic> productor;
  final int totalOrdenes;
  final VoidCallback onTap;

  const _ProductorCard({
    required this.productor,
    required this.totalOrdenes,
    required this.onTap,
  });

  String _iniciales(String nombre) {
    final partes =
        nombre.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes[0][0] + partes[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final String nombre = productor['productor']?.toString() ?? 'Sin nombre';
    final String cuit = productor['cuit']?.toString() ?? 'S/D';
    final String renspa = productor['renspa']?.toString() ?? 'S/D';
    final String localidad =
        productor['localidad']?.toString() ?? 'Sin localidad';
    final bool tieneOrdenes = totalOrdenes > 0;

    return AgroCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tieneOrdenes
                      ? AgroColors.primarioSoft
                      : AgroColors.neutralSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _iniciales(nombre),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: tieneOrdenes
                        ? AgroColors.primario
                        : AgroColors.neutral,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.tituloCard.copyWith(fontSize: 14.5),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: AgroTheme.colorTextSecondary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            localidad,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AgroText.secundario.copyWith(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AgroTheme.colorTextSecondary),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AgroTheme.colorBorder),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  "CUIT $cuit  ·  RENSPA $renspa",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.secundario.copyWith(fontSize: 11.5),
                ),
              ),
              const SizedBox(width: 8),
              AgroBadge(
                texto:
                    "$totalOrdenes ${totalOrdenes == 1 ? 'orden activa' : 'órdenes activas'}",
                color: tieneOrdenes ? AgroColors.ok : AgroColors.neutral,
                fondo: tieneOrdenes ? AgroColors.okSoft : AgroColors.neutralSoft,
                icono: tieneOrdenes ? Icons.circle : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
