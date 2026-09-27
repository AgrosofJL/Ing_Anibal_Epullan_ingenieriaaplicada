// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl hide Border;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/agro_reportes_ui.dart';
import '../widgets/agro_ui.dart';

class LecturasTrampasScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const LecturasTrampasScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<LecturasTrampasScreen> createState() => _LecturasTrampasScreenState();
}

class _LecturasTrampasScreenState extends State<LecturasTrampasScreen> {
  static const int _umbral = 5;

  bool _cargando = true;
  bool _exportando = false;
  String _userName = "Operario";

  List<Map<String, dynamic>> _trampasMaestras = [];
  List<Map<String, dynamic>> _lecturasTemporada = [];
  List<String> _semanasDetectadas = [];

  List<String> _chacrasDisponibles = [];
  String _chacraSeleccionada = "TODAS";

  List<String> _cuadrosDisponibles = ["TODOS"];
  String _cuadroSeleccionado = "TODOS";

  final TextEditingController _searchCtrl = TextEditingController();
  String _filtroTexto = "";

  /// Filtro rápido solo de pantalla (no afecta las exportaciones):
  /// 'todas' | 'pendientes' | 'alerta'
  String _filtroEstado = 'todas';

  final ImagePicker _picker = ImagePicker();

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
    setState(() => _cargando = true);
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('userName') ?? "Operario";
    await _cargarDatosCompletos();
  }

  Future<void> _cargarDatosCompletos() async {
    final db = await DatabaseHelper.instance.database;
    final int anioActual = DateTime.now().year;

    final List<Map<String, dynamic>> trampas = await db.rawQuery('''
      SELECT
        t.cod_trampa,
        t.trampa_numero,
        t.tipo_trampa,
        t.sector as chacra,
        t.cuadro,
        t.fila,
        t.variedad,
        t.cultivo,
        t.ubicacion,
        (
          SELECT l.created_at FROM lecturas_trampas l
          WHERE l.cod_trampa = t.cod_trampa AND l.semana != 'INSTALACION'
          ORDER BY l.created_at DESC LIMIT 1
        ) as ultima_fecha,
        (
          SELECT l.semana FROM lecturas_trampas l
          WHERE l.cod_trampa = t.cod_trampa AND l.semana != 'INSTALACION'
          ORDER BY l.created_at DESC LIMIT 1
        ) as ultima_semana,
        (
          SELECT l.url_evidencia FROM lecturas_trampas l
          WHERE l.cod_trampa = t.cod_trampa AND l.semana != 'INSTALACION' AND l.url_evidencia IS NOT NULL AND l.url_evidencia != ''
          ORDER BY l.created_at DESC LIMIT 1
        ) as ultima_foto,
        (
          SELECT CAST(l.macho AS INTEGER) + CAST(l.hembra_virgen AS INTEGER) + CAST(l.hembra_gravida AS INTEGER)
          FROM lecturas_trampas l
          WHERE l.cod_trampa = t.cod_trampa AND l.semana != 'INSTALACION'
          ORDER BY l.created_at DESC LIMIT 1
        ) as ultimo_total
      FROM lecturas_trampas t
      WHERE t.cod_establecimiento = ? AND t.cod_trampa IS NOT NULL
      GROUP BY t.cod_trampa
      ORDER BY t.cuadro ASC, CAST(t.trampa_numero AS INTEGER) ASC
    ''', [widget.codProductor]);

    final List<Map<String, dynamic>> lecturas = await db.query(
      'lecturas_trampas',
      where: 'cod_establecimiento = ? AND semana != ? AND temporada = ?',
      whereArgs: [widget.codProductor, 'INSTALACION', '$anioActual'],
      orderBy: 'created_at ASC',
    );

    final Set<String> semanasSet = {};
    for (var l in lecturas) {
      final sem = l['semana']?.toString();
      if (sem != null && sem.isNotEmpty) {
        semanasSet.add(sem);
      }
    }
    final List<String> semanasList = semanasSet.toList()..sort();

    final Set<String> chacrasSet = {"TODAS"};
    for (var t in trampas) {
      final ch = t['chacra']?.toString();
      if (ch != null && ch.isNotEmpty) chacrasSet.add(ch);
    }

    if (!mounted) return;
    setState(() {
      _trampasMaestras = trampas;
      _lecturasTemporada = lecturas;
      _semanasDetectadas = semanasList;
      _chacrasDisponibles = chacrasSet.toList();
      _actualizarCuadrosDisponibles();
      _cargando = false;
    });
  }

  void _actualizarCuadrosDisponibles() {
    final Set<String> cuadrosSet = {"TODOS"};
    for (var t in _trampasMaestras) {
      final matchChacra = _chacraSeleccionada == "TODAS" ||
          (t['chacra'] ?? '').toString() == _chacraSeleccionada;
      if (matchChacra) {
        final cu = t['cuadro']?.toString();
        if (cu != null && cu.isNotEmpty) cuadrosSet.add(cu);
      }
    }
    _cuadrosDisponibles = cuadrosSet.toList();
    if (!_cuadrosDisponibles.contains(_cuadroSeleccionado)) {
      _cuadroSeleccionado = "TODOS";
    }
  }

  List<Map<String, dynamic>> get _trampasFiltradas {
    return _trampasMaestras.where((t) {
      final matchChacra = _chacraSeleccionada == "TODAS" ||
          (t['chacra'] ?? '').toString() == _chacraSeleccionada;
      if (!matchChacra) return false;

      final matchCuadro = _cuadroSeleccionado == "TODOS" ||
          (t['cuadro'] ?? '').toString() == _cuadroSeleccionado;
      if (!matchCuadro) return false;

      if (_filtroTexto.isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final nro = (t['trampa_numero'] ?? '').toString().toLowerCase();
      final plaga = (t['tipo_trampa'] ?? '').toString().toLowerCase();
      final variedad = (t['variedad'] ?? '').toString().toLowerCase();
      return nro.contains(q) || plaga.contains(q) || variedad.contains(q);
    }).toList();
  }

  int get _trampasEnAlerta {
    return _trampasFiltradas.where((t) {
      final tot = int.tryParse(t['ultimo_total']?.toString() ?? '0') ?? 0;
      return tot >= 5;
    }).length;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _calcularSemanaIso(DateTime f) {
    final dayOfYear = int.parse(DateFormat("D").format(f));
    final int w = ((dayOfYear - f.weekday + 10) / 7).floor();
    return "Semana ${w.toString().padLeft(2, '0')}";
  }

  int _totalLectura(Map<String, dynamic> l) {
    final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
    final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
    final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
    return m + hv + hg;
  }

  /// Verde bajo umbral, ámbar cerca del umbral, rojo desde el umbral (>= 5).
  Color _colorCaptura(int total) {
    if (total >= _umbral) return AgroColors.danger;
    if (total >= _umbral - 2) return AgroColors.warn;
    return AgroColors.ok;
  }

  Color _fondoCaptura(int total) {
    if (total >= _umbral) return AgroColors.dangerSoft;
    if (total >= _umbral - 2) return AgroColors.warnSoft;
    return AgroColors.okSoft;
  }

  String _fmtFecha(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.split('T').first;
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  String get _semanaActual => _calcularSemanaIso(DateTime.now());

  /// Códigos de trampa con lectura cargada en la semana en curso.
  Set<String> get _codigosLeidosSemanaActual {
    final sem = _semanaActual;
    return _lecturasTemporada
        .where((l) => l['semana']?.toString() == sem)
        .map((l) => (l['cod_trampa'] ?? '').toString())
        .toSet();
  }

  List<AgroLeyendaItem> get _leyendaUmbral => const [
        AgroLeyendaItem('0–2 ind.', AgroColors.ok),
        AgroLeyendaItem('3–4 ind. (cerca del umbral)', AgroColors.warn),
        AgroLeyendaItem('≥ 5 ind. (umbral de daño)', AgroColors.danger),
      ];

  /// Promedio de capturas por trampa leída, por semana (trampas del filtro).
  List<AgroBarItem> _itemsResumenSemanal(List<Map<String, dynamic>> trampas) {
    final codigos = trampas.map((t) => (t['cod_trampa'] ?? '').toString()).toSet();
    final List<AgroBarItem> items = [];
    for (final sem in _semanasDetectadas) {
      int total = 0;
      final Set<String> leidas = {};
      for (final l in _lecturasTemporada) {
        if (l['semana']?.toString() != sem) continue;
        final cod = (l['cod_trampa'] ?? '').toString();
        if (!codigos.contains(cod)) continue;
        total += _totalLectura(l);
        leidas.add(cod);
      }
      if (leidas.isEmpty) continue;
      final double prom = total / leidas.length;
      items.add(AgroBarItem(
        label: sem.replaceAll('Semana ', 'S'),
        valor: prom,
        detalle:
            '$sem · $total capturas en ${leidas.length} trampas · promedio ${prom.toStringAsFixed(1)}',
      ));
    }
    return items;
  }

  // ============================================================
  // EXPORTACIONES
  // ============================================================

  void _abrirMenuExportar() {
    final n = _trampasFiltradas.length;
    mostrarAgroPanel<void>(
      context: context,
      titulo: 'Exportar monitoreo',
      subtitulo: 'Se exportan las $n trampas del filtro activo',
      icono: Icons.file_download_rounded,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgroOptionTile(
            icono: Icons.grid_on_rounded,
            titulo: 'Matriz semanal (Excel)',
            descripcion:
                'Capturas por trampa y semana, con las celdas sobre umbral resaltadas.',
            onTap: () {
              Navigator.pop(ctx);
              _exportarExcelMatrizTrampas();
            },
          ),
          AgroOptionTile(
            icono: Icons.picture_as_pdf_rounded,
            color: AgroColors.danger,
            titulo: 'Planilla oficial (PDF)',
            descripcion: 'Matriz de monitoreo y trampeo semanal en formato apaisado.',
            onTap: () {
              Navigator.pop(ctx);
              _exportarPdfMatrizOficial();
            },
          ),
          const SizedBox(height: 4),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: AgroTheme.colorTextSecondary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Para el informe individual de una trampa, abrí su curva de capturas y usá el botón PDF.',
                  style: AgroText.secundario,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportarExcelMatrizTrampas() async {
    if (_trampasFiltradas.isEmpty) {
      mostrarAgroSnack(context, 'No hay datos para exportar en el filtro activo.',
          tipo: AgroSnackTipo.aviso);
      return;
    }
    if (_exportando) return;
    setState(() => _exportando = true);

    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Matriz_Trampeo'];
      excel.delete('Sheet1');

      final headerStyle = xl.CellStyle(
        bold: true,
        fontColorHex: xl.ExcelColor.white,
        backgroundColorHex: xl.ExcelColor.fromHexString('#1E6B4C'),
        horizontalAlign: xl.HorizontalAlign.Center,
      );

      final List<String> semanas = List<String>.from(_semanasDetectadas);
      if (semanas.isEmpty) semanas.add("Semana ${DateFormat('w').format(DateTime.now())}");

      final headers = [
        'Trampa N°',
        'Chacra',
        'Cuadro',
        'Fila',
        'Plaga',
        'Cultivo',
        'Variedad',
        ...semanas.map((s) => s.replaceAll('Semana ', 'SEM ')),
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = xl.TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      int rowIdx = 1;
      for (var t in _trampasFiltradas) {
        final String codTr = t['cod_trampa'] ?? '';

        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value =
            xl.TextCellValue(t['trampa_numero']?.toString() ?? '');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value =
            xl.TextCellValue(t['chacra']?.toString() ?? '');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value =
            xl.TextCellValue(t['cuadro']?.toString() ?? '');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value =
            xl.TextCellValue(t['fila']?.toString() ?? '');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value =
            xl.TextCellValue(t['tipo_trampa']?.toString() ?? '');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value =
            xl.TextCellValue(t['cultivo']?.toString() ?? '');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value =
            xl.TextCellValue(t['variedad']?.toString() ?? '');

        int colOffset = 7;
        for (var sem in semanas) {
          final lecturasSem = _lecturasTemporada.where(
            (l) => l['cod_trampa'] == codTr && l['semana'] == sem,
          );

          if (lecturasSem.isEmpty) {
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colOffset, rowIndex: rowIdx)).value =
                xl.TextCellValue('-');
          } else {
            final l = lecturasSem.first;
            final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
            final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
            final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
            final int total = m + hv + hg;

            final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colOffset, rowIndex: rowIdx));
            cell.value = xl.IntCellValue(total);

            if (total >= 5) {
              cell.cellStyle = xl.CellStyle(
                bold: true,
                fontColorHex: xl.ExcelColor.fromHexString('#C62828'),
                backgroundColorHex: xl.ExcelColor.fromHexString('#FFEBEE'),
              );
            }
          }
          colOffset++;
        }
        rowIdx++;
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) return;

      final Uint8List bytes = Uint8List.fromList(fileBytes);
      final String nombreArchivo =
          'Monitoreo_Trampas_${widget.nombreProductor.replaceAll(' ', '_')}.xlsx';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.xlsx,
        texto: 'Matriz de Trampas - ${widget.nombreProductor}',
        context: context,
      );
    } catch (e) {
      if (!mounted) return;
      mostrarAgroSnack(context, "Error al exportar: $e", tipo: AgroSnackTipo.error);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _generarPdfTrampa(
      Map<String, dynamic> trampa, List<Map<String, dynamic>> lecturas) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('logo/logo_anibal.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      try {
        final logoBytesFallback = await rootBundle.load('logo/logo.png');
        logoImage = pw.MemoryImage(logoBytesFallback.buffer.asUint8List());
      } catch (_) {}
    }

    final List<Map<String, dynamic>> datosGrafico = [];
    int maxValor = 5;

    for (var l in lecturas) {
      final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
      final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
      final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
      final int total = m + hv + hg;
      if (total > maxValor) maxValor = total;
      datosGrafico.add({
        'semana': (l['semana'] ?? '').toString().replaceAll('Semana ', 'S'),
        'total': total,
        'machos': m,
        'hembras': hv + hg,
      });
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(thickness: 0.8, color: PdfColors.grey300),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "Powered by AgroSoft J&L Soluciones Integrales · Chimpay, Río Negro",
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                  ),
                  pw.Text(
                    "Página ${context.pageNumber} de ${context.pagesCount}",
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.Container(
                  width: 56.7,
                  height: 56.7,
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 14),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("AGROSOFT J&L",
                        style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF123F2C))),
                    pw.Text("INFORME DINÁMICO DE TRAMPEO FITOSANITARIO",
                        style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF1E6B4C))),
                    pw.SizedBox(height: 2),
                    pw.Text("Establecimiento: ${widget.nombreProductor}",
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("EMISIÓN",
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                  pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF1E6B4C)),
          pw.SizedBox(height: 8),

          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF9FAFB),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("TRAMPA: N° ${trampa['trampa_numero']}",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                pw.Text("PLAGA: ${trampa['tipo_trampa']}",
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text("CHACRA: ${trampa['chacra']} · CD: ${trampa['cuadro']}",
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text("VARIEDAD: ${trampa['variedad']}",
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          pw.Text("CURVA DE FLUCTUACIÓN POBLACIONAL (CAPTURAS / SEMANA)",
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF1E6B4C))),
          pw.SizedBox(height: 6),

          pw.Container(
            height: 90,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF9FAFB),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: datosGrafico.map((d) {
                final int total = d['total'] as int;
                final double alturaPct = (total / maxValor).clamp(0.05, 1.0);
                final bool alerta = total >= 5;

                return pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text("$total",
                        style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: alerta
                                ? const PdfColor.fromInt(0xFFB91C1C)
                                : const PdfColor.fromInt(0xFF1E6B4C))),
                    pw.SizedBox(height: 2),
                    pw.Container(
                      width: 14,
                      height: 52 * alturaPct,
                      decoration: pw.BoxDecoration(
                        color: alerta
                            ? const PdfColor.fromInt(0xFFDC2626)
                            : const PdfColor.fromInt(0xFF1E6B4C),
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(d['semana'].toString(),
                        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                  ],
                );
              }).toList(),
            ),
          ),
          pw.SizedBox(height: 14),

          pw.Text("RECUENTO SEMANAL DETALLADO",
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF1E6B4C))),
          pw.SizedBox(height: 6),

          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
            headerStyle: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E6B4C)),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headers: ['FECHA', 'SEMANA', 'MACHOS', 'H. VÍRGENES', 'H. GRÁVIDAS', 'TOTAL', 'ESTADO'],
            data: lecturas.map((l) {
              final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
              final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
              final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
              final int tot = m + hv + hg;
              final String fecha = l['created_at']?.toString().split('T').first ?? '';

              return [
                fecha,
                l['semana'] ?? '',
                m.toString(),
                hv.toString(),
                hg.toString(),
                tot.toString(),
                tot >= 5 ? 'SUPERA UMBRAL (!)' : 'NORMAL'
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 16),

          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Umbral de daño económico = 5 individuos por trampa / semana.",
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.red900)),
              pw.Text("Firma Responsable Fitosanitario: ___________________________",
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    final String nombreArchivo = 'Reporte_Trampa_${trampa['trampa_numero']}.pdf';

    if (!mounted) return;
    await exportarArchivoAgro(
      bytes: bytes,
      nombre: nombreArchivo,
      mime: AgroMime.pdf,
      texto: 'Curva Semanal Trampa #${trampa['trampa_numero']} - ${widget.nombreProductor}',
      context: context,
    );
  }

  Future<void> _exportarPdfMatrizOficial() async {
    if (_trampasFiltradas.isEmpty) {
      mostrarAgroSnack(context, 'No hay datos para exportar en este filtro',
          tipo: AgroSnackTipo.aviso);
      return;
    }
    if (_exportando) return;
    setState(() => _exportando = true);

    try {
      final pdf = pw.Document();
      final int anio = DateTime.now().year;

      pw.MemoryImage? logoImage;
      try {
        final logoBytes = await rootBundle.load('logo/logo_anibal.png');
        logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {
        try {
          final logoBytesFallback = await rootBundle.load('logo/logo.png');
          logoImage = pw.MemoryImage(logoBytesFallback.buffer.asUint8List());
        } catch (_) {}
      }

      final List<String> semanas = List<String>.from(_semanasDetectadas);
      if (semanas.isEmpty) semanas.add("Semana ${DateFormat('w').format(DateTime.now())}");

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(26),
          footer: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Divider(thickness: 0.8, color: PdfColors.grey300),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "Powered by AgroSoft J&L Soluciones Integrales · Chimpay, Río Negro",
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      "Página ${context.pageNumber} de ${context.pagesCount}",
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            );
          },
          build: (pw.Context context) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null) ...[
                  pw.Container(
                    width: 56.7,
                    height: 56.7,
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(width: 14),
                ],
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        "AGROSOFT J&L",
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF123F2C),
                        ),
                      ),
                      pw.Text(
                        "PLANILLA OFICIAL DE MONITOREO Y TRAMPEO SEMANAL · TEMPORADA $anio",
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF1E6B4C),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        "Establecimiento: ${widget.nombreProductor} · Chacra: $_chacraSeleccionada · Cuadro: $_cuadroSeleccionado",
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("FECHA EMISIÓN",
                        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                    pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1.2, color: const PdfColor.fromInt(0xFF1E6B4C)),
            pw.SizedBox(height: 8),

            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
              headerStyle: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1E6B4C),
              ),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              headers: [
                'TR.',
                'CHACRA',
                'CD.',
                'FILA',
                'PLAGA',
                'VARIEDAD',
                ...semanas.map((s) => s.replaceAll('Semana ', 'SEM ')),
              ],
              data: _trampasFiltradas.map((t) {
                final String codTr = t['cod_trampa'] ?? '';

                final valoresSemanas = semanas.map((sem) {
                  final lecturasSem = _lecturasTemporada.where(
                    (l) => l['cod_trampa'] == codTr && l['semana'] == sem,
                  );

                  if (lecturasSem.isEmpty) return "-";
                  final l = lecturasSem.first;
                  final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
                  final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
                  final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
                  final int total = m + hv + hg;
                  return total >= 5 ? "$total (!)" : "$total";
                }).toList();

                return [
                  t['trampa_numero'] ?? '',
                  t['chacra'] ?? '',
                  t['cuadro'] ?? '',
                  t['fila'] ?? '',
                  (t['tipo_trampa'] ?? '').toString().split(' ').first,
                  t['variedad'] ?? '',
                  ...valoresSemanas,
                ];
              }).toList(),
            ),
          ],
        ),
      );

      final Uint8List bytes = await pdf.save();
      final String nombreArchivo = 'Matriz_Trampas_$anio.pdf';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.pdf,
        texto: 'Matriz Semanal de Trampeo - ${widget.nombreProductor}',
        context: context,
      );
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'Error al generar el PDF: $e',
            tipo: AgroSnackTipo.error);
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ============================================================
  // CURVA / REPORTE POR SEMANAS DE UNA TRAMPA
  // ============================================================

  Future<void> _mostrarReporteSemanas(Map<String, dynamic> trampa) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> lecturas = await db.query(
      'lecturas_trampas',
      where: 'cod_trampa = ? AND semana != ?',
      whereArgs: [trampa['cod_trampa'], 'INSTALACION'],
      orderBy: 'created_at ASC',
    );

    if (!mounted) return;

    int acumulado = 0;
    int maxCaptura = 0;
    int semanasAlerta = 0;
    for (var l in lecturas) {
      final int tot = _totalLectura(l);
      acumulado += tot;
      if (tot > maxCaptura) maxCaptura = tot;
      if (tot >= _umbral) semanasAlerta++;
    }

    mostrarAgroPanel<void>(
      context: context,
      titulo: "Curva de capturas · TR #${trampa['trampa_numero']}",
      subtitulo: "${trampa['chacra']} · Cd. ${trampa['cuadro']} · ${trampa['tipo_trampa']}",
      icono: Icons.show_chart_rounded,
      maxWidth: 640,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AgroTag(texto: "Fila ${trampa['fila'] ?? '-'}", icono: Icons.straighten_rounded),
                AgroTag(texto: "${trampa['cultivo'] ?? '-'}", icono: Icons.eco_outlined),
                AgroTag(texto: "${trampa['variedad'] ?? '-'}", icono: Icons.local_florist_outlined),
                AgroTag(texto: "${lecturas.length} semanas", icono: Icons.date_range_rounded),
              ],
            ),
            const SizedBox(height: 14),
            AgroStatGrid(
              stats: [
                AgroStat(
                  label: 'Acumulado',
                  valor: '$acumulado ind.',
                  icono: Icons.functions_rounded,
                ),
                AgroStat(
                  label: 'Máximo semanal',
                  valor: '$maxCaptura ind.',
                  icono: Icons.trending_up_rounded,
                  color: _colorCaptura(maxCaptura),
                ),
                AgroStat(
                  label: 'Semanas ≥ umbral',
                  valor: '$semanasAlerta',
                  icono: Icons.warning_amber_rounded,
                  color: semanasAlerta > 0 ? AgroColors.danger : AgroColors.ok,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (lecturas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  "No hay recuentos semanales cargados aún.",
                  textAlign: TextAlign.center,
                  style: AgroText.secundario,
                ),
              )
            else ...[
              const AgroSectionHeader(
                titulo: 'Evolución y fluctuación poblacional',
                subtitulo: 'Capturas totales por semana · umbral 5 individuos',
                icono: Icons.bar_chart_rounded,
              ),
              const SizedBox(height: 12),
              AgroColumnChart(
                items: lecturas.map((l) {
                  final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
                  final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
                  final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
                  final String sem = (l['semana'] ?? 'S/D').toString();
                  return AgroBarItem(
                    label: sem.replaceAll('Semana ', 'S'),
                    valor: (m + hv + hg).toDouble(),
                    detalle: '$sem · M $m · HV $hv · HG $hg',
                  );
                }).toList(),
                umbral: _umbral.toDouble(),
                altura: 160,
              ),
              const SizedBox(height: 8),
              const AgroLeyenda(items: [
                AgroLeyendaItem('Bajo umbral', AgroColors.primario),
                AgroLeyendaItem('Supera umbral (≥ 5)', AgroColors.danger),
              ]),
              const SizedBox(height: 18),
              const Text('RECUENTO SEMANAL', style: AgroText.overline),
              const SizedBox(height: 8),
              ...lecturas.reversed.map(_filaSemana),
            ],
            const SizedBox(height: 12),
            AgroExportBar(
              info: 'Informe dinámico de trampeo de esta trampa.',
              onPdf: () => _generarPdfTrampa(trampa, lecturas),
            ),
            const SizedBox(height: 10),
            AgroButton(
              label: 'Cargar lectura',
              icono: Icons.add_rounded,
              expandido: true,
              onTap: () {
                Navigator.pop(ctx);
                _abrirModalLecturaDirecta(trampa);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _filaSemana(Map<String, dynamic> l) {
    final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
    final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
    final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
    final int total = m + hv + hg;
    final bool alertaUmbral = total >= _umbral;
    final String semNom = (l['semana'] ?? 'S/D').toString();
    final String? foto = l['url_evidencia']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: alertaUmbral ? AgroColors.dangerSoft : AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        border: Border.all(
          color: alertaUmbral
              ? AgroColors.danger.withOpacity(0.35)
              : AgroTheme.colorBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$semNom · ${_fmtFecha(l['created_at']?.toString())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.valor.copyWith(
                    fontSize: 13,
                    color: alertaUmbral ? AgroColors.danger : AgroTheme.colorText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Machos $m · H. vírgenes $hv · H. grávidas $hg',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.secundario.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AgroBadge(
            texto: '$total ind.',
            color: _colorCaptura(total),
            fondo: _fondoCaptura(total),
            grande: true,
          ),
          if (foto != null && foto.isNotEmpty) ...[
            const SizedBox(width: 6),
            AgroIconButton(
              icono: Icons.image_outlined,
              tooltip: 'Ver foto',
              size: 34,
              color: AgroColors.primario,
              onTap: () => _verFoto(foto),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // CARGA DE LECTURA (rápida, pensada para el celular)
  // ============================================================

  Future<void> _abrirModalLecturaDirecta(Map<String, dynamic> trampa) async {
    DateTime fechaSeleccionada = DateTime.now();
    final machosCtrl = TextEditingController(text: "0");
    final hembrasVirgCtrl = TextEditingController(text: "0");
    final hembrasGravCtrl = TextEditingController(text: "0");
    String? rutaFotoEvidencia;
    bool guardando = false;
    bool panelAbierto = true;

    await mostrarAgroPanel<void>(
      context: context,
      titulo: "Nueva lectura · Trampa #${trampa['trampa_numero']}",
      subtitulo: "${trampa['chacra']} · Cd. ${trampa['cuadro']} (${trampa['tipo_trampa']})",
      icono: Icons.bug_report_rounded,
      maxWidth: 560,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sbCtx, setModalState) {
            final int m = int.tryParse(machosCtrl.text) ?? 0;
            final int hv = int.tryParse(hembrasVirgCtrl.text) ?? 0;
            final int hg = int.tryParse(hembrasGravCtrl.text) ?? 0;
            final int total = m + hv + hg;
            final bool alertaUmbral = total >= 5;
            final String semanaCalc = _calcularSemanaIso(fechaSeleccionada);

            Future<void> guardar() async {
              setModalState(() => guardando = true);
              try {
                final db = await DatabaseHelper.instance.database;
                final ahora = DateTime.now();
                final String idReg = "LEC_${ahora.millisecondsSinceEpoch}";
                final String semanaCalculada = _calcularSemanaIso(fechaSeleccionada);

                await db.insert('lecturas_trampas', {
                  'id': trampa['cod_trampa'],
                  'id_reg': idReg,
                  'created_at': DateFormat('yyyy-MM-dd').format(fechaSeleccionada),
                  'establecimiento': widget.nombreProductor,
                  'sector': trampa['chacra'],
                  'cuadro': trampa['cuadro'],
                  'cultivo': trampa['cultivo'],
                  'variedad': trampa['variedad'],
                  'fila': trampa['fila'],
                  'ubicacion': trampa['ubicacion'],
                  'tipo_trampa': trampa['tipo_trampa'],
                  'cod_trampa': trampa['cod_trampa'],
                  'usuario': _userName,
                  'trampa_numero': trampa['trampa_numero'],
                  'semana': semanaCalculada,
                  'temporada': "${fechaSeleccionada.year}",
                  'macho': machosCtrl.text.trim(),
                  'hembra_virgen': hembrasVirgCtrl.text.trim(),
                  'hembra_gravida': hembrasGravCtrl.text.trim(),
                  'url_evidencia': rutaFotoEvidencia,
                  'cod_establecimiento': widget.codProductor,
                  'sincronizado': 0,
                });

                if (ctx.mounted) Navigator.pop(ctx);
                _cargarDatosCompletos();
                if (mounted) {
                  mostrarAgroSnack(
                    context,
                    alertaUmbral
                        ? 'Lectura registrada para $semanaCalculada · supera el umbral ($total ind.)'
                        : '¡Lectura registrada para $semanaCalculada!',
                    tipo: alertaUmbral ? AgroSnackTipo.aviso : AgroSnackTipo.ok,
                  );
                }
              } catch (e) {
                if (panelAbierto) setModalState(() => guardando = false);
                if (sbCtx.mounted) {
                  mostrarAgroSnack(sbCtx, 'No se pudo guardar la lectura: $e',
                      tipo: AgroSnackTipo.error);
                }
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fecha + semana calculada
                InkWell(
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sbCtx,
                      initialDate: fechaSeleccionada,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: 'Fecha de revisión',
                    );
                    if (picked != null && panelAbierto) {
                      setModalState(() => fechaSeleccionada = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: agroInputDecoration(
                      label: 'Fecha de revisión',
                      icono: Icons.calendar_today_rounded,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat('dd/MM/yyyy').format(fechaSeleccionada),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AgroTheme.colorText,
                            ),
                          ),
                        ),
                        AgroBadge(texto: semanaCalc, icono: Icons.date_range_rounded),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('CONTEO DE INDIVIDUOS', style: AgroText.overline),
                const SizedBox(height: 8),
                _StepperConteo(
                  titulo: 'Machos',
                  color: AgroColors.danger,
                  ctrl: machosCtrl,
                  onChanged: () => setModalState(() {}),
                ),
                _StepperConteo(
                  titulo: 'Hembras vírgenes',
                  color: Colors.purple.shade700,
                  ctrl: hembrasVirgCtrl,
                  onChanged: () => setModalState(() {}),
                ),
                _StepperConteo(
                  titulo: 'Hembras grávidas',
                  color: Colors.orange.shade800,
                  ctrl: hembrasGravCtrl,
                  onChanged: () => setModalState(() {}),
                ),
                const SizedBox(height: 6),
                _TileToggle(
                  icono: Icons.camera_alt_outlined,
                  iconoActivo: Icons.check_circle_rounded,
                  texto: 'Fotografiar placa',
                  textoActivo: 'Evidencia lista · tocar para repetir',
                  activo: rutaFotoEvidencia != null,
                  onTap: () async {
                    try {
                      final XFile? foto = await _picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 75,
                        maxWidth: 1280,
                      );
                      if (foto != null && panelAbierto) {
                        setModalState(() {
                          rutaFotoEvidencia = foto.path;
                        });
                      }
                    } catch (_) {}
                  },
                ),
                const SizedBox(height: 14),

                // Total en vivo con alerta de umbral
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: alertaUmbral ? AgroColors.dangerSoft : AgroColors.okSoft,
                    borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                    border: Border.all(
                      color: (alertaUmbral ? AgroColors.danger : AgroColors.ok)
                          .withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        alertaUmbral
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        color: alertaUmbral ? AgroColors.danger : AgroColors.ok,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alertaUmbral
                                  ? 'Supera el umbral económico'
                                  : 'Nivel tolerable',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: alertaUmbral ? AgroColors.danger : AgroColors.ok,
                              ),
                            ),
                            const Text('Umbral: 5 individuos por trampa / semana',
                                style: AgroText.secundario),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$total',
                            style: TextStyle(
                              fontSize: 26,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                              color: alertaUmbral ? AgroColors.danger : AgroColors.ok,
                            ),
                          ),
                          const Text('ind.', style: AgroText.label),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AgroButton(
                  label: 'Guardar lectura de trampa',
                  icono: Icons.save_rounded,
                  expandido: true,
                  cargando: guardando,
                  onTap: guardar,
                ),
              ],
            );
          },
        );
      },
    );

    panelAbierto = false;
    Future.delayed(const Duration(milliseconds: 500), () {
      machosCtrl.dispose();
      hembrasVirgCtrl.dispose();
      hembrasGravCtrl.dispose();
    });
  }

  // ============================================================
  // VISOR DE FOTO
  // ============================================================

  void _verFoto(String url) {
    // En web image_picker devuelve blob URLs: siempre Image.network.
    final bool esRemota = kIsWeb || url.startsWith('http') || url.startsWith('blob:');
    Widget error(BuildContext _, Object __, StackTrace? ___) => Container(
          width: 280,
          height: 200,
          color: AgroTheme.colorSurface,
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  size: 36, color: AgroTheme.colorTextSecondary),
              SizedBox(height: 8),
              Text('Foto no disponible en este dispositivo',
                  style: AgroText.secundario),
            ],
          ),
        );

    showDialog(
      context: context,
      builder: (dCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: esRemota
                    ? Image.network(url, fit: BoxFit.contain, errorBuilder: error)
                    : Image.file(File(url), fit: BoxFit.contain, errorBuilder: error),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(dCtx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UI PRINCIPAL
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: "Monitoreo de trampas",
        subtitulo: widget.nombreProductor,
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: 'Actualizar',
            onTap: _cargando
                ? null
                : () {
                    setState(() => _cargando = true);
                    _cargarDatosCompletos();
                  },
          ),
          const SizedBox(width: 8),
          AgroIconButton(
            icono: _exportando ? Icons.hourglass_top_rounded : Icons.file_download_rounded,
            tooltip: 'Exportar Excel / PDF',
            color: AgroColors.primario,
            onTap: (_cargando || _exportando || _trampasFiltradas.isEmpty)
                ? null
                : _abrirMenuExportar,
          ),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const AgroLoading(mensaje: 'Cargando trampas y lecturas…')
            : _trampasMaestras.isEmpty
                ? const AgroEmptyState(
                    icono: Icons.bug_report_outlined,
                    titulo: 'Sin trampas instaladas',
                    mensaje:
                        'Instalá las trampas desde "Ubicación de trampas" para empezar a cargar las lecturas semanales.',
                  )
                : RefreshIndicator(
                    color: AgroColors.primario,
                    onRefresh: _cargarDatosCompletos,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 16, bottom: 32),
                      children: [
                        AgroContent(child: _contenido()),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _contenido() {
    final filtradas = _trampasFiltradas;
    final leidasSemana = _codigosLeidosSemanaActual;
    final int leidas = filtradas
        .where((t) => leidasSemana.contains((t['cod_trampa'] ?? '').toString()))
        .length;
    final int pendientes = filtradas.length - leidas;
    final int enAlerta = _trampasEnAlerta;
    final String semanaActual = _semanaActual;

    final visibles = filtradas.where((t) {
      final cod = (t['cod_trampa'] ?? '').toString();
      if (_filtroEstado == 'pendientes') return !leidasSemana.contains(cod);
      if (_filtroEstado == 'alerta') {
        final tot = int.tryParse(t['ultimo_total']?.toString() ?? '0') ?? 0;
        return tot >= _umbral;
      }
      return true;
    }).toList();

    final double progreso = filtradas.isEmpty ? 0 : leidas / filtradas.length;
    final itemsSemanales = _itemsResumenSemanal(filtradas);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // KPIs
        AgroKpiGrid(
          kpis: [
            AgroKpiTile(
              label: 'Trampas activas',
              valor: '${filtradas.length}',
              icono: Icons.grid_view_rounded,
              detalle: 'en el filtro actual',
            ),
            AgroKpiTile(
              label: 'Leídas esta semana',
              valor: '$leidas',
              icono: Icons.fact_check_rounded,
              color: AgroColors.ok,
              detalle: semanaActual,
            ),
            AgroKpiTile(
              label: 'Pendientes',
              valor: '$pendientes',
              icono: Icons.pending_actions_rounded,
              color: pendientes > 0 ? AgroColors.warn : AgroColors.ok,
              detalle: 'esta semana',
              onTap: () => setState(() => _filtroEstado = 'pendientes'),
            ),
            AgroKpiTile(
              label: 'Sobre umbral',
              valor: '$enAlerta',
              icono: Icons.warning_amber_rounded,
              color: enAlerta > 0 ? AgroColors.danger : AgroColors.neutral,
              detalle: 'última lectura ≥ 5',
              onTap: () => setState(() => _filtroEstado = 'alerta'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Progreso semanal
        AgroCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.today_rounded, size: 18, color: AgroColors.primario),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recorrida de la $semanaActual',
                      style: AgroText.valor,
                    ),
                  ),
                  Text(
                    '$leidas de ${filtradas.length}',
                    style: AgroText.valor.copyWith(color: AgroColors.primario),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progreso.clamp(0.0, 1.0).toDouble(),
                  minHeight: 8,
                  color: pendientes == 0 ? AgroColors.ok : AgroColors.primario,
                  backgroundColor: AgroTheme.colorBorder,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pendientes == 0
                    ? 'Todas las trampas del filtro tienen lectura esta semana.'
                    : 'Faltan $pendientes trampas por leer esta semana.',
                style: AgroText.secundario,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Filtros
        AgroCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AgroSearchField(
                controller: _searchCtrl,
                hint: 'Buscar trampa, plaga o variedad…',
                onChanged: (v) => setState(() => _filtroTexto = v),
              ),
              if (_chacrasDisponibles.length > 1) ...[
                const SizedBox(height: 12),
                AgroChipSelector(
                  label: 'Chacra',
                  opciones: _chacrasDisponibles.where((c) => c != "TODAS").toList(),
                  valor: _chacraSeleccionada == "TODAS" ? null : _chacraSeleccionada,
                  textoTodos: 'Todas',
                  onChanged: (v) => setState(() {
                    _chacraSeleccionada = v ?? "TODAS";
                    _actualizarCuadrosDisponibles();
                  }),
                ),
              ],
              if (_cuadrosDisponibles.length > 1) ...[
                const SizedBox(height: 12),
                AgroChipSelector(
                  label: 'Cuadro',
                  opciones: _cuadrosDisponibles.where((c) => c != "TODOS").toList(),
                  valor: _cuadroSeleccionado == "TODOS" ? null : _cuadroSeleccionado,
                  onChanged: (v) => setState(() => _cuadroSeleccionado = v ?? "TODOS"),
                ),
              ],
              const SizedBox(height: 12),
              AgroSegmentedTabs(
                seleccionado: _filtroEstado,
                onChanged: (id) => setState(() => _filtroEstado = id),
                items: [
                  AgroTabItem(
                    id: 'todas',
                    label: 'Todas',
                    icono: Icons.list_rounded,
                    count: filtradas.length,
                  ),
                  AgroTabItem(
                    id: 'pendientes',
                    label: 'Pendientes',
                    icono: Icons.pending_actions_rounded,
                    count: pendientes,
                    color: AgroColors.warn,
                  ),
                  AgroTabItem(
                    id: 'alerta',
                    label: 'Umbral',
                    icono: Icons.warning_amber_rounded,
                    count: enAlerta,
                    color: AgroColors.danger,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Resumen semanal
        if (itemsSemanales.isNotEmpty) ...[
          AgroCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AgroSectionHeader(
                  titulo: 'Resumen semanal de la temporada',
                  subtitulo: 'Promedio de capturas por trampa leída · umbral 5',
                  icono: Icons.bar_chart_rounded,
                ),
                const SizedBox(height: 12),
                AgroColumnChart(
                  items: itemsSemanales,
                  umbral: _umbral.toDouble(),
                ),
                const SizedBox(height: 8),
                AgroLeyenda(items: _leyendaUmbral),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        // Listado
        AgroSectionHeader(
          titulo: 'Trampas',
          subtitulo: 'Tocá "Cargar lectura" para registrar el recuento semanal',
          icono: Icons.bug_report_rounded,
          trailing: AgroBadge(texto: '${visibles.length}'),
        ),
        const SizedBox(height: 12),
        if (visibles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'No se encontraron trampas con los filtros seleccionados.',
              textAlign: TextAlign.center,
              style: AgroText.secundario,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final int cols = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 720 ? 2 : 1);
              final double ancho =
                  ((c.maxWidth - (cols - 1) * 12) / cols).floorToDouble();
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: visibles
                    .map((t) => SizedBox(
                          width: ancho,
                          child: _tarjetaTrampa(
                            t,
                            leidasSemana.contains((t['cod_trampa'] ?? '').toString()),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _tarjetaTrampa(Map<String, dynamic> t, bool leidaEstaSemana) {
    final String? ultimaSemana = t['ultima_semana']?.toString();
    final bool tieneLecturas = ultimaSemana != null && ultimaSemana.isNotEmpty;
    final int totalInd = int.tryParse(t['ultimo_total']?.toString() ?? '0') ?? 0;
    final bool enAlerta = totalInd >= _umbral;
    final String? fotoUrl = t['ultima_foto']?.toString();

    return AgroCard(
      accentColor: enAlerta ? AgroColors.danger : null,
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
                  color: enAlerta ? AgroColors.danger : AgroColors.primarioSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${t['trampa_numero'] ?? '-'}",
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: enAlerta ? Colors.white : AgroColors.primario,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (t['tipo_trampa'] ?? 'Plaga').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.tituloCard,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Ch. ${t['chacra'] ?? '-'} · Cd. ${t['cuadro'] ?? '-'} · Fila ${t['fila'] ?? '-'}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.secundario,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              tieneLecturas
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AgroBadge(
                          texto: '$totalInd ind.',
                          color: _colorCaptura(totalInd),
                          fondo: _fondoCaptura(totalInd),
                          icono: enAlerta ? Icons.warning_amber_rounded : null,
                          grande: true,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          (ultimaSemana ?? '').replaceAll('Semana ', 'Sem. '),
                          style: AgroText.label.copyWith(fontSize: 10.5),
                        ),
                      ],
                    )
                  : const AgroBadge(
                      texto: 'Sin lecturas',
                      color: AgroColors.neutral,
                      fondo: AgroColors.neutralSoft,
                    ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if ((t['variedad'] ?? '').toString().isNotEmpty)
                AgroTag(
                  texto: (t['variedad'] ?? '').toString(),
                  icono: Icons.local_florist_outlined,
                ),
              if (tieneLecturas)
                AgroTag(
                  texto: 'Últ.: ${_fmtFecha(t['ultima_fecha']?.toString())}',
                  icono: Icons.event_rounded,
                ),
              leidaEstaSemana
                  ? const AgroBadge(
                      texto: 'Leída esta semana',
                      color: AgroColors.ok,
                      fondo: AgroColors.okSoft,
                      icono: Icons.check_circle_rounded,
                    )
                  : const AgroBadge(
                      texto: 'Pendiente',
                      color: AgroColors.warn,
                      fondo: AgroColors.warnSoft,
                      icono: Icons.schedule_rounded,
                    ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AgroButton(
                  label: 'Cargar lectura',
                  icono: Icons.add_rounded,
                  expandido: true,
                  compacto: true,
                  onTap: () => _abrirModalLecturaDirecta(t),
                ),
              ),
              const SizedBox(width: 8),
              AgroButton(
                label: 'Curva',
                icono: Icons.show_chart_rounded,
                tipo: AgroButtonTipo.secundario,
                compacto: true,
                onTap: () => _mostrarReporteSemanas(t),
              ),
              if (fotoUrl != null && fotoUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                AgroIconButton(
                  icono: Icons.image_outlined,
                  tooltip: 'Ver última foto',
                  size: 38,
                  color: AgroColors.primario,
                  onTap: () => _verFoto(fotoUrl),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// STEPPER DE CONTEO (+ / −) — carga rápida en el campo
// ============================================================

class _StepperConteo extends StatelessWidget {
  final String titulo;
  final Color color;
  final TextEditingController ctrl;
  final VoidCallback onChanged;

  const _StepperConteo({
    required this.titulo,
    required this.color,
    required this.ctrl,
    required this.onChanged,
  });

  int _valor() => int.tryParse(ctrl.text.trim()) ?? 0;

  void _set(int v) {
    ctrl.text = '${v < 0 ? 0 : v}';
    onChanged();
  }

  Widget _boton(IconData icono, VoidCallback onTap, {bool relleno = false}) {
    return Material(
      color: relleno ? color : AgroTheme.colorSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: relleno ? color : AgroTheme.colorBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icono, size: 24, color: relleno ? Colors.white : color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        border: Border.all(color: AgroTheme.colorBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titulo,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AgroTheme.colorText,
              ),
            ),
          ),
          _boton(Icons.remove_rounded, () => _set(_valor() - 1)),
          SizedBox(
            width: 60,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AgroTheme.colorText,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onTap: () {
                // Selecciona todo para sobrescribir rápido.
                ctrl.selection =
                    TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
              },
              onChanged: (_) => onChanged(),
            ),
          ),
          _boton(Icons.add_rounded, () => _set(_valor() + 1), relleno: true),
        ],
      ),
    );
  }
}

// ============================================================
// TILE TOGGLE (foto)
// ============================================================

class _TileToggle extends StatelessWidget {
  final IconData icono;
  final IconData iconoActivo;
  final String texto;
  final String textoActivo;
  final bool activo;
  final VoidCallback? onTap;

  const _TileToggle({
    required this.icono,
    required this.iconoActivo,
    required this.texto,
    required this.textoActivo,
    required this.activo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = activo ? AgroColors.ok : AgroTheme.colorTextSecondary;
    return Material(
      color: activo ? AgroColors.okSoft : AgroTheme.colorBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        side: BorderSide(
          color: activo ? AgroColors.ok.withOpacity(0.5) : AgroTheme.colorBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(activo ? iconoActivo : icono, size: 20, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    activo ? textoActivo : texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: activo ? AgroColors.ok : AgroTheme.colorText,
                    ),
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
