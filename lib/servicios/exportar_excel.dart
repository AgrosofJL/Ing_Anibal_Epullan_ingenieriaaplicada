import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../base/base.dart';

class ServicioExportacionExcel {
  static Future<void> exportarRecetas() async {
    final db = await DatabaseHelper.instance.database;

    // Traer siempre el detalle con estado activo
    final List<Map<String, dynamic>> registros = await db.query(
      'recetas_aplicaciones',
      where: 'habilitado = ?',
      whereArgs: ['ACTIVO'],
      orderBy: 'cod_receta ASC',
    );

    final excel = Excel.createExcel();

    // Eliminar la hoja por defecto 'Sheet1' si existe
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final Sheet sheet = excel['Recetas'];
    excel.setDefaultSheet('Recetas');

    final List<CellValue> headers = [
      TextCellValue('Cod Receta'),
      TextCellValue('Cod Orden'),
      TextCellValue('Fecha'),
      TextCellValue('Productor'),
      TextCellValue('Chacra'),
      TextCellValue('Cuadros'),
      TextCellValue('Motivo'),
      TextCellValue('Momento'),
      TextCellValue('Producto'),
      TextCellValue('Dosis 100L'),
      TextCellValue('Dosis Máq'),
      TextCellValue('Vol/Ha'),
      TextCellValue('TC'),
      TextCellValue('TI'),
      TextCellValue('Responsable'),
      TextCellValue('Estado'),
    ];

    sheet.appendRow(headers);

    final estiloHeader = CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#1E6B4C'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    for (int col = 0; col < headers.length; col++) {
      sheet.row(0)[col]?.cellStyle = estiloHeader;
    }

    // Carga de filas con tipos de celda específicos
    for (var r in registros) {
      sheet.appendRow([
        IntCellValue(int.tryParse(r['cod_receta']?.toString() ?? '') ?? 0),
        IntCellValue(int.tryParse(r['cod_orden']?.toString() ?? '') ?? 0),
        TextCellValue(r['fecha']?.toString() ?? ''),
        TextCellValue(r['productor']?.toString() ?? ''),
        TextCellValue(r['chacra']?.toString() ?? ''),
        TextCellValue(r['cuadros']?.toString() ?? ''),
        TextCellValue(r['motivo_aplic']?.toString() ?? ''),
        TextCellValue(r['momento_aplic']?.toString() ?? ''),
        TextCellValue(r['producto']?.toString() ?? ''),
        DoubleCellValue(double.tryParse(r['dosis_100']?.toString() ?? '') ?? 0.0),
        DoubleCellValue(double.tryParse(r['dosis_maq']?.toString() ?? '') ?? 0.0),
        DoubleCellValue(double.tryParse(r['vol_aplic_ha']?.toString() ?? '') ?? 0.0),
        TextCellValue(r['tc']?.toString() ?? ''),
        TextCellValue(r['ti']?.toString() ?? ''),
        TextCellValue(r['responsable']?.toString() ?? ''),
        TextCellValue(r['habilitado']?.toString() ?? 'ACTIVO'),
      ]);
    }

    // Autoajuste de anchos para legibilidad
    sheet.setColumnWidth(0, 12.0);
    sheet.setColumnWidth(1, 12.0);
    sheet.setColumnWidth(2, 14.0);
    sheet.setColumnWidth(3, 22.0);
    sheet.setColumnWidth(4, 16.0);
    sheet.setColumnWidth(5, 14.0);
    sheet.setColumnWidth(6, 20.0);
    sheet.setColumnWidth(7, 16.0);
    sheet.setColumnWidth(8, 22.0);
    sheet.setColumnWidth(9, 13.0);
    sheet.setColumnWidth(10, 13.0);
    sheet.setColumnWidth(11, 13.0);
    sheet.setColumnWidth(12, 10.0);
    sheet.setColumnWidth(13, 10.0);
    sheet.setColumnWidth(14, 18.0);
    sheet.setColumnWidth(15, 12.0);

    final List<int>? fileBytes = excel.save();
    if (fileBytes == null) return;

    final Uint8List bytes = Uint8List.fromList(fileBytes);
    const String nombreArchivo = 'reporte_aplicaciones_foliares.xlsx';

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
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        text: 'Reporte de Recetas de Aplicación Foliar',
      );
    }
  }
}