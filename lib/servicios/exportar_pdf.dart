import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../base/base.dart';

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

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/reporte_aplicaciones.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Reporte PDF de Aplicaciones');
  }
}