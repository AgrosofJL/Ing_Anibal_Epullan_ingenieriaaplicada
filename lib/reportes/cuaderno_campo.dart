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

class CuadernoCampoScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const CuadernoCampoScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<CuadernoCampoScreen> createState() => _CuadernoCampoScreenState();
}

class _CuadernoCampoScreenState extends State<CuadernoCampoScreen> {
  static const int _maxFilas = 200;
  static const List<String> _meses = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  bool _cargando = true;
  bool _exportandoPdf = false;
  bool _exportandoExcel = false;

  int _userCodProductor = 0;
  String _nombreProductor = "";
  String _cuitProductor = "S/D";
  String _renspaProductor = "S/D";

  // Filtros de pantalla
  String _tipoReporte = "AUDITORIA"; // 'AUDITORIA' | 'INTERNO'
  String _filtroRubro = "TODOS"; // 'TODOS' | 'AGROQUÍMICOS' | 'FERTILIZANTE' | 'FERTIRRIEGO' | 'HERBICIDAS'
  String _filtroChacra = "TODAS";
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  List<String> _chacrasDisponibles = ["TODAS"];
  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _catalogoInsumos = [];

  /// ID_Insumos -> valor de 'Mostrar' (primera coincidencia del catálogo).
  Map<dynamic, dynamic> _mostrarPorInsumo = {};

  final List<String> _rubrosDisponibles = [
    "TODOS",
    "AGROQUÍMICOS",
    "FERTILIZANTE",
    "FERTIRRIEGO",
    "HERBICIDAS",
  ];

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

      // Obtener datos del productor actual
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

      // Cargar catálogo de insumos para cruce de auditoría
      _catalogoInsumos = await db.query('catalogo_insumos');
      final Map<dynamic, dynamic> mostrar = {};
      for (final c in _catalogoInsumos) {
        mostrar.putIfAbsent(c['ID_Insumos'], () => c['Mostrar']);
      }
      _mostrarPorInsumo = mostrar;

      await _cargarRegistros();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      mostrarAgroSnack(context, 'No se pudieron cargar los registros: $e',
          tipo: AgroSnackTipo.error);
    }
  }

  Future<void> _cargarRegistros() async {
    if (mounted) setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    // Leemos registros de aplicaciones de este productor
    final List<Map<String, dynamic>> rawRegs = await db.query(
      'aplicaciones_registros',
      where: 'cod_productor = ?',
      whereArgs: [_userCodProductor],
      orderBy: 'fecha DESC, cod_orden DESC',
    );

    final Set<String> chSet = {"TODAS"};
    for (var r in rawRegs) {
      final ch = (r['chacra'] ?? '').toString().trim();
      if (ch.isNotEmpty) chSet.add(ch);
    }

    if (!mounted) return;
    setState(() {
      _registros = rawRegs;
      _chacrasDisponibles = chSet.toList();
      if (!chSet.contains(_filtroChacra)) _filtroChacra = "TODAS";
      _cargando = false;
    });
  }

  // Registros procesados y filtrados
  List<Map<String, dynamic>> get _registrosFiltrados {
    return _registros.where((r) {
      // 1. Filtro de Auditoría vs Interno
      if (_tipoReporte == 'AUDITORIA') {
        final hab = (r['habilitado'] ?? 'ACTIVO').toString().toUpperCase();
        if (hab == 'INACTIVO' || hab == 'NO') return false;

        // Comprobación de catálogo si está configurado Mostrar = 1
        final codProd = r['cod_producto'];
        if (codProd != null && _mostrarPorInsumo.containsKey(codProd)) {
          if (_mostrarPorInsumo[codProd] == 0) return false;
        }
      }

      // 2. Filtro de Chacra
      final ch = (r['chacra'] ?? '').toString();
      if (_filtroChacra != "TODAS" && ch != _filtroChacra) return false;

      // 3. Filtro de Tipo / Rubro
      final motivo = (r['motivo_aplic'] ?? '').toString().toUpperCase();
      final prod = (r['producto'] ?? '').toString().toUpperCase();

      if (_filtroRubro == "AGROQUÍMICOS" &&
          (motivo.contains('FERTI') || prod.contains('FERTI') || prod.contains('UREA'))) {
        return false;
      }
      if (_filtroRubro == "FERTILIZANTE" &&
          (!motivo.contains('FERTI') && !prod.contains('FERTI') && !prod.contains('ABONO'))) {
        return false;
      }
      if (_filtroRubro == "FERTIRRIEGO" &&
          (!motivo.contains('RIEGO') && !prod.contains('RIEGO'))) {
        return false;
      }
      if (_filtroRubro == "HERBICIDAS" &&
          (!motivo.contains('HERBI') && !prod.contains('GLIFO') && !prod.contains('HERBI'))) {
        return false;
      }

      // 4. Filtro de Rango de Fechas
      final String fStr = (r['fecha'] ?? '').toString().split('T').first;
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
    return _filtroRubro != "TODOS" || _filtroChacra != "TODAS" || !fechasDef;
  }

  void _restablecerFiltros() {
    setState(() {
      _filtroRubro = "TODOS";
      _filtroChacra = "TODAS";
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

  // ==========================================================================
  // FILAS / ENCABEZADOS (compartidos entre PDF y tabla en pantalla)
  // ==========================================================================
  List<String> _headersPdf(bool esAuditoria) => esAuditoria
      ? ['FECHA', 'CHACRA/CUADRO', 'VARIEDAD', 'PLAGA / TARGET', 'PRODUCTO COMERCIAL', 'DOSIS / 100L', 'VOL. HA', 'T.C.', 'T.I.', 'OPERARIO']
      : ['FECHA', 'ÓRDEN', 'CHACRA/CUADRO', 'VARIEDAD', 'SUP', 'PRODUCTO', 'DOSIS 100', 'DOSIS MAQ', 'VOL/HA', 'TRACTORISTA', 'CONSUMO'];

  List<int> _flexTabla(bool esAuditoria) => esAuditoria
      ? [3, 4, 3, 4, 5, 2, 2, 2, 2, 3]
      : [3, 2, 4, 3, 2, 5, 2, 2, 2, 3, 3];

  List<String> _filaPdf(Map<String, dynamic> r, bool esAuditoria) {
    final fStr = (r['fecha'] ?? '').toString().split('T').first;
    final cuadroInfo = "${r['chacra'] ?? ''} - C.${r['cuadros'] ?? r['cuadro'] ?? '-'}";
    final dosis100 = "${r['dosis_100'] ?? '-'}";
    final volHa = "${r['vol_aplic_ha'] ?? '-'} L";

    if (esAuditoria) {
      return [
        fStr,
        cuadroInfo,
        (r['variedad'] ?? 'General').toString(),
        (r['motivo_aplic'] ?? 'Fitosanitario').toString(),
        (r['producto'] ?? '').toString(),
        dosis100,
        volHa,
        (r['tc'] ?? '-').toString(),
        (r['ti'] ?? '-').toString(),
        (r['tractorista'] ?? r['responsable'] ?? '-').toString(),
      ];
    } else {
      return [
        fStr,
        "${r['cod_orden'] ?? '-'}",
        cuadroInfo,
        (r['variedad'] ?? 'General').toString(),
        "${r['sup_aplic'] ?? '-'} Ha",
        (r['producto'] ?? '').toString(),
        dosis100,
        "${r['dosis_maq'] ?? '-'}",
        volHa,
        (r['tractorista'] ?? '-').toString(),
        "${r['consumo_prod'] ?? '-'} L/Kg",
      ];
    }
  }

  // ==========================================================================
  // 📄 EXPORTADOR PDF DEL CUADERNO DE CAMPO (REGLAMENTARIO)
  // ==========================================================================
  Future<void> _exportarPdfCuaderno() async {
    if (_exportandoPdf || _exportandoExcel) return;
    final filtrados = _registrosFiltrados;
    if (filtrados.isEmpty) {
      mostrarAgroSnack(context, 'No hay registros para los filtros seleccionados.',
          tipo: AgroSnackTipo.aviso);
      return;
    }

    setState(() => _exportandoPdf = true);
    try {
      final pdf = pw.Document();
      final String anio = DateTime.now().year.toString();

      // Carga de logo segura sin crash en Web
      pw.MemoryImage? logoImage;
      try {
        final ByteData bytes = await rootBundle.load('logo/logo_anibal.png');
        logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
      } catch (_) {
        try {
          final ByteData bytesFallback = await rootBundle.load('logo/logo.png');
          logoImage = pw.MemoryImage(bytesFallback.buffer.asUint8List());
        } catch (_) {}
      }

      const colorVerdeOscuro = PdfColor.fromInt(0xFF134E32);
      const colorVerdeSecundario = PdfColor.fromInt(0xFF1E6B4C);
      const colorBorde = PdfColor.fromInt(0xFFE5E7EB);
      const colorFondoGris = PdfColor.fromInt(0xFFF9FAFB);

      final bool esAuditoria = _tipoReporte == "AUDITORIA";

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
                            "CUADERNO DE CAMPO · REGISTRO OFICIAL DE APLICACIONES FITOSANITARIAS",
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
                            "Modalidad: ${esAuditoria ? 'DOCUMENTO DE AUDITORÍA OFICIAL (SENASA / GLOBALGAP)' : 'REGISTRO DE CONTROL OPERATIVO INTERNO'}",
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
                        pw.Text(" · Sistema Integral de Trazabilidad y Buenas Prácticas Agrícolas",
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
                        pw.Text("Firma del Responsable Técnico", style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Container(width: 140, height: 1, color: PdfColors.grey600),
                        pw.SizedBox(height: 2),
                        pw.Text("Firma del Productor / Aplicador", style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
          build: (pw.Context context) {
            final List<String> headers = _headersPdf(esAuditoria);
            final data = filtrados.map((r) => _filaPdf(r, esAuditoria)).toList();

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
          'Cuaderno_Campo_${_tipoReporte}_${agroNombreArchivo(_nombreProductor)}_$anio.pdf';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.pdf,
        texto: 'Cuaderno de Campo Oficial - $_nombreProductor',
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
  // 📊 EXPORTADOR EXCEL (.XLSX) PROFESIONAL
  // ==========================================================================
  Future<void> _exportarExcelCuaderno() async {
    if (_exportandoPdf || _exportandoExcel) return;
    final filtrados = _registrosFiltrados;
    if (filtrados.isEmpty) {
      mostrarAgroSnack(context, 'No hay registros para exportar.', tipo: AgroSnackTipo.aviso);
      return;
    }

    setState(() => _exportandoExcel = true);
    try {
      final excel = xl.Excel.createExcel();
      final defSheet = excel.getDefaultSheet();
      if (defSheet != null) excel.delete(defSheet);

      final bool esAuditoria = _tipoReporte == "AUDITORIA";
      final String nombreHoja = esAuditoria ? "Cuaderno_Auditoria" : "Cuaderno_Interno";
      final xl.Sheet sheet = excel[nombreHoja];
      excel.setDefaultSheet(nombreHoja);

      final estiloHeader = xl.CellStyle(
        bold: true,
        fontSize: 10,
        backgroundColorHex: xl.ExcelColor.fromHexString("#1E6B4C"),
        fontColorHex: xl.ExcelColor.fromHexString("#FFFFFF"),
        horizontalAlign: xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
      );

      // Cabecera institucional
      sheet.appendRow([xl.TextCellValue("AGROSOFT J&L · CUADERNO DE CAMPO DIGITAL")]);
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
        xl.TextCellValue(esAuditoria ? "AUDITORÍA OFICIAL" : "CONTROL OPERATIVO INTERNO"),
        xl.TextCellValue("RUBRO:"),
        xl.TextCellValue(_filtroRubro),
        xl.TextCellValue("EMISIÓN:"),
        xl.TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
      ]);
      sheet.appendRow([]); // Separador

      final List<xl.CellValue> cabeceras = esAuditoria
          ? [
              xl.TextCellValue("FECHA"),
              xl.TextCellValue("CHACRA"),
              xl.TextCellValue("CUADRO"),
              xl.TextCellValue("VARIEDAD"),
              xl.TextCellValue("TARGET / MOTIVO"),
              xl.TextCellValue("PRODUCTO COMERCIAL"),
              xl.TextCellValue("DOSIS 100L"),
              xl.TextCellValue("VOLUMEN/HA"),
              xl.TextCellValue("T.C. (DÍAS)"),
              xl.TextCellValue("T.I. (HS)"),
              xl.TextCellValue("OPERARIO RESPONSABLE"),
            ]
          : [
              xl.TextCellValue("REGISTRO"),
              xl.TextCellValue("ÓRDEN"),
              xl.TextCellValue("FECHA"),
              xl.TextCellValue("CHACRA"),
              xl.TextCellValue("CUADROS"),
              xl.TextCellValue("VARIEDAD"),
              xl.TextCellValue("SUPERFICIE (HA)"),
              xl.TextCellValue("PRODUCTO"),
              xl.TextCellValue("DOSIS 100L"),
              xl.TextCellValue("DOSIS MÁQ"),
              xl.TextCellValue("VOL/HA"),
              xl.TextCellValue("TRACTORISTA"),
              xl.TextCellValue("PULVERIZADORA"),
              xl.TextCellValue("CONSUMO TOTAL"),
              xl.TextCellValue("ESTADO"),
            ];

      sheet.appendRow(cabeceras);
      final int idxFilaCab = sheet.maxRows - 1;
      for (int c = 0; c < cabeceras.length; c++) {
        sheet.row(idxFilaCab)[c]?.cellStyle = estiloHeader;
      }

      for (var r in filtrados) {
        final fStr = (r['fecha'] ?? '').toString().split('T').first;

        if (esAuditoria) {
          sheet.appendRow([
            xl.TextCellValue(fStr),
            xl.TextCellValue((r['chacra'] ?? '').toString()),
            xl.TextCellValue((r['cuadros'] ?? r['cuadro'] ?? '').toString()),
            xl.TextCellValue((r['variedad'] ?? 'General').toString()),
            xl.TextCellValue((r['motivo_aplic'] ?? '').toString()),
            xl.TextCellValue((r['producto'] ?? '').toString()),
            xl.DoubleCellValue(double.tryParse((r['dosis_100'] ?? '0').toString()) ?? 0.0),
            xl.DoubleCellValue(double.tryParse((r['vol_aplic_ha'] ?? '0').toString()) ?? 0.0),
            xl.TextCellValue((r['tc'] ?? '-').toString()),
            xl.TextCellValue((r['ti'] ?? '-').toString()),
            xl.TextCellValue((r['tractorista'] ?? r['responsable'] ?? '').toString()),
          ]);
        } else {
          sheet.appendRow([
            xl.TextCellValue((r['registro'] ?? '').toString()),
            xl.IntCellValue(int.tryParse((r['cod_orden'] ?? '0').toString()) ?? 0),
            xl.TextCellValue(fStr),
            xl.TextCellValue((r['chacra'] ?? '').toString()),
            xl.TextCellValue((r['cuadros'] ?? r['cuadro'] ?? '').toString()),
            xl.TextCellValue((r['variedad'] ?? 'General').toString()),
            xl.DoubleCellValue(double.tryParse((r['sup_aplic'] ?? '0').toString()) ?? 0.0),
            xl.TextCellValue((r['producto'] ?? '').toString()),
            xl.DoubleCellValue(double.tryParse((r['dosis_100'] ?? '0').toString()) ?? 0.0),
            xl.DoubleCellValue(double.tryParse((r['dosis_maq'] ?? '0').toString()) ?? 0.0),
            xl.DoubleCellValue(double.tryParse((r['vol_aplic_ha'] ?? '0').toString()) ?? 0.0),
            xl.TextCellValue((r['tractorista'] ?? '').toString()),
            xl.TextCellValue((r['pulverizadora'] ?? '').toString()),
            xl.DoubleCellValue(double.tryParse((r['consumo_prod'] ?? '0').toString()) ?? 0.0),
            xl.TextCellValue((r['habilitado'] ?? 'ACTIVO').toString()),
          ]);
        }
      }

      final List<int>? fileBytes = excel.encode();
      if (fileBytes == null) {
        if (mounted) {
          mostrarAgroSnack(context, 'No se pudo generar el Excel.', tipo: AgroSnackTipo.error);
        }
        return;
      }

      final Uint8List bytes = Uint8List.fromList(fileBytes);
      final String nombreArchivo =
          'Cuaderno_Campo_${_tipoReporte}_${agroNombreArchivo(_nombreProductor)}.xlsx';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.xlsx,
        texto: 'Cuaderno de Campo Excel - $_nombreProductor',
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
    final filtrados = _registrosFiltrados;
    final bool esAncho = AgroBreakpoints.ancho(context) >= 900;
    const gap = SizedBox(height: 16);

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: 'Cuaderno de campo',
        subtitulo: _nombreProductor.isEmpty
            ? 'Registro oficial de aplicaciones'
            : _nombreProductor,
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: 'Actualizar',
            onTap: _cargando ? null : _inicializar,
          ),
        ],
      ),
      body: _cargando
          ? const AgroLoading(mensaje: 'Cargando aplicaciones…')
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
                onPdf: _exportarPdfCuaderno,
                onExcel: _exportarExcelCuaderno,
                cargandoPdf: _exportandoPdf,
                cargandoExcel: _exportandoExcel,
                info: '${filtrados.length} registros · $_textoModo',
              ),
            ),
    );
  }

  Widget _encabezado(int total) {
    return AgroReporteHeader(
      titulo: 'Cuaderno de campo oficial',
      subtitulo: _nombreProductor.isEmpty
          ? 'Registro de aplicaciones fitosanitarias'
          : 'Establecimiento: $_nombreProductor',
      icono: Icons.menu_book_rounded,
      chips: [
        AgroHeaderChip(texto: 'CUIT $_cuitProductor', icono: Icons.badge_outlined),
        AgroHeaderChip(texto: 'RENSPA $_renspaProductor', icono: Icons.verified_user_outlined),
        AgroHeaderChip(texto: _textoRango, icono: Icons.date_range_rounded),
        AgroHeaderChip(
          texto: '$total ${total == 1 ? 'registro' : 'registros'}',
          icono: Icons.list_alt_rounded,
        ),
      ],
    );
  }

  Widget _panelFiltros() {
    final chacras = _chacrasDisponibles.where((c) => c != "TODAS").toList();
    final rubros = _rubrosDisponibles.where((r) => r != "TODOS").toList();

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
                ? 'Formato SENASA / GlobalGAP: excluye registros inactivos y productos ocultos del catálogo.'
                : 'Gestión interna completa: incluye todos los registros, consumos y órdenes.',
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
          const SizedBox(height: 14),
          AgroChipSelector(
            label: 'Rubro',
            opciones: rubros,
            valor: _filtroRubro == "TODOS" ? null : _filtroRubro,
            textoTodos: 'Todos',
            onChanged: (v) => setState(() => _filtroRubro = v ?? "TODOS"),
          ),
          if (chacras.isNotEmpty) ...[
            const SizedBox(height: 14),
            AgroChipSelector(
              label: 'Chacra',
              opciones: chacras,
              valor: _filtroChacra == "TODAS" ? null : _filtroChacra,
              textoTodos: 'Todas',
              onChanged: (v) => setState(() => _filtroChacra = v ?? "TODAS"),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpis(List<Map<String, dynamic>> filtrados) {
    final Set<String> productos = {};
    final Set<String> fechas = {};
    final Set<String> ordenes = {};
    final Set<String> chacras = {};
    final Map<String, double> supPorCuadro = {};

    for (final r in filtrados) {
      final p = (r['producto'] ?? '').toString().trim().toUpperCase();
      if (p.isNotEmpty) productos.add(p);
      final f = (r['fecha'] ?? '').toString().split('T').first;
      if (f.isNotEmpty) fechas.add(f);
      final o = (r['cod_orden'] ?? '').toString();
      if (o.isNotEmpty) ordenes.add(o);
      final ch = (r['chacra'] ?? '').toString().trim();
      if (ch.isNotEmpty) chacras.add(ch);
      // La superficie se repite por cada producto de la misma orden/cuadro:
      // se cuenta una sola vez por combinación orden + chacra + cuadros.
      final clave = '$o|$ch|${r['cuadros'] ?? r['cuadro'] ?? ''}';
      supPorCuadro.putIfAbsent(clave, () => _num(r['sup_aplic']));
    }
    final double superficie = supPorCuadro.values.fold<double>(0, (a, b) => a + b);

    return AgroKpiGrid(
      kpis: [
        AgroKpiTile(
          label: 'Aplicaciones',
          valor: '${filtrados.length}',
          icono: Icons.water_drop_outlined,
          detalle: '${ordenes.length} ${ordenes.length == 1 ? 'orden' : 'órdenes'}',
        ),
        AgroKpiTile(
          label: 'Productos distintos',
          valor: '${productos.length}',
          icono: Icons.science_outlined,
          color: AgroColors.info,
        ),
        AgroKpiTile(
          label: 'Días con labores',
          valor: '${fechas.length}',
          icono: Icons.event_available_outlined,
          color: AgroColors.warn,
          detalle: '${chacras.length} ${chacras.length == 1 ? 'chacra' : 'chacras'}',
        ),
        AgroKpiTile(
          label: 'Superficie tratada',
          valor: '${superficie.toStringAsFixed(1)} ha',
          icono: Icons.landscape_outlined,
          color: AgroColors.ok,
          detalle: 'Por orden y cuadro',
        ),
      ],
    );
  }

  Widget _graficos(List<Map<String, dynamic>> filtrados, bool esAncho) {
    // Top productos por cantidad de aplicaciones
    final Map<String, int> porProducto = {};
    final Map<String, int> porMes = {};
    for (final r in filtrados) {
      final p = (r['producto'] ?? '').toString().trim();
      if (p.isNotEmpty) porProducto[p] = (porProducto[p] ?? 0) + 1;
      final d = DateTime.tryParse((r['fecha'] ?? '').toString().split('T').first);
      if (d != null) {
        final k = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        porMes[k] = (porMes[k] ?? 0) + 1;
      }
    }
    final top = porProducto.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final itemsProd = top
        .take(8)
        .map((e) => AgroBarItem(label: e.key, valor: e.value.toDouble()))
        .toList();

    final meses = porMes.keys.toList()..sort();
    final ultimos = meses.length > 12 ? meses.sublist(meses.length - 12) : meses;
    final itemsMes = ultimos.map((k) {
      final partes = k.split('-');
      final anio = partes[0].substring(2);
      final mes = int.tryParse(partes[1]) ?? 1;
      final label = '${_meses[mes - 1]} $anio';
      final v = porMes[k] ?? 0;
      return AgroBarItem(
        label: label,
        valor: v.toDouble(),
        detalle: '$label: $v aplicaciones',
      );
    }).toList();

    final cardProductos = AgroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgroSectionHeader(
            titulo: 'Productos más aplicados',
            subtitulo: 'Cantidad de aplicaciones en el período',
            icono: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 14),
          AgroBarChart(items: itemsProd, anchoLabel: 130),
        ],
      ),
    );

    final cardMeses = AgroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgroSectionHeader(
            titulo: 'Aplicaciones por mes',
            subtitulo: 'Evolución de las labores registradas',
            icono: Icons.calendar_month_rounded,
          ),
          const SizedBox(height: 14),
          AgroColumnChart(items: itemsMes, color: AgroColors.info),
        ],
      ),
    );

    if (esAncho) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: cardProductos),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: cardMeses),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cardProductos,
        const SizedBox(height: 16),
        cardMeses,
      ],
    );
  }

  Widget _listado(List<Map<String, dynamic>> filtrados, bool esAncho) {
    if (filtrados.isEmpty) {
      return SizedBox(
        height: 360,
        child: AgroEmptyState(
          icono: Icons.menu_book_rounded,
          titulo: _registros.isEmpty
              ? 'Todavía no hay aplicaciones registradas'
              : 'Sin aplicaciones para estos filtros',
          mensaje: _registros.isEmpty
              ? 'Cuando se registren labores de aplicación aparecerán en este cuaderno.'
              : 'Probá ampliar el período o cambiar el rubro, la chacra o la modalidad.',
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
          titulo: 'Registro de aplicaciones',
          subtitulo: esAuditoria
              ? 'Vista previa del formato de auditoría'
              : 'Vista previa del formato interno',
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
            filas: visibles.map((r) => _filaPdf(r, esAuditoria)).toList(),
          )
        else
          ...visibles.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _tarjeta(r, esAuditoria),
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

  Widget _tarjeta(Map<String, dynamic> r, bool esAuditoria) {
    final fStr = (r['fecha'] ?? '').toString().split('T').first;
    final chacraCuadro = "${r['chacra'] ?? '-'} · C.${r['cuadros'] ?? r['cuadro'] ?? '-'}";
    final motivo = (r['motivo_aplic'] ?? '').toString().trim();
    final operario = (r['tractorista'] ?? r['responsable'] ?? '').toString().trim();

    return AgroCard(
      padding: const EdgeInsets.all(14),
      accentColor: esAuditoria ? AgroColors.primario : AgroColors.warn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AgroBadge(
                texto: _fechaCorta(fStr),
                icono: Icons.event_rounded,
                color: AgroColors.primario,
                fondo: AgroColors.primarioSoft,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chacraCuadro,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.valor.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  (r['variedad'] ?? 'General').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AgroText.secundario.copyWith(fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${r['producto'] ?? 'S/D'}",
            style: AgroText.tituloCard.copyWith(fontSize: 14.5),
          ),
          if (motivo.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(motivo, style: AgroText.secundario),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AgroTag(texto: "Dosis ${r['dosis_100'] ?? '-'} /100 L", icono: Icons.opacity_rounded),
              AgroTag(texto: "Vol/ha ${r['vol_aplic_ha'] ?? '-'} L", icono: Icons.speed_rounded),
              if (esAuditoria) ...[
                AgroTag(texto: "TC ${r['tc'] ?? '-'} d", icono: Icons.hourglass_bottom_rounded),
                AgroTag(texto: "TI ${r['ti'] ?? '-'} h", icono: Icons.timer_outlined),
              ] else ...[
                AgroTag(texto: "Orden ${r['cod_orden'] ?? '-'}", icono: Icons.tag_rounded),
                AgroTag(texto: "${r['sup_aplic'] ?? '-'} ha", icono: Icons.landscape_outlined),
                AgroTag(
                    texto: "Consumo ${r['consumo_prod'] ?? '-'} L/Kg",
                    icono: Icons.inventory_2_outlined),
              ],
              if (operario.isNotEmpty)
                AgroTag(texto: operario, icono: Icons.person_outline_rounded),
            ],
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
