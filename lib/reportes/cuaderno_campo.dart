import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

class CuadernoCampoScreen extends StatefulWidget {
  const CuadernoCampoScreen({super.key});

  @override
  State<CuadernoCampoScreen> createState() => _CuadernoCampoScreenState();
}

class _CuadernoCampoScreenState extends State<CuadernoCampoScreen> {
  bool _cargando = true;
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;
  String _nombreProductor = "";
  String _cuitProductor = "S/D";
  String _renspaProductor = "S/D";

  // Filtros de pantalla
  String _tipoReporte = "AUDITORIA"; // 'AUDITORIA' | 'INTERNO'
  String _filtroRubro = "TODOS"; // 'TODOS' | 'AGROQUIMICOS' | 'FERTILIZANTE' | 'FERTIRRIEGO'
  String _filtroChacra = "TODAS";
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  List<String> _chacrasDisponibles = ["TODAS"];
  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _catalogoInsumos = [];

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

    // Obtener datos del productor actual
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

    // Cargar catálogo de insumos para cruce de auditoría
    _catalogoInsumos = await db.query('catalogo_insumos');

    await _cargarRegistros();
  }

  Future<void> _cargarRegistros() async {
    setState(() => _cargando = true);
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
        if (codProd != null) {
          final ins = _catalogoInsumos.firstWhere(
            (c) => c['ID_Insumos'] == codProd,
            orElse: () => {},
          );
          if (ins.isNotEmpty && ins['Mostrar'] == 0) {
            return false;
          }
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

  // ==========================================================================
  // 📄 EXPORTADOR PDF DEL CUADERNO DE CAMPO (REGLAMENTARIO)
  // ==========================================================================
  Future<void> _exportarPdfCuaderno() async {
    final filtrados = _registrosFiltrados;
    if (filtrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros para los filtros seleccionados.')),
      );
      return;
    }

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
          final List<String> headers = esAuditoria
              ? ['FECHA', 'CHACRA/CUADRO', 'VARIEDAD', 'PLAGA / TARGET', 'PRODUCTO COMERCIAL', 'DOSIS / 100L', 'VOL. HA', 'T.C.', 'T.I.', 'OPERARIO']
              : ['FECHA', 'ÓRDEN', 'CHACRA/CUADRO', 'VARIEDAD', 'SUP', 'PRODUCTO', 'DOSIS 100', 'DOSIS MAQ', 'VOL/HA', 'TRACTORISTA', 'CONSUMO'];

          final data = filtrados.map((r) {
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
    final String nombreArchivo = 'Cuaderno_Campo_${_tipoReporte}_${_nombreProductor.replaceAll(' ', '_')}_$anio.pdf';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
    } else {
      await Share.shareXFiles(
        [
          XFile.fromData(bytes, name: nombreArchivo, mimeType: 'application/pdf'),
        ],
        text: 'Cuaderno de Campo Oficial - $_nombreProductor',
      );
    }
  }

  // ==========================================================================
  // 📊 EXPORTADOR EXCEL (.XLSX) PROFESIONAL
  // ==========================================================================
  Future<void> _exportarExcelCuaderno() async {
    final filtrados = _registrosFiltrados;
    if (filtrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros para exportar.')),
      );
      return;
    }

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

    final List<int>? fileBytes = excel.save();
    if (fileBytes == null) return;

    final Uint8List bytes = Uint8List.fromList(fileBytes);
    final String nombreArchivo = 'Cuaderno_Campo_${_tipoReporte}_${_nombreProductor.replaceAll(' ', '_')}.xlsx';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
    } else {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: nombreArchivo,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        text: 'Cuaderno de Campo Excel - $_nombreProductor',
      );
    }
  }

  void _mostrarSelectorFecha({required bool esDesde}) async {
    final DateTime? seleccionada = await showDatePicker(
      context: context,
      initialDate: esDesde ? (_fechaDesde ?? DateTime.now()) : (_fechaHasta ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: AgroTheme.colorAccentDark),
          ),
          child: child!,
        );
      },
    );

    if (seleccionada != null) {
      setState(() {
        if (esDesde) {
          _fechaDesde = seleccionada;
        } else {
          _fechaHasta = seleccionada;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _registrosFiltrados;

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
              "Cuaderno de Campo Oficial",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText),
            ),
            Text(
              "Establecimiento: $_nombreProductor · CUIT: $_cuitProductor",
              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // =========================================================
            // 1. SELECTOR PRINCIPAL: AUDITORÍA vs INTERNO
            // =========================================================
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
                              "OFICIAL / AUDITORÍA (SENASA)",
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
                              "GESTIÓN INTERNA COMPLETA",
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

            // =========================================================
            // 2. FILTROS RÁPIDOS: RUBROS DE INSUMOS
            // =========================================================
            Container(
              height: 42,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _rubrosDisponibles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final rubro = _rubrosDisponibles[idx];
                  final bool sel = _filtroRubro == rubro;

                  return ChoiceChip(
                    label: Text(rubro),
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
                    onSelected: (_) => setState(() => _filtroRubro = rubro),
                  );
                },
              ),
            ),

            // =========================================================
            // 3. BARRA DE PARÁMETROS (FECHAS Y CHACRA)
            // =========================================================
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
                  if (_chacrasDisponibles.length > 1)
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
                            value: _filtroChacra,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AgroTheme.colorText),
                            items: _chacrasDisponibles.map((ch) {
                              return DropdownMenuItem(value: ch, child: Text(ch, overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (v) => setState(() => _filtroChacra = v ?? "TODAS"),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // =========================================================
            // 4. LISTADO DE PASADAS / APLICACIONES
            // =========================================================
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: AgroTheme.colorAccent))
                  : filtrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.menu_book_rounded, size: 48, color: AgroTheme.colorTextSecondary),
                              SizedBox(height: 10),
                              Text(
                                "No se encontraron labores de aplicación registradas.",
                                style: TextStyle(color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                          itemCount: filtrados.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final r = filtrados[idx];
                            final fStr = (r['fecha'] ?? '').toString().split('T').first;
                            final bool esAuditoria = _tipoReporte == "AUDITORIA";

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AgroTheme.colorSurface,
                                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                                border: Border.all(color: AgroTheme.colorBorder),
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
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AgroTheme.colorAccentSoft,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              fStr,
                                              style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: AgroTheme.colorAccentDark),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "${r['chacra']} - C.${r['cuadros'] ?? r['cuadro'] ?? '-'}",
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        (r['variedad'] ?? 'General').toString(),
                                        style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "${r['producto'] ?? 'S/D'}",
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: AgroTheme.colorText),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Dosis: ${r['dosis_100'] ?? '-'}  ·  Vol/Ha: ${r['vol_aplic_ha'] ?? '-'} L",
                                        style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary),
                                      ),
                                      if (esAuditoria)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AgroTheme.colorBg,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AgroTheme.colorBorder),
                                          ),
                                          child: Text(
                                            "TC: ${r['tc'] ?? '-'} d | TI: ${r['ti'] ?? '-'} h",
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      else
                                        Text(
                                          "Consumo: ${r['consumo_prod'] ?? '-'} L/Kg",
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgroTheme.colorGold),
                                        ),
                                    ],
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
            onTap: _exportarPdfCuaderno,
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
            onTap: _exportarExcelCuaderno,
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