import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

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

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
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
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _trampasFiltradas {
    if (_chacraSeleccionada == "TODAS") return _todasTrampas;
    return _todasTrampas
        .where((t) => (t['chacra'] ?? '').toString() == _chacraSeleccionada)
        .toList();
  }

  // ==========================================================================
  // 🗺️ PANTALLA COMPLETA DE MAPA SATELITAL CON PINS POR PLAGA Y DETALLE
  // ==========================================================================
  void _abrirMapaGlobalTrampas() {
    final trampasConGps = _trampasFiltradas.where((t) {
      final u = t['ubicacion']?.toString() ?? '';
      return u.contains(',') && u.split(',').length >= 2;
    }).toList();

    if (trampasConGps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AgroTheme.colorDanger,
          content: Text('No hay trampas con coordenadas GPS válidas en este sector.'),
        ),
      );
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
  // 💡 FORMULARIO MODAL: UBICAR TRAMPA (QR + GPS + CÁMARA)
  // ==========================================================================
  void _abrirModalInstalarTrampa() async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AgroTheme.colorDanger,
            content: Text('No hay cuarteles registrados en el inventario para este productor.'),
          ),
        );
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
    File? fotoEvidenciaTrampa;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                      const Text(
                        "Ubicar Trampa de Plagas",
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                            color: AgroTheme.colorText),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(color: AgroTheme.colorBorder),
                  const SizedBox(height: 8),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: claveCuartelSeleccionado,
                            isExpanded: true,
                            decoration: _inputDecoration("Chacra y Cuadro"),
                            items: cuarteles.map((c) {
                              final clave = generarClave(c);
                              return DropdownMenuItem<String>(
                                value: clave,
                                child: Text(
                                  "${c['chacra']} · Cuadro ${c['cuadro']} (${c['variedad']})",
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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

                          DropdownButtonFormField<String>(
                            value: tipoPlaga,
                            isExpanded: true,
                            decoration: _inputDecoration("Plaga / Tipo de Trampa"),
                            items: const [
                              DropdownMenuItem(
                                  value: "CARPOCAPSA (Cydia pomonella)",
                                  child: Text("Carpocapsa (Delta con Feromona)")),
                              DropdownMenuItem(
                                  value: "GRAFOLITA (Grapholita molesta)",
                                  child: Text("Grafolita (Delta con Feromona)")),
                              DropdownMenuItem(
                                  value: "MOSCA DE LOS FRUTOS (Ceratitis)",
                                  child: Text("Mosca de los Frutos (Jackson/Polillero)")),
                              DropdownMenuItem(
                                  value: "PSILIDO DE LA PERA (Cacopsylla)",
                                  child: Text("Psílido del Peral (Placa Amarilla)")),
                            ],
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
                                  decoration: _inputDecoration("N° o Código de Trampa"),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _abrirEscannerQR((codigoLeido) {
                                  setModalState(() {
                                    nroTrampaCtrl.text = codigoLeido;
                                  });
                                }),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AgroTheme.colorAccentSoft,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AgroTheme.colorAccent),
                                  ),
                                  child: const Icon(Icons.qr_code_scanner_rounded,
                                      color: AgroTheme.colorAccentDark, size: 22),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: filaCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration("Fila / Hilera"),
                          ),
                          const SizedBox(height: 14),

                          // Coordenadas GPS
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AgroTheme.colorBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AgroTheme.colorBorder),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.my_location_rounded,
                                        color: Color(0xFFB8862A), size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      gpsCoords.isNotEmpty
                                          ? "GPS: $gpsCoords"
                                          : "Sin coordenadas fijadas",
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: capturandoGps
                                      ? null
                                      : () async {
                                          setModalState(() => capturandoGps = true);
                                          try {
                                            LocationPermission perm =
                                                await Geolocator.checkPermission();
                                            if (perm == LocationPermission.denied) {
                                              perm = await Geolocator.requestPermission();
                                            }
                                            final pos = await Geolocator.getCurrentPosition();
                                            setModalState(() {
                                              gpsCoords =
                                                  "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
                                            });
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Error GPS: $e')),
                                              );
                                            }
                                          }
                                          setModalState(() => capturandoGps = false);
                                        },
                                  child: capturandoGps
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text(
                                          "Fijar Posición",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFFB8862A)),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Cámara
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
                                    fotoEvidenciaTrampa = File(foto.path);
                                  });
                                }
                              } catch (_) {}
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: fotoEvidenciaTrampa != null
                                    ? AgroTheme.colorAccentSoft
                                    : AgroTheme.colorBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: fotoEvidenciaTrampa != null
                                      ? AgroTheme.colorAccent
                                      : AgroTheme.colorBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt_outlined,
                                    size: 18,
                                    color: fotoEvidenciaTrampa != null
                                        ? AgroTheme.colorAccentDark
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    fotoEvidenciaTrampa != null
                                        ? "Evidencia de Trampa Lista ✓"
                                        : "Fotografiar Trampa / Placa",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: fotoEvidenciaTrampa != null
                                          ? AgroTheme.colorAccentDark
                                          : AgroTheme.colorText,
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

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: SoftButton(
                      onTap: () async {
                        if (nroTrampaCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingresá el número o escaneá el QR')),
                          );
                          return;
                        }

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
                          'url_evidencia': fotoEvidenciaTrampa?.path,
                          'cod_establecimiento': widget.codProductor,
                          'sincronizado': 0,
                        });

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _cargarDatos();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AgroTheme.colorAccent,
                              content: Text('Trampa ubicada con éxito'),
                            ),
                          );
                        }
                      },
                      child: const Center(
                        child: Text(
                          "Guardar Ubicación de Trampa",
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

  void _abrirEscannerQR(Function(String) onCodeFound) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(
            title: const Text("Escanear Código de Trampa",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            backgroundColor: Colors.black87,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String valor = barcodes.first.rawValue ?? '';
                if (valor.isNotEmpty) {
                  Navigator.pop(c);
                  onCodeFound(valor);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  void _mostrarModalLectura(Map<String, dynamic> trampa) {
    DateTime fechaSeleccionada = DateTime.now();
    final fechaCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(fechaSeleccionada));
    final machosCtrl = TextEditingController(text: "0");
    final hembrasVirgCtrl = TextEditingController(text: "0");
    final hembrasGravCtrl = TextEditingController(text: "0");
    File? fotoLectura;

    String obtenerSemana(DateTime f) {
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
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
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
                  Text(
                    "Lectura: Trampa N° ${trampa['trampa_numero']}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16.5,
                        color: AgroTheme.colorText),
                  ),
                  Text(
                    "${trampa['chacra']} · Cuadro ${trampa['cuadro']} (${trampa['tipo_trampa']})",
                    style: const TextStyle(
                        fontSize: 11.5, color: AgroTheme.colorTextSecondary),
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
                                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: const Icon(Icons.calendar_today_rounded,
                                  size: 18, color: AgroTheme.colorAccentDark),
                            ),
                          ),
                          const SizedBox(height: 14),

                          const Text(
                            "Capturas de la Semana:",
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AgroTheme.colorText),
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: _buildContadorMini("Machos", machosCtrl, () => setModalState(() {})),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildContadorMini("H. Vírgenes", hembrasVirgCtrl, () => setModalState(() {})),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildContadorMini("H. Grávidas", hembrasGravCtrl, () => setModalState(() {})),
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
                                    fotoLectura = File(foto.path);
                                  });
                                }
                              } catch (_) {}
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: fotoLectura != null ? AgroTheme.colorAccentSoft : AgroTheme.colorBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: fotoLectura != null ? AgroTheme.colorAccent : AgroTheme.colorBorder),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_outlined,
                                      size: 18,
                                      color: fotoLectura != null ? AgroTheme.colorAccentDark : Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(
                                    fotoLectura != null ? "Evidencia Lista ✓" : "Fotografiar Placa",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: fotoLectura != null ? AgroTheme.colorAccentDark : AgroTheme.colorText),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: alertaUmbral ? const Color(0xFFFEF2F2) : AgroTheme.colorAccentSoft,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: alertaUmbral
                                      ? AgroTheme.colorDanger.withOpacity(0.5)
                                      : AgroTheme.colorAccent),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  alertaUmbral ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                                  color: alertaUmbral ? AgroTheme.colorDanger : AgroTheme.colorAccentDark,
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
                                    color: alertaUmbral ? AgroTheme.colorDanger : AgroTheme.colorAccentDark,
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
                        final String semanaCalculada = obtenerSemana(fechaSeleccionada);

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
                          'url_evidencia': fotoLectura?.path,
                          'cod_establecimiento': widget.codProductor,
                          'sincronizado': 0,
                        });

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _cargarDatos();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AgroTheme.colorAccent,
                              content: Text('¡Lectura guardada para $semanaCalculada con éxito!'),
                            ),
                          );
                        }
                      },
                      child: const Center(
                        child: Text("Guardar Lectura",
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
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

  // ==========================================================================
  // 💡 MODAL DE CURVA COMPACTA CON BOTÓN PDF EN CABECERA
  // ==========================================================================
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
                          "Curva Semanal · TR #${trampa['trampa_numero']}",
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16, color: AgroTheme.colorText),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "${trampa['chacra']} · Cd. ${trampa['cuadro']} · ${trampa['tipo_trampa']}",
                          style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      // 💡 Botón PDF oficial colocado arriba junto a la cruz
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf_outlined,
                            color: AgroTheme.colorAccentDark, size: 22),
                        tooltip: "Exportar Reporte Semanal en PDF",
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

              Expanded(
                child: lecturas.isEmpty
                    ? const Center(
                        child: Text("No hay recuentos semanales cargados aún.",
                            style: TextStyle(color: AgroTheme.colorTextSecondary)))
                    : ListView.separated(
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
                              color: alertaUmbral ? const Color(0xFFFEF2F2) : AgroTheme.colorBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: alertaUmbral
                                    ? AgroTheme.colorDanger.withOpacity(0.4)
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
                                    color: alertaUmbral ? AgroTheme.colorDanger : AgroTheme.colorText,
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
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: alertaUmbral
                                                ? [AgroTheme.colorDanger, const Color(0xFFF87171)]
                                                : [AgroTheme.colorAccentDark, AgroTheme.colorAccent],
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Center(
                                          child: Text(
                                            "$total",
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900),
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
                                        size: 14, color: AgroTheme.colorAccentDark),
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
        );
      },
    );
  }

  // ==========================================================================
  // 📄 EXPORTACIÓN PDF PROFESIONAL CON GRÁFICO DE CURVA
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

    final List<int> bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Reporte_Trampa_${trampa['trampa_numero']}.pdf');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: 'Reporte de Trampa N° ${trampa['trampa_numero']} - ${widget.nombreProductor}',
    );
  }

  void _verFoto(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
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

  Widget _buildContadorMini(String label, TextEditingController ctrl, VoidCallback onChanged) {
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
          Text(label,
              style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: AgroTheme.colorTextSecondary)),
          const SizedBox(height: 2),
          TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AgroTheme.colorTextSecondary),
      filled: true,
      fillColor: AgroTheme.colorBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd), borderSide: BorderSide.none),
    );
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
            const Text("Ubicación y Trampeo",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText)),
            Text(widget.nombreProductor,
                style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          // 💡 Botón Pin para abrir el mapa satelital interactivo
          IconButton(
            icon: const Icon(Icons.map_rounded, color: AgroTheme.colorAccentDark, size: 24),
            tooltip: "Ver Mapa Satelital de Trampas",
            onPressed: _abrirMapaGlobalTrampas,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_chacrasDisponibles.length > 1)
              Container(
                height: 42,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _chacrasDisponibles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final ch = _chacrasDisponibles[idx];
                    final isSelected = _chacraSeleccionada == ch;

                    return ChoiceChip(
                      label: Text(ch == "TODAS" ? "Todas las Chacras" : "Chacra $ch"),
                      selected: isSelected,
                      selectedColor: AgroTheme.colorAccentDark,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : AgroTheme.colorText,
                      ),
                      backgroundColor: AgroTheme.colorSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                            color: isSelected ? AgroTheme.colorAccentDark : AgroTheme.colorBorder),
                      ),
                      onSelected: (selected) {
                        if (selected) setState(() => _chacraSeleccionada = ch);
                      },
                    );
                  },
                ),
              ),

            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: AgroTheme.colorAccent))
                  : _trampasFiltradas.isEmpty
                      ? const Center(child: Text("No hay trampas ubicadas en este sector."))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                          itemCount: _trampasFiltradas.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final trampa = _trampasFiltradas[idx];
                            final fechaStr =
                                trampa['created_at']?.toString().split('T').first ?? '';
                            final String? fotoUrl = trampa['url_evidencia']?.toString();

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AgroTheme.colorSurface,
                                borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                                border: Border.all(color: AgroTheme.colorBorder),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x04141E18), blurRadius: 8, offset: Offset(0, 2)),
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
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: const Color(0xFFB8862A),
                                                borderRadius: BorderRadius.circular(6)),
                                            child: Text(
                                              "TRAMPA #${trampa['trampa_numero']}",
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 11),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text("Chacra: ${trampa['chacra']}",
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700, fontSize: 13)),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          if (fotoUrl != null && fotoUrl.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.image_outlined,
                                                  size: 20, color: AgroTheme.colorAccentDark),
                                              onPressed: () => _verFoto(fotoUrl),
                                              tooltip: "Ver Foto de Trampa",
                                            ),
                                          Text(fechaStr,
                                              style: const TextStyle(
                                                  fontSize: 11.5, color: AgroTheme.colorTextSecondary)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  Text(
                                    trampa['tipo_trampa'] ?? 'Plaga no definida',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                        color: AgroTheme.colorText),
                                  ),
                                  const SizedBox(height: 8),

                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                        color: AgroTheme.colorBg,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("Cuadro: ${trampa['cuadro']}",
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.w700)),
                                        Text("Fila: ${trampa['fila']}",
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.w600)),
                                        Text("${trampa['cultivo']} - ${trampa['variedad']}",
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AgroTheme.colorTextSecondary)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      SoftButton(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 7),
                                        borderRadius: 8,
                                        onTap: () => _mostrarModalLectura(trampa),
                                        child: Row(
                                          children: const [
                                            Icon(Icons.add_task_rounded,
                                                size: 14, color: Colors.white),
                                            SizedBox(width: 5),
                                            Text("Lectura",
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 11.5)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SoftButton(
                                        isSecondary: true,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 7),
                                        borderRadius: 8,
                                        onTap: () => _mostrarReporteSemanas(trampa),
                                        child: Row(
                                          children: const [
                                            Icon(Icons.show_chart_rounded,
                                                size: 14, color: AgroTheme.colorAccentDark),
                                            SizedBox(width: 5),
                                            Text("Curva",
                                                style: TextStyle(
                                                    color: AgroTheme.colorAccentDark,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 11.5)),
                                          ],
                                        ),
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
      floatingActionButton: SoftButton(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        borderRadius: 28,
        onTap: _abrirModalInstalarTrampa,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add_location_alt_outlined, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text("Ubicar Trampa",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 🗺️ VISTA COMPLETA: MAPA SATELITAL CON PINS POR COLOR Y TRAMPAS
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
  late GoogleMapController _mapController;
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

          final String codTr = t['cod_trampa'] ?? '';
          final String nro = t['trampa_numero'] ?? '';
          final String plaga = t['tipo_trampa'] ?? 'Plaga';

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
        backgroundColor: Colors.black87,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Mapa Satelital de Trampas",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
            Text(widget.nombreProductor,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _currentMapType == MapType.hybrid ? Icons.satellite_alt_rounded : Icons.map_outlined,
              color: Colors.white,
            ),
            tooltip: "Alternar Capa Satélite/Normal",
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

          // 💡 REFERENCIAS DE PLAGAS ARRIBA
          PositionEdgeWidget(),
        ],
      ),
    );
  }
}

class PositionEdgeWidget extends StatelessWidget {
  const PositionEdgeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 14,
      right: 14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.82),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: const [
              _RefChip(label: "Carpocapsa", color: Colors.red),
              SizedBox(width: 10),
              _RefChip(label: "Grafolita", color: Colors.orange),
              SizedBox(width: 10),
              _RefChip(label: "Mosca Frutos", color: Colors.yellow),
              SizedBox(width: 10),
              _RefChip(label: "Psílido", color: Colors.cyan),
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