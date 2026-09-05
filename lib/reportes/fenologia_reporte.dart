import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

class ReportesFenologiaScreen extends StatefulWidget {
  const ReportesFenologiaScreen({super.key});

  @override
  State<ReportesFenologiaScreen> createState() => _ReportesFenologiaScreenState();
}

class _ReportesFenologiaScreenState extends State<ReportesFenologiaScreen> {
  bool _cargando = true;
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;
  String _nombreProductor = "";
  String _cuitProductor = "S/D";
  String _renspaProductor = "S/D";

  String _tipoReporte = "AUDITORIA"; // AUDITORIA | INTERNO
  String _filtroCultivo = "TODOS";
  String _filtroSector = "TODOS";
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  List<String> _cultivosDisponibles = ["TODOS"];
  List<String> _sectoresDisponibles = ["TODOS"];
  List<Map<String, dynamic>> _lecturas = [];

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _fechaDesde = DateTime(hoy.year, hoy.month - 2, 1);
    _fechaHasta = hoy;
    _inicializar();
  }

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = (prefs.getString('userRole') ?? "OPERARIO").toUpperCase();
    _userCodProductor = prefs.getInt('userCodProductor') ?? 0;

    final db = await DatabaseHelper.instance.database;

    final resProd = await db.query(
      'productores',
      where: 'cod_productor = ?',
      whereArgs: [_userCodProductor],
      limit: 1,
    );
    if (resProd.isNotEmpty) {
      _nombreProductor = (resProd.first['productor'] ?? '').toString();
      _cuitProductor = (resProd.first['cuit'] ?? 'S/D').toString();
      _renspaProductor = (resProd.first['renspa'] ?? 'S/D').toString();
    }

    await _cargarLecturas();
  }

  Future<void> _cargarLecturas() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final rawLecturas = await db.query(
      'lecturas_fenologia',
      where: 'cod_establecimiento = ?',
      whereArgs: [_userCodProductor],
      orderBy: 'fecha DESC, created_at DESC',
    );

    final Set<String> culSet = {"TODOS"};
    final Set<String> secSet = {"TODOS"};

    for (var l in rawLecturas) {
      final c = (l['cultivo'] ?? '').toString().trim();
      final s = (l['sector'] ?? '').toString().trim();
      if (c.isNotEmpty) culSet.add(c);
      if (s.isNotEmpty) secSet.add(s);
    }

    if (!mounted) return;
    setState(() {
      _lecturas = rawLecturas;
      _cultivosDisponibles = culSet.toList();
      _sectoresDisponibles = secSet.toList();
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _lecturasFiltradas {
    return _lecturas.where((l) {
      final cul = (l['cultivo'] ?? '').toString();
      if (_filtroCultivo != "TODOS" && cul != _filtroCultivo) return false;

      final sec = (l['sector'] ?? '').toString();
      if (_filtroSector != "TODOS" && sec != _filtroSector) return false;

      final String fStr = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
      final DateTime? fReg = DateTime.tryParse(fStr);
      if (fReg != null) {
        if (_fechaDesde != null && fReg.isBefore(_fechaDesde!)) return false;
        if (_fechaHasta != null && fReg.isAfter(_fechaHasta!.add(const Duration(days: 1)))) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int _calcularSemana(DateTime date) {
    final primerDiaAnio = DateTime(date.year, 1, 1);
    final dias = date.difference(primerDiaAnio).inDays;
    return ((dias + primerDiaAnio.weekday) / 7).ceil();
  }

  // ==========================================================================
  // EXPORTADOR PDF
  // ==========================================================================
  Future<void> _exportarPdf() async {
    final filtrados = _lecturasFiltradas;
    if (filtrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos fenológicos para exportar.')),
      );
      return;
    }

    final pdf = pw.Document();
    final String anio = DateTime.now().year.toString();
    final bool esAuditoria = _tipoReporte == "AUDITORIA";

    pw.MemoryImage? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('logo/logo_anibal.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      try {
        final ByteData bytesFb = await rootBundle.load('logo/logo.png');
        logoImage = pw.MemoryImage(bytesFb.buffer.asUint8List());
      } catch (_) {}
    }

    const colorVerdeOscuro = PdfColor.fromInt(0xFF134E32);
    const colorVerdeSecundario = PdfColor.fromInt(0xFF1E6B4C);
    const colorBorde = PdfColor.fromInt(0xFFE5E7EB);
    const colorFondoGris = PdfColor.fromInt(0xFFF9FAFB);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null) ...[
                    pw.Container(width: 44, height: 44, child: pw.Image(logoImage)),
                    pw.SizedBox(width: 12),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "REPORTE OFICIAL DE MONITOREO Y EVOLUCIÓN FENOLÓGICA",
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: colorVerdeOscuro,
                          ),
                        ),
                        pw.Text(
                          "Establecimiento: ${_nombreProductor.toUpperCase()}  ·  CUIT: $_cuitProductor  ·  RENSPA: $_renspaProductor",
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
                        ),
                        pw.Text(
                          "Modalidad: ${esAuditoria ? 'REGISTRO DE AUDITORÍA BOTÁNICA / FITOSANITARIA' : 'PLANILLA INTERNA DE MONITOREO'}",
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: esAuditoria ? colorVerdeSecundario : PdfColors.orange900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: colorFondoGris,
                          borderRadius: pw.BorderRadius.circular(4),
                          border: pw.Border.all(color: colorBorde, width: 0.8),
                        ),
                        child: pw.Text("TEMPORADA $anio",
                            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        "Emisión: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}",
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: colorVerdeSecundario),
              pw.SizedBox(height: 8),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(thickness: 0.8, color: colorBorde),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Text("AgroSoft J&L",
                          style: pw.TextStyle(
                              fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: colorVerdeOscuro)),
                      pw.Text(" · Trazabilidad Agronómica & Curvas de Desarrollo",
                          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text("Página ${context.pageNumber} de ${context.pagesCount}",
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey600),
                      pw.SizedBox(height: 2),
                      pw.Text("Firma Responsable Fitosanitario", style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey600),
                      pw.SizedBox(height: 2),
                      pw.Text("Firma Técnico Auditor", style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          final headers = esAuditoria
              ? ['FECHA', 'SEM.', 'SECTOR', 'CUADRO', 'ESPECIE', 'VARIEDAD', 'CÓDIGO', 'DESCRIPCIÓN ESTADO', 'VALOR (%)']
              : ['FECHA', 'SEM.', 'CUADRO', 'FILA/PL.', 'ESPECIE', 'VARIEDAD', 'ESTADO', 'VALOR (%)', 'TEMP. CRÍT.', 'EVIDENCIA'];

          final data = filtrados.map((l) {
            final fStr = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
            DateTime? dt = DateTime.tryParse(fStr);
            final sem = dt != null ? "S.${_calcularSemana(dt)}" : "S/-";
            final val = "${l['valor_lectura'] ?? '0'}%";

            if (esAuditoria) {
              return [
                fStr,
                sem,
                (l['sector'] ?? 'Principal').toString(),
                "C.${l['cuadro'] ?? '-'}",
                (l['cultivo'] ?? '-').toString(),
                (l['variedad'] ?? '-').toString(),
                (l['estado_codigo'] ?? '-').toString(),
                (l['descripcion_estado'] ?? '-').toString(),
                val,
              ];
            } else {
              return [
                fStr,
                sem,
                "C.${l['cuadro'] ?? '-'}",
                "F.${l['fila'] ?? '-'} P.${l['planta_numero'] ?? '-'}",
                (l['cultivo'] ?? '-').toString(),
                (l['variedad'] ?? '-').toString(),
                "${l['estado_codigo'] ?? ''} - ${l['descripcion_estado'] ?? ''}",
                val,
                "${l['temp_critica_min'] ?? '-'}° / ${l['temp_critica_max'] ?? '-'}°",
                (l['url_evidencia'] != null && (l['url_evidencia'] as String).isNotEmpty) ? 'REGISTRADA' : 'S/FOTO',
              ];
            }
          }).toList();

          return [
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: colorBorde, width: 0.5),
              headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: colorVerdeSecundario),
              headerHeight: 20,
              cellHeight: 18,
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellAlignment: pw.Alignment.centerLeft,
              headers: headers,
              data: data,
            ),
          ];
        },
      ),
    );

    final Uint8List bytes = await pdf.save();
    final String nombreArchivo = 'Reporte_Fenologia_${_tipoReporte}_${_nombreProductor.replaceAll(' ', '_')}_$anio.pdf';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
    } else {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: nombreArchivo, mimeType: 'application/pdf')],
        text: 'Reporte Oficial de Fenología - $_nombreProductor',
      );
    }
  }

  // ==========================================================================
  // EXPORTADOR EXCEL
  // ==========================================================================
  Future<void> _exportarExcel() async {
    final filtrados = _lecturasFiltradas;
    if (filtrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros para exportar.')),
      );
      return;
    }

    final excel = xl.Excel.createExcel();
    final defSheet = excel.getDefaultSheet();
    if (defSheet != null) excel.delete(defSheet);

    final String sheetName = "Monitoreo_Fenologia";
    final xl.Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    final estiloHeader = xl.CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: xl.ExcelColor.fromHexString("#1E6B4C"),
      fontColorHex: xl.ExcelColor.fromHexString("#FFFFFF"),
      horizontalAlign: xl.HorizontalAlign.Center,
      verticalAlign: xl.VerticalAlign.Center,
    );

    sheet.appendRow([xl.TextCellValue("AGROSOFT J&L · MONITOREO DE FENOLOGÍA")]);
    sheet.appendRow([
      xl.TextCellValue("ESTABLECIMIENTO:"),
      xl.TextCellValue(_nombreProductor.toUpperCase()),
      xl.TextCellValue("CUIT:"),
      xl.TextCellValue(_cuitProductor),
      xl.TextCellValue("RENSPA:"),
      xl.TextCellValue(_renspaProductor),
    ]);
    sheet.appendRow([
      xl.TextCellValue("MODALIDAD:"),
      xl.TextCellValue(_tipoReporte),
      xl.TextCellValue("CULTIVO:"),
      xl.TextCellValue(_filtroCultivo),
      xl.TextCellValue("FECHA EMISIÓN:"),
      xl.TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
    ]);
    sheet.appendRow([]);

    final List<xl.CellValue> cabeceras = [
      xl.TextCellValue("ID_REG"),
      xl.TextCellValue("FECHA"),
      xl.TextCellValue("SEMANA"),
      xl.TextCellValue("SECTOR"),
      xl.TextCellValue("CUADRO"),
      xl.TextCellValue("FILA"),
      xl.TextCellValue("PLANTA"),
      xl.TextCellValue("CULTIVO"),
      xl.TextCellValue("VARIEDAD"),
      xl.TextCellValue("COD_ESTADO"),
      xl.TextCellValue("DESCRIPCION_ESTADO"),
      xl.TextCellValue("VALOR_LECTURA_%"),
      xl.TextCellValue("TEMP_CRIT_MIN"),
      xl.TextCellValue("TEMP_CRIT_MAX"),
      xl.TextCellValue("URL_EVIDENCIA"),
    ];

    sheet.appendRow(cabeceras);
    final int idxFila = sheet.maxRows - 1;
    for (int i = 0; i < cabeceras.length; i++) {
      sheet.row(idxFila)[i]?.cellStyle = estiloHeader;
    }

    for (var l in filtrados) {
      final fStr = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
      DateTime? dt = DateTime.tryParse(fStr);
      final sem = dt != null ? "Semana ${_calcularSemana(dt)}" : "S/-";

      sheet.appendRow([
        xl.TextCellValue((l['id_reg'] ?? l['id'] ?? '').toString()),
        xl.TextCellValue(fStr),
        xl.TextCellValue(sem),
        xl.TextCellValue((l['sector'] ?? '').toString()),
        xl.TextCellValue((l['cuadro'] ?? '').toString()),
        xl.TextCellValue((l['fila'] ?? '').toString()),
        xl.TextCellValue((l['planta_numero'] ?? '').toString()),
        xl.TextCellValue((l['cultivo'] ?? '').toString()),
        xl.TextCellValue((l['variedad'] ?? '').toString()),
        xl.TextCellValue((l['estado_codigo'] ?? '').toString()),
        xl.TextCellValue((l['descripcion_estado'] ?? '').toString()),
        xl.DoubleCellValue(double.tryParse((l['valor_lectura'] ?? '0').toString()) ?? 0.0),
        xl.DoubleCellValue(double.tryParse((l['temp_critica_min'] ?? '0').toString()) ?? 0.0),
        xl.DoubleCellValue(double.tryParse((l['temp_critica_max'] ?? '0').toString()) ?? 0.0),
        xl.TextCellValue((l['url_evidencia'] ?? '').toString()),
      ]);
    }

    final List<int>? fileBytes = excel.save();
    if (fileBytes == null) return;

    final Uint8List bytes = Uint8List.fromList(fileBytes);
    final String nombreArchivo = 'Planilla_Fenologia_${_nombreProductor.replaceAll(' ', '_')}.xlsx';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
    } else {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: nombreArchivo, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        text: 'Planilla de Fenología - $_nombreProductor',
      );
    }
  }

  void _mostrarSelectorFecha({required bool esDesde}) async {
    final DateTime? sel = await showDatePicker(
      context: context,
      initialDate: esDesde ? (_fechaDesde ?? DateTime.now()) : (_fechaHasta ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, ch) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: AgroTheme.colorAccentDark),
        ),
        child: ch!,
      ),
    );

    if (sel != null) {
      setState(() {
        if (esDesde) {
          _fechaDesde = sel;
        } else {
          _fechaHasta = sel;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _lecturasFiltradas;

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
              "Reportes de Fenología",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText),
            ),
            Text(
              "Establecimiento: $_nombreProductor",
              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Selector Modalidad
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: AgroTheme.colorSurface,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AgroTheme.colorBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AgroTheme.colorBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _tipoReporte = "AUDITORIA"),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _tipoReporte == "AUDITORIA" ? AgroTheme.colorAccentDark : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              "AUDITORÍA OFICIAL",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _tipoReporte == "AUDITORIA" ? Colors.white : AgroTheme.colorTextSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _tipoReporte = "INTERNO"),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _tipoReporte == "INTERNO" ? AgroTheme.colorGold : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              "PLANILLA INTERNA COMPLETA",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _tipoReporte == "INTERNO" ? Colors.white : AgroTheme.colorTextSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Chips de Cultivos
            Container(
              height: 42,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _cultivosDisponibles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final cul = _cultivosDisponibles[idx];
                  final bool sel = _filtroCultivo == cul;

                  return ChoiceChip(
                    label: Text(cul),
                    selected: sel,
                    selectedColor: AgroTheme.colorAccentDark,
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? Colors.white : AgroTheme.colorText,
                    ),
                    backgroundColor: AgroTheme.colorSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: sel ? AgroTheme.colorAccentDark : AgroTheme.colorBorder),
                    ),
                    onSelected: (_) => setState(() => _filtroCultivo = cul),
                  );
                },
              ),
            ),

            // Fechas y Sector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _mostrarSelectorFecha(esDesde: true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range_rounded, size: 16, color: AgroTheme.colorTextSecondary),
                            const SizedBox(width: 6),
                            Text(
                              _fechaDesde != null ? DateFormat('dd/MM/yy').format(_fechaDesde!) : "Desde",
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => _mostrarSelectorFecha(esDesde: false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available_rounded, size: 16, color: AgroTheme.colorTextSecondary),
                            const SizedBox(width: 6),
                            Text(
                              _fechaHasta != null ? DateFormat('dd/MM/yy').format(_fechaHasta!) : "Hasta",
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_sectoresDisponibles.length > 1)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _filtroSector,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AgroTheme.colorText),
                            items: _sectoresDisponibles.map((s) {
                              return DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (v) => setState(() => _filtroSector = v ?? "TODOS"),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Lista
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: AgroTheme.colorAccent))
                  : filtrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.park_outlined, size: 48, color: AgroTheme.colorTextSecondary),
                              SizedBox(height: 10),
                              Text("No se encontraron registros de fenología.",
                                  style: TextStyle(color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                          itemCount: filtrados.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final l = filtrados[idx];
                            final fStr = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AgroTheme.colorSurface,
                                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                                border: Border.all(color: AgroTheme.colorBorder),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AgroTheme.colorAccentSoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "${l['valor_lectura'] ?? 0}%",
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: AgroTheme.colorAccentDark),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              "${l['cultivo']} · ${l['variedad']}",
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                            ),
                                            Text(fStr, style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary)),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "${l['estado_codigo']} - ${l['descripcion_estado']}",
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AgroTheme.colorText),
                                        ),
                                        Text(
                                          "Cuadro: ${l['cuadro']} · Fila: ${l['fila'] ?? '-'} · Planta: ${l['planta_numero'] ?? '-'}",
                                          style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary),
                                        ),
                                      ],
                                    ),
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
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SoftButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderRadius: 24,
            onTap: _exportarPdf,
            child: Row(
              children: const [
                Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text("PDF Oficial", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SoftButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderRadius: 24,
            onTap: _exportarExcel,
            child: Row(
              children: const [
                Icon(Icons.table_chart_rounded, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text("Excel", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}