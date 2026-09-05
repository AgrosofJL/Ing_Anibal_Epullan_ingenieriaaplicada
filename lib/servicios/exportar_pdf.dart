import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../base/base.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class ServicioExportacionPdf {
  static Future<void> exportarRecetasPdf() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> registros =
        await db.query('recetas_aplicaciones', where: 'habilitado = ?', whereArgs: ['ACTIVO']);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text('REPORTE DE APLICACIONES FOLIARES',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          ),
          pw.TableHelper.fromTextArray(
            headers: ['Receta', 'Fecha', 'Productor', 'Chacra', 'Producto', 'Dosis Maq'],
            data: registros
                .map((r) => [
                      r['cod_receta']?.toString() ?? '',
                      r['fecha']?.toString() ?? '',
                      r['productor']?.toString() ?? '',
                      r['chacra']?.toString() ?? '',
                      r['producto']?.toString() ?? '',
                      r['dosis_maq']?.toString() ?? '',
                    ])
                .toList(),
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
const String nombreArchivo = 'reporte_aplicaciones.pdf';

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
    text: 'Reporte PDF de Aplicaciones',
  );
}
  }
}