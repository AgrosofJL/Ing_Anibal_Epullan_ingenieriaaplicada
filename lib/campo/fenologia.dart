// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl hide Border;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/agro_reportes_ui.dart';
import '../widgets/agro_ui.dart';

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
  bool _exportandoExcel = false;
  String _userName = "Operario";

  List<Map<String, dynamic>> _gruposVariedadMuestreadas = [];
  List<Map<String, dynamic>> _lecturasAnioActual = [];
  List<Map<String, dynamic>> _cuartelesInventarioParaCarga = [];

  /// Filtro de cultivo en pantalla (null = todos).
  String? _filtroCultivo;

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

  // ============================================================
  // HELPERS
  // ============================================================

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

  Color _getColorSemaforo(double valor) {
    if (valor <= 0) return Colors.grey.shade400;
    if (valor < 25) return const Color(0xFF60A5FA);
    if (valor < 50) return const Color(0xFF34D399);
    if (valor < 75) return const Color(0xFFFBBF24);
    return const Color(0xFFEF4444);
  }

  /// Versión oscurecida del color del semáforo para textos legibles.
  Color _colorTextoSemaforo(double valor) =>
      Color.lerp(_getColorSemaforo(valor), Colors.black, 0.35)!;

  IconData _getIconoCultivo(String cultivo) {
    final c = cultivo.toLowerCase();
    if (c.contains('manzan') || c.contains('pera')) return Icons.apple_rounded;
    if (c.contains('cerez') || c.contains('ciruel')) return Icons.nature_rounded;
    if (c.contains('vid') || c.contains('uva')) return Icons.grain_rounded;
    return Icons.eco_rounded;
  }

  List<AgroLeyendaItem> get _leyendaSemaforo => [
        AgroLeyendaItem('0 %', Colors.grey.shade400),
        const AgroLeyendaItem('1–24 %', Color(0xFF60A5FA)),
        const AgroLeyendaItem('25–49 %', Color(0xFF34D399)),
        const AgroLeyendaItem('50–74 %', Color(0xFFFBBF24)),
        const AgroLeyendaItem('≥ 75 %', Color(0xFFEF4444)),
      ];

  String _fechaLimpia(Map<String, dynamic> l) =>
      (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;

  String _fmtFecha(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.isEmpty ? '—' : raw;
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  int _semanaDelAnio(DateTime date) {
    final comienzoAnio = DateTime(date.year, 1, 1);
    final diferenciaDias = date.difference(comienzoAnio).inDays;
    return ((diferenciaDias + comienzoAnio.weekday) / 7).ceil();
  }

  /// Agrupa los registros de una variedad por muestreo
  /// (fecha + cuadro + fila + planta), igual que el detalle y el PDF.
  List<List<Map<String, dynamic>>> _agruparMuestreos(
      List<Map<String, dynamic>> lecturas) {
    final Map<String, List<Map<String, dynamic>>> muestreosAgrupados = {};
    for (var l in lecturas) {
      final fechaLimpia = _fechaLimpia(l);
      final key =
          "${fechaLimpia}__${l['cuadro']}__${l['fila']}__${l['planta_numero']}";
      if (!muestreosAgrupados.containsKey(key)) {
        muestreosAgrupados[key] = [];
      }
      muestreosAgrupados[key]!.add(l);
    }
    return muestreosAgrupados.values.toList();
  }

  String _ultimaFecha(List<Map<String, dynamic>> lecturas) {
    String max = '';
    for (var l in lecturas) {
      final f = _fechaLimpia(l);
      if (f.compareTo(max) > 0) max = f;
    }
    return max;
  }

  // ============================================================
  // CARGA DE DATOS
  // ============================================================

  Future<void> _cargarDatosDashboard({bool silencioso = false}) async {
    if (!silencioso && mounted) setState(() => _cargando = true);
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

      for (var key in mapaGrupos.keys) {
        final List<Map<String, dynamic>> listaLec =
            mapaGrupos[key]!['lecturas'] as List<Map<String, dynamic>>;

        final Map<String, List<double>> acum = {};
        for (var l in listaLec) {
          final String cod = (l['estado_codigo'] ?? '').toString();
          final String desc = (l['descripcion_estado'] ?? '').toString();
          final String label = cod.isNotEmpty ? "$cod - $desc" : desc;
          final double valor =
              double.tryParse(l['valor_lectura']?.toString() ?? '0') ?? 0.0;

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

  // ============================================================
  // EXPORTACIÓN EXCEL (curva fenológica)
  // ============================================================

  Future<void> _exportarExcelCurvaFenologica() async {
    if (_gruposVariedadMuestreadas.isEmpty) {
      mostrarAgroSnack(context, 'No hay registros fenológicos para exportar.',
          tipo: AgroSnackTipo.aviso);
      return;
    }
    if (_exportandoExcel) return;
    setState(() => _exportandoExcel = true);

    try {
      final excel = xl.Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) excel.delete(defaultSheet);

      final int anio = DateTime.now().year;

      int obtenerSemanaDelAnio(DateTime date) {
        final comienzoAnio = DateTime(date.year, 1, 1);
        final diferenciaDias = date.difference(comienzoAnio).inDays;
        return ((diferenciaDias + comienzoAnio.weekday) / 7).ceil();
      }

      final List<List<xl.CellValue>> filasDatosCrudos = [];

      for (var g in _gruposVariedadMuestreadas) {
        final String variedad = (g['variedad'] ?? 'Variedad').toString();
        final String cultivo = (g['cultivo'] ?? 'Frutal').toString();

        String rawSheetName = "$cultivo-$variedad"
            .replaceAll('/', '-')
            .replaceAll('\\', '-')
            .replaceAll('?', '')
            .replaceAll('*', '')
            .replaceAll(':', '');
        if (rawSheetName.length > 30) rawSheetName = rawSheetName.substring(0, 30);

        final xl.Sheet sheet = excel[rawSheetName];
        final List<Map<String, dynamic>> lecturas =
            (g['lecturas'] as List).cast<Map<String, dynamic>>();

        final rawCuadros = g['cuadros'];
        final String textoCuadros = rawCuadros is Iterable
            ? rawCuadros.map((e) => e.toString()).join(', ')
            : (rawCuadros?.toString() ?? 'S/D');

        sheet.appendRow([xl.TextCellValue("AGROSOFT J&L · SISTEMA DE GESTIÓN FITOSANITARIA Y FENOLOGÍA")]);
        sheet.appendRow([xl.TextCellValue("INFORME DE EVOLUCIÓN FENOLÓGICA Y CURVAS DE DESARROLLO")]);
        sheet.appendRow([]);
        sheet.appendRow([
          xl.TextCellValue("ESTABLECIMIENTO:"),
          xl.TextCellValue(widget.nombreProductor.toUpperCase()),
          xl.TextCellValue("TEMPORADA:"),
          xl.IntCellValue(anio),
          xl.TextCellValue("FECHA EMISIÓN:"),
          xl.TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
        ]);
        sheet.appendRow([
          xl.TextCellValue("ESPECIE:"),
          xl.TextCellValue(cultivo.toUpperCase()),
          xl.TextCellValue("VARIEDAD:"),
          xl.TextCellValue(variedad.toUpperCase()),
          xl.TextCellValue("CUADROS:"),
          xl.TextCellValue(textoCuadros),
        ]);
        sheet.appendRow([]);

        final Set<String> fechasSet = {};
        final Set<String> estadosSet = {};

        for (var l in lecturas) {
          final f = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
          if (f.isNotEmpty) fechasSet.add(f);

          final cod = (l['estado_codigo'] ?? '').toString().trim();
          final desc = (l['descripcion_estado'] ?? '').toString().trim();
          final label = cod.isNotEmpty ? "$cod - $desc" : desc;
          if (label.isNotEmpty) estadosSet.add(label);

          DateTime? dtRaw = DateTime.tryParse(f);
          filasDatosCrudos.add([
            xl.TextCellValue((l['id_reg'] ?? l['id'] ?? '').toString()),
            xl.TextCellValue(f),
            xl.TextCellValue(dtRaw != null ? "Semana ${obtenerSemanaDelAnio(dtRaw)}" : "S/-"),
            xl.TextCellValue(widget.nombreProductor),
            xl.TextCellValue((l['sector'] ?? l['chacra'] ?? 'Principal').toString()),
            xl.TextCellValue((l['cuadro'] ?? '').toString()),
            xl.TextCellValue((l['fila'] ?? '-').toString()),
            xl.TextCellValue((l['planta_numero'] ?? '-').toString()),
            xl.TextCellValue(cultivo),
            xl.TextCellValue(variedad),
            xl.TextCellValue(cod),
            xl.TextCellValue(desc),
            xl.DoubleCellValue(double.tryParse((l['valor_lectura'] ?? '0').toString()) ?? 0.0),
            xl.TextCellValue((l['observaciones'] ?? '').toString()),
            xl.TextCellValue((l['url_evidencia'] ?? '').toString()),
          ]);
        }

        final List<String> fechasOrdenadas = fechasSet.toList()..sort();
        final List<String> estadosOrdenados = estadosSet.toList()..sort();

        final List<xl.CellValue> filaSemanas = [xl.TextCellValue("SEMANA FENOLÓGICA")];
        final List<xl.CellValue> filaFechas = [xl.TextCellValue("ESTADO / FECHA")];

        for (var f in fechasOrdenadas) {
          DateTime? dt = DateTime.tryParse(f);
          if (dt != null) {
            filaSemanas.add(xl.TextCellValue("SEM ${obtenerSemanaDelAnio(dt)}"));
            filaFechas.add(xl.TextCellValue(DateFormat('dd/MM').format(dt)));
          } else {
            filaSemanas.add(xl.TextCellValue("SEM -"));
            filaFechas.add(xl.TextCellValue(f));
          }
        }

        sheet.appendRow(filaSemanas);
        sheet.appendRow(filaFechas);

        for (var estado in estadosOrdenados) {
          final List<xl.CellValue> filaValores = [xl.TextCellValue(estado)];

          for (int i = 0; i < fechasOrdenadas.length; i++) {
            final fechaRaw = fechasOrdenadas[i];
            final matches = lecturas.where((l) {
              final f = (l['fecha'] ?? l['created_at'] ?? '').toString().split('T').first;
              final cod = (l['estado_codigo'] ?? '').toString().trim();
              final desc = (l['descripcion_estado'] ?? '').toString().trim();
              final label = cod.isNotEmpty ? "$cod - $desc" : desc;
              return f == fechaRaw && label == estado;
            });

            if (matches.isNotEmpty) {
              double suma = 0.0;
              for (var m in matches) {
                suma += double.tryParse(m['valor_lectura']?.toString() ?? '0') ?? 0.0;
              }
              final double prom = suma / matches.length;
              filaValores.add(xl.TextCellValue("${prom.toStringAsFixed(0)}%"));
            } else {
              filaValores.add(xl.TextCellValue("-"));
            }
          }

          sheet.appendRow(filaValores);
        }

        sheet.setColumnWidth(0, 36.0);
        for (int col = 1; col <= fechasOrdenadas.length; col++) {
          sheet.setColumnWidth(col, 14.0);
        }
      }

      final xl.Sheet sheetCrudos = excel['DATOS_CRUDOS'];
      sheetCrudos.appendRow([
        xl.TextCellValue("ID_REG"),
        xl.TextCellValue("FECHA"),
        xl.TextCellValue("SEMANA"),
        xl.TextCellValue("PRODUCTOR"),
        xl.TextCellValue("CHACRA"),
        xl.TextCellValue("CUADRO"),
        xl.TextCellValue("FILA"),
        xl.TextCellValue("PLANTA"),
        xl.TextCellValue("CULTIVO"),
        xl.TextCellValue("VARIEDAD"),
        xl.TextCellValue("COD_ESTADO"),
        xl.TextCellValue("DESCRIPCION"),
        xl.TextCellValue("VALOR_%"),
        xl.TextCellValue("OBS"),
        xl.TextCellValue("EVIDENCIA"),
      ]);

      for (var fila in filasDatosCrudos) {
        sheetCrudos.appendRow(fila);
      }

      final List<int>? fileBytes = excel.encode();
      if (fileBytes == null) return;

      final Uint8List bytes = Uint8List.fromList(fileBytes);
      final String nombreArchivo =
          'Curva_Fenologia_${widget.nombreProductor.replaceAll(' ', '_')}_$anio.xlsx';

      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: nombreArchivo,
        mime: AgroMime.xlsx,
        texto: 'Evolución Fenológica - ${widget.nombreProductor}',
        context: context,
      );
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'No se pudo generar el Excel: $e',
            tipo: AgroSnackTipo.error);
      }
    } finally {
      if (mounted) setState(() => _exportandoExcel = false);
    }
  }

  // ============================================================
  // DETALLE DE VARIEDAD (panel)
  // ============================================================

  void _mostrarDetalleVariedad(Map<String, dynamic> grupo) {
    final String cultivo = (grupo['cultivo'] ?? '').toString();
    final String variedad = (grupo['variedad'] ?? '').toString();
    final List<Map<String, dynamic>> lecturas =
        (grupo['lecturas'] as List).cast<Map<String, dynamic>>();
    final promedios = (grupo['promedios_estados'] as Map<String, double>?) ??
        <String, double>{};
    final ordenados = promedios.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final listaMuestreos = _agruparMuestreos(lecturas);

    mostrarAgroPanel<void>(
      context: context,
      titulo: "$cultivo · $variedad",
      subtitulo:
          "Temporada ${DateTime.now().year} · ${listaMuestreos.length} muestreos · ${lecturas.length} registros",
      icono: _getIconoCultivo(cultivo),
      maxWidth: 680,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AgroExportBar(
              info: 'Curva completa de la temporada (Excel) o reporte oficial de esta variedad (PDF).',
              onExcel: _exportarExcelCurvaFenologica,
              onPdf: () => _exportarPdfIndividualVariedad(grupo, listaMuestreos),
            ),
            const SizedBox(height: 18),
            const AgroSectionHeader(
              titulo: 'Promedio por estado',
              subtitulo: 'Promedio de todos los muestreos de la temporada',
              icono: Icons.bar_chart_rounded,
            ),
            const SizedBox(height: 10),
            AgroBarChart(
              items: ordenados
                  .map((e) => AgroBarItem(
                        label: e.key,
                        valor: e.value,
                        color: _getColorSemaforo(e.value),
                      ))
                  .toList(),
              unidad: '%',
              anchoLabel: 140,
            ),
            const SizedBox(height: 10),
            AgroLeyenda(items: _leyendaSemaforo),
            const SizedBox(height: 20),
            AgroSectionHeader(
              titulo: 'Muestreos',
              subtitulo: 'Del más reciente al más antiguo',
              icono: Icons.timeline_rounded,
              trailing: AgroBadge(
                texto: '${listaMuestreos.length}',
                icono: Icons.fact_check_rounded,
              ),
            ),
            const SizedBox(height: 12),
            ...listaMuestreos.map(_itemMuestreo),
          ],
        );
      },
    );
  }

  Widget _itemMuestreo(List<Map<String, dynamic>> items) {
    final cab = items.first;
    final fechaRaw = _fechaLimpia(cab);
    final dt = DateTime.tryParse(fechaRaw);
    final String? fotoUrl = items
        .map((e) => e['url_evidencia']?.toString())
        .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);

    final ordenados = [...items]..sort((a, b) {
        final va = double.tryParse(a['valor_lectura']?.toString() ?? '0') ?? 0.0;
        final vb = double.tryParse(b['valor_lectura']?.toString() ?? '0') ?? 0.0;
        return vb.compareTo(va);
      });

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        border: Border.all(color: AgroTheme.colorBorder),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: AgroColors.primario,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AgroTheme.radiusMd),
                  bottomLeft: Radius.circular(AgroTheme.radiusMd),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_rounded,
                        size: 16, color: AgroColors.primario),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _fmtFecha(fechaRaw),
                              style: AgroText.valor.copyWith(fontSize: 13),
                            ),
                            if (dt != null)
                              TextSpan(
                                text: '  ·  Sem. ${_semanaDelAnio(dt)}',
                                style: AgroText.secundario,
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (fotoUrl != null && fotoUrl.isNotEmpty)
                      AgroIconButton(
                        icono: Icons.image_outlined,
                        tooltip: 'Ver foto',
                        size: 34,
                        color: AgroColors.primario,
                        onTap: () => _verFoto(fotoUrl),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AgroBadge(
                      texto: 'Cd. ${cab['cuadro'] ?? '-'}',
                      icono: Icons.grid_view_rounded,
                    ),
                    AgroTag(
                      texto: 'Fila ${cab['fila'] ?? '-'} · Pl. ${cab['planta_numero'] ?? '-'}',
                      icono: Icons.park_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ordenados.map((sub) {
                    final double val =
                        double.tryParse(sub['valor_lectura']?.toString() ?? '0') ?? 0.0;
                    final String cod = (sub['estado_codigo'] ?? '').toString();
                    return _chipEstado("$cod: ${val.toStringAsFixed(0)}%", val);
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipEstado(String texto, double val) {
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
            texto,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _colorTextoSemaforo(val),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NUEVO MUESTREO (panel con formulario)
  // ============================================================

  Future<void> _abrirModalNuevoMuestreo() async {
    if (_cuartelesInventarioParaCarga.isEmpty) {
      mostrarAgroSnack(
          context, 'No hay parcelas en el inventario para asociar la lectura.',
          tipo: AgroSnackTipo.error);
      return;
    }

    String claveCuartel(Map<String, dynamic> c) =>
        "${c['chacra']}__${c['cuadro']}__${c['variedad']}";

    Map<String, dynamic> cuartelSeleccionado = _cuartelesInventarioParaCarga.first;
    String claveSeleccionada = claveCuartel(cuartelSeleccionado);

    DateTime fechaSeleccionada = DateTime.now();
    final filaCtrl = TextEditingController(text: "1");
    final plantaCtrl = TextEditingController(text: "1");

    String? rutaFotoEvidencia;
    String latitud = "";
    String longitud = "";
    bool capturandoGps = false;
    bool guardando = false;
    bool parametrosSolicitados = false;
    bool cargandoParametros = true;
    bool panelAbierto = true;

    List<Map<String, dynamic>> estadosParametros = [];
    final Map<String, TextEditingController> controladoresPorcentajes = {};

    void limpiarControladores() {
      for (var c in controladoresPorcentajes.values) {
        c.dispose();
      }
      controladoresPorcentajes.clear();
    }

    // Nota: no llama a setModalState de forma sincrónica (se invoca
    // también durante el build del StatefulBuilder).
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
          final resAll = await db.query('fenologia_parametros', orderBy: 'estado_codigo ASC');
          listaMutada = List<Map<String, dynamic>>.from(resAll);
        }

        if (!panelAbierto) return;

        limpiarControladores();
        for (var e in listaMutada) {
          final String cod = e['id']?.toString() ?? e['estado_codigo']?.toString() ?? '';
          controladoresPorcentajes[cod] = TextEditingController(text: "");
        }

        setModalState(() {
          estadosParametros = listaMutada;
          cargandoParametros = false;
        });
      } catch (e) {
        debugPrint("Error al cargar parámetros: $e");
        if (panelAbierto) setModalState(() => cargandoParametros = false);
      }
    }

    await mostrarAgroPanel<void>(
      context: context,
      titulo: 'Nuevo muestreo de campo',
      subtitulo: 'Registrá el porcentaje de cada estado fenológico',
      icono: Icons.add_chart_rounded,
      maxWidth: 620,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sbCtx, setModalState) {
            if (!parametrosSolicitados) {
              parametrosSolicitados = true;
              cargarParametros(cuartelSeleccionado['cultivo']?.toString() ?? '', setModalState);
            }

            double totalPct = 0.0;
            for (var c in controladoresPorcentajes.values) {
              totalPct += double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;
            }
            final bool esCien = (totalPct - 100.0).abs() < 0.1;
            final bool excede = totalPct > 100.1;
            final Color colorTotal = esCien
                ? AgroColors.ok
                : (excede ? AgroColors.danger : AgroColors.warn);

            Future<void> guardar() async {
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
                mostrarAgroSnack(sbCtx, 'Ingresá el porcentaje en al menos un estado fenológico',
                    tipo: AgroSnackTipo.error);
                return;
              }

              setModalState(() => guardando = true);
              try {
                final db = await DatabaseHelper.instance.database;
                final ahora = DateTime.now();
                final fechaIso = DateFormat('yyyy-MM-dd').format(fechaSeleccionada);
                int sigId = await DatabaseHelper.instance.obtenerSiguienteId('lecturas_fenologia', 'id');
                final rutaFoto = rutaFotoEvidencia;

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

                if (ctx.mounted) Navigator.pop(ctx);
                _cargarDatosDashboard(silencioso: true);
                if (mounted) {
                  mostrarAgroSnack(context, '¡Se guardaron $creados registros fenológicos!',
                      tipo: AgroSnackTipo.ok);
                }
              } catch (e) {
                if (panelAbierto) setModalState(() => guardando = false);
                if (sbCtx.mounted) {
                  mostrarAgroSnack(sbCtx, 'No se pudo guardar el muestreo: $e',
                      tipo: AgroSnackTipo.error);
                }
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------------- Ubicación ----------------
                const Text('UBICACIÓN', style: AgroText.overline),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: claveSeleccionada,
                  isExpanded: true,
                  decoration: agroInputDecoration(
                    label: 'Cuadro y variedad',
                    icono: Icons.grid_view_rounded,
                  ),
                  items: _cuartelesInventarioParaCarga.map((c) {
                    final clave = claveCuartel(c);
                    return DropdownMenuItem<String>(
                      value: clave,
                      child: Text(
                        "${c['chacra']} · Cuadro ${c['cuadro']} (${c['variedad']} - ${c['cultivo']})",
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AgroTheme.colorText),
                      ),
                    );
                  }).toList(),
                  onChanged: (nuevaClave) {
                    if (nuevaClave != null) {
                      setModalState(() {
                        cargandoParametros = true;
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
                      flex: 5,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                        onTap: () async {
                          final hoy = DateTime.now();
                          final elegida = await showDatePicker(
                            context: sbCtx,
                            initialDate: fechaSeleccionada,
                            firstDate: DateTime(hoy.year - 2, 1, 1),
                            lastDate: DateTime(hoy.year + 1, 12, 31),
                            helpText: 'Fecha del muestreo',
                          );
                          if (elegida != null && panelAbierto) {
                            setModalState(() => fechaSeleccionada = elegida);
                          }
                        },
                        child: InputDecorator(
                          decoration: agroInputDecoration(
                            label: 'Fecha',
                            icono: Icons.event_rounded,
                          ),
                          child: Text(
                            DateFormat('dd/MM/yyyy').format(fechaSeleccionada),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AgroTheme.colorText,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: filaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: agroInputDecoration(label: 'Fila'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: plantaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: agroInputDecoration(label: 'Planta'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TileToggle(
                        icono: Icons.photo_camera_outlined,
                        iconoActivo: Icons.check_circle_rounded,
                        texto: 'Fotografiar',
                        textoActivo: 'Foto lista',
                        activo: rutaFotoEvidencia != null,
                        onTap: () async {
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
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TileToggle(
                        icono: Icons.location_on_outlined,
                        iconoActivo: Icons.my_location_rounded,
                        texto: 'Fijar GPS',
                        textoActivo: 'GPS OK',
                        detalle: latitud.isNotEmpty ? '$latitud, $longitud' : null,
                        activo: latitud.isNotEmpty,
                        cargando: capturandoGps,
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
                                  if (panelAbierto) {
                                    setModalState(() {
                                      latitud = pos.latitude.toStringAsFixed(6);
                                      longitud = pos.longitude.toStringAsFixed(6);
                                    });
                                  }
                                } catch (_) {}
                                if (panelAbierto) {
                                  setModalState(() => capturandoGps = false);
                                }
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ---------------- Estados ----------------
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ESTADOS FENOLÓGICOS', style: AgroText.overline),
                          const SizedBox(height: 2),
                          Text(
                            "Cultivo: ${cuartelSeleccionado['cultivo'] ?? 'General'}",
                            style: AgroText.secundario,
                          ),
                        ],
                      ),
                    ),
                    AgroBadge(
                      texto: 'Total ${totalPct.toStringAsFixed(0)}%',
                      color: colorTotal,
                      icono: esCien
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      grande: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (totalPct / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 6,
                    color: colorTotal,
                    backgroundColor: AgroTheme.colorBorder,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  esCien
                      ? 'La distribución suma 100%.'
                      : (excede
                          ? 'La suma supera el 100%. Revisá los valores.'
                          : 'La suma de los estados debería llegar al 100%.'),
                  style: AgroText.secundario.copyWith(fontSize: 11.5, color: colorTotal),
                ),
                const SizedBox(height: 12),
                if (cargandoParametros && estadosParametros.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: AgroLoading(mensaje: 'Cargando estados fenológicos…'),
                  )
                else if (estadosParametros.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No hay estados fenológicos configurados para este cultivo.',
                      textAlign: TextAlign.center,
                      style: AgroText.secundario,
                    ),
                  )
                else
                  ...estadosParametros.map((param) {
                    final String cod =
                        param['id']?.toString() ?? param['estado_codigo']?.toString() ?? '';
                    final ctrl = controladoresPorcentajes[cod];
                    final double valActual =
                        double.tryParse(ctrl?.text.replaceAll(',', '.') ?? '0') ?? 0.0;
                    final Color colorSemaforo = _getColorSemaforo(valActual);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: valActual > 0
                            ? colorSemaforo.withOpacity(0.08)
                            : AgroTheme.colorBg,
                        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                        border: Border.all(
                          color: valActual > 0
                              ? colorSemaforo.withOpacity(0.45)
                              : AgroTheme.colorBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 30,
                            decoration: BoxDecoration(
                              color: colorSemaforo,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AgroTheme.colorSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AgroTheme.colorBorder),
                            ),
                            child: Text(
                              (param['estado_codigo'] ?? 'S/C').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                                color: AgroTheme.colorText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (param['descripcion'] ?? 'Estado').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                color: AgroTheme.colorText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 78,
                            child: TextFormField(
                              controller: ctrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: "0",
                                suffixText: "%",
                                isDense: true,
                                filled: true,
                                fillColor: AgroTheme.colorSurface,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: AgroTheme.colorBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: AgroColors.primario, width: 1.5),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 18),
                AgroButton(
                  label: 'Guardar muestreo fenológico',
                  icono: Icons.save_rounded,
                  expandido: true,
                  cargando: guardando,
                  onTap: estadosParametros.isEmpty ? null : guardar,
                ),
              ],
            );
          },
        );
      },
    );

    // El panel se cerró (guardado o cancelado): liberar controladores
    // después de la animación de salida.
    panelAbierto = false;
    Future.delayed(const Duration(milliseconds: 500), () {
      limpiarControladores();
      filaCtrl.dispose();
      plantaCtrl.dispose();
    });
  }

  // ============================================================
  // PDF INDIVIDUAL POR VARIEDAD
  // ============================================================

  Future<void> _exportarPdfIndividualVariedad(
      Map<String, dynamic> grupo, List<List<Map<String, dynamic>>> muestreos) async {
    final pdf = pw.Document();
    final String anio = DateTime.now().year.toString();

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

    final rawCuadros = grupo['cuadros'];
    final String textoCuadros = rawCuadros is Iterable
        ? rawCuadros.map((e) => e.toString()).join(', ')
        : (rawCuadros?.toString() ?? 'S/D');

    const colorVerdeOscuro = PdfColor.fromInt(0xFF134E32);
    const colorVerdeSecundario = PdfColor.fromInt(0xFF1E6B4C);
    const colorFondoGris = PdfColor.fromInt(0xFFF9FAFB);
    const colorBorde = PdfColor.fromInt(0xFFE5E7EB);

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
            ],
          );
        },
        build: (pw.Context context) => [
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

          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: colorBorde, width: 0.6),
            headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: colorVerdeSecundario),
            headerHeight: 22,
            cellHeight: 20,
            cellStyle: const pw.TextStyle(fontSize: 7.5),
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

              final rawFecha = (cab['fecha'] ?? cab['created_at'] ?? '').toString();
              final DateTime? dt = DateTime.tryParse(rawFecha);
              final String fechaStr = dt != null
                  ? "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}"
                  : rawFecha.split('T').first;
              final String semStr = dt != null ? "S.${obtenerSemanaDelAnio(dt)}" : "S/-";

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
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    final String nombreArchivo = "Fenologia_${grupo['variedad'] ?? 'Variedad'}_$anio.pdf";

    if (!mounted) return;
    await exportarArchivoAgro(
      bytes: bytes,
      nombre: nombreArchivo,
      mime: AgroMime.pdf,
      texto: 'Reporte Oficial de Fenología - ${widget.nombreProductor}',
      context: context,
    );
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
    final int anioActual = DateTime.now().year;

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: "Fenología $anioActual",
        subtitulo: widget.nombreProductor,
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: 'Actualizar',
            onTap: _cargando ? null : () => _cargarDatosDashboard(),
          ),
          const SizedBox(width: 8),
          AgroIconButton(
            icono: Icons.table_view_rounded,
            tooltip: 'Exportar Excel curva fenológica',
            color: AgroColors.primario,
            onTap: (_cargando || _exportandoExcel || _gruposVariedadMuestreadas.isEmpty)
                ? null
                : _exportarExcelCurvaFenologica,
          ),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const AgroLoading(mensaje: 'Cargando registros fenológicos…')
            : _gruposVariedadMuestreadas.isEmpty
                ? AgroEmptyState(
                    icono: Icons.spa_outlined,
                    titulo: 'Sin registros fenológicos',
                    mensaje:
                        'No hay muestreos cargados en la temporada $anioActual. Registrá la primera lectura para empezar a construir la curva.',
                    accion: AgroButton(
                      label: 'Nueva lectura',
                      icono: Icons.add_chart_rounded,
                      onTap: _abrirModalNuevoMuestreo,
                    ),
                  )
                : RefreshIndicator(
                    color: AgroColors.primario,
                    onRefresh: () => _cargarDatosDashboard(silencioso: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 16, bottom: 110),
                      children: [
                        AgroContent(child: _contenido(anioActual)),
                      ],
                    ),
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirModalNuevoMuestreo,
        backgroundColor: AgroColors.primario,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_chart_rounded),
        label: const Text(
          'Nueva lectura',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _contenido(int anioActual) {
    // Métricas generales
    final int totalRegistros = _lecturasAnioActual.length;
    int totalMuestreos = 0;
    final Set<String> cuadrosTotales = {};
    for (var g in _gruposVariedadMuestreadas) {
      totalMuestreos +=
          _agruparMuestreos((g['lecturas'] as List).cast<Map<String, dynamic>>()).length;
      for (var c in (g['cuadros'] as Set<String>)) {
        cuadrosTotales.add(c);
      }
    }
    final String ultima = _ultimaFecha(_lecturasAnioActual);

    final List<String> cultivos = _gruposVariedadMuestreadas
        .map((g) => (g['cultivo'] ?? '').toString())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final String? filtro = cultivos.contains(_filtroCultivo) ? _filtroCultivo : null;
    final grupos = filtro == null
        ? _gruposVariedadMuestreadas
        : _gruposVariedadMuestreadas
            .where((g) => (g['cultivo'] ?? '').toString() == filtro)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgroReporteHeader(
          titulo: 'Seguimiento fenológico',
          subtitulo: 'Evolución de estados por variedad · ${widget.nombreProductor}',
          icono: Icons.spa_rounded,
          chips: [
            AgroHeaderChip(
                texto: 'Temporada $anioActual', icono: Icons.calendar_month_rounded),
            AgroHeaderChip(
                texto: '${_gruposVariedadMuestreadas.length} variedades',
                icono: Icons.local_florist_rounded),
            AgroHeaderChip(
                texto: '$totalMuestreos muestreos', icono: Icons.fact_check_rounded),
          ],
        ),
        const SizedBox(height: 14),
        AgroKpiGrid(
          kpis: [
            AgroKpiTile(
              label: 'Muestreos',
              valor: '$totalMuestreos',
              detalle: '$totalRegistros registros',
              icono: Icons.fact_check_rounded,
            ),
            AgroKpiTile(
              label: 'Variedades',
              valor: '${_gruposVariedadMuestreadas.length}',
              detalle: '${cultivos.length} cultivos',
              icono: Icons.local_florist_rounded,
              color: AgroColors.info,
            ),
            AgroKpiTile(
              label: 'Cuadros',
              valor: '${cuadrosTotales.length}',
              detalle: 'con muestreo',
              icono: Icons.grid_view_rounded,
              color: AgroColors.neutral,
            ),
            AgroKpiTile(
              label: 'Último muestreo',
              valor: _fmtFecha(ultima),
              icono: Icons.event_available_rounded,
              color: AgroColors.warn,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AgroCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cultivos.length > 1) ...[
                AgroChipSelector(
                  label: 'Cultivo',
                  opciones: cultivos,
                  valor: filtro,
                  onChanged: (v) => setState(() => _filtroCultivo = v),
                ),
                const SizedBox(height: 12),
              ],
              const Text('SEMÁFORO DE PORCENTAJES', style: AgroText.overline),
              const SizedBox(height: 6),
              AgroLeyenda(items: _leyendaSemaforo),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AgroSectionHeader(
          titulo: 'Variedades muestreadas',
          subtitulo: 'Promedio por estado fenológico · tocá una tarjeta para ver el detalle',
          icono: Icons.insights_rounded,
          trailing: AgroBadge(texto: '${grupos.length}'),
        ),
        const SizedBox(height: 12),
        if (grupos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No hay variedades para el filtro seleccionado.',
                textAlign: TextAlign.center, style: AgroText.secundario),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final int cols = c.maxWidth >= 760 ? 2 : 1;
              final double ancho =
                  ((c.maxWidth - (cols - 1) * 12) / cols).floorToDouble();
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: grupos
                    .map((g) => SizedBox(width: ancho, child: _tarjetaVariedad(g)))
                    .toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _tarjetaVariedad(Map<String, dynamic> g) {
    final String cultivo = (g['cultivo'] ?? '').toString();
    final String variedad = (g['variedad'] ?? '').toString();
    final Set<String> cuadros = g['cuadros'] as Set<String>;
    final promedios =
        (g['promedios_estados'] as Map<String, double>?) ?? <String, double>{};
    final lecturas = (g['lecturas'] as List).cast<Map<String, dynamic>>();
    final int totalReg = lecturas.length;
    final int nMuestreos = _agruparMuestreos(lecturas).length;
    final ordenados = promedios.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    const int maxBarras = 6;
    final top = ordenados.take(maxBarras).toList();
    final MapEntry<String, double>? dominante =
        ordenados.isNotEmpty ? ordenados.first : null;
    final String ultima = _ultimaFecha(lecturas);

    final cuadrosLista = cuadros.toList();
    const int maxCuadros = 8;

    return AgroCard(
      onTap: () => _mostrarDetalleVariedad(g),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AgroIconBox(icono: _getIconoCultivo(cultivo), size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variedad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.tituloCard,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$cultivo · $totalReg registros',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.secundario,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AgroBadge(
                texto: '$nMuestreos muestreos',
                color: AgroColors.ok,
                fondo: AgroColors.okSoft,
              ),
            ],
          ),
          if (cuadrosLista.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...cuadrosLista
                    .take(maxCuadros)
                    .map((c) => AgroTag(texto: 'Cd. $c', icono: Icons.grid_view_rounded)),
                if (cuadrosLista.length > maxCuadros)
                  AgroTag(texto: '+${cuadrosLista.length - maxCuadros}'),
              ],
            ),
          ],
          if (dominante != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _getColorSemaforo(dominante.value).withOpacity(0.10),
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                border: Border.all(
                    color: _getColorSemaforo(dominante.value).withOpacity(0.40)),
              ),
              child: Row(
                children: [
                  Icon(Icons.star_rounded,
                      size: 18, color: _colorTextoSemaforo(dominante.value)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ESTADO DOMINANTE', style: AgroText.overline),
                        const SizedBox(height: 1),
                        Text(
                          dominante.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AgroText.valor.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${dominante.value.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _colorTextoSemaforo(dominante.value),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (top.isNotEmpty) ...[
            const SizedBox(height: 10),
            AgroBarChart(
              items: top
                  .map((e) => AgroBarItem(
                        label: e.key,
                        valor: e.value,
                        color: _getColorSemaforo(e.value),
                      ))
                  .toList(),
              unidad: '%',
              anchoLabel: 124,
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: AgroTheme.colorBorder),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.event_rounded,
                  size: 15, color: AgroTheme.colorTextSecondary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  ordenados.length > maxBarras
                      ? 'Último: ${_fmtFecha(ultima)} · +${ordenados.length - maxBarras} estados'
                      : 'Último: ${_fmtFecha(ultima)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.secundario,
                ),
              ),
              const Text(
                'Ver detalle',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AgroColors.primario,
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AgroColors.primario),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TILE TOGGLE (foto / GPS)
// ============================================================

class _TileToggle extends StatelessWidget {
  final IconData icono;
  final IconData iconoActivo;
  final String texto;
  final String textoActivo;
  final String? detalle;
  final bool activo;
  final bool cargando;
  final VoidCallback? onTap;

  const _TileToggle({
    required this.icono,
    required this.iconoActivo,
    required this.texto,
    required this.textoActivo,
    required this.activo,
    this.detalle,
    this.cargando = false,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (cargando)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AgroColors.primario),
                  )
                else
                  Icon(activo ? iconoActivo : icono, size: 19, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cargando ? 'Buscando…' : (activo ? textoActivo : texto),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: activo ? AgroColors.ok : AgroTheme.colorText,
                        ),
                      ),
                      if (detalle != null)
                        Text(
                          detalle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AgroText.secundario.copyWith(fontSize: 10.5),
                        ),
                    ],
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
