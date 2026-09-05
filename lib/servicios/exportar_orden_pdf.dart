import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../base/base.dart';

class ServicioExportarOrdenPdf {
  static Future<void> compartirOrdenPdf({
    required Map<String, dynamic> orden,
    required String nombreProductor,
    required String cuit,
    required String renspa,
  }) async {
    final pdf = pw.Document();
    final db = await DatabaseHelper.instance.database;

    // 💡 Carga del logo con fallback seguro si no existe en assets
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
        : int.tryParse(orden['cod_orden'].toString()) ?? 0;
    final String fecha = orden['fecha']?.toString() ?? 'S/F';
    final String chacra = orden['chacra']?.toString() ?? 'S/D';
    final String cuadros = orden['cuadros']?.toString() ?? 'S/D';
    final String motivo = orden['motivo']?.toString() ?? 'Aplicación Fitosanitaria';
    final String momento = orden['momento']?.toString() ?? 'A determinar';
    final String volHa = orden['vol_ha']?.toString() ?? '1000';
    final String responsable = orden['responsable']?.toString() ?? 'Ingeniero Agrónomo';

    final List<Map<String, dynamic>> itemsRaw =
        (orden['items'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];

    // =========================================================================
    // 💡 CONSULTA A catalogo_insumos PARA OBTENER T_C Y TRI REALES
    // =========================================================================
    final List<Map<String, dynamic>> itemsEnriquecidos = [];

    for (var item in itemsRaw) {
      final itemModificado = Map<String, dynamic>.from(item);

      final dynamic codProd = item['cod_producto'] ?? item['ID_Insumos'];
      final String nombreProd = (item['producto'] ?? item['Descripcion1'] ?? '').toString().trim();

      List<Map<String, dynamic>> resCatalogo = [];

      // 1. Búsqueda por ID_Insumos si existe
      if (codProd != null && codProd.toString().isNotEmpty && codProd.toString() != '0') {
        resCatalogo = await db.query(
          'catalogo_insumos',
          columns: ['T_C', 'TRI', 'principio_activo'],
          where: 'ID_Insumos = ?',
          whereArgs: [codProd],
          limit: 1,
        );
      }

      // 2. Búsqueda por nombre de producto si no se encontró por ID
      if (resCatalogo.isEmpty && nombreProd.isNotEmpty) {
        resCatalogo = await db.query(
          'catalogo_insumos',
          columns: ['T_C', 'TRI', 'principio_activo'],
          where: 'LOWER(TRIM(Descripcion1)) = LOWER(?)',
          whereArgs: [nombreProd],
          limit: 1,
        );
      }

      // Si existe en el catálogo, asignamos los valores reales; sino, usamos los que traía el ítem
      if (resCatalogo.isNotEmpty) {
        final cat = resCatalogo.first;
        itemModificado['T_C'] = cat['T_C'] ?? item['T_C'] ?? item['tc'];
        itemModificado['TRI'] = cat['TRI'] ?? item['TRI'] ?? item['ti'];
        if ((itemModificado['principio_activo'] == null ||
                itemModificado['principio_activo'].toString().isEmpty) &&
            cat['principio_activo'] != null) {
          itemModificado['principio_activo'] = cat['principio_activo'];
        }
      } else {
        itemModificado['T_C'] = item['T_C'] ?? item['tc'];
        itemModificado['TRI'] = item['TRI'] ?? item['ti'];
      }

      itemsEnriquecidos.add(itemModificado);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logoImage != null)
                        pw.Container(
                          width: 50,
                          height: 50,
                          margin: const pw.EdgeInsets.only(right: 12),
                          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                        )
                      else
                        pw.Container(
                          width: 50,
                          height: 50,
                          margin: const pw.EdgeInsets.only(right: 12),
                          decoration: pw.BoxDecoration(
                            color: const PdfColor.fromInt(0xFF1E6B4C),
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          child: pw.Center(
                            child: pw.Text('AGRO',
                                style: pw.TextStyle(
                                    color: PdfColors.white,
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                        ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("AGROSOFT J&L",
                              style: pw.TextStyle(
                                  fontSize: 15,
                                  fontWeight: pw.FontWeight.bold,
                                  color: const PdfColor.fromInt(0xFF123F2C))),
                          pw.Text("SOLUCIONES INTEGRALES AGROPECUARIAS",
                              style: const pw.TextStyle(
                                  fontSize: 8, color: PdfColors.grey700)),
                          pw.Text("CHIMPAY · RÍO NEGRO",
                              style: const pw.TextStyle(
                                  fontSize: 8, color: PdfColors.grey600)),
                        ],
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFF3F5F1),
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(
                          color: const PdfColor.fromInt(0xFF1E6B4C), width: 1),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("ORDEN TÉCNICA",
                            style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF1E6B4C))),
                        pw.Text("#$codOrden",
                            style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF1B231D))),
                        pw.Text("Fecha: $fecha",
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey800)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF1E6B4C)),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(thickness: 0.8, color: PdfColors.grey400),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "Powered by AgroSoft J&L Soluciones Integrales - jsosa190585@gmail.com - Chimpay, Río Negro",
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                  ),
                  pw.Text(
                    "Pág. ${context.pageNumber} de ${context.pagesCount}",
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF9FAFB),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB)),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: _buildInfoItem("PRODUCTOR / RAZÓN SOCIAL", nombreProductor),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: _buildInfoItem("CUIT", cuit),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: _buildInfoItem("RENSPA", renspa),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 2,
                      child: _buildInfoItem("ESTABLECIMIENTO / CHACRA", chacra),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: _buildInfoItem("CUARTEL / CUADROS APLICADOS", cuadros),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: _buildInfoItem("VOLUMEN CALDO", "$volHa Lts / Ha"),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: _buildInfoItem("MOTIVO TÉCNICO", motivo),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: _buildInfoItem("MOMENTO O ESTADO FENOLÓGICO", momento),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          pw.Text("DETALLE DE LA RECETA Y DOSIFICACIÓN (MÁQUINA 2.000 LTS)",
              style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF1E6B4C))),
          pw.SizedBox(height: 6),

          // 💡 Tabla con T_C (días) y TRI (horas) garantizados desde el catálogo
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
            headerStyle: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E6B4C)),
            cellStyle: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            headers: [
              '#',
              'PRODUCTO / PRINCIPIO ACTIVO',
              'DOSIS / 100L',
              'DOSIS x MÁQ (2.000L)',
              'T.C.',
              'T.R.I.'
            ],
            data: itemsEnriquecidos.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final item = entry.value;

              final String tcValor = (item['T_C'] != null && item['T_C'].toString().isNotEmpty && item['T_C'].toString() != '0')
                  ? "${item['T_C']} d"
                  : "S/D";

              final String triValor = (item['TRI'] != null && item['TRI'].toString().isNotEmpty && item['TRI'].toString() != '0')
                  ? "${item['TRI']} hs"
                  : "S/D";

              return [
                idx.toString(),
                item['producto']?.toString() ?? item['Descripcion1']?.toString() ?? '',
                "${item['dosis_100'] ?? '0'} Lts/Kg",
                "${item['dosis_maq'] ?? '0'} Lts/Kg",
                tcValor,
                triValor,
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 14),

          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFFFBEB),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFFDE68A)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("INDICACIONES GENERALES DE SEGURIDAD:",
                    style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF92400E))),
                pw.SizedBox(height: 3),
                pw.Text(
                  "• Respetar estrictamente el Tiempo de Carencia (T.C.) y Tiempo de Reingreso (T.R.I.) antes de cosechar o ingresar al cuadro.\n"
                  "• Usar equipo de protección personal completo (máscara con filtro, mameluco impermeable, guantes de nitrilo).\n"
                  "• Verificar condiciones meteorológicas: viento < 10 km/h y temperatura adecuada antes de comenzar la labor.",
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF78350F), lineSpacing: 1.5),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 36),

          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Container(width: 180, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(responsable,
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text("RESPONSABLE TÉCNICO",
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(width: 180, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text("FIRMA DEL OPERARIO / APLICADOR",
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text("CONFORMIDAD DE LABOR",
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

// 1. Guardar los bytes del documento
final Uint8List bytes = await pdf.save();
final String nombreArchivo = 'Orden_Aplicacion_$codOrden.pdf';

if (kIsWeb) {
  // 💡 Solución Web / Safari: Dispara la descarga o visor nativo sin tocar disco
  await Printing.sharePdf(
    bytes: bytes,
    filename: nombreArchivo,
  );
} else {
  // Móvil nativo (Android / iOS clásico): Se envía directamente en memoria con XFile.fromData
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        name: nombreArchivo,
        mimeType: 'application/pdf',
      ),
    ],
    text: 'Orden Técnica de Aplicación Foliar #$codOrden - $nombreProductor',
  );
}
  }

  static pw.Widget _buildInfoItem(String label, String valor) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 6.5,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF5F6B62))),
        pw.SizedBox(height: 1),
        pw.Text(valor,
            style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF1B231D))),
      ],
    );
  }
}