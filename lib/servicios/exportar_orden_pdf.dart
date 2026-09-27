import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../aplicaciones/calculo_dosis.dart';
import '../aplicaciones/orden_cuadros.dart';
import '../base/base.dart';

class ServicioExportarOrdenPdf {
  // 2x2 cm exactos en puntos tipográficos (1 cm = 28.3465 pt -> 2 cm = 56.7 pt)
  static const double dimLogo2x2Cm = 56.7;

  static const PdfColor colorVerdeBosque = PdfColor.fromInt(0xFF1E6B4C);
  static const PdfColor colorGrisFondo = PdfColor.fromInt(0xFFF9FAF9);
  static const PdfColor colorGrisBorde = PdfColor.fromInt(0xFFE2E8E2);
  static const PdfColor colorTextoPrincipal = PdfColor.fromInt(0xFF1A2E22);
  static const PdfColor colorTextoSecundario = PdfColor.fromInt(0xFF5A6E62);
  static const PdfColor colorDoradoPastel = PdfColor.fromInt(0xFFFFF8E1);
  static const PdfColor colorVerdeSuave = PdfColor.fromInt(0xFFE6F2EC);

  static Future<Uint8List> generarBytesPdf({
    required Map<String, dynamic> orden,
    required String nombreProductor,
    required String cuit,
    required String renspa,
  }) async {
    final pdf = pw.Document();

    // Carga de logotipo con restricción a 2x2 cm
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

    final int codOrden = orden['cod_orden'] is int
        ? orden['cod_orden']
        : int.tryParse(orden['cod_orden']?.toString() ?? '0') ?? 0;
    final String fecha = orden['fecha']?.toString() ?? 'S/F';
    // Una o varias chacras (formato "5, 7" / cuadros "5:1, 7:3").
    final List<String> chacrasOrden =
        chacrasDeOrden(orden['chacra'], orden['cuadros']);
    final String chacra =
        chacrasOrden.isEmpty ? 'S/D' : chacrasOrden.join(', ');
    final bool variasChacras = chacrasOrden.length > 1;

    // Cultivos / variedades a tratar (vacío = todos)
    final Set<String> cultivosF = parsearFiltroOrden(orden['cultivos']);
    final Set<String> variedadesF = parsearFiltroOrden(orden['variedades']);
    final String cultivosTxt = [
      cultivosF.isEmpty ? 'Todos' : (cultivosF.toList()..sort()).join(', '),
      if (variedadesF.isNotEmpty) '(${(variedadesF.toList()..sort()).join(', ')})',
    ].join(' ');
    final String motivo = orden['motivo']?.toString() ?? 'Aplicación Foliar';
    final String momento = orden['momento']?.toString() ?? 'S/D';
    final String volHa = (orden['vol_ha']?.toString() ?? '1000').replaceAll('.0', '');
    final String responsable = orden['responsable']?.toString() ?? 'Ing. Agrónomo';
    final double supTotal = double.tryParse(orden['sup_total_calculada']?.toString() ?? '0') ?? 0.0;

    final List<Map<String, dynamic>> cuadrosDetalle =
        (orden['cuadros_detalle'] as List? ?? []).cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> items =
        (orden['items'] as List? ?? []).cast<Map<String, dynamic>>();

    // Traer parámetros técnicos desde SQLite
    Map<String, dynamic> parametros = {};
    try {
      final db = await DatabaseHelper.instance.database;
      final resParams = await db.query(
        'parametros_aplic',
        where: 'cod_orden = ?',
        whereArgs: [codOrden],
        limit: 1,
      );
      if (resParams.isNotEmpty) {
        parametros = resParams.first;
      }
    } catch (_) {}

    final String velViento = parametros['vel_viento']?.toString() ?? '5-10 km/h';
    final String temperatura = parametros['Temperatura']?.toString() ?? '18-22 °C';
    final String tamGota = parametros['Tamano_gota']?.toString() ?? 'Media (250 µm)';
    final String velAvance = parametros['Vel_Aplicacion']?.toString() ?? '5.5 km/h';
    final String caudalHa = parametros['Caudal_Ha']?.toString() ?? '$volHa L/Ha';

    // Caldo por hectárea para los cálculos de consumo.
    // En recetas_aplicaciones, vol_aplic_ha de cada fila guarda la dosis/Ha
    // (dosis_ha) o 0 (vol_100), así que el caldo real se toma de los
    // parámetros o de la cabecera de la orden.
    double caldoHa = _primerNumero(parametros['Caudal_Ha']) ?? 0.0;
    if (caldoHa <= 0) {
      try {
        final db = await DatabaseHelper.instance.database;
        final cab = await db.query(
          'ordenes_aplicaciones',
          columns: ['vol_aplic_ha'],
          where: 'cod_orden = ?',
          whereArgs: [codOrden.toString()],
          limit: 1,
        );
        if (cab.isNotEmpty) {
          caldoHa = _primerNumero(cab.first['vol_aplic_ha']) ?? 0.0;
        }
      } catch (_) {}
    }
    if (caldoHa <= 0) caldoHa = _primerNumero(volHa) ?? 0.0;
    if (caldoHa <= 0) caldoHa = 1000.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 30),
        footer: (pw.Context context) => _buildFooter(context),
        build: (pw.Context context) => [
          // 1. Encabezado con logo exacto 2x2 cm
          _buildEncabezadoInstitucional(logoImage, codOrden, fecha),
          pw.SizedBox(height: 12),

          // 2. Ficha de Productor y Establecimiento
          _buildFichaEstablecimiento(
            nombreProductor: nombreProductor,
            cuit: cuit,
            renspa: renspa,
            chacra: chacra,
            variasChacras: variasChacras,
            responsable: responsable,
            cultivos: cultivosTxt,
          ),
          pw.SizedBox(height: 10),

          // 3. Parámetros Técnicos de Pulverización (parametros_aplic)
          _buildSeccionTitulo("Parámetros Técnicos de Pulverización"),
          pw.SizedBox(height: 5),
          _buildFichaParametrosCompletos(
            motivo: motivo,
            momento: momento,
            volHa: caudalHa,
            supTotal: supTotal,
            velViento: velViento,
            temperatura: temperatura,
            tamGota: tamGota,
            velAvance: velAvance,
          ),
          pw.SizedBox(height: 12),

          // 4. PRIMERO: Receta Foliar, Dosis y Consumo de Caldo
          _buildSeccionTitulo("Receta de Insumos, Dosificación y Consumo de Caldo"),
          pw.SizedBox(height: 5),
          _buildTablaInsumosConConsumo(items, supTotal, caldoHa),
          pw.SizedBox(height: 12),

          // 5. LUEGO: Detalle de Cuadros a Tratar
          _buildSeccionTitulo("Cuadros y Cuarteles Asignados (${cuadrosDetalle.length})"),
          pw.SizedBox(height: 5),
          _buildTablaCuadros(cuadrosDetalle, supTotal, variasChacras),
          pw.SizedBox(height: 18),

          // 6. Firmas
          _buildAreaFirmas(responsable),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> compartirOrdenPdf({
    required Map<String, dynamic> orden,
    required String nombreProductor,
    required String cuit,
    required String renspa,
  }) async {
    final bytes = await generarBytesPdf(
      orden: orden,
      nombreProductor: nombreProductor,
      cuit: cuit,
      renspa: renspa,
    );

    final int codOrden = orden['cod_orden'];
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Orden_Tecnica_N${codOrden}_$nombreProductor.pdf',
    );
  }

  static Future<void> guardarOImprimirPdf({
    required Map<String, dynamic> orden,
    required String nombreProductor,
    required String cuit,
    required String renspa,
  }) async {
    final bytes = await generarBytesPdf(
      orden: orden,
      nombreProductor: nombreProductor,
      cuit: cuit,
      renspa: renspa,
    );

    final int codOrden = orden['cod_orden'];
    await Printing.layoutPdf(
      name: 'Orden_Tecnica_$codOrden.pdf',
      onLayout: (_) async => bytes,
    );
  }

  // ===========================================================================
  // WIDGETS DEL PDF
  // ===========================================================================

  static pw.Widget _buildEncabezadoInstitucional(
    pw.MemoryImage? logoImage,
    int codOrden,
    String fecha,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: colorGrisFondo,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: colorGrisBorde, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Logo 2x2 cm exactos
              pw.Container(
                width: dimLogo2x2Cm,
                height: dimLogo2x2Cm,
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: colorGrisBorde, width: 0.8),
                ),
                child: logoImage != null
                    ? pw.ClipRRect(
                        horizontalRadius: 6,
                        verticalRadius: 6,
                        child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                      )
                    : pw.Center(
                        child: pw.Text(
                          "AS",
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: colorVerdeBosque,
                          ),
                        ),
                      ),
              ),
              pw.SizedBox(width: 12),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    "AGROSOFT J&L",
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: colorTextoPrincipal,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "Ingeniería Aplicada & Gestión Agronómica",
                    style: const pw.TextStyle(fontSize: 9, color: colorTextoSecundario),
                  ),
                  pw.Text(
                    "Certificación de Buenas Prácticas Agrícolas (BPA)",
                    style: const pw.TextStyle(fontSize: 8, color: colorTextoSecundario),
                  ),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: const pw.BoxDecoration(
                  color: colorVerdeBosque,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(
                  "ORDEN TÉCNICA #$codOrden",
                  style: pw.TextStyle(
                    fontSize: 11.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                "Fecha Emisión: $fecha",
                style: const pw.TextStyle(fontSize: 9, color: colorTextoSecundario),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFichaEstablecimiento({
    required String nombreProductor,
    required String cuit,
    required String renspa,
    required String chacra,
    bool variasChacras = false,
    required String responsable,
    String cultivos = 'Todos',
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: colorGrisBorde, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildDatoLinea("Establecimiento:", nombreProductor, bold: true),
                pw.SizedBox(height: 2),
                _buildDatoLinea("CUIT:", cuit),
              ],
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              
              children: [
                _buildDatoLinea(
                    variasChacras ? "Chacras:" : "Chacra:", chacra,
                    bold: true),
                pw.SizedBox(height: 2),
                _buildDatoLinea("RENSPA:", renspa),
              ],
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              
              children: [
                _buildDatoLinea("Responsable:", responsable),
                pw.SizedBox(height: 2),
                _buildDatoLinea("Cultivos:", cultivos, bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFichaParametrosCompletos({
    required String motivo,
    required String momento,
    required String volHa,
    required double supTotal,
    required String velViento,
    required String temperatura,
    required String tamGota,
    required String velAvance,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: colorGrisFondo,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: colorGrisBorde, width: 0.8),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                flex: 4,
                child: _buildDatoLinea("Objetivo / Motivo:", motivo, bold: true),
              ),
              pw.Expanded(
                flex: 3,
                child: _buildDatoLinea("Momento:", momento.isEmpty ? "No especificado" : momento),
              ),
              pw.Expanded(
                flex: 2,
                child: _buildDatoLinea("Caudal:", volHa),
              ),
              pw.Expanded(
                flex: 2,
                child: _buildDatoLinea("Sup. Total:", "${supTotal.toStringAsFixed(2)} Ha", bold: true),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Container(height: 0.5, color: colorGrisBorde),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: _buildDatoLinea("Vel. Viento:", velViento)),
              pw.Expanded(child: _buildDatoLinea("Temperatura:", temperatura)),
              pw.Expanded(child: _buildDatoLinea("Tamaño Gota:", tamGota)),
              pw.Expanded(child: _buildDatoLinea("Vel. Avance:", velAvance)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTablaInsumosConConsumo(
    List<Map<String, dynamic>> items,
    double supTotal,
    double caldoHa,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: colorGrisBorde, width: 0.7),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: colorGrisFondo),
          children: [
            _buildCeldaHeader("Ord", width: 22, align: pw.TextAlign.center),
            _buildCeldaHeader("Producto / Principio Activo", align: pw.TextAlign.left),
            _buildCeldaHeader("Dosis Prescripta", align: pw.TextAlign.center),
            _buildCeldaHeader("Dosis x Máq (2000L)", align: pw.TextAlign.right),
            _buildCeldaHeader("Consumo Total", align: pw.TextAlign.right),
            _buildCeldaHeader("T.C.", width: 34, align: pw.TextAlign.center),
            _buildCeldaHeader("T.R.I.", width: 36, align: pw.TextAlign.center),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final it = entry.value;
          final prod = it['producto']?.toString() ?? 'Insumo';
          final tc = it['tc']?.toString() ?? it['T_C']?.toString() ?? '0';
          final ti = it['ti']?.toString() ?? it['TRI']?.toString() ?? '0';

          // Por 100 L: cantMaq = Sup × caldo ÷ 2000 ; total = cantMaq × dosisMaq
          // Por Ha   : total = dosis/Ha × Sup
          final double dosisMaq = CalculoDosis.dosisMaquina(it, caldoHa);
          final double consumoTotal =
              CalculoDosis.cantidadProducto(it, supTotal, caldoHa);

          return pw.TableRow(
            children: [
              _buildCelda("$idx", align: pw.TextAlign.center),
              _buildCelda(prod, bold: true),
              _buildCelda(CalculoDosis.textoDosis(it), align: pw.TextAlign.center),
              _buildCelda("${dosisMaq.toStringAsFixed(2)} L/Kg",
                  align: pw.TextAlign.right, bold: true),
              _buildCelda("${consumoTotal.toStringAsFixed(2)} L/Kg",
                  align: pw.TextAlign.right, bold: true),
              _buildCelda("${tc}d", align: pw.TextAlign.center),
              _buildCelda("${ti}hs", align: pw.TextAlign.center),
            ],
          );
        }),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: colorDoradoPastel),
          children: [
            _buildCelda(""),
            _buildCelda(
                "Máquinas de ${CalculoDosis.volumenMaquina.toStringAsFixed(0)} L: "
                "${CalculoDosis.cantidadMaquinas(supTotal, caldoHa).toStringAsFixed(2)}  "
                "(${supTotal.toStringAsFixed(2)} Ha × ${caldoHa.toStringAsFixed(0)} L/Ha)",
                bold: true),
            _buildCelda(""),
            _buildCelda(""),
            _buildCelda(""),
            _buildCelda(""),
            _buildCelda(""),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTablaCuadros(
    List<Map<String, dynamic>> cuadrosDetalle,
    double supTotal,
    bool variasChacras,
  ) {
    pw.TableRow filaCuadro(Map<String, dynamic> c) {
      final String nomCuadro = c['cuadro']?.toString() ?? 'S/N';
      final String cultivo = c['cultivo']?.toString() ?? 'Frutales';
      final String variedad = c['variedad']?.toString() ?? 'S/D';
      final double ha = double.tryParse(c['ha']?.toString() ?? '0') ?? 0.0;
      return pw.TableRow(
        children: [
          _buildCelda("Cuadro $nomCuadro", bold: true),
          _buildCelda(cultivo.isEmpty ? "General" : cultivo),
          _buildCelda(variedad),
          _buildCelda("${ha.toStringAsFixed(2)} Ha", align: pw.TextAlign.right),
        ],
      );
    }

    final List<pw.TableRow> cuerpo = [];

    if (!variasChacras) {
      cuerpo.addAll(cuadrosDetalle.map(filaCuadro));
    } else {
      // Agrupado por chacra, con subtotal de cada una.
      final Map<String, List<Map<String, dynamic>>> grupos = {};
      for (final c in cuadrosDetalle) {
        final ch = (c['chacra'] ?? 'S/D').toString();
        grupos.putIfAbsent(ch, () => []).add(c);
      }
      final claves = grupos.keys.toList()..sort(compararNatural);
      for (final ch in claves) {
        final filas = grupos[ch]!;
        final double sub = filas.fold(
            0.0, (s, c) => s + (double.tryParse(c['ha']?.toString() ?? '0') ?? 0.0));
        cuerpo.add(pw.TableRow(
          decoration: const pw.BoxDecoration(color: colorVerdeSuave),
          children: [
            _buildCelda("CHACRA $ch", bold: true, color: colorVerdeBosque),
            _buildCelda("${filas.length} ${filas.length == 1 ? 'cuadro' : 'cuadros'}",
                color: colorVerdeBosque),
            _buildCelda(""),
            _buildCelda("${sub.toStringAsFixed(2)} Ha",
                align: pw.TextAlign.right, bold: true, color: colorVerdeBosque),
          ],
        ));
        cuerpo.addAll(filas.map(filaCuadro));
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(color: colorGrisBorde, width: 0.7),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: colorGrisFondo),
          children: [
            _buildCeldaHeader("Cuartel / Cuadro", align: pw.TextAlign.left),
            _buildCeldaHeader("Cultivo", align: pw.TextAlign.left),
            _buildCeldaHeader("Variedad", align: pw.TextAlign.left),
            _buildCeldaHeader("Superficie Tratada", align: pw.TextAlign.right),
          ],
        ),
        ...cuerpo,
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: colorDoradoPastel),
          children: [
            _buildCelda("TOTAL SUPERFICIE TRATADA", bold: true),
            _buildCelda(""),
            _buildCelda(""),
            _buildCelda("${supTotal.toStringAsFixed(2)} Ha", align: pw.TextAlign.right, bold: true),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildAreaFirmas(String responsable) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Container(width: 160, height: 0.8, color: colorGrisBorde),
                pw.SizedBox(height: 4),
                pw.Text(
                  responsable,
                  style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: colorTextoPrincipal),
                ),
                pw.Text(
                  "Asesor Técnico / Ing. Agrónomo",
                  style: const pw.TextStyle(fontSize: 8, color: colorTextoSecundario),
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Container(width: 160, height: 0.8, color: colorGrisBorde),
                pw.SizedBox(height: 4),
                pw.Text(
                  "Firma Aplicador / Tractorista",
                  style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: colorTextoPrincipal),
                ),
                pw.Text(
                  "Conformidad de Aplicación en Campo",
                  style: const pw.TextStyle(fontSize: 8, color: colorTextoSecundario),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: colorGrisBorde, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "AgroSoft J&L · Cuaderno de Campo Oficial · Sistema de Pulverizaciones",
            style: const pw.TextStyle(fontSize: 8, color: colorTextoSecundario),
          ),
          pw.Text(
            "Página ${context.pageNumber} de ${context.pagesCount}",
            style: const pw.TextStyle(fontSize: 8, color: colorTextoSecundario),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static pw.Widget _buildSeccionTitulo(String titulo) {
    return pw.Row(
      children: [
        pw.Container(width: 3.5, height: 11, color: colorVerdeBosque),
        pw.SizedBox(width: 6),
        pw.Text(
          titulo,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: colorTextoPrincipal,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildDatoLinea(String etiqueta, String valor, {bool bold = false}) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: "$etiqueta ",
            style: const pw.TextStyle(
              fontSize: 8.5,
              color: colorTextoSecundario,
            ),
          ),
          pw.TextSpan(
            text: valor,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: colorTextoPrincipal,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCeldaHeader(
    String texto, {
    double? width,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        texto,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: colorTextoPrincipal,
        ),
      ),
    );
  }

  static pw.Widget _buildCelda(
    String texto, {
    bool bold = false,
    int colSpan = 1,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor color = colorTextoPrincipal,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        texto,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  /// Primer número dentro de un texto: "1000 L/Ha" → 1000.
  static double? _primerNumero(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(v.toString());
    if (m == null) return null;
    return double.tryParse(m.group(0)!.replaceAll(',', '.'));
  }

}