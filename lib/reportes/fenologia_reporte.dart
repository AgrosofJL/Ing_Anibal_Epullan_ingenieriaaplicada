// ignore_for_file: deprecated_member_use

import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/agro_reportes_ui.dart';
import '../widgets/agro_ui.dart';

class ReportesFenologiaScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const ReportesFenologiaScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<ReportesFenologiaScreen> createState() => _ReportesFenologiaScreenState();
}

class _ReportesFenologiaScreenState extends State<ReportesFenologiaScreen> {
  static const int _maxFilas = 200;

  bool _cargando = true;
  bool _exportandoPdf = false;
  bool _exportandoExcel = false;

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
    _nombreProductor = widget.nombreProductor;
    _fijarFechasPorDefecto();
    _inicializar();
  }

  void _fijarFechasPorDefecto() {
    final hoy = DateTime.now();
    _fechaDesde = DateTime(hoy.year, hoy.month - 2, 1);
    _fechaHasta = hoy;
  }

  Future<void> _inicializar() async {
    if (mounted) setState(() => _cargando = true);
    try {
      int cod = widget.codProductor;
      if (cod == 0) {
        final prefs = await SharedPreferences.getInstance();
        cod = prefs.getInt('userCodProductor') ?? 0;
      }
      _userCodProductor = cod;

      final db = await DatabaseHelper.instance.database;

      final resProd = await db.query(
        'productores',
        where: 'cod_productor = ?',
        whereArgs: [_userCodProductor],
        limit: 1,
      );
      if (resProd.isNotEmpty) {
        final nom = (resProd.first['productor'] ?? '').toString();
        if (nom.trim().isNotEmpty) _nombreProductor = nom;
        _cuitProductor = (resProd.first['cuit'] ?? 'S/D').toString();
        _renspaProductor = (resProd.first['renspa'] ?? 'S/D').toString();
      }

      await _cargarLecturas();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      mostrarAgroSnack(context, 'No se pudieron cargar las lecturas: $e',
          tipo: AgroSnackTipo.error);
    }
  }

  Future<void> _cargarLecturas() async {
    if (mounted) setState(() => _cargando = true);
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
      if (!culSet.contains(_filtroCultivo)) _filtroCultivo = "TODOS";
      if (!secSet.contains(_filtroSector)) _filtroSector = "TODOS";
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

  bool get _hayFiltrosActivos {
    final hoy = DateTime.now();
    final desdeDef = DateTime(hoy.year, hoy.month - 2, 1);
    final bool fechasDef = _fechaDesde != null &&
        _fechaHasta != null &&
        _fechaDesde!.year == desdeDef.year &&
        _fechaDesde!.month == desdeDef.month &&
        _fechaDesde!.day == desdeDef.day &&
        _fechaHasta!.year == hoy.year &&
        _fechaHasta!.month == hoy.month &&
        _fechaHasta!.day == hoy.day;
    return _filtroCultivo != "TODOS" || _filtroSector != "TODOS" || !fechasDef;
  }

  void _restablecerFiltros() {
    setState(() {
      _filtroCultivo = "TODOS";
      _filtroSector = "TODOS";
      _fijarFechasPorDefecto();
    });
  }

  String get _textoRango {
    final f = DateFormat('dd/MM/yy');
    if (_fechaDesde == null && _fechaHasta == null) return 'Todas las fechas';
    final d = _fechaDesde != null ? f.format(_fechaDesde!) : '…';
    final h = _fechaHasta != null ? f.format(_fechaHasta!) : 'hoy';
    return '$d – $h';
  }

  String get _textoModo => _tipoReporte == "AUDITORIA" ? 'Auditoría' : 'Interno';

  String _fechaCorta(String fStr) {
    final d = DateTime.tryParse(fStr);
    if (d == null) return fStr.isEmpty ? '-' : fStr;
    return DateFormat('dd/MM/yy').format(d);
  }

  double _num(dynamic v) => double.tryParse((v ?? '').toString().replaceAll(',', '.')) ?? 0.0;

  String _fmtPct(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  // ==========================================================================
  // FILAS / ENCABEZADOS (compartidos entre PDF y tabla en pantalla)
  // ==========================================================================
  List<String> _headersPdf(bool esAuditoria) => esAuditoria
      ? ['FECHA', 'SEM.', 'SECTOR', 'CUADRO', 'ESPECIE', 'VARIEDAD', 'CÓDIGO', 'DESCRIPCIÓN ESTADO', 'VALOR (%)']
      : ['FECHA', 'SEM.', 'CUADRO', 'FILA/PL.', 'ESPECIE', 'VARIEDAD', 'ESTADO', 'VALOR (%)', 'TEMP. CRÍT.', 'EVIDENCIA'];

  List<int> _flexTabla(bool esAuditoria) => esAuditoria
      ? [3, 2, 3, 2, 3, 3, 2, 6, 2]
      : [3, 2, 2, 3, 3, 3, 6, 2, 3, 3];

  List<String> _filaPdf(Map<String, dynamic> l, bool esAuditoria) {
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
        (l['url_evidencia'] != null && l['url_evidencia'].toString().isNotEmpty) ? 'REGISTRADA' : 'S/FOTO',
      ];
    }
  }

  // ==========================================================================
  // EXPORTADOR PDF
  // ==========================================================================
  Future<void> _exportarPdf() async {
    if (_exportandoPdf || _exportandoExcel) return;
    final filtrados = _lecturasFiltradas;
    if (filtrados.isEmpty) {
      mostrarAgroSnack(context, 'No hay datos fenológicos para exportar.',
          tipo: AgroSnackTipo.aviso);
      return;
    }

    setState(() => _exportandoPdf = true);
    try {
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
            final headers = _headersPdf(esAuditoria);
            final data = filtrados.map((l) => _filaPdf(l, esAuditoria)).toList();

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
      final String nombreArchivo =
          'Reporte_Fenologia_${_tipoReporte}_${agroNombreArchivo(_nombreProductor)}_$anio.pdf';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.pdf,
        texto: 'Reporte Oficial de Fenología - $_nombreProductor',
        context: context,
      );
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'No se pudo generar el PDF: $e', tipo: AgroSnackTipo.error);
      }
    } finally {
      if (mounted) setState(() => _exportandoPdf = false);
    }
  }

  // ==========================================================================
  // EXPORTADOR EXCEL
  // ==========================================================================
  Future<void> _exportarExcel() async {
    if (_exportandoPdf || _exportandoExcel) return;
    final filtrados = _lecturasFiltradas;
    if (filtrados.isEmpty) {
      mostrarAgroSnack(context, 'No hay registros para exportar.', tipo: AgroSnackTipo.aviso);
      return;
    }

    setState(() => _exportandoExcel = true);
    try {
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

      final List<int>? fileBytes = excel.encode();
      if (fileBytes == null) {
        if (mounted) {
          mostrarAgroSnack(context, 'No se pudo generar el Excel.', tipo: AgroSnackTipo.error);
        }
        return;
      }

      final Uint8List bytes = Uint8List.fromList(fileBytes);
      final String nombreArchivo = 'Planilla_Fenologia_${agroNombreArchivo(_nombreProductor)}.xlsx';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.xlsx,
        texto: 'Planilla de Fenología - $_nombreProductor',
        context: context,
      );
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'No se pudo generar el Excel: $e', tipo: AgroSnackTipo.error);
      }
    } finally {
      if (mounted) setState(() => _exportandoExcel = false);
    }
  }

  // ==========================================================================
  // UI
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final filtrados = _lecturasFiltradas;
    final bool esAncho = AgroBreakpoints.ancho(context) >= 900;
    const gap = SizedBox(height: 16);

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: 'Reportes de fenología',
        subtitulo: _nombreProductor.isEmpty ? 'Monitoreo fenológico' : _nombreProductor,
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: 'Actualizar',
            onTap: _cargando ? null : _inicializar,
          ),
        ],
      ),
      body: _cargando
          ? const AgroLoading(mensaje: 'Cargando lecturas fenológicas…')
          : ListView(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              children: [
                AgroContent(child: _encabezado(filtrados.length)),
                gap,
                AgroContent(child: _panelFiltros()),
                gap,
                AgroContent(child: _kpis(filtrados)),
                if (filtrados.isNotEmpty) ...[
                  gap,
                  AgroContent(child: _graficos(filtrados, esAncho)),
                ],
                gap,
                AgroContent(child: _listado(filtrados, esAncho)),
              ],
            ),
      bottomNavigationBar: _cargando
          ? null
          : AgroBottomExport(
              child: AgroExportBar(
                onPdf: _exportarPdf,
                onExcel: _exportarExcel,
                cargandoPdf: _exportandoPdf,
                cargandoExcel: _exportandoExcel,
                info: '${filtrados.length} registros · $_textoModo',
              ),
            ),
    );
  }

  Widget _encabezado(int total) {
    return AgroReporteHeader(
      titulo: 'Monitoreo y evolución fenológica',
      subtitulo: _nombreProductor.isEmpty
          ? 'Lecturas de estados fenológicos'
          : 'Establecimiento: $_nombreProductor',
      icono: Icons.eco_rounded,
      chips: [
        AgroHeaderChip(texto: 'CUIT $_cuitProductor', icono: Icons.badge_outlined),
        AgroHeaderChip(texto: 'RENSPA $_renspaProductor', icono: Icons.verified_user_outlined),
        AgroHeaderChip(texto: _textoRango, icono: Icons.date_range_rounded),
        AgroHeaderChip(
          texto: '$total ${total == 1 ? 'lectura' : 'lecturas'}',
          icono: Icons.list_alt_rounded,
        ),
      ],
    );
  }

  Widget _panelFiltros() {
    final cultivos = _cultivosDisponibles.where((c) => c != "TODOS").toList();
    final sectores = _sectoresDisponibles.where((s) => s != "TODOS").toList();

    return AgroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgroSectionHeader(
            titulo: 'Filtros',
            subtitulo: 'Los cambios se aplican al instante',
            icono: Icons.tune_rounded,
            trailing: _hayFiltrosActivos
                ? AgroButton(
                    label: 'Restablecer',
                    icono: Icons.restart_alt_rounded,
                    tipo: AgroButtonTipo.texto,
                    compacto: true,
                    onTap: _restablecerFiltros,
                  )
                : null,
          ),
          const SizedBox(height: 14),
          const Text('MODALIDAD', style: AgroText.overline),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AgroModoSelector(
                valor: _tipoReporte,
                onChanged: (v) => setState(() => _tipoReporte = v),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _tipoReporte == "AUDITORIA"
                ? 'Registro de auditoría botánica / fitosanitaria por sector y cuadro.'
                : 'Planilla interna completa: fila, planta, temperaturas críticas y evidencia.',
            style: AgroText.secundario.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          const Text('PERÍODO', style: AgroText.overline),
          const SizedBox(height: 6),
          AgroFiltroFechas(
            desde: _fechaDesde,
            hasta: _fechaHasta,
            onChanged: (d, h) => setState(() {
              _fechaDesde = d;
              _fechaHasta = h;
            }),
          ),
          if (cultivos.isNotEmpty) ...[
            const SizedBox(height: 14),
            AgroChipSelector(
              label: 'Cultivo',
              opciones: cultivos,
              valor: _filtroCultivo == "TODOS" ? null : _filtroCultivo,
              textoTodos: 'Todos',
              onChanged: (v) => setState(() => _filtroCultivo = v ?? "TODOS"),
            ),
          ],
          if (sectores.isNotEmpty) ...[
            const SizedBox(height: 14),
            AgroChipSelector(
              label: 'Sector',
              opciones: sectores,
              valor: _filtroSector == "TODOS" ? null : _filtroSector,
              textoTodos: 'Todos',
              onChanged: (v) => setState(() => _filtroSector = v ?? "TODOS"),
            ),
          ],
        ],
      ),
    );
  }

  String _etiquetaEstado(Map<String, dynamic> l) {
    final cod = (l['estado_codigo'] ?? '').toString().trim();
    final desc = (l['descripcion_estado'] ?? '').toString().trim();
    if (cod.isEmpty && desc.isEmpty) return 'Sin estado';
    if (cod.isEmpty) return desc;
    if (desc.isEmpty) return cod;
    return '$cod · $desc';
  }

  Widget _kpis(List<Map<String, dynamic>> filtrados) {
    final Set<String> variedades = {};
    final Set<String> cuadros = {};
    final Map<String, int> frecEstado = {};
    double suma = 0;

    for (final l in filtrados) {
      final v = (l['variedad'] ?? '').toString().trim();
      if (v.isNotEmpty) variedades.add(v);
      final c = (l['cuadro'] ?? '').toString().trim();
      if (c.isNotEmpty) cuadros.add('${l['sector'] ?? ''}|$c');
      final e = _etiquetaEstado(l);
      frecEstado[e] = (frecEstado[e] ?? 0) + 1;
      suma += _num(l['valor_lectura']);
    }
    final double promedio = filtrados.isEmpty ? 0 : suma / filtrados.length;
    String estadoFrecuente = '-';
    int maxFrec = 0;
    frecEstado.forEach((k, v) {
      if (v > maxFrec) {
        maxFrec = v;
        estadoFrecuente = k;
      }
    });

    return AgroKpiGrid(
      kpis: [
        AgroKpiTile(
          label: 'Lecturas',
          valor: '${filtrados.length}',
          icono: Icons.fact_check_outlined,
        ),
        AgroKpiTile(
          label: 'Variedades',
          valor: '${variedades.length}',
          icono: Icons.spa_outlined,
          color: AgroColors.info,
        ),
        AgroKpiTile(
          label: 'Cuadros monitoreados',
          valor: '${cuadros.length}',
          icono: Icons.grid_view_rounded,
          color: AgroColors.warn,
        ),
        AgroKpiTile(
          label: 'Avance promedio',
          valor: '${_fmtPct(promedio)} %',
          icono: Icons.trending_up_rounded,
          color: AgroColors.ok,
          detalle: 'Más frecuente: $estadoFrecuente',
        ),
      ],
    );
  }

  Widget _graficos(List<Map<String, dynamic>> filtrados, bool esAncho) {
    // Promedio de % por estado (los 8 estados más registrados)
    final Map<String, double> sumaEstado = {};
    final Map<String, int> cantEstado = {};
    final Map<int, int> porSemana = {};
    for (final l in filtrados) {
      final e = _etiquetaEstado(l);
      sumaEstado[e] = (sumaEstado[e] ?? 0) + _num(l['valor_lectura']);
      cantEstado[e] = (cantEstado[e] ?? 0) + 1;

      final fStr = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
      final dt = DateTime.tryParse(fStr);
      if (dt != null) {
        final k = dt.year * 100 + _calcularSemana(dt);
        porSemana[k] = (porSemana[k] ?? 0) + 1;
      }
    }
    final estados = cantEstado.keys.toList()
      ..sort((a, b) => (cantEstado[b] ?? 0).compareTo(cantEstado[a] ?? 0));
    final itemsEstado = estados.take(8).map((e) {
      final n = cantEstado[e] ?? 1;
      return AgroBarItem(
        label: e,
        valor: (sumaEstado[e] ?? 0) / n,
        detalle: '$n lecturas',
      );
    }).toList();

    final semanas = porSemana.keys.toList()..sort();
    final ultimas = semanas.length > 16 ? semanas.sublist(semanas.length - 16) : semanas;
    final itemsSemana = ultimas.map((k) {
      final sem = k % 100;
      final v = porSemana[k] ?? 0;
      return AgroBarItem(
        label: 'S$sem',
        valor: v.toDouble(),
        detalle: 'Semana $sem (${k ~/ 100}): $v lecturas',
      );
    }).toList();

    final cardEstados = AgroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgroSectionHeader(
            titulo: 'Avance promedio por estado',
            subtitulo: 'Valor medio de lectura (%) · estados más registrados',
            icono: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 14),
          AgroBarChart(items: itemsEstado, unidad: '%', anchoLabel: 140),
        ],
      ),
    );

    final cardSemanas = AgroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgroSectionHeader(
            titulo: 'Lecturas por semana',
            subtitulo: 'Intensidad del monitoreo',
            icono: Icons.calendar_view_week_rounded,
          ),
          const SizedBox(height: 14),
          AgroColumnChart(items: itemsSemana, color: AgroColors.info),
        ],
      ),
    );

    if (esAncho) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: cardEstados),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: cardSemanas),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cardEstados,
        const SizedBox(height: 16),
        cardSemanas,
      ],
    );
  }

  Widget _listado(List<Map<String, dynamic>> filtrados, bool esAncho) {
    if (filtrados.isEmpty) {
      return SizedBox(
        height: 360,
        child: AgroEmptyState(
          icono: Icons.park_outlined,
          titulo: _lecturas.isEmpty
              ? 'Todavía no hay lecturas de fenología'
              : 'Sin lecturas para estos filtros',
          mensaje: _lecturas.isEmpty
              ? 'Las lecturas registradas en el monitoreo fenológico aparecerán acá.'
              : 'Probá ampliar el período o cambiar el cultivo o el sector.',
          accion: _hayFiltrosActivos
              ? AgroButton(
                  label: 'Restablecer filtros',
                  icono: Icons.restart_alt_rounded,
                  tipo: AgroButtonTipo.secundario,
                  onTap: _restablecerFiltros,
                )
              : null,
        ),
      );
    }

    final bool esAuditoria = _tipoReporte == "AUDITORIA";
    final visibles = filtrados.length > _maxFilas
        ? filtrados.sublist(0, _maxFilas)
        : filtrados;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgroSectionHeader(
          titulo: 'Lecturas fenológicas',
          subtitulo: esAuditoria
              ? 'Vista previa del formato de auditoría'
              : 'Vista previa de la planilla interna',
          icono: Icons.list_alt_rounded,
          trailing: AgroBadge(texto: '${filtrados.length}', grande: true),
        ),
        const SizedBox(height: 12),
        if (filtrados.length > _maxFilas) ...[
          _avisoLimite(visibles.length, filtrados.length),
          const SizedBox(height: 10),
        ],
        if (esAncho)
          _TablaReporte(
            titulos: _headersPdf(esAuditoria),
            flex: _flexTabla(esAuditoria),
            filas: visibles.map((l) => _filaPdf(l, esAuditoria)).toList(),
          )
        else
          ...visibles.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _tarjeta(l, esAuditoria),
              )),
      ],
    );
  }

  Widget _avisoLimite(int mostrados, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AgroColors.infoSoft,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AgroColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Mostrando $mostrados de $total — exportá para ver todo.',
              style: AgroText.secundario.copyWith(color: AgroColors.info),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> l, bool esAuditoria) {
    final fStr = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
    final dt = DateTime.tryParse(fStr);
    final double valor = _num(l['valor_lectura']);
    final String sector = (l['sector'] ?? '').toString().trim();
    final bool conFoto = l['url_evidencia'] != null &&
        l['url_evidencia'].toString().isNotEmpty;

    return AgroCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AgroColors.primarioSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '${_fmtPct(valor)}%',
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AgroColors.primario,
                  ),
                ),
                const SizedBox(height: 2),
                Text('avance', style: AgroText.label.copyWith(fontSize: 9.5)),
              ],
            ),
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
                        "${l['cultivo'] ?? '-'} · ${l['variedad'] ?? '-'}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.valor.copyWith(fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dt != null
                          ? '${_fechaCorta(fStr)} · S.${_calcularSemana(dt)}'
                          : _fechaCorta(fStr),
                      style: AgroText.secundario.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "${l['estado_codigo'] ?? '-'} - ${l['descripcion_estado'] ?? '-'}",
                  style: AgroText.cuerpo.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (sector.isNotEmpty)
                      AgroTag(texto: sector, icono: Icons.place_outlined),
                    AgroTag(texto: "Cuadro ${l['cuadro'] ?? '-'}", icono: Icons.grid_view_rounded),
                    if (!esAuditoria) ...[
                      AgroTag(
                        texto: "F.${l['fila'] ?? '-'} P.${l['planta_numero'] ?? '-'}",
                        icono: Icons.park_outlined,
                      ),
                      AgroTag(
                        texto: "${l['temp_critica_min'] ?? '-'}° / ${l['temp_critica_max'] ?? '-'}°",
                        icono: Icons.thermostat_rounded,
                      ),
                      AgroBadge(
                        texto: conFoto ? 'Con foto' : 'Sin foto',
                        icono: conFoto ? Icons.photo_camera_outlined : Icons.no_photography_outlined,
                        color: conFoto ? AgroColors.ok : AgroColors.neutral,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TABLA PARA PANTALLAS ANCHAS (mismas columnas que el PDF)
// ============================================================

class _TablaReporte extends StatelessWidget {
  final List<String> titulos;
  final List<int> flex;
  final List<List<String>> filas;

  const _TablaReporte({
    required this.titulos,
    required this.flex,
    required this.filas,
  });

  int _flex(int j) => j < flex.length ? flex[j] : 2;

  @override
  Widget build(BuildContext context) {
    return AgroCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AgroColors.primarioSoft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                for (int j = 0; j < titulos.length; j++)
                  Expanded(
                    flex: _flex(j),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        titulos[j],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.overline.copyWith(color: AgroColors.primario),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (int i = 0; i < filas.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: i.isOdd ? AgroTheme.colorBg.withOpacity(0.55) : null,
                border: const Border(top: BorderSide(color: AgroTheme.colorBorder)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int j = 0; j < filas[i].length && j < titulos.length; j++)
                    Expanded(
                      flex: _flex(j),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          filas[i][j],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: j == 0 ? FontWeight.w700 : FontWeight.w500,
                            color: AgroTheme.colorText,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
