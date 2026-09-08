import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:excel/excel.dart' hide Border;

import '../base/base.dart';
import '../constantes/tema.dart';
import 'ordenes_generadas.dart';

class AplicaProductorScreen extends StatefulWidget {
  const AplicaProductorScreen({
    super.key,
    required int codProductor,
    required String nombreProductor,
  });

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

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final prefs = await SharedPreferences.getInstance();
    _userRole = (prefs.getString('userRole') ?? "OPE-PROD").toUpperCase().trim();
    _userCodProductor = prefs.getInt('userCodProductor') ?? 0;

    final db = await DatabaseHelper.instance.database;

    List<Map<String, dynamic>> listaProds = [];

    if (_userRole == 'ADMIN' || _userRole == 'INGENIERO' || _userRole == 'OPE-APLI') {
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
      return nombre.contains(query) ||
          cuit.contains(query) ||
          renspa.contains(query) ||
          loc.contains(query);
    }).toList();
  }

  Future<void> _exportarExcelProductores() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Productores'];
      excel.delete('Sheet1');

      // Estilos de encabezado
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
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      int rowIdx = 1;
      for (var p in _productoresFiltrados) {
        final cod = p['cod_productor'] as int;
        final totalOrd = _conteoOrdenes[cod] ?? 0;

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value =
            IntCellValue(cod);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value =
            TextCellValue(p['productor']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value =
            TextCellValue(p['cuit']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value =
            TextCellValue(p['renspa']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value =
            TextCellValue(p['localidad']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value =
            TextCellValue(p['estado']?.toString() ?? 'ACTIVO');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value =
            IntCellValue(totalOrd);
        rowIdx++;
      }

      final fileBytes = excel.save();
      if (fileBytes == null) return;

      final tempDir = await getTemporaryDirectory();
      final filePath = "${tempDir.path}/Resumen_Productores_AgroSoft.xlsx";
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: "Listado de Productores - AgroSoft J&L",
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFC62828), content: Text("Error al exportar Excel: $e")),
      );
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
              "Seleccionar Productor",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText),
            ),
            Text(
              "Rol activo: $_userRole",
              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          // Botón Exportar a Excel
          IconButton(
            icon: const Icon(Icons.table_view_rounded, color: Color(0xFF2E7D32)),
            tooltip: "Exportar listado a Excel",
            onPressed: _productoresFiltrados.isEmpty ? null : _exportarExcelProductores,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E6B4C)),
            tooltip: "Recargar",
            onPressed: _cargarDatos,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AgroTheme.colorSurface,
                      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                      border: Border.all(color: AgroTheme.colorBorder),
                      boxShadow: const [
                        BoxShadow(color: Color(0x04141E18), blurRadius: 8, offset: Offset(0, 2)),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _filtroTexto = val),
                      style: const TextStyle(color: AgroTheme.colorText, fontSize: 13.5),
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
                        contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _cargando
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B4C)))
                      : _productoresFiltrados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.person_search_outlined, size: 44, color: AgroTheme.colorTextSecondary),
                                  SizedBox(height: 12),
                                  Text(
                                    "No se encontraron productores",
                                    style: TextStyle(fontWeight: FontWeight.w700, color: AgroTheme.colorTextSecondary, fontSize: 15),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                              itemCount: _productoresFiltrados.length,
                              // ignore: unnecessary_underscores
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
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
        ),
      ),
    );
  }
}



class _ProductorCard extends StatelessWidget {
  final Map<String, dynamic> productor;
  final int totalOrdenes;
  final VoidCallback onTap;

  const _ProductorCard({
    required this.productor,
    required this.totalOrdenes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = productor['productor'] ?? 'Sin Nombre';
    final cuit = productor['cuit'] ?? 'S/D';
    final renspa = productor['renspa'] ?? 'S/D';
    final localidad = productor['localidad'] ?? 'Sin Localidad';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
          border: Border.all(color: AgroTheme.colorBorder),
          boxShadow: const [
            BoxShadow(color: Color(0x03141E18), blurRadius: 4, offset: Offset(0, 1.5)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.business_outlined, color: Color(0xFF2E7D32), size: 20),
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
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AgroTheme.colorText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: totalOrdenes > 0 ? const Color(0xFFE8F5E9) : const Color(0xFFECEFF1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "$totalOrdenes ${totalOrdenes == 1 ? 'orden' : 'órdenes'}",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: totalOrdenes > 0 ? const Color(0xFF2E7D32) : const Color(0xFF546E7A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "CUIT: $cuit  ·  RENSPA: $renspa",
                          style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: AgroTheme.colorTextSecondary),
                          const SizedBox(width: 2),
                          Text(
                            localidad,
                            style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AgroTheme.colorTextSecondary),
          ],
        ),
      ),
    );
  }
}