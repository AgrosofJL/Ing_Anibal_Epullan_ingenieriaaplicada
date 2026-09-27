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

class ReportesTrampasScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const ReportesTrampasScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<ReportesTrampasScreen> createState() => _ReportesTrampasScreenState();
}

class _ReportesTrampasScreenState extends State<ReportesTrampasScreen> {
  static const int _maxFilas = 200;

  /// Capturas por trampa a partir de las cuales una lectura se considera
  /// sobre umbral.
  static const double _umbral = 5;

  bool _cargando = true;
  bool _exportandoPdf = false;
  bool _exportandoExcel = false;

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
      if (!plagaSet.contains(_filtroTipoPlaga)) _filtroTipoPlaga = "TODOS";
      if (!secSet.contains(_filtroSector)) _filtroSector = "TODOS";
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
    return _filtroTipoPlaga != "TODOS" || _filtroSector != "TODOS" || !fechasDef;
  }

  void _restablecerFiltros() {
    setState(() {
      _filtroTipoPlaga = "TODOS";
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

  int _macho(Map<String, dynamic> l) => int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
  int _hVirgen(Map<String, dynamic> l) => int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
  int _hGravida(Map<String, dynamic> l) => int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
  int _total(Map<String, dynamic> l) => _macho(l) + _hVirgen(l) + _hGravida(l);

  /// Semana de la lectura (campo 'semana'; si falta, se calcula con la fecha).
  int? _semana(Map<String, dynamic> l, DateTime? fecha) {
    final s = int.tryParse((l['semana'] ?? '').toString());
    if (s != null) return s;
    if (fecha == null) return null;
    final primerDiaAnio = DateTime(fecha.year, 1, 1);
    final dias = fecha.difference(primerDiaAnio).inDays;
    return ((dias + primerDiaAnio.weekday) / 7).ceil();
  }

  Color _colorNivel(int total) {
    if (total >= _umbral) return AgroColors.danger;
    if (total > 0) return AgroColors.warn;
    return AgroColors.ok;
  }

  // ==========================================================================
  // FILAS / ENCABEZADOS (compartidos entre PDF y tabla en pantalla)
  // ==========================================================================
  List<String> _headersPdf(bool esAuditoria) => esAuditoria
      ? ['FECHA', 'SEM.', 'SECTOR', 'CUADRO', 'TRAMPA', 'PLAGA / TIPO', 'MACHOS', 'H. VIRGEN', 'H. GRÁVIDA', 'TOTAL']
      : ['FECHA', 'SEM.', 'CUADRO', 'FILA', 'TRAMPA N°', 'CÓDIGO', 'TIPO', 'MACHOS', 'HEMBRAS', 'OPERARIO', 'EVIDENCIA'];

  List<int> _flexTabla(bool esAuditoria) => esAuditoria
      ? [3, 2, 3, 2, 2, 4, 2, 2, 2, 2]
      : [3, 2, 2, 2, 2, 3, 4, 2, 2, 3, 2];

  List<String> _filaPdf(Map<String, dynamic> l, bool esAuditoria) {
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
        (l['url_evidencia'] != null && l['url_evidencia'].toString().isNotEmpty) ? 'FOTO' : 'S/FOTO',
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
      mostrarAgroSnack(context, 'No hay capturas registradas para exportar.',
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
          'Reporte_Trampas_${_tipoReporte}_${agroNombreArchivo(_nombreProductor)}_$anio.pdf';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.pdf,
        texto: 'Reporte Oficial de Trampas - $_nombreProductor',
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

      final List<int>? fileBytes = excel.encode();
      if (fileBytes == null) {
        if (mounted) {
          mostrarAgroSnack(context, 'No se pudo generar el Excel.', tipo: AgroSnackTipo.error);
        }
        return;
      }

      final Uint8List bytes = Uint8List.fromList(fileBytes);
      final String nombreArchivo = 'Planilla_Trampas_${agroNombreArchivo(_nombreProductor)}.xlsx';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.xlsx,
        texto: 'Planilla de Trampas - $_nombreProductor',
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
        titulo: 'Monitoreo de trampas',
        subtitulo: _nombreProductor.isEmpty ? 'Red de trampas y capturas' : _nombreProductor,
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: 'Actualizar',
            onTap: _cargando ? null : _inicializar,
          ),
        ],
      ),
      body: _cargando
          ? const AgroLoading(mensaje: 'Cargando lecturas de trampas…')
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
      titulo: 'Monitoreo de plagas y red de trampas',
      subtitulo: _nombreProductor.isEmpty
          ? 'Capturas y dinámica poblacional'
          : 'Establecimiento: $_nombreProductor',
      icono: Icons.pest_control_rounded,
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
    final plagas = _plagasDisponibles.where((p) => p != "TODOS").toList();
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
                ? 'Registro de auditoría fitosanitaria: machos, hembras vírgenes, grávidas y total por trampa.'
                : 'Control interno de capturas: fila, código de trampa, operario y evidencia.',
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
          if (plagas.isNotEmpty) ...[
            const SizedBox(height: 14),
            AgroChipSelector(
              label: 'Plaga / tipo de trampa',
              opciones: plagas,
              valor: _filtroTipoPlaga == "TODOS" ? null : _filtroTipoPlaga,
              textoTodos: 'Todas',
              onChanged: (v) => setState(() => _filtroTipoPlaga = v ?? "TODOS"),
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

  /// Agrupa por semana: clave año*100+semana -> [total capturas, lecturas].
  Map<int, List<int>> _porSemana(List<Map<String, dynamic>> filtrados) {
    final Map<int, List<int>> res = {};
    for (final l in filtrados) {
      final fecha = DateTime.tryParse((l['created_at'] ?? '').toString().split('T').first);
      final sem = _semana(l, fecha);
      if (sem == null) continue;
      final anio = fecha?.year ?? DateTime.now().year;
      final k = anio * 100 + sem;
      final acc = res.putIfAbsent(k, () => [0, 0]);
      acc[0] += _total(l);
      acc[1] += 1;
    }
    return res;
  }

  Widget _kpis(List<Map<String, dynamic>> filtrados) {
    int capturas = 0;
    int sobreUmbral = 0;
    final Set<String> trampas = {};
    for (final l in filtrados) {
      final t = _total(l);
      capturas += t;
      if (t >= _umbral) sobreUmbral++;
      final cod = (l['cod_trampa'] ?? '').toString().trim();
      trampas.add(cod.isNotEmpty
          ? cod
          : '${l['sector'] ?? ''}|${l['cuadro'] ?? ''}|${l['tipo_trampa'] ?? ''}|${l['trampa_numero'] ?? ''}');
    }

    final semanas = _porSemana(filtrados);
    int picoKey = 0;
    int picoTotal = 0;
    semanas.forEach((k, v) {
      if (v[0] > picoTotal) {
        picoTotal = v[0];
        picoKey = k;
      }
    });
    final double pct = filtrados.isEmpty ? 0 : sobreUmbral * 100 / filtrados.length;

    return AgroKpiGrid(
      kpis: [
        AgroKpiTile(
          label: 'Capturas totales',
          valor: '$capturas',
          icono: Icons.bug_report_outlined,
          detalle: '${filtrados.length} lecturas',
        ),
        AgroKpiTile(
          label: 'Trampas distintas',
          valor: '${trampas.length}',
          icono: Icons.location_on_outlined,
          color: AgroColors.info,
        ),
        AgroKpiTile(
          label: 'Sobre umbral (≥ ${_umbral.toStringAsFixed(0)})',
          valor: '$sobreUmbral',
          icono: Icons.warning_amber_rounded,
          color: sobreUmbral > 0 ? AgroColors.danger : AgroColors.ok,
          detalle: '${pct.toStringAsFixed(0)} % de las lecturas',
        ),
        AgroKpiTile(
          label: 'Pico semanal',
          valor: '$picoTotal',
          icono: Icons.show_chart_rounded,
          color: AgroColors.warn,
          detalle: picoTotal > 0 ? 'Semana ${picoKey % 100} · ${picoKey ~/ 100}' : 'Sin capturas',
        ),
      ],
    );
  }

  Widget _graficos(List<Map<String, dynamic>> filtrados, bool esAncho) {
    // Promedio de capturas por trampa, por semana (comparable con el umbral)
    final semanas = _porSemana(filtrados);
    final claves = semanas.keys.toList()..sort();
    final ultimas = claves.length > 20 ? claves.sublist(claves.length - 20) : claves;
    final itemsSemana = ultimas.map((k) {
      final v = semanas[k] ?? [0, 0];
      final lecturas = v[1] == 0 ? 1 : v[1];
      final prom = v[0] / lecturas;
      return AgroBarItem(
        label: 'S${k % 100}',
        valor: prom,
        detalle:
            'Semana ${k % 100} (${k ~/ 100}): ${prom.toStringAsFixed(1)} capt./trampa · ${v[0]} capturas en ${v[1]} lecturas',
      );
    }).toList();

    // Capturas totales por plaga / tipo de trampa
    final Map<String, int> porPlaga = {};
    for (final l in filtrados) {
      final t = (l['tipo_trampa'] ?? '').toString().trim();
      final k = t.isEmpty ? 'Sin tipo' : t;
      porPlaga[k] = (porPlaga[k] ?? 0) + _total(l);
    }
    final plagas = porPlaga.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final itemsPlaga = plagas
        .take(8)
        .map((e) => AgroBarItem(label: e.key, valor: e.value.toDouble()))
        .toList();

    final cardSemanas = AgroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgroSectionHeader(
            titulo: 'Capturas por semana',
            subtitulo: 'Promedio de capturas por trampa · umbral 5',
            icono: Icons.stacked_bar_chart_rounded,
          ),
          const SizedBox(height: 14),
          AgroColumnChart(items: itemsSemana, umbral: _umbral),
          const SizedBox(height: 10),
          const AgroLeyenda(
            items: [
              AgroLeyendaItem('Bajo umbral', AgroColors.primario),
              AgroLeyendaItem('Sobre umbral (≥ 5 por trampa)', AgroColors.danger),
            ],
          ),
        ],
      ),
    );

    final cardPlagas = AgroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgroSectionHeader(
            titulo: 'Capturas por plaga',
            subtitulo: 'Total del período por tipo de trampa',
            icono: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 14),
          AgroBarChart(items: itemsPlaga, color: AgroColors.warn, anchoLabel: 120),
        ],
      ),
    );

    if (esAncho) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: cardSemanas),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: cardPlagas),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cardSemanas,
        const SizedBox(height: 16),
        cardPlagas,
      ],
    );
  }

  Widget _listado(List<Map<String, dynamic>> filtrados, bool esAncho) {
    if (filtrados.isEmpty) {
      return SizedBox(
        height: 360,
        child: AgroEmptyState(
          icono: Icons.pest_control_outlined,
          titulo: _lecturas.isEmpty
              ? 'Todavía no hay capturas registradas'
              : 'Sin capturas para estos filtros',
          mensaje: _lecturas.isEmpty
              ? 'Las lecturas de la red de trampas aparecerán acá.'
              : 'Probá ampliar el período o cambiar la plaga o el sector.',
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
    // En auditoría, la columna TOTAL se colorea según el nivel de capturas.
    const int colTotal = 9;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgroSectionHeader(
          titulo: 'Lecturas de trampas',
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
            colorCelda: esAuditoria
                ? ((int i, int j) =>
                    j == colTotal ? _colorNivel(_total(visibles[i])) : null)
                : null,
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
    final fStr = (l['created_at'] ?? '').toString().split('T').first;
    final m = _macho(l);
    final hv = _hVirgen(l);
    final hg = _hGravida(l);
    final tot = m + hv + hg;
    final color = _colorNivel(tot);
    final sector = (l['sector'] ?? '').toString().trim();
    final usuario = (l['usuario'] ?? '').toString().trim();
    final bool conFoto = l['url_evidencia'] != null &&
        l['url_evidencia'].toString().isNotEmpty;

    return AgroCard(
      padding: const EdgeInsets.all(14),
      accentColor: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '$tot',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text('capturas', style: AgroText.label.copyWith(fontSize: 9.5)),
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
                        "${l['tipo_trampa'] ?? '-'} (T-${l['trampa_numero'] ?? '-'})",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.valor.copyWith(fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_fechaCorta(fStr)} · S.${l['semana'] ?? '-'}',
                      style: AgroText.secundario.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (sector.isNotEmpty) sector,
                    "Cuadro ${l['cuadro'] ?? '-'}",
                    "Fila ${l['fila'] ?? '-'}",
                    if (!esAuditoria && (l['cod_trampa'] ?? '').toString().isNotEmpty)
                      "Cód. ${l['cod_trampa']}",
                  ].join(' · '),
                  style: AgroText.cuerpo.copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AgroTag(texto: 'Machos $m', icono: Icons.male_rounded),
                    AgroTag(texto: 'H. virgen $hv', icono: Icons.female_rounded),
                    AgroTag(texto: 'H. grávida $hg', icono: Icons.egg_outlined),
                    if (tot >= _umbral)
                      const AgroBadge(
                        texto: 'Sobre umbral',
                        icono: Icons.warning_amber_rounded,
                        color: AgroColors.danger,
                        fondo: AgroColors.dangerSoft,
                      ),
                    if (!esAuditoria && usuario.isNotEmpty)
                      AgroTag(texto: usuario, icono: Icons.person_outline_rounded),
                    if (!esAuditoria)
                      AgroBadge(
                        texto: conFoto ? 'Con foto' : 'Sin foto',
                        icono: conFoto ? Icons.photo_camera_outlined : Icons.no_photography_outlined,
                        color: conFoto ? AgroColors.ok : AgroColors.neutral,
                      ),
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
  final Color? Function(int fila, int columna)? colorCelda;

  const _TablaReporte({
    required this.titulos,
    required this.flex,
    required this.filas,
    this.colorCelda,
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
                            fontWeight: (j == 0 || colorCelda?.call(i, j) != null)
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: colorCelda?.call(i, j) ?? AgroTheme.colorText,
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
