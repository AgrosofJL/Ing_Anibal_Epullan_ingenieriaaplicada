import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xl hide Border;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

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
  bool _cargando = true;
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

  Future<void> _exportarExcelMatrizTrampas() async {
    if (_trampasFiltradas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar en el filtro activo.')),
      );
      return;
    }

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

      final fileBytes = excel.save();
      if (fileBytes == null) return;

      final Uint8List bytes = Uint8List.fromList(fileBytes);
      final String nombreArchivo =
          'Monitoreo_Trampas_${widget.nombreProductor.replaceAll(' ', '_')}.xlsx';

      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
      } else if (Platform.isWindows) {
        final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final filePath = "${dir.path}/$nombreArchivo";
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        await OpenFilex.open(filePath);
      } else {
        await Share.shareXFiles(
          [
            XFile.fromData(
              bytes,
              name: nombreArchivo,
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          text: 'Matriz de Trampas - ${widget.nombreProductor}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFC62828), content: Text("Error al exportar: $e")),
      );
    }
  }

  void _mostrarReporteSemanas(Map<String, dynamic> trampa) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> lecturas = await db.query(
      'lecturas_trampas',
      where: 'cod_trampa = ? AND semana != ?',
      whereArgs: [trampa['cod_trampa'], 'INSTALACION'],
      orderBy: 'created_at ASC',
    );

    if (!mounted) return;

    int maxCaptura = 1;
    for (var l in lecturas) {
      final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
      final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
      final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
      final int tot = m + hv + hg;
      if (tot > maxCaptura) maxCaptura = tot;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: AgroTheme.colorSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Curva de Capturas · TR #${trampa['trampa_numero']}",
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AgroTheme.colorText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "${trampa['chacra']} · Cd. ${trampa['cuadro']} · ${trampa['tipo_trampa']}",
                          style: const TextStyle(
                              fontSize: 11.5, color: AgroTheme.colorTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf_outlined,
                            color: Color(0xFF1E6B4C), size: 22),
                        tooltip: "Exportar Reporte PDF",
                        onPressed: () => _generarPdfTrampa(trampa, lecturas),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(color: AgroTheme.colorBorder, height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildTagBadge("Fila: ${trampa['fila']}"),
                  _buildTagBadge("Cultivo: ${trampa['cultivo']}"),
                  _buildTagBadge("Variedad: ${trampa['variedad']}"),
                  _buildTagBadge("${lecturas.length} semanas"),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: lecturas.isEmpty
                    ? const Center(
                        child: Text(
                          "No hay recuentos semanales cargados aún.",
                          style: TextStyle(
                              color: AgroTheme.colorTextSecondary, fontSize: 13),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Evolución y Fluctuación Poblacional:",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AgroTheme.colorTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: lecturas.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (context, i) {
                                final l = lecturas[i];
                                final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
                                final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
                                final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
                                final int total = m + hv + hg;
                                final bool alertaUmbral = total >= 5;
                                final String semNom =
                                    (l['semana'] ?? 'S/D').toString().replaceAll('Semana ', 'Sem ');
                                final String? foto = l['url_evidencia']?.toString();
                                final double ratio = (total / maxCaptura).clamp(0.08, 1.0);

                                return Container(
                                  width: 95,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: alertaUmbral
                                        ? const Color(0xFFFEF2F2)
                                        : AgroTheme.colorBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: alertaUmbral
                                          ? const Color(0xFFC62828).withOpacity(0.4)
                                          : AgroTheme.colorBorder,
                                      width: alertaUmbral ? 1.2 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        semNom,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          color: alertaUmbral
                                              ? const Color(0xFFC62828)
                                              : AgroTheme.colorText,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: FractionallySizedBox(
                                            heightFactor: ratio,
                                            child: Container(
                                              width: 22,
                                              decoration: BoxDecoration(
                                                color: alertaUmbral
                                                    ? const Color(0xFFC62828)
                                                    : const Color(0xFF1E6B4C),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  "$total",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text("M: $m · H: ${hv + hg}",
                                          style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w600,
                                              color: AgroTheme.colorTextSecondary)),
                                      const SizedBox(height: 4),
                                      if (foto != null && foto.isNotEmpty)
                                        InkWell(
                                          onTap: () => _verFoto(foto),
                                          child: const Icon(Icons.camera_alt_rounded,
                                              size: 14, color: Color(0xFF1E6B4C)),
                                        )
                                      else
                                        const SizedBox(height: 14),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _abrirModalLecturaDirecta(Map<String, dynamic> trampa) {
    DateTime fechaSeleccionada = DateTime.now();
    final fechaCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(fechaSeleccionada));
    final machosCtrl = TextEditingController(text: "0");
    final hembrasVirgCtrl = TextEditingController(text: "0");
    final hembrasGravCtrl = TextEditingController(text: "0");
    File? fotoEvidencia;

    String calcularSemanaIso(DateTime f) {
      final dayOfYear = int.parse(DateFormat("D").format(f));
      final int w = ((dayOfYear - f.weekday + 10) / 7).floor();
      return "Semana ${w.toString().padLeft(2, '0')}";
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final int m = int.tryParse(machosCtrl.text) ?? 0;
            final int hv = int.tryParse(hembrasVirgCtrl.text) ?? 0;
            final int hg = int.tryParse(hembrasGravCtrl.text) ?? 0;
            final int total = m + hv + hg;
            final bool alertaUmbral = total >= 5;

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                top: 18,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Nueva Lectura · Trampa #${trampa['trampa_numero']}",
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16.5,
                                color: AgroTheme.colorText),
                          ),
                          Text(
                            "${trampa['chacra']} · Cd. ${trampa['cuadro']} (${trampa['tipo_trampa']})",
                            style: const TextStyle(
                                fontSize: 11.5, color: AgroTheme.colorTextSecondary),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(color: AgroTheme.colorBorder),
                  const SizedBox(height: 10),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: fechaCtrl,
                            readOnly: true,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: fechaSeleccionada,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  fechaSeleccionada = picked;
                                  fechaCtrl.text =
                                      DateFormat('yyyy-MM-dd').format(picked);
                                });
                              }
                            },
                            decoration: InputDecoration(
                              labelText: "Fecha de Revisión",
                              filled: true,
                              fillColor: AgroTheme.colorBg,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AgroTheme.radiusMd),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: const Icon(
                                Icons.calendar_today_rounded,
                                size: 18,
                                color: Color(0xFF1E6B4C),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          const Text(
                            "Conteo de Individuos:",
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AgroTheme.colorText),
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: _buildContador(
                                  "Machos",
                                  machosCtrl,
                                  const Color(0xFFC62828),
                                  () => setModalState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildContador(
                                  "H. Vírgenes",
                                  hembrasVirgCtrl,
                                  Colors.purple.shade700,
                                  () => setModalState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildContador(
                                  "H. Grávidas",
                                  hembrasGravCtrl,
                                  Colors.orange.shade800,
                                  () => setModalState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          InkWell(
                            onTap: () async {
                              try {
                                final XFile? foto = await _picker.pickImage(
                                  source: ImageSource.camera,
                                  imageQuality: 75,
                                  maxWidth: 1280,
                                );
                                if (foto != null) {
                                  setModalState(() {
                                    fotoEvidencia = File(foto.path);
                                  });
                                }
                              } catch (_) {}
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: fotoEvidencia != null
                                    ? const Color(0xFFE8F5E9)
                                    : AgroTheme.colorBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: fotoEvidencia != null
                                      ? const Color(0xFFA5D6A7)
                                      : AgroTheme.colorBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt_outlined,
                                    size: 18,
                                    color: fotoEvidencia != null
                                        ? const Color(0xFF1E6B4C)
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    fotoEvidencia != null
                                        ? "Evidencia Lista ✓"
                                        : "Fotografiar Placa",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: fotoEvidencia != null
                                          ? const Color(0xFF1E6B4C)
                                          : AgroTheme.colorText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: alertaUmbral
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: alertaUmbral
                                      ? const Color(0xFFEF9A9A)
                                      : const Color(0xFFA5D6A7)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  alertaUmbral
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline_rounded,
                                  color: alertaUmbral
                                      ? const Color(0xFFC62828)
                                      : const Color(0xFF1E6B4C),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  alertaUmbral
                                      ? "Total: $total ind. (Supera Umbral Económico)"
                                      : "Total: $total ind. (Nivel Tolerable)",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: alertaUmbral
                                        ? const Color(0xFFC62828)
                                        : const Color(0xFF1E6B4C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: SoftButton(
                      onTap: () async {
                        final db = await DatabaseHelper.instance.database;
                        final ahora = DateTime.now();
                        final String idReg = "LEC_${ahora.millisecondsSinceEpoch}";
                        final String semanaCalculada =
                            calcularSemanaIso(fechaSeleccionada);

                        await db.insert('lecturas_trampas', {
                          'id': trampa['cod_trampa'],
                          'id_reg': idReg,
                          'created_at': fechaCtrl.text.trim(),
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
                          'url_evidencia': fotoEvidencia?.path,
                          'cod_establecimiento': widget.codProductor,
                          'sincronizado': 0,
                        });

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _cargarDatosCompletos();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF1E6B4C),
                              content: Text('¡Lectura registrada para $semanaCalculada!'),
                            ),
                          );
                        }
                      },
                      child: const Center(
                        child: Text(
                          "Guardar Lectura de Trampa",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContador(String titulo, TextEditingController ctrl, Color color,
      VoidCallback onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AgroTheme.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            decoration:
                const InputDecoration(isDense: true, border: InputBorder.none),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }

  void _verFoto(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: url.startsWith('http')
              ? Image.network(url, fit: BoxFit.cover)
              : Image.file(File(url), fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _buildTagBadge(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgroTheme.colorBorder),
      ),
      child: Text(texto,
          style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AgroTheme.colorTextSecondary)),
    );
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

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
    } else if (Platform.isWindows) {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/$nombreArchivo";
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      await OpenFilex.open(filePath);
    } else {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: nombreArchivo, mimeType: 'application/pdf')],
        text: 'Curva Semanal Trampa #${trampa['trampa_numero']} - ${widget.nombreProductor}',
      );
    }
  }

  Future<void> _exportarPdfMatrizOficial() async {
    if (_trampasFiltradas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar en este filtro')),
      );
      return;
    }

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

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
    } else if (Platform.isWindows) {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/$nombreArchivo";
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      await OpenFilex.open(filePath);
    } else {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: nombreArchivo, mimeType: 'application/pdf')],
        text: 'Matriz Semanal de Trampeo - ${widget.nombreProductor}',
      );
    }
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
              "Monitoreo de Trampas",
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText),
            ),
            Text(
              widget.nombreProductor,
              style: const TextStyle(
                  fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_rounded, color: Color(0xFF2E7D32)),
            tooltip: "Exportar a Excel",
            onPressed: _trampasFiltradas.isEmpty ? null : _exportarExcelMatrizTrampas,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF1E6B4C)),
            tooltip: "Exportar PDF Matriz",
            onPressed: _exportarPdfMatrizOficial,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // KPI Bar: Total vs Alertas de Daño Económico
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              color: AgroTheme.colorSurface,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AgroTheme.colorBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AgroTheme.colorBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.grid_view_rounded, size: 16, color: Color(0xFF1E6B4C)),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Instaladas",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgroTheme.colorTextSecondary)),
                              Text("${_trampasFiltradas.length}",
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AgroTheme.colorText)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _trampasEnAlerta > 0 ? const Color(0xFFFEF2F2) : AgroTheme.colorBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _trampasEnAlerta > 0 ? const Color(0xFFEF9A9A) : AgroTheme.colorBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: _trampasEnAlerta > 0 ? const Color(0xFFC62828) : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("En Alerta (>=5)",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _trampasEnAlerta > 0 ? const Color(0xFFC62828) : AgroTheme.colorTextSecondary,
                                  )),
                              Text("$_trampasEnAlerta",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: _trampasEnAlerta > 0 ? const Color(0xFFC62828) : AgroTheme.colorText,
                                  )),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Filtros de Chacra y Cuadro
            Container(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              color: AgroTheme.colorSurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _chacrasDisponibles.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final ch = _chacrasDisponibles[i];
                        final isSel = _chacraSeleccionada == ch;
                        return ChoiceChip(
                          label: Text(ch == "TODAS" ? "Todas las Chacras" : "Ch. $ch"),
                          selected: isSel,
                          selectedColor: const Color(0xFF1E6B4C),
                          labelStyle: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                            color: isSel ? Colors.white : AgroTheme.colorText,
                          ),
                          backgroundColor: AgroTheme.colorBg,
                          onSelected: (sel) {
                            if (sel) {
                              setState(() {
                                _chacraSeleccionada = ch;
                                _actualizarCuadrosDisponibles();
                              });
                            }
                          },
                        );
                      },
                    ),
                  ),
                  if (_cuadrosDisponibles.length > 1) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 30,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _cuadrosDisponibles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          final cu = _cuadrosDisponibles[i];
                          final isSel = _cuadroSeleccionado == cu;
                          return ChoiceChip(
                            label: Text(cu == "TODOS" ? "Todos los Cuadros" : "Cuadro $cu"),
                            selected: isSel,
                            selectedColor: const Color(0xFF8A6A1E),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                              color: isSel ? Colors.white : AgroTheme.colorTextSecondary,
                            ),
                            backgroundColor: AgroTheme.colorBg,
                            onSelected: (sel) {
                              if (sel) setState(() => _cuadroSeleccionado = cu);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Buscador Rápido
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border: Border.all(color: AgroTheme.colorBorder),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _filtroTexto = v),
                  style: const TextStyle(color: AgroTheme.colorText, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: "Buscar trampa, plaga o variedad...",
                    hintStyle: TextStyle(color: AgroTheme.colorTextSecondary, fontSize: 12),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: AgroTheme.colorTextSecondary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),

            // Encabezado Fijo de Tabla
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F8E9),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text("ESTACIÓN / TRAMPA",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text("UBICACIÓN / CUADRO",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text("ÚLTIMO RECUENTO",
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                    ),
                  ],
                ),
              ),
            ),

            // Listado de Trampas
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B4C)))
                  : _trampasFiltradas.isEmpty
                      ? const Center(child: Text("No se encontraron trampas en este sector."))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
                          itemCount: _trampasFiltradas.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final t = _trampasFiltradas[idx];
                            final ultimaSemana = t['ultima_semana'] ?? 'Sin lecturas';
                            final int totalInd = int.tryParse(t['ultimo_total']?.toString() ?? '0') ?? 0;
                            final bool enAlerta = totalInd >= 5;
                            final String? fotoUrl = t['ultima_foto']?.toString();

                            return InkWell(
                              onTap: () => _mostrarReporteSemanas(t),
                              borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorSurface,
                                  borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                                  border: Border.all(
                                    color: enAlerta ? const Color(0xFFEF9A9A) : AgroTheme.colorBorder,
                                    width: enAlerta ? 1.2 : 1.0,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x04141E18), blurRadius: 6, offset: Offset(0, 2)),
                                  ],
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
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: enAlerta ? const Color(0xFFC62828) : const Color(0xFFE8F5E9),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                "TR #${t['trampa_numero']}",
                                                style: TextStyle(
                                                  color: enAlerta ? Colors.white : const Color(0xFF2E7D32),
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              t['tipo_trampa'] ?? 'Plaga',
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            if (fotoUrl != null && fotoUrl.isNotEmpty)
                                              IconButton(
                                                icon: const Icon(Icons.image_outlined, size: 20, color: Color(0xFF1E6B4C)),
                                                onPressed: () => _verFoto(fotoUrl),
                                              ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: enAlerta ? const Color(0xFFFFEBEE) : AgroTheme.colorBg,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: enAlerta ? const Color(0xFFEF9A9A) : AgroTheme.colorBorder,
                                                ),
                                              ),
                                              child: Text(
                                                "$ultimaSemana: $totalInd ind.",
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: enAlerta ? const Color(0xFFC62828) : AgroTheme.colorTextSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: AgroTheme.colorBg,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("Chacra ${t['chacra']} · Cd. ${t['cuadro']}",
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                                          Text("Fila ${t['fila']} · ${t['variedad']}",
                                              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: SizedBox(
                                            height: 36,
                                            child: SoftButton(
                                              borderRadius: 8,
                                              onTap: () => _abrirModalLecturaDirecta(t),
                                              child: const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.edit_note_rounded, color: Colors.white, size: 16),
                                                  SizedBox(width: 5),
                                                  Text("Registrar",
                                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: SizedBox(
                                            height: 36,
                                            child: SoftButton(
                                              isSecondary: true,
                                              borderRadius: 8,
                                              onTap: () => _mostrarReporteSemanas(t),
                                              child: const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.show_chart_rounded, color: Color(0xFF1E6B4C), size: 15),
                                                  SizedBox(width: 4),
                                                  Text("Curva",
                                                      style: TextStyle(color: Color(0xFF1E6B4C), fontWeight: FontWeight.w800, fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}