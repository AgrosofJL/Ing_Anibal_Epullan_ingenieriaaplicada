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

class ReportesTrampasScreen extends StatefulWidget {
  const ReportesTrampasScreen({super.key});

  @override
  State<ReportesTrampasScreen> createState() => _ReportesTrampasScreenState();
}

class _ReportesTrampasScreenState extends State<ReportesTrampasScreen> {
  bool _cargando = true;
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;
  String _nombreProductor = "";
  String _cuitProductor = "S/D";
  String _renspaProductor = "S/D";

  String _tipoReporte = "AUDITORIA"; // AUDITORIA | INTERNO
  String _filtroTipoPlaga = "TODOS";
  String _filtroSector = "TODOS";
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  List<String> _plagasDisponibles = ["TODOS"];
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
      'lecturas_trampas',
      where: 'cod_establecimiento = ?',
      whereArgs: [_userCodProductor],
      orderBy: 'created_at DESC, semana DESC',
    );

    final Set<String> plagaSet = {"TODOS"};
    final Set<String> secSet = {"TODOS"};

    for (var l in rawLecturas) {
      final t = (l['tipo_trampa'] ?? '').toString().trim();
      final s = (l['sector'] ?? '').toString().trim();
      if (t.isNotEmpty) plagaSet.add(t);
      if (s.isNotEmpty) secSet.add(s);
    }

    if (!mounted) return;
    setState(() {
      _lecturas = rawLecturas;
      _plagasDisponibles = plagaSet.toList();
      _sectoresDisponibles = secSet.toList();
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _lecturasFiltradas {
    return _lecturas.where((l) {
      final tp = (l['tipo_trampa'] ?? '').toString();
      if (_filtroTipoPlaga != "TODOS" && tp != _filtroTipoPlaga) return false;

      final sec = (l['sector'] ?? '').toString();
      if (_filtroSector != "TODOS" && sec != _filtroSector) return false;

      final String fStr = (l['created_at'] ?? '').toString().split('T').first;
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

  // ==========================================================================
  // EXPORTADOR PDF
  // ==========================================================================
  Future<void> _exportarPdf() async {
    final filtrados = _lecturasFiltradas;
    if (filtrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay capturas registradas para exportar.')),
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
                          "PLANILLA OFICIAL DE MONITOREO DE PLAGAS Y RED DE TRAMPAS",
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
                          "Modalidad: ${esAuditoria ? 'REGISTRO AUDITORÍA FITOSANITARIA (CARPOCAPSA / GRAFOLITA / MOSCA)' : 'CONTROL INTERNO DE CAPTURAS'}",
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
                      pw.Text(" · Sistema de Dinámica Poblacional & Trampeo Masivo",
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
                      pw.Text("Firma del Monitor de Campo", style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey600),
                      pw.SizedBox(height: 2),
                      pw.Text("Firma Responsable Fitosanitario", style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          final headers = esAuditoria
              ? ['FECHA', 'SEM.', 'SECTOR', 'CUADRO', 'TRAMPA', 'PLAGA / TIPO', 'MACHOS', 'H. VIRGEN', 'H. GRÁVIDA', 'TOTAL']
              : ['FECHA', 'SEM.', 'CUADRO', 'FILA', 'TRAMPA N°', 'CÓDIGO', 'TIPO', 'MACHOS', 'HEMBRAS', 'OPERARIO', 'EVIDENCIA'];

          final data = filtrados.map((l) {
            final fStr = (l['created_at'] ?? '').toString().split('T').first;
            final m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
            final hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
            final hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
            final tot = m + hv + hg;

            if (esAuditoria) {
              return [
                fStr,
                "S.${l['semana'] ?? '-'}",
                (l['sector'] ?? 'Principal').toString(),
                "C.${l['cuadro'] ?? '-'}",
                "T-${l['trampa_numero'] ?? '-'}",
                (l['tipo_trampa'] ?? '-').toString(),
                "$m",
                "$hv",
                "$hg",
                "$tot",
              ];
            } else {
              return [
                fStr,
                "S.${l['semana'] ?? '-'}",
                "C.${l['cuadro'] ?? '-'}",
                "${l['fila'] ?? '-'}",
                "${l['trampa_numero'] ?? '-'}",
                "${l['cod_trampa'] ?? '-'}",
                (l['tipo_trampa'] ?? '-').toString(),
                "$m",
                "${hv + hg}",
                (l['usuario'] ?? '-').toString(),
                (l['url_evidencia'] != null && (l['url_evidencia'] as String).isNotEmpty) ? 'FOTO' : 'S/FOTO',
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
    final String nombreArchivo = 'Reporte_Trampas_${_tipoReporte}_${_nombreProductor.replaceAll(' ', '_')}_$anio.pdf';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
    } else {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: nombreArchivo, mimeType: 'application/pdf')],
        text: 'Reporte Oficial de Trampas - $_nombreProductor',
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

    final String sheetName = "Monitoreo_Trampas";
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

    sheet.appendRow([xl.TextCellValue("AGROSOFT J&L · REGISTRO DE TRAMPAS Y DINÁMICA DE PLAGAS")]);
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
      xl.TextCellValue("TIPO PLAGA:"),
      xl.TextCellValue(_filtroTipoPlaga),
      xl.TextCellValue("FECHA EMISIÓN:"),
      xl.TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
    ]);
    sheet.appendRow([]);

    final List<xl.CellValue> cabeceras = [
      xl.TextCellValue("ID_REG"),
      xl.TextCellValue("FECHA"),
      xl.TextCellValue("SEMANA"),
      xl.TextCellValue("TEMPORADA"),
      xl.TextCellValue("SECTOR"),
      xl.TextCellValue("CUADRO"),
      xl.TextCellValue("FILA"),
      xl.TextCellValue("UBICACION"),
      xl.TextCellValue("TRAMPA_NUM"),
      xl.TextCellValue("COD_TRAMPA"),
      xl.TextCellValue("TIPO_TRAMPA"),
      xl.TextCellValue("CULTIVO"),
      xl.TextCellValue("VARIEDAD"),
      xl.TextCellValue("MACHOS"),
      xl.TextCellValue("HEMBRAS_VIRGEN"),
      xl.TextCellValue("HEMBRAS_GRAVIDA"),
      xl.TextCellValue("TOTAL_CAPTURAS"),
      xl.TextCellValue("USUARIO_MONITOR"),
      xl.TextCellValue("URL_EVIDENCIA"),
    ];

    sheet.appendRow(cabeceras);
    final int idxFila = sheet.maxRows - 1;
    for (int i = 0; i < cabeceras.length; i++) {
      sheet.row(idxFila)[i]?.cellStyle = estiloHeader;
    }

    for (var l in filtrados) {
      final fStr = (l['created_at'] ?? '').toString().split('T').first;
      final m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
      final hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
      final hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;

      sheet.appendRow([
        xl.TextCellValue((l['id_reg'] ?? l['id'] ?? '').toString()),
        xl.TextCellValue(fStr),
        xl.TextCellValue("Semana ${(l['semana'] ?? '').toString()}"),
        xl.TextCellValue((l['temporada'] ?? '').toString()),
        xl.TextCellValue((l['sector'] ?? '').toString()),
        xl.TextCellValue((l['cuadro'] ?? '').toString()),
        xl.TextCellValue((l['fila'] ?? '').toString()),
        xl.TextCellValue((l['ubicacion'] ?? '').toString()),
        xl.TextCellValue((l['trampa_numero'] ?? '').toString()),
        xl.TextCellValue((l['cod_trampa'] ?? '').toString()),
        xl.TextCellValue((l['tipo_trampa'] ?? '').toString()),
        xl.TextCellValue((l['cultivo'] ?? '').toString()),
        xl.TextCellValue((l['variedad'] ?? '').toString()),
        xl.IntCellValue(m),
        xl.IntCellValue(hv),
        xl.IntCellValue(hg),
        xl.IntCellValue(m + hv + hg),
        xl.TextCellValue((l['usuario'] ?? '').toString()),
        xl.TextCellValue((l['url_evidencia'] ?? '').toString()),
      ]);
    }

    final List<int>? fileBytes = excel.save();
    if (fileBytes == null) return;

    final Uint8List bytes = Uint8List.fromList(fileBytes);
    final String nombreArchivo = 'Planilla_Trampas_${_nombreProductor.replaceAll(' ', '_')}.xlsx';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
    } else {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: nombreArchivo, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        text: 'Planilla de Trampas - $_nombreProductor',
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
              "Monitoreo de Trampas",
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
            // Modalidad
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

            // Chips Plagas
            Container(
              height: 42,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _plagasDisponibles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final p = _plagasDisponibles[idx];
                  final bool sel = _filtroTipoPlaga == p;

                  return ChoiceChip(
                    label: Text(p),
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
                    onSelected: (_) => setState(() => _filtroTipoPlaga = p),
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
                              Icon(Icons.pest_control_outlined, size: 48, color: AgroTheme.colorTextSecondary),
                              SizedBox(height: 10),
                              Text("No se encontraron capturas de trampas registradas.",
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
                            final fStr = (l['created_at'] ?? '').toString().split('T').first;
                            final m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
                            final hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
                            final hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
                            final tot = m + hv + hg;

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
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: tot > 0
                                          ? AgroTheme.colorDanger.withOpacity(0.12)
                                          : AgroTheme.colorAccentSoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "$tot",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: tot > 0 ? AgroTheme.colorDanger : AgroTheme.colorAccentDark,
                                      ),
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
                                              "${l['tipo_trampa']} (T-${l['trampa_numero'] ?? '-'})",
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                            ),
                                            Text(fStr, style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary)),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "Cuadro ${l['cuadro']} · Fila ${l['fila'] ?? '-'} · Sem. ${l['semana'] ?? '-'}",
                                          style: const TextStyle(fontSize: 12, color: AgroTheme.colorText),
                                        ),
                                        Text(
                                          "Macho: $m | H. Virgen: $hv | H. Grávida: $hg",
                                          style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.bold),
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