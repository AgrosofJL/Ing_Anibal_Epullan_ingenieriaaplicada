import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

class FenologiaScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const FenologiaScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<FenologiaScreen> createState() => _FenologiaScreenState();
}

class _FenologiaScreenState extends State<FenologiaScreen> {
  bool _cargando = true;
  String _userName = "Operario";

  List<Map<String, dynamic>> _gruposVariedadMuestreadas = [];
  List<Map<String, dynamic>> _lecturasAnioActual = [];
  List<Map<String, dynamic>> _cuartelesInventarioParaCarga = [];

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('userName') ?? "Operario";
    await _cargarDatosDashboard();
  }

  String _normalizarCultivoCanonica(String entrada) {
    if (entrada.trim().isEmpty) return '';
    final clean = entrada.trim().toUpperCase();

    if (clean.contains('CEREZ')) return 'Cereza';
    if (clean.contains('CIRUEL')) return 'Ciruela';
    if (clean.contains('DURAZN')) return 'Duraznero';
    if (clean.contains('MANZAN')) return 'Manzano';
    if (clean.contains('PERA') || clean.contains('PERAL')) return 'Pera';
    if (clean.contains('NOGAL') || clean.contains('NUEZ')) return 'Nogal';
    if (clean.contains('VID') || clean.contains('UVA')) return 'Vid';
    if (clean.contains('PELON')) return 'Pelon';
    if (clean.contains('DZ') || clean.contains('PL')) return 'Dz y Pl';

    return clean[0] + clean.substring(1).toLowerCase();
  }

  // 💡 Semáforo de avance por cuartiles (cada 25%)
  Color _getColorSemaforo(double valor) {
    if (valor <= 0) return Colors.grey.shade400;
    if (valor < 25) return const Color(0xFF60A5FA); // Azul inicio
    if (valor < 50) return const Color(0xFF34D399); // Verde medio
    if (valor < 75) return const Color(0xFFFBBF24); // Amarillo / Ámbar
    return const Color(0xFFEF4444); // Rojo / Pleno estado
  }

  IconData _getIconoCultivo(String cultivo) {
    final c = cultivo.toLowerCase();
    if (c.contains('manzan') || c.contains('pera')) return Icons.apple_rounded;
    if (c.contains('cerez') || c.contains('ciruel')) return Icons.nature_rounded;
    if (c.contains('vid') || c.contains('uva')) return Icons.grain_rounded;
    return Icons.eco_rounded;
  }

  // ==========================================================================
  // CARGA Y AGRUPACIÓN DE LECTURAS POR VARIEDAD
  // ==========================================================================
  Future<void> _cargarDatosDashboard() async {
    setState(() => _cargando = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final int anioActual = DateTime.now().year;
      final String anioPrefijo = "$anioActual%";

      final lecturasRes = await db.query(
        'lecturas_fenologia',
        where: 'cod_establecimiento = ? AND (fecha LIKE ? OR created_at LIKE ?)',
        whereArgs: [widget.codProductor, anioPrefijo, anioPrefijo],
        orderBy: 'fecha DESC, created_at DESC',
      );
      _lecturasAnioActual = List<Map<String, dynamic>>.from(lecturasRes);

      final invRes = await db.query(
        'inventario_plantacion',
        where: 'cod_productor = ?',
        whereArgs: [widget.codProductor],
        orderBy: 'chacra ASC, CAST(cuadro AS INTEGER) ASC',
      );
      _cuartelesInventarioParaCarga = List<Map<String, dynamic>>.from(invRes);

      final Map<String, Map<String, dynamic>> mapaGrupos = {};

      for (var l in _lecturasAnioActual) {
        final variedad = (l['variedad'] ?? 'S/D').toString().trim();
        final cultivo = (l['cultivo'] ?? 'Frutal').toString().trim();
        final key = "${cultivo}__$variedad";

        if (!mapaGrupos.containsKey(key)) {
          mapaGrupos[key] = {
            'cultivo': cultivo,
            'variedad': variedad,
            'cuadros': <String>{},
            'lecturas': <Map<String, dynamic>>[],
            'promedios_estados': <String, double>{},
          };
        }

        final Set<String> cuadros = mapaGrupos[key]!['cuadros'] as Set<String>;
        if (l['cuadro'] != null && l['cuadro'].toString().isNotEmpty) {
          cuadros.add(l['cuadro'].toString());
        }

        (mapaGrupos[key]!['lecturas'] as List<Map<String, dynamic>>).add(l);
      }

      // Cálculo de promedios para cada estado fenológico
      for (var key in mapaGrupos.keys) {
        final List<Map<String, dynamic>> listaLec =
            mapaGrupos[key]!['lecturas'] as List<Map<String, dynamic>>;

        final Map<String, List<double>> acum = {};
        for (var l in listaLec) {
          final String cod = (l['estado_codigo'] ?? '').toString();
          final String desc = (l['descripcion_estado'] ?? '').toString();
          final String label = cod.isNotEmpty ? "$cod - $desc" : desc;
          final double valor = double.tryParse(l['valor_lectura']?.toString() ?? '0') ?? 0.0;

          if (!acum.containsKey(label)) {
            acum[label] = [];
          }
          acum[label]!.add(valor);
        }

        final Map<String, double> promedios = {};
        acum.forEach((estado, valores) {
          final suma = valores.reduce((a, b) => a + b);
          promedios[estado] = suma / valores.length;
        });

        mapaGrupos[key]!['promedios_estados'] = promedios;
      }

      _gruposVariedadMuestreadas = mapaGrupos.values.toList();
    } catch (e) {
      debugPrint("Error cargando fenología: $e");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ==========================================================================
  // 📊 REPORTE EN EXCEL: VARIEDAD ARRIBA + MATRIZ DE ESTADOS CON "DD/MM VALOR%"
  // ==========================================================================
  Future<void> _exportarExcelCurvaFenologica() async {
    if (_gruposVariedadMuestreadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros fenológicos para exportar.')),
      );
      return;
    }

    final excel = xl.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) excel.delete(defaultSheet);

    final int anio = DateTime.now().year;

    for (var g in _gruposVariedadMuestreadas) {
      final String variedad = g['variedad'] ?? 'Variedad';
      final String cultivo = g['cultivo'] ?? 'Frutal';
      final String sheetName = "$cultivo-$variedad".replaceAll('/', '-').replaceAll('\\', '-');
      final xl.Sheet sheet = excel[sheetName.length > 30 ? sheetName.substring(0, 30) : sheetName];

      final List<Map<String, dynamic>> lecturas =
          (g['lecturas'] as List).cast<Map<String, dynamic>>();

      // 1. Título y datos de cabecera
      sheet.appendRow([
        xl.TextCellValue("AGROSOFT J&L - REPORTE DE EVOLUCIÓN FENOLÓGICA"),
      ]);
      sheet.appendRow([
        xl.TextCellValue("ESTABLECIMIENTO:"),
        xl.TextCellValue(widget.nombreProductor),
        xl.TextCellValue("TEMPORADA:"),
        xl.IntCellValue(anio),
      ]);
      sheet.appendRow([
        xl.TextCellValue("VARIEDAD:"),
        xl.TextCellValue("$variedad ($cultivo)"),
        xl.TextCellValue("CUADROS:"),
        xl.TextCellValue((g['cuadros'] as Set<String>).join(', ')),
      ]);
      sheet.appendRow([]); // Fila libre

      // 2. Extraer fechas únicas ordenadas y estados fenológicos únicos
      final Set<String> fechasSet = {};
      final Set<String> estadosSet = {};

      for (var l in lecturas) {
        final f = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
        if (f.isNotEmpty) fechasSet.add(f);

        final cod = (l['estado_codigo'] ?? '').toString().trim();
        final desc = (l['descripcion_estado'] ?? '').toString().trim();
        final label = cod.isNotEmpty ? "$cod ($desc)" : desc;
        if (label.isNotEmpty) estadosSet.add(label);
      }

      final List<String> fechasOrdenadas = fechasSet.toList()..sort();
      final List<String> estadosOrdenados = estadosSet.toList()..sort();

      // Formato de fechas para cabecera: "DD/MM"
      final List<String> fechasHeaderFormato = fechasOrdenadas.map((f) {
        try {
          final dt = DateTime.parse(f);
          return DateFormat('dd/MM').format(dt);
        } catch (_) {
          return f;
        }
      }).toList();

      // 3. Fila de Encabezados de la Matriz: [ESTADO FENOLÓGICO, DD/MM, DD/MM...]
      sheet.appendRow([
        xl.TextCellValue("ESTADOS FENOLÓGICOS"),
        ...fechasHeaderFormato.map((f) => xl.TextCellValue(f)),
      ]);

      // 4. Renglones por cada Estado con su formato: "dd/mm valor%"
      for (var estado in estadosOrdenados) {
        final List<xl.CellValue> filaValores = [xl.TextCellValue(estado)];

        for (int i = 0; i < fechasOrdenadas.length; i++) {
          final fechaRaw = fechasOrdenadas[i];
          final fechaFmt = fechasHeaderFormato[i];

          // Filtrar lecturas de este estado en esta fecha
          final matches = lecturas.where((l) {
            final f = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
            final cod = (l['estado_codigo'] ?? '').toString().trim();
            final desc = (l['descripcion_estado'] ?? '').toString().trim();
            final label = cod.isNotEmpty ? "$cod ($desc)" : desc;
            return f == fechaRaw && label == estado;
          });

          if (matches.isNotEmpty) {
            double suma = 0.0;
            for (var m in matches) {
              suma += double.tryParse(m['valor_lectura']?.toString() ?? '0') ?? 0.0;
            }
            final double prom = suma / matches.length;
            // 💡 Formato exacto solicitado: "dd/mm valor%"
            filaValores.add(xl.TextCellValue("$fechaFmt ${prom.toStringAsFixed(0)}%"));
          } else {
            filaValores.add(xl.TextCellValue("-"));
          }
        }

        sheet.appendRow(filaValores);
      }

      sheet.appendRow([]);
    }

    final bytes = excel.save();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Curva_Fenologia_${widget.nombreProductor}_$anio.xlsx');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      text: 'Planilla Curva Fenológica - ${widget.nombreProductor}',
    );
  }

  // ==========================================================================
  // MODAL DETALLE DE MUESTREOS DE LA VARIEDAD
  // ==========================================================================
  void _mostrarDetalleVariedad(Map<String, dynamic> grupo) {
    final String cultivo = grupo['cultivo'] ?? '';
    final String variedad = grupo['variedad'] ?? '';
    final List<Map<String, dynamic>> lecturas =
        (grupo['lecturas'] as List).cast<Map<String, dynamic>>();

    final Map<String, List<Map<String, dynamic>>> muestreosAgrupados = {};
    for (var l in lecturas) {
      final fechaLimpia = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
      final key = "${fechaLimpia}__${l['cuadro']}__${l['fila']}__${l['planta_numero']}";
      if (!muestreosAgrupados.containsKey(key)) {
        muestreosAgrupados[key] = [];
      }
      muestreosAgrupados[key]!.add(l);
    }

    final listaMuestreos = muestreosAgrupados.values.toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
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
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(_getIconoCultivo(cultivo), color: AgroTheme.colorAccentDark, size: 24),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "$cultivo · $variedad",
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16, color: AgroTheme.colorText),
                          ),
                          Text(
                            "Temporada ${DateTime.now().year} · ${listaMuestreos.length} muestreos",
                            style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.table_view_rounded, color: Color(0xFF1E6B4C)),
                        tooltip: "Exportar Excel Curva",
                        onPressed: _exportarExcelCurvaFenologica,
                      ),
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf_outlined, color: AgroTheme.colorAccentDark),
                        tooltip: "Exportar PDF",
                        onPressed: () => _exportarPdfIndividualVariedad(grupo, listaMuestreos),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(color: AgroTheme.colorBorder),
              const SizedBox(height: 8),

              Expanded(
                child: ListView.separated(
                  itemCount: listaMuestreos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final items = listaMuestreos[idx];
                    final cab = items.first;
                    final fechaFormato =
                        (cab['fecha'] ?? cab['created_at'] ?? '').toString().split('T').first;
                    final String? fotoUrl = items
                        .map((e) => e['url_evidencia'])
                        .firstWhere((u) => u != null && u.toString().isNotEmpty, orElse: () => null);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AgroTheme.colorBg,
                        borderRadius: BorderRadius.circular(12),
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
                                      color: AgroTheme.colorAccentDark,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "Cd. ${cab['cuadro']}",
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    fechaFormato,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Fila ${cab['fila']} · Pl. ${cab['planta_numero']}",
                                    style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary),
                                  ),
                                ],
                              ),
                              if (fotoUrl != null && fotoUrl.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.image_outlined, size: 18, color: AgroTheme.colorAccentDark),
                                  onPressed: () => _verFoto(fotoUrl),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Desglose de estados con badges semafóricos
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: items.map((sub) {
                              final double val =
                                  double.tryParse(sub['valor_lectura']?.toString() ?? '0') ?? 0.0;
                              final Color colorSemaforo = _getColorSemaforo(val);
                              final String cod = sub['estado_codigo'] ?? '';

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colorSemaforo.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: colorSemaforo.withOpacity(0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(color: colorSemaforo, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      "$cod: ${val.toStringAsFixed(0)}%",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: colorSemaforo.withOpacity(0.95),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================================
  // MODAL DE REGISTRO NUEVO
  // ==========================================================================
  void _abrirModalNuevoMuestreo() {
    if (_cuartelesInventarioParaCarga.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AgroTheme.colorDanger,
          content: Text('No hay parcelas en el inventario para asociar la lectura.'),
        ),
      );
      return;
    }

    String claveCuartel(Map<String, dynamic> c) =>
        "${c['chacra']}__${c['cuadro']}__${c['variedad']}";

    Map<String, dynamic> cuartelSeleccionado = _cuartelesInventarioParaCarga.first;
    String claveSeleccionada = claveCuartel(cuartelSeleccionado);

    final fechaCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final filaCtrl = TextEditingController(text: "1");
    final plantaCtrl = TextEditingController(text: "1");

    File? fotoEvidencia;
    String latitud = "";
    String longitud = "";
    bool capturandoGps = false;

    List<Map<String, dynamic>> estadosParametros = [];
    final Map<String, TextEditingController> controladoresPorcentajes = {};

    void limpiarControladores() {
      for (var c in controladoresPorcentajes.values) {
        c.dispose();
      }
      controladoresPorcentajes.clear();
    }

    Future<void> cargarParametros(String cultivoRaw, StateSetter setModalState) async {
      try {
        final db = await DatabaseHelper.instance.database;
        final String cultivoCanonico = _normalizarCultivoCanonica(cultivoRaw);

        final res = await db.rawQuery('''
          SELECT * FROM fenologia_parametros
          WHERE LOWER(TRIM(cultivo)) = LOWER(?)
             OR LOWER(cultivo) LIKE '%' || LOWER(?) || '%'
             OR LOWER(?) LIKE '%' || LOWER(cultivo) || '%'
          ORDER BY estado_codigo ASC
        ''', [cultivoCanonico, cultivoCanonico, cultivoCanonico]);

        List<Map<String, dynamic>> listaMutada = List<Map<String, dynamic>>.from(res);

        if (listaMutada.isEmpty) {
          final resGen = await db.rawQuery('''
            SELECT * FROM fenologia_parametros
            WHERE cultivo IS NULL OR TRIM(cultivo) = ''
            ORDER BY estado_codigo ASC
          ''');
          listaMutada = List<Map<String, dynamic>>.from(resGen);
        }

        if (listaMutada.isEmpty) {
          final resAll = await db.query('fenologia_parametros', orderBy: 'estado_codigo ASC');
          listaMutada = List<Map<String, dynamic>>.from(resAll);
        }

        limpiarControladores();
        for (var e in listaMutada) {
          final String cod = e['id']?.toString() ?? e['estado_codigo']?.toString() ?? '';
          controladoresPorcentajes[cod] = TextEditingController(text: "");
        }

        setModalState(() {
          estadosParametros = listaMutada;
        });
      } catch (e) {
        debugPrint("Error al cargar parámetros: $e");
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (estadosParametros.isEmpty && controladoresPorcentajes.isEmpty) {
              cargarParametros(cuartelSeleccionado['cultivo']?.toString() ?? '', setModalState);
            }

            double totalPct = 0.0;
            for (var c in controladoresPorcentajes.values) {
              totalPct += double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;
            }
            final bool esCien = (totalPct - 100.0).abs() < 0.1;

            return Container(
              height: MediaQuery.of(context).size.height * 0.90,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                top: 18,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Nuevo Muestreo de Campo",
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          limpiarControladores();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const Divider(color: AgroTheme.colorBorder),
                  const SizedBox(height: 8),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            value: claveSeleccionada,
                            isExpanded: true,
                            decoration: _inputDecoration("Cuadro y Variedad"),
                            items: _cuartelesInventarioParaCarga.map((c) {
                              final clave = claveCuartel(c);
                              return DropdownMenuItem<String>(
                                value: clave,
                                child: Text(
                                  "${c['chacra']} · Cuadro ${c['cuadro']} (${c['variedad']} - ${c['cultivo']})",
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                ),
                              );
                            }).toList(),
                            onChanged: (nuevaClave) {
                              if (nuevaClave != null) {
                                setModalState(() {
                                  claveSeleccionada = nuevaClave;
                                  cuartelSeleccionado = _cuartelesInventarioParaCarga.firstWhere(
                                    (c) => claveCuartel(c) == nuevaClave,
                                  );
                                });
                                cargarParametros(
                                  cuartelSeleccionado['cultivo']?.toString() ?? '',
                                  setModalState,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(controller: fechaCtrl, decoration: _inputDecoration("Fecha")),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                    controller: filaCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration("Fila")),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                    controller: plantaCtrl, keyboardType: TextInputType.number, decoration: _inputDecoration("Planta")),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
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
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: fotoEvidencia != null ? AgroTheme.colorAccentSoft : AgroTheme.colorBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: fotoEvidencia != null ? AgroTheme.colorAccent : AgroTheme.colorBorder),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.camera_alt_outlined,
                                            size: 16,
                                            color: fotoEvidencia != null ? AgroTheme.colorAccentDark : Colors.grey),
                                        const SizedBox(width: 6),
                                        Text(fotoEvidencia != null ? "Foto Lista ✓" : "Fotografiar",
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: fotoEvidencia != null ? AgroTheme.colorAccentDark : AgroTheme.colorText)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: capturandoGps
                                      ? null
                                      : () async {
                                          setModalState(() => capturandoGps = true);
                                          try {
                                            LocationPermission perm = await Geolocator.checkPermission();
                                            if (perm == LocationPermission.denied) {
                                              perm = await Geolocator.requestPermission();
                                            }
                                            final pos = await Geolocator.getCurrentPosition();
                                            setModalState(() {
                                              latitud = pos.latitude.toStringAsFixed(6);
                                              longitud = pos.longitude.toStringAsFixed(6);
                                            });
                                          } catch (_) {}
                                          setModalState(() => capturandoGps = false);
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: latitud.isNotEmpty ? AgroTheme.colorAccentSoft : AgroTheme.colorBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: latitud.isNotEmpty ? AgroTheme.colorAccent : AgroTheme.colorBorder),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.location_on_outlined,
                                            size: 16,
                                            color: latitud.isNotEmpty ? AgroTheme.colorAccentDark : Colors.grey),
                                        const SizedBox(width: 6),
                                        Text(latitud.isNotEmpty ? "GPS OK" : "Fijar GPS",
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: latitud.isNotEmpty ? AgroTheme.colorAccentDark : AgroTheme.colorText)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Estados (${cuartelSeleccionado['cultivo'] ?? 'General'})",
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AgroTheme.colorText),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: esCien ? AgroTheme.colorAccentSoft : AgroTheme.colorGoldSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  "Total: ${totalPct.toStringAsFixed(0)}%",
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: esCien ? AgroTheme.colorAccentDark : const Color(0xFF8A6A1E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: estadosParametros.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, idx) {
                              final param = estadosParametros[idx];
                              final String cod = param['id']?.toString() ?? param['estado_codigo']?.toString() ?? '';
                              final ctrl = controladoresPorcentajes[cod];
                              final double valActual =
                                  double.tryParse(ctrl?.text.replaceAll(',', '.') ?? '0') ?? 0.0;
                              final Color colorSemaforo = _getColorSemaforo(valActual);

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AgroTheme.colorBorder),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: colorSemaforo,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AgroTheme.colorSurface,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AgroTheme.colorBorder),
                                      ),
                                      child: Text(
                                        param['estado_codigo'] ?? 'S/C',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(param['descripcion'] ?? 'Estado',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                    SizedBox(
                                      width: 60,
                                      child: TextFormField(
                                        controller: ctrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: "0",
                                          suffixText: "%",
                                          isDense: true,
                                          filled: true,
                                          fillColor: AgroTheme.colorSurface,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                        ),
                                        onChanged: (_) => setModalState(() {}),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: SoftButton(
                      onTap: () async {
                        final List<Map<String, dynamic>> estadosConValor = [];

                        for (var e in estadosParametros) {
                          final String cod = e['id']?.toString() ?? e['estado_codigo']?.toString() ?? '';
                          final ctrl = controladoresPorcentajes[cod];
                          if (ctrl != null && ctrl.text.trim().isNotEmpty) {
                            final double pct = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0.0;
                            if (pct > 0) {
                              estadosConValor.add({'parametro': e, 'valor': pct});
                            }
                          }
                        }

                        if (estadosConValor.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AgroTheme.colorDanger,
                              content: Text('Ingresá el porcentaje en al menos un estado fenológico'),
                            ),
                          );
                          return;
                        }

                        final db = await DatabaseHelper.instance.database;
                        final ahora = DateTime.now();
                        final fechaIso = fechaCtrl.text.trim();
                        int sigId = await DatabaseHelper.instance.obtenerSiguienteId('lecturas_fenologia', 'id');
                        final rutaFoto = fotoEvidencia?.path;

                        Batch batch = db.batch();
                        int creados = 0;

                        for (int i = 0; i < estadosConValor.length; i++) {
                          final item = estadosConValor[i];
                          final param = item['parametro'] as Map<String, dynamic>;
                          final double porcentaje = item['valor'] as double;
                          final String idReg = "FEN_${ahora.millisecondsSinceEpoch}_$i";

                          batch.insert('lecturas_fenologia', {
                            'id': sigId + i,
                            'id_reg': idReg,
                            'created_at': ahora.toIso8601String(),
                            'establecimiento': widget.nombreProductor,
                            'sector': cuartelSeleccionado['chacra'] ?? '',
                            'cuadro': cuartelSeleccionado['cuadro'] ?? '',
                            'fila': filaCtrl.text.trim(),
                            'variedad': cuartelSeleccionado['variedad'] ?? '',
                            'planta_numero': plantaCtrl.text.trim(),
                            'cultivo': cuartelSeleccionado['cultivo'] ?? '',
                            'estado_codigo': param['estado_codigo'] ?? '',
                            'descripcion_estado': param['descripcion'] ?? '',
                            'temp_aire_api': null,
                            'temp_critica_min': param['temp_critica_min'],
                            'temp_critica_max': param['temp_critica_max'],
                            'url_evidencia': rutaFoto,
                            'latitud': latitud,
                            'longitud': longitud,
                            'usuario': _userName,
                            'fecha': fechaIso,
                            'valor_lectura': porcentaje.round(),
                            'cod_establecimiento': widget.codProductor,
                            'sincronizado': 0,
                          });
                          creados++;
                        }

                        await batch.commit(noResult: true);
                        limpiarControladores();

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _cargarDatosDashboard();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AgroTheme.colorAccent,
                              content: Text('¡Se guardaron $creados registros fenológicos!'),
                            ),
                          );
                        }
                      },
                      child: const Center(
                        child: Text("Guardar Muestreo Fenológico",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
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

 Future<void> _exportarPdfIndividualVariedad(
    Map<String, dynamic> grupo, List<List<Map<String, dynamic>>> muestreos) async {
  final pdf = pw.Document();
  final String anio = DateTime.now().year.toString();

  // 1. Carga segura del logo (nunca detiene la ejecución si da 404 en Web)
  pw.MemoryImage? logoImage;
  try {
    final ByteData bytes = await rootBundle.load('logo/logo_anibal.png');
    logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {
    try {
      final ByteData bytesFallback = await rootBundle.load('logo/logo.png');
      logoImage = pw.MemoryImage(bytesFallback.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }
  }

  // 2. Sanitización de cuadros
  final rawCuadros = grupo['cuadros'];
  final String textoCuadros = rawCuadros is Iterable
      ? rawCuadros.map((e) => e.toString()).join(', ')
      : (rawCuadros?.toString() ?? 'S/D');

  // Colores corporativos AgroSoft
  const colorVerdeOscuro = PdfColor.fromInt(0xFF134E32);
  const colorVerdeSecundario = PdfColor.fromInt(0xFF1E6B4C);
  const colorFondoGris = PdfColor.fromInt(0xFFF9FAFB);
  const colorBorde = PdfColor.fromInt(0xFFE5E7EB);

  // Función interna para calcular la semana del año
  int obtenerSemanaDelAnio(DateTime date) {
    final comienzoAnio = DateTime(date.year, 1, 1);
    final diferenciaDias = date.difference(comienzoAnio).inDays;
    return ((diferenciaDias + comienzoAnio.weekday) / 7).ceil();
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      header: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // 💡 LOGO EN LA ESQUINA SUPERIOR IZQUIERDA
                if (logoImage != null) ...[
                  pw.Container(
                    width: 46,
                    height: 46,
                    child: pw.Image(logoImage),
                  ),
                  pw.SizedBox(width: 14),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "INGENIERÍA APLICADA · MONITOREO AGRONÓMICO",
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: colorVerdeSecundario,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        "REPORTE OFICIAL DE ESTADOS FENOLÓGICOS",
                        style: pw.TextStyle(
                          fontSize: 14.5,
                          fontWeight: pw.FontWeight.bold,
                          color: colorVerdeOscuro,
                        ),
                      ),
                      pw.Text(
                        "Establecimiento: ${widget.nombreProductor.toUpperCase()}",
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: colorFondoGris,
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(color: colorBorde, width: 0.8),
                      ),
                      child: pw.Text(
                        "TEMPORADA $anio",
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: colorVerdeOscuro,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      "Emisión: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}",
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1.2, color: colorVerdeSecundario),
            pw.SizedBox(height: 10),
          ],
        );
      },
      footer: (pw.Context context) {
        // 💡 PIE DE PÁGINA CORPORATIVO AGROSOFT J&L
        return pw.Column(
          children: [
            pw.Divider(thickness: 0.7, color: colorBorde),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      "AgroSoft J&L",
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: colorVerdeOscuro),
                    ),
                    pw.Text(
                      " · Sistema Integral de Gestión Agrícola & Trazabilidad Fitosanitaria",
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Text(
                  "Página ${context.pageNumber} de ${context.pagesCount}",
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                "Documento técnico agronómico válido para auditorías de inocuidad y control de evolución fenológica.",
                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey500),
              ),
            ),
          ],
        );
      },
      build: (pw.Context context) => [
        // Ficha resumida del cuartel/variedad
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: colorFondoGris,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: colorBorde, width: 0.8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("ESPECIE / CULTIVO", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  pw.Text("${grupo['cultivo'] ?? 'FRUTALES'}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("VARIEDAD BOTÁNICA", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  pw.Text("${grupo['variedad'] ?? 'S/D'}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerdeOscuro)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("CUADROS AUDITADOS", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  pw.Text(textoCuadros, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("TOTAL MUESTREOS", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  pw.Text("${muestreos.length} estaciones", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              "HISTORIAL CRONOLÓGICO Y DINÁMICA DE ESTADOS (%)",
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: colorVerdeOscuro,
                letterSpacing: 0.3,
              ),
            ),
            pw.Text(
              "* Valores expresados en proporción porcentual de yemas/flores/frutos observados",
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // 💡 TABLA TÉCNICA CON FECHA, SEMANA Y PORCENTAJES DESGLOSADOS
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: colorBorde, width: 0.6),
          headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: colorVerdeSecundario),
          headerHeight: 22,
          cellHeight: 20,
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellAlignment: pw.Alignment.centerLeft,
          headers: const [
            'FECHA',
            'SEM.',
            'CUADRO',
            'ESTACIÓN / PLANTA',
            'ESTADO DOMINANTE',
            'DISTRIBUCIÓN DE ESTADOS (%)',
          ],
          columnWidths: const {
            0: pw.FixedColumnWidth(55),
            1: pw.FixedColumnWidth(30),
            2: pw.FixedColumnWidth(48),
            3: pw.FixedColumnWidth(75),
            4: pw.FixedColumnWidth(95),
            5: pw.FlexColumnWidth(2),
          },
          data: muestreos.map((m) {
            if (m.isEmpty) return ['', '', '', '', '', ''];
            final cab = m.first;

            // Formateo de fecha y semana
            final rawFecha = (cab['fecha'] ?? cab['created_at'] ?? '').toString();
            final DateTime? dt = DateTime.tryParse(rawFecha);
            final String fechaStr = dt != null
                ? "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}"
                : rawFecha.split('T').first;
            final String semStr = dt != null ? "S.${obtenerSemanaDelAnio(dt)}" : "S/-";

            // Localizar el estado dominante (mayor porcentaje)
            Map<String, dynamic>? dominante;
            double maxPorcentaje = -1.0;
            for (var sub in m) {
              final val = double.tryParse((sub['valor_lectura'] ?? '0').toString()) ?? 0.0;
              if (val > maxPorcentaje) {
                maxPorcentaje = val;
                dominante = sub;
              }
            }

            final String estadoDomTxt = dominante != null
                ? "${dominante['estado_codigo']} (${maxPorcentaje.toInt()}%)"
                : "S/D";

            // Detalle concatenado con porcentajes
            final String desgloseTotal = m.map((sub) {
              final double p = double.tryParse((sub['valor_lectura'] ?? '0').toString()) ?? 0.0;
              return "${sub['estado_codigo']} : ${p.toStringAsFixed(0)}%";
            }).join("  |  ");

            return [
              fechaStr,
              semStr,
              "Cuadro ${cab['cuadro'] ?? '-'}",
              "Fila ${cab['fila'] ?? '-'} · Pl. ${cab['planta_numero'] ?? '-'}",
              estadoDomTxt,
              desgloseTotal,
            ];
          }).toList(),
        ),

        pw.SizedBox(height: 16),
        // Cuadro de notas / observaciones de campo
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: colorFondoGris,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: colorBorde, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "CRITERIO TÉCNICO DE EVOLUCIÓN:",
                style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: colorVerdeOscuro),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                "El seguimiento fenológico semanal permite sincronizar las aplicaciones de inductores de cuaja, raleo químico y monitoreo de carpocapsa/grafolita en función de la susceptibilidad tisular del cultivo.",
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // Compartir PDF según plataforma (Web o Móvil)
  await _compartirArchivoPdf(pdf, "Fenologia_${grupo['variedad'] ?? 'Variedad'}_$anio.pdf");
}

  pw.Widget _buildCabeceraPdf(String subtitulo) {
    return pw.Column(

      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("AGROSOFT J&L",
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF123F2C))),
                pw.Text("SISTEMA DE GESTIÓN FITOSANITARIA Y FENOLOGÍA",
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
            pw.Text(widget.nombreProductor, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF1E6B4C)),
        pw.SizedBox(height: 4),
        pw.Text(subtitulo, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
      ],
    );
  }

  Future<void> _compartirArchivoPdf(pw.Document pdf, String nombreArchivo) async {
  final Uint8List bytes = await pdf.save();

  if (kIsWeb) {
    await Printing.sharePdf(
      bytes: bytes,
      filename: nombreArchivo,
    );
  } else {
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          name: nombreArchivo,
          mimeType: 'application/pdf',
        ),
      ],
      text: 'Reporte Oficial de Fenología - ${widget.nombreProductor}',
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final int anioActual = DateTime.now().year;

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
            Text("Fenología $anioActual",
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText)),
            Text(widget.nombreProductor,
                style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          // 💡 Botón Excel de Curva y Botón PDF
          IconButton(
            icon: const Icon(Icons.table_view_rounded, color: Color(0xFF1E6B4C)),
            tooltip: "Exportar Excel Curva Fenológica",
            onPressed: _exportarExcelCurvaFenologica,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: AgroTheme.colorAccent))
            : _gruposVariedadMuestreadas.isEmpty
                ? const Center(
                    child: Text("No hay registros fenológicos en la temporada actual.",
                        style: TextStyle(color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w600)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
                    itemCount: _gruposVariedadMuestreadas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) {
                      final g = _gruposVariedadMuestreadas[idx];
                      final String cultivo = g['cultivo'] ?? '';
                      final Set<String> cuadros = g['cuadros'] as Set<String>;
                      final promedios = (g['promedios_estados'] as Map<String, double>?) ?? {};
                      final int totalReg = (g['lecturas'] as List).length;

                      return InkWell(
                        onTap: () => _mostrarDetalleVariedad(g),
                        borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AgroTheme.colorSurface,
                            borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                            border: Border.all(color: AgroTheme.colorBorder),
                            boxShadow: const [
                              BoxShadow(color: Color(0x04141E18), blurRadius: 8, offset: Offset(0, 2)),
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
                                      Icon(_getIconoCultivo(cultivo), color: AgroTheme.colorAccentDark, size: 22),
                                      const SizedBox(width: 8),
                                      Text(
                                        "${g['variedad']}",
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AgroTheme.colorText),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AgroTheme.colorAccentSoft,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "$totalReg muestreos",
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AgroTheme.colorAccentDark),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Cultivo: $cultivo  ·  Cuadros: ${cuadros.join(', ')}",
                                style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 12),

                              // Semáforos y porcentajes de estados promedios
                              if (promedios.isNotEmpty)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: promedios.entries.map((e) {
                                    final double val = e.value;
                                    final Color colorSemaforo = _getColorSemaforo(val);

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colorSemaforo.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: colorSemaforo.withOpacity(0.5)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(color: colorSemaforo, shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            "${e.key}: ${val.toStringAsFixed(0)}%",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: colorSemaforo.withOpacity(0.95),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: SoftButton(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        borderRadius: 28,
        onTap: _abrirModalNuevoMuestreo,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add_chart_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text("Nueva Lectura Fenológica",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12.5, color: AgroTheme.colorTextSecondary),
      filled: true,
      fillColor: AgroTheme.colorBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AgroTheme.radiusMd), borderSide: BorderSide.none),
    );
  }
}