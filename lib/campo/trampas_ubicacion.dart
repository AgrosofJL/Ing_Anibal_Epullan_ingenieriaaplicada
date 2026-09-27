// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FilteringTextInputFormatter;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/agro_reportes_ui.dart';
import '../widgets/agro_ui.dart';

/// Color de referencia por plaga. Coincide con el color de los pines del
/// mapa satelital (ver [_MapaTrampasViewState._getHueForPlaga]).
Color _colorPlaga(String plagaRaw) {
  final p = plagaRaw.toUpperCase();
  if (p.contains("CARPO")) return Colors.red;
  if (p.contains("GRAFO")) return Colors.orange;
  if (p.contains("MOSCA")) return Colors.yellow.shade700;
  if (p.contains("PSILIDO") || p.contains("PERA")) return Colors.cyan;
  return Colors.purple;
}

class TrampasUbicacionScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const TrampasUbicacionScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<TrampasUbicacionScreen> createState() => _TrampasUbicacionScreenState();
}

class _TrampasUbicacionScreenState extends State<TrampasUbicacionScreen> {
  static const int _umbral = 5;

  /// Valor guardado en la base / texto visible en el selector.
  static const List<List<String>> _opcionesPlaga = [
    ["CARPOCAPSA (Cydia pomonella)", "Carpocapsa (Delta con Feromona)"],
    ["GRAFOLITA (Grapholita molesta)", "Grafolita (Delta con Feromona)"],
    ["MOSCA DE LOS FRUTOS (Ceratitis)", "Mosca de los Frutos (Jackson/Polillero)"],
    ["PSILIDO DE LA PERA (Cacopsylla)", "Psílido del Peral (Placa Amarilla)"],
  ];

  bool _cargando = true;
  String _userName = "Operario";

  List<Map<String, dynamic>> _todasTrampas = [];
  List<String> _chacrasDisponibles = [];
  String _chacraSeleccionada = "TODAS";

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('userName') ?? "Operario";
    final db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> trampas = await db.rawQuery('''
      SELECT
        cod_trampa,
        trampa_numero,
        tipo_trampa,
        sector as chacra,
        cuadro,
        fila,
        variedad,
        cultivo,
        ubicacion,
        url_evidencia,
        created_at
      FROM lecturas_trampas
      WHERE cod_establecimiento = ? AND cod_trampa IS NOT NULL
      GROUP BY cod_trampa
      ORDER BY cuadro ASC, CAST(trampa_numero AS INTEGER) ASC
    ''', [widget.codProductor]);

    final Set<String> chacrasSet = {"TODAS"};
    for (var t in trampas) {
      final ch = t['chacra']?.toString();
      if (ch != null && ch.isNotEmpty) chacrasSet.add(ch);
    }

    if (!mounted) return;
    setState(() {
      _todasTrampas = trampas;
      _chacrasDisponibles = chacrasSet.toList();
      if (!_chacrasDisponibles.contains(_chacraSeleccionada)) {
        _chacraSeleccionada = "TODAS";
      }
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _trampasFiltradas {
    if (_chacraSeleccionada == "TODAS") return _todasTrampas;
    return _todasTrampas
        .where((t) => (t['chacra'] ?? '').toString() == _chacraSeleccionada)
        .toList();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  bool _tieneGps(Map<String, dynamic> t) {
    final u = t['ubicacion']?.toString() ?? '';
    return u.contains(',') && u.split(',').length >= 2;
  }

  int _totalLectura(Map<String, dynamic> l) {
    final int m = int.tryParse(l['macho']?.toString() ?? '0') ?? 0;
    final int hv = int.tryParse(l['hembra_virgen']?.toString() ?? '0') ?? 0;
    final int hg = int.tryParse(l['hembra_gravida']?.toString() ?? '0') ?? 0;
    return m + hv + hg;
  }

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

  Widget _punto(Color color, {double size = 10}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.35), blurRadius: 3),
          ],
        ),
      );

  // ==========================================================================
  // MAPA SATELITAL CON PINS POR PLAGA
  // ==========================================================================
  void _abrirMapaGlobalTrampas() {
    final trampasConGps = _trampasFiltradas.where((t) {
      final u = t['ubicacion']?.toString() ?? '';
      return u.contains(',') && u.split(',').length >= 2;
    }).toList();

    if (trampasConGps.isEmpty) {
      mostrarAgroSnack(
          context, 'No hay trampas con coordenadas GPS válidas en este sector.',
          tipo: AgroSnackTipo.error);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MapaTrampasView(
          trampas: trampasConGps,
          nombreProductor: widget.nombreProductor,
          onVerReporte: (t) => _mostrarReporteSemanas(t),
        ),
      ),
    );
  }

  // ==========================================================================
  // FORMULARIO: UBICAR / INSTALAR TRAMPA (QR + GPS + CÁMARA)
  // ==========================================================================
  Future<void> _abrirModalInstalarTrampa() async {
    final db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> cuarteles = await db.query(
      'inventario_plantacion',
      columns: ['id', 'chacra', 'cuadro', 'variedad', 'cultivo'],
      where: 'cod_productor = ?',
      whereArgs: [widget.codProductor],
      groupBy: 'chacra, cuadro, variedad',
      orderBy: 'chacra ASC, cuadro ASC',
    );

    if (cuarteles.isEmpty) {
      if (mounted) {
        mostrarAgroSnack(context,
            'No hay cuarteles registrados en el inventario para este productor.',
            tipo: AgroSnackTipo.error);
      }
      return;
    }

    String generarClave(Map<String, dynamic> c) =>
        "${c['chacra']}__${c['cuadro']}__${c['variedad']}";

    String claveCuartelSeleccionado = generarClave(cuarteles.first);
    Map<String, dynamic> cuartelSelec = cuarteles.first;

    String tipoPlaga = "CARPOCAPSA (Cydia pomonella)";
    final nroTrampaCtrl = TextEditingController();
    final filaCtrl = TextEditingController(text: "1");
    String gpsCoords = "";
    bool capturandoGps = false;
    bool guardando = false;
    bool panelAbierto = true;
    String? rutaFotoEvidenciaTrampa;

    if (!mounted) return;

    await mostrarAgroPanel<void>(
      context: context,
      titulo: 'Ubicar trampa de plagas',
      subtitulo: 'Registrá la instalación con código, GPS y foto',
      icono: Icons.add_location_alt_rounded,
      maxWidth: 580,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sbCtx, setModalState) {
            Future<void> guardar() async {
              if (nroTrampaCtrl.text.trim().isEmpty) {
                mostrarAgroSnack(sbCtx, 'Ingresá el número o escaneá el QR',
                    tipo: AgroSnackTipo.aviso);
                return;
              }

              setModalState(() => guardando = true);
              try {
                final ahora = DateTime.now();
                final String nro = nroTrampaCtrl.text.trim();
                final String cod = "TRP_${widget.codProductor}_$nro";
                final String idReg = "LOC_${ahora.millisecondsSinceEpoch}";

                await db.insert('lecturas_trampas', {
                  'id': cod,
                  'id_reg': idReg,
                  'created_at': ahora.toIso8601String(),
                  'establecimiento': widget.nombreProductor,
                  'sector': cuartelSelec['chacra'] ?? '',
                  'cuadro': cuartelSelec['cuadro'] ?? '',
                  'cultivo': cuartelSelec['cultivo'] ?? '',
                  'variedad': cuartelSelec['variedad'] ?? '',
                  'fila': filaCtrl.text.trim(),
                  'ubicacion': gpsCoords,
                  'tipo_trampa': tipoPlaga,
                  'cod_trampa': cod,
                  'usuario': _userName,
                  'trampa_numero': nro,
                  'semana': "INSTALACION",
                  'temporada': "${ahora.year}",
                  'macho': "0",
                  'hembra_virgen': "0",
                  'hembra_gravida': "0",
                  'url_evidencia': rutaFotoEvidenciaTrampa,
                  'cod_establecimiento': widget.codProductor,
                  'sincronizado': 0,
                });

                if (ctx.mounted) Navigator.pop(ctx);
                _cargarDatos(silencioso: true);
                if (mounted) {
                  mostrarAgroSnack(context, 'Trampa ubicada con éxito',
                      tipo: AgroSnackTipo.ok);
                }
              } catch (e) {
                if (panelAbierto) setModalState(() => guardando = false);
                if (sbCtx.mounted) {
                  mostrarAgroSnack(sbCtx, 'No se pudo guardar la trampa: $e',
                      tipo: AgroSnackTipo.error);
                }
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('UBICACIÓN EN EL MONTE', style: AgroText.overline),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: claveCuartelSeleccionado,
                  isExpanded: true,
                  decoration: agroInputDecoration(
                    label: 'Chacra y cuadro',
                    icono: Icons.grid_view_rounded,
                  ),
                  items: cuarteles.map((c) {
                    final clave = generarClave(c);
                    return DropdownMenuItem<String>(
                      value: clave,
                      child: Text(
                        "${c['chacra']} · Cuadro ${c['cuadro']} (${c['variedad']})",
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AgroTheme.colorText,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (nuevaClave) {
                    if (nuevaClave != null) {
                      setModalState(() {
                        claveCuartelSeleccionado = nuevaClave;
                        cuartelSelec = cuarteles.firstWhere(
                          (c) => generarClave(c) == nuevaClave,
                        );
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: filaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: agroInputDecoration(
                    label: 'Fila / hilera',
                    icono: Icons.straighten_rounded,
                  ),
                ),
                const SizedBox(height: 18),
                const Text('TRAMPA', style: AgroText.overline),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: tipoPlaga,
                  isExpanded: true,
                  decoration: agroInputDecoration(
                    label: 'Plaga / tipo de trampa',
                    icono: Icons.bug_report_outlined,
                  ),
                  items: _opcionesPlaga
                      .map((o) => DropdownMenuItem<String>(
                            value: o[0],
                            child: Row(
                              children: [
                                _punto(_colorPlaga(o[0])),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    o[1],
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AgroTheme.colorText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setModalState(() => tipoPlaga = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: nroTrampaCtrl,
                        keyboardType: TextInputType.text,
                        decoration: agroInputDecoration(
                          label: 'N° o código de trampa',
                          icono: Icons.tag_rounded,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Escanear código QR',
                      child: Material(
                        color: AgroColors.primarioSoft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                          side: BorderSide(
                              color: AgroColors.primario.withOpacity(0.35)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                          onTap: () => _abrirEscannerQR((codigoLeido) {
                            if (!panelAbierto) return;
                            setModalState(() {
                              nroTrampaCtrl.text = codigoLeido;
                            });
                          }),
                          child: const SizedBox(
                            width: 50,
                            height: 50,
                            child: Icon(Icons.qr_code_scanner_rounded,
                                color: AgroColors.primario, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('EVIDENCIA', style: AgroText.overline),
                const SizedBox(height: 8),
                _TileToggle(
                  icono: Icons.my_location_rounded,
                  iconoActivo: Icons.gps_fixed_rounded,
                  texto: 'Fijar posición GPS',
                  textoActivo: 'GPS fijado · tocar para actualizar',
                  detalle: gpsCoords.isNotEmpty ? gpsCoords : 'Sin coordenadas fijadas',
                  activo: gpsCoords.isNotEmpty,
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
                                gpsCoords =
                                    "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
                              });
                            }
                          } catch (e) {
                            if (sbCtx.mounted) {
                              mostrarAgroSnack(sbCtx, 'Error GPS: $e',
                                  tipo: AgroSnackTipo.error);
                            }
                          }
                          if (panelAbierto) {
                            setModalState(() => capturandoGps = false);
                          }
                        },
                ),
                const SizedBox(height: 8),
                _TileToggle(
                  icono: Icons.camera_alt_outlined,
                  iconoActivo: Icons.check_circle_rounded,
                  texto: 'Fotografiar trampa / placa',
                  textoActivo: 'Evidencia de trampa lista',
                  activo: rutaFotoEvidenciaTrampa != null,
                  onTap: () async {
                    try {
                      final XFile? foto = await _picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 75,
                        maxWidth: 1280,
                      );
                      if (foto != null && panelAbierto) {
                        setModalState(() {
                          rutaFotoEvidenciaTrampa = foto.path;
                        });
                      }
                    } catch (_) {}
                  },
                ),
                const SizedBox(height: 20),
                AgroButton(
                  label: 'Guardar ubicación de trampa',
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
      nroTrampaCtrl.dispose();
      filaCtrl.dispose();
    });
  }

  void _abrirEscannerQR(Function(String) onCodeFound) {
    bool leido = false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text("Escanear código de trampa",
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
          ),
          body: Stack(
            children: [
              MobileScanner(
                onDetect: (capture) {
                  if (leido) return;
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    final String valor = barcodes.first.rawValue ?? '';
                    if (valor.isNotEmpty) {
                      leido = true;
                      Navigator.pop(c);
                      onCodeFound(valor);
                    }
                  }
                },
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Apuntá la cámara al código QR de la trampa.',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // LECTURA SEMANAL
  // ==========================================================================
  Future<void> _mostrarModalLectura(Map<String, dynamic> trampa) async {
    DateTime fechaSeleccionada = DateTime.now();
    final machosCtrl = TextEditingController(text: "0");
    final hembrasVirgCtrl = TextEditingController(text: "0");
    final hembrasGravCtrl = TextEditingController(text: "0");
    String? rutaFotoLectura;
    bool guardando = false;
    bool panelAbierto = true;

    String obtenerSemana(DateTime f) {
      final dayOfYear = int.parse(DateFormat("D").format(f));
      final int w = ((dayOfYear - f.weekday + 10) / 7).floor();
      return "Semana ${w.toString().padLeft(2, '0')}";
    }

    await mostrarAgroPanel<void>(
      context: context,
      titulo: "Lectura · Trampa N° ${trampa['trampa_numero']}",
      subtitulo: "${trampa['chacra']} · Cuadro ${trampa['cuadro']} (${trampa['tipo_trampa']})",
      icono: Icons.add_task_rounded,
      maxWidth: 560,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sbCtx, setModalState) {
            final int m = int.tryParse(machosCtrl.text) ?? 0;
            final int hv = int.tryParse(hembrasVirgCtrl.text) ?? 0;
            final int hg = int.tryParse(hembrasGravCtrl.text) ?? 0;
            final int total = m + hv + hg;
            final bool alertaUmbral = total >= 5;

            Future<void> guardar() async {
              setModalState(() => guardando = true);
              try {
                final db = await DatabaseHelper.instance.database;
                final ahora = DateTime.now();
                final String idReg = "LEC_${ahora.millisecondsSinceEpoch}";
                final String semanaCalculada = obtenerSemana(fechaSeleccionada);

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
                  'url_evidencia': rutaFotoLectura,
                  'cod_establecimiento': widget.codProductor,
                  'sincronizado': 0,
                });

                if (ctx.mounted) Navigator.pop(ctx);
                _cargarDatos(silencioso: true);
                if (mounted) {
                  mostrarAgroSnack(
                    context,
                    '¡Lectura guardada para $semanaCalculada con éxito!',
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
                        AgroBadge(
                          texto: obtenerSemana(fechaSeleccionada),
                          icono: Icons.date_range_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('CAPTURAS DE LA SEMANA', style: AgroText.overline),
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
                  activo: rutaFotoLectura != null,
                  onTap: () async {
                    try {
                      final XFile? foto = await _picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 75,
                        maxWidth: 1280,
                      );
                      if (foto != null && panelAbierto) {
                        setModalState(() {
                          rutaFotoLectura = foto.path;
                        });
                      }
                    } catch (_) {}
                  },
                ),
                const SizedBox(height: 14),
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
                  label: 'Guardar lectura',
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

  // ==========================================================================
  // CURVA SEMANAL DE UNA TRAMPA (con PDF)
  // ==========================================================================
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
      titulo: "Curva semanal · TR #${trampa['trampa_numero']}",
      subtitulo: "${trampa['chacra']} · Cd. ${trampa['cuadro']} · ${trampa['tipo_trampa']}",
      icono: Icons.show_chart_rounded,
      maxWidth: 640,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AgroStatGrid(
              stats: [
                AgroStat(
                  label: 'Semanas',
                  valor: '${lecturas.length}',
                  icono: Icons.date_range_rounded,
                ),
                AgroStat(
                  label: 'Acumulado',
                  valor: '$acumulado ind.',
                  icono: Icons.functions_rounded,
                ),
                AgroStat(
                  label: 'Máximo',
                  valor: '$maxCaptura ind.',
                  icono: Icons.trending_up_rounded,
                  color: _colorCaptura(maxCaptura),
                ),
                AgroStat(
                  label: 'Sobre umbral',
                  valor: '$semanasAlerta sem.',
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
                titulo: 'Capturas por semana',
                subtitulo: 'Total de individuos · umbral 5',
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
                    detalle: '$sem · M $m · H ${hv + hg}',
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
              const Text('DETALLE SEMANAL', style: AgroText.overline),
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
              icono: Icons.add_task_rounded,
              expandido: true,
              onTap: () {
                Navigator.pop(ctx);
                _mostrarModalLectura(trampa);
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

  // ==========================================================================
  // PDF DE LA TRAMPA (contenido original)
  // ==========================================================================
  Future<void> _generarPdfTrampa(
      Map<String, dynamic> trampa, List<Map<String, dynamic>> lecturas) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('logo/logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

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
                  width: 85,
                  height: 85,
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
                pw.Text("PLAGA: ${trampa['tipo_trampa']}", style: const pw.TextStyle(fontSize: 9)),
                pw.Text("CHACRA: ${trampa['chacra']} · CD: ${trampa['cuadro']}",
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text("VARIEDAD: ${trampa['variedad']}", style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          pw.Text("CURVA DE CAPTURAS SEMANALES",
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF1E6B4C))),
          pw.SizedBox(height: 6),

          pw.Container(
            height: 80,
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
                            color: alerta ? PdfColors.red800 : const PdfColor.fromInt(0xFF1E6B4C))),
                    pw.SizedBox(height: 2),
                    pw.Container(
                      width: 14,
                      height: 46 * alturaPct,
                      decoration: pw.BoxDecoration(
                        color: alerta ? PdfColors.red600 : const PdfColor.fromInt(0xFF1E6B4C),
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

          pw.Text("TABLA DE RECUENTO SEMANAL",
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF1E6B4C))),
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
                tot >= 5 ? 'ALERTA UMBRAL' : 'NORMAL'
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();

    if (!mounted) return;
    await exportarArchivoAgro(
      bytes: bytes,
      nombre: 'Reporte_Trampa_${trampa['trampa_numero']}.pdf',
      mime: AgroMime.pdf,
      texto: 'Reporte de Trampa N° ${trampa['trampa_numero']} - ${widget.nombreProductor}',
      context: context,
    );
  }

  // ==========================================================================
  // VISOR DE FOTO
  // ==========================================================================
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

  // ==========================================================================
  // UI PRINCIPAL
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: "Ubicación y trampeo",
        subtitulo: widget.nombreProductor,
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: 'Actualizar',
            onTap: _cargando ? null : () => _cargarDatos(),
          ),
          const SizedBox(width: 8),
          AgroIconButton(
            icono: Icons.map_rounded,
            tooltip: 'Ver mapa satelital de trampas',
            color: AgroColors.primario,
            onTap: _cargando ? null : _abrirMapaGlobalTrampas,
          ),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const AgroLoading(mensaje: 'Cargando trampas…')
            : _todasTrampas.isEmpty
                ? AgroEmptyState(
                    icono: Icons.add_location_alt_outlined,
                    titulo: 'Todavía no hay trampas ubicadas',
                    mensaje:
                        'Registrá cada trampa con su código, posición GPS y una foto para empezar el monitoreo.',
                    accion: AgroButton(
                      label: 'Ubicar trampa',
                      icono: Icons.add_location_alt_outlined,
                      onTap: _abrirModalInstalarTrampa,
                    ),
                  )
                : RefreshIndicator(
                    color: AgroColors.primario,
                    onRefresh: () => _cargarDatos(silencioso: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 16, bottom: 110),
                      children: [
                        AgroContent(child: _contenido()),
                      ],
                    ),
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirModalInstalarTrampa,
        backgroundColor: AgroColors.primario,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text(
          'Ubicar trampa',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _contenido() {
    final trampas = _trampasFiltradas;
    final int conGps = trampas.where(_tieneGps).length;
    final int sinGps = trampas.length - conGps;
    final Map<String, int> porPlaga = {};
    for (var t in trampas) {
      final p = (t['tipo_trampa'] ?? 'Sin definir').toString();
      porPlaga[p] = (porPlaga[p] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgroKpiGrid(
          kpis: [
            AgroKpiTile(
              label: 'Trampas',
              valor: '${trampas.length}',
              icono: Icons.pest_control_rounded,
              detalle: _chacraSeleccionada == "TODAS"
                  ? 'todas las chacras'
                  : 'chacra $_chacraSeleccionada',
            ),
            AgroKpiTile(
              label: 'Con GPS',
              valor: '$conGps',
              icono: Icons.gps_fixed_rounded,
              color: AgroColors.ok,
              detalle: 'ver en el mapa',
              onTap: conGps > 0 ? _abrirMapaGlobalTrampas : null,
            ),
            AgroKpiTile(
              label: 'Sin GPS',
              valor: '$sinGps',
              icono: Icons.gps_off_rounded,
              color: sinGps > 0 ? AgroColors.warn : AgroColors.neutral,
              detalle: sinGps > 0 ? 'completar posición' : 'todo georreferenciado',
            ),
            AgroKpiTile(
              label: 'Plagas',
              valor: '${porPlaga.length}',
              icono: Icons.bug_report_rounded,
              color: AgroColors.info,
              detalle: 'monitoreadas',
            ),
          ],
        ),
        const SizedBox(height: 12),
        AgroCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_chacrasDisponibles.length > 1) ...[
                AgroChipSelector(
                  label: 'Chacra',
                  opciones: _chacrasDisponibles.where((c) => c != "TODAS").toList(),
                  valor: _chacraSeleccionada == "TODAS" ? null : _chacraSeleccionada,
                  textoTodos: 'Todas',
                  onChanged: (v) => setState(() => _chacraSeleccionada = v ?? "TODAS"),
                ),
                const SizedBox(height: 12),
              ],
              const Text('PLAGAS (COLOR EN EL MAPA)', style: AgroText.overline),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: porPlaga.entries
                    .map((e) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _punto(_colorPlaga(e.key)),
                            const SizedBox(width: 6),
                            Text(
                              '${e.key.split(' (').first} · ${e.value}',
                              style: AgroText.secundario.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AgroTheme.colorText,
                              ),
                            ),
                          ],
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AgroSectionHeader(
          titulo: 'Trampas instaladas',
          subtitulo: 'Cargá la lectura semanal o revisá la curva de capturas',
          icono: Icons.pest_control_rounded,
          trailing: AgroBadge(texto: '${trampas.length}'),
        ),
        const SizedBox(height: 12),
        if (trampas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'No hay trampas ubicadas en este sector.',
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
                children: trampas
                    .map((t) => SizedBox(width: ancho, child: _tarjetaTrampa(t)))
                    .toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _tarjetaTrampa(Map<String, dynamic> trampa) {
    final String plaga = (trampa['tipo_trampa'] ?? 'Plaga no definida').toString();
    final Color colorPlaga = _colorPlaga(plaga);
    final bool gps = _tieneGps(trampa);
    final String? fotoUrl = trampa['url_evidencia']?.toString();
    final String cultivo = (trampa['cultivo'] ?? '').toString();
    final String variedad = (trampa['variedad'] ?? '').toString();

    return AgroCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _mostrarReporteSemanas(trampa),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorPlaga.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorPlaga.withOpacity(0.45)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('TR', style: AgroText.overline),
                    Text(
                      "${trampa['trampa_numero'] ?? '-'}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: AgroTheme.colorText,
                      ),
                    ),
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
                        _punto(colorPlaga),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            plaga,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AgroText.tituloCard,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Chacra ${trampa['chacra'] ?? '-'} · Cuadro ${trampa['cuadro'] ?? '-'}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.secundario,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              gps
                  ? const AgroBadge(
                      texto: 'GPS',
                      color: AgroColors.ok,
                      fondo: AgroColors.okSoft,
                      icono: Icons.gps_fixed_rounded,
                    )
                  : const AgroBadge(
                      texto: 'Sin GPS',
                      color: AgroColors.warn,
                      fondo: AgroColors.warnSoft,
                      icono: Icons.gps_off_rounded,
                    ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AgroTag(texto: "Fila ${trampa['fila'] ?? '-'}", icono: Icons.straighten_rounded),
              if (cultivo.isNotEmpty || variedad.isNotEmpty)
                AgroTag(
                  texto: [cultivo, variedad].where((s) => s.isNotEmpty).join(' - '),
                  icono: Icons.local_florist_outlined,
                ),
              AgroTag(
                texto: 'Instalada ${_fmtFecha(trampa['created_at']?.toString())}',
                icono: Icons.event_rounded,
              ),
              if (gps)
                AgroTag(
                  texto: (trampa['ubicacion'] ?? '').toString(),
                  icono: Icons.place_outlined,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AgroButton(
                  label: 'Lectura',
                  icono: Icons.add_task_rounded,
                  expandido: true,
                  compacto: true,
                  onTap: () => _mostrarModalLectura(trampa),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AgroButton(
                  label: 'Curva',
                  icono: Icons.show_chart_rounded,
                  tipo: AgroButtonTipo.secundario,
                  expandido: true,
                  compacto: true,
                  onTap: () => _mostrarReporteSemanas(trampa),
                ),
              ),
              if (fotoUrl != null && fotoUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                AgroIconButton(
                  icono: Icons.image_outlined,
                  tooltip: 'Ver foto de trampa',
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

// ============================================================================
// VISTA COMPLETA: MAPA SATELITAL CON PINS POR COLOR Y TRAMPAS
// ============================================================================
class _MapaTrampasView extends StatefulWidget {
  final List<Map<String, dynamic>> trampas;
  final String nombreProductor;
  final Function(Map<String, dynamic>) onVerReporte;

  const _MapaTrampasView({
    required this.trampas,
    required this.nombreProductor,
    required this.onVerReporte,
  });

  @override
  State<_MapaTrampasView> createState() => _MapaTrampasViewState();
}

class _MapaTrampasViewState extends State<_MapaTrampasView> {
  GoogleMapController? _mapController;
  MapType _currentMapType = MapType.hybrid; // Satelital híbrido por defecto
  final Set<Marker> _markers = {};
  LatLng _initialPosition = const LatLng(-39.1250, -67.1450); // Valle Medio / Alto Valle

  @override
  void initState() {
    super.initState();
    _construirMarcadores();
  }

  double _getHueForPlaga(String plagaRaw) {
    final p = plagaRaw.toUpperCase();
    if (p.contains("CARPO")) return BitmapDescriptor.hueRed;
    if (p.contains("GRAFO")) return BitmapDescriptor.hueOrange;
    if (p.contains("MOSCA")) return BitmapDescriptor.hueYellow;
    if (p.contains("PSILIDO") || p.contains("PERA")) return BitmapDescriptor.hueCyan;
    return BitmapDescriptor.hueViolet;
  }

  void _construirMarcadores() {
    _markers.clear();
    double sumLat = 0.0;
    double sumLng = 0.0;
    int count = 0;

    for (var t in widget.trampas) {
      final u = t['ubicacion']?.toString() ?? '';
      final partes = u.split(',');
      if (partes.length >= 2) {
        final double? lat = double.tryParse(partes[0].trim());
        final double? lng = double.tryParse(partes[1].trim());

        if (lat != null && lng != null) {
          sumLat += lat;
          sumLng += lng;
          count++;

          final String codTr = (t['cod_trampa'] ?? '').toString();
          final String nro = (t['trampa_numero'] ?? '').toString();
          final String plaga = (t['tipo_trampa'] ?? 'Plaga').toString();

          _markers.add(
            Marker(
              markerId: MarkerId(codTr),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(_getHueForPlaga(plaga)),
              infoWindow: InfoWindow(
                title: "TR #$nro · Cd. ${t['cuadro']}",
                snippet: "$plaga (Toca para ver curva)",
                onTap: () {
                  widget.onVerReporte(t);
                },
              ),
            ),
          );
        }
      }
    }

    if (count > 0) {
      _initialPosition = LatLng(sumLat / count, sumLng / count);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF12241B),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back_rounded, size: 22, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Mapa satelital de trampas",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
            Text("${widget.nombreProductor} · ${_markers.length} trampas",
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white),
            tooltip: "Centrar en las trampas",
            onPressed: () {
              _mapController?.animateCamera(
                CameraUpdate.newLatLngZoom(_initialPosition, 15.5),
              );
            },
          ),
          IconButton(
            icon: Icon(
              _currentMapType == MapType.hybrid ? Icons.satellite_alt_rounded : Icons.map_outlined,
              color: Colors.white,
            ),
            tooltip: "Alternar capa satélite / normal",
            onPressed: () {
              setState(() {
                _currentMapType = _currentMapType == MapType.hybrid ? MapType.normal : MapType.hybrid;
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: _currentMapType,
            initialCameraPosition: CameraPosition(target: _initialPosition, zoom: 15.5),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            compassEnabled: true,
            onMapCreated: (controller) => _mapController = controller,
          ),

          // Referencias de plagas arriba
          const _LeyendaPlagasMapa(),
        ],
      ),
    );
  }
}

/// Leyenda flotante de colores por plaga (debe ser hijo directo del Stack).
class _LeyendaPlagasMapa extends StatelessWidget {
  const _LeyendaPlagasMapa();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 14,
      right: 14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.78),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _RefChip(label: "Carpocapsa", color: Colors.red),
              SizedBox(width: 12),
              _RefChip(label: "Grafolita", color: Colors.orange),
              SizedBox(width: 12),
              _RefChip(label: "Mosca Frutos", color: Colors.yellow),
              SizedBox(width: 12),
              _RefChip(label: "Psílido", color: Colors.cyan),
              SizedBox(width: 12),
              _RefChip(label: "Otras", color: Colors.purple),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefChip extends StatelessWidget {
  final String label;
  final Color color;
  const _RefChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ============================================================
// STEPPER DE CONTEO (+ / −)
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
// TILE TOGGLE (GPS / foto)
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
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (cargando)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AgroColors.primario),
                  )
                else
                  Icon(activo ? iconoActivo : icono, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cargando ? 'Obteniendo posición…' : (activo ? textoActivo : texto),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: activo ? AgroColors.ok : AgroTheme.colorText,
                        ),
                      ),
                      if (detalle != null)
                        Text(
                          detalle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AgroText.secundario.copyWith(fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
                Icon(
                  activo ? Icons.check_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
