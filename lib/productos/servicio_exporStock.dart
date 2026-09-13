// lib/servicios/servicio_exporStock.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class ServicioExportarStock {
  static Future<void> exportarStockPanolero({
    required List<Map<String, dynamic>> items,
    required String nombreProductor,
    required String depositoFiltro,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Stock_Panol'];
    excel.delete('Sheet1');

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#37474F'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final estiloTotal = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#1E2A30'),
    );

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue("GESTIÓN · PAÑOL — INVENTARIO DE EXISTENCIAS");
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        TextCellValue("PRODUCTOR: ${nombreProductor.toUpperCase()} · DEPÓSITO: $depositoFiltro · EMISIÓN: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}");

    final headers = [
      'INSUMO',
      'PRINCIPIO ACTIVO',
      'CONCENTRACIÓN',
      'RUBRO',
      'STOCK INICIAL',
      'CONSUMOS',
      'BAJAS',
      'STOCK NETO',
      'UNIDAD',
      'DEPÓSITOS'
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    int rowIdx = 4;
    double tInicial = 0.0;
    double tConsumos = 0.0;
    double tBajas = 0.0;
    double tNeto = 0.0;

    for (var it in items) {
      final double ini = (it['stock_inicial'] as num?)?.toDouble() ?? 0.0;
      final double con = (it['consumos'] as num?)?.toDouble() ?? 0.0;
      final double baj = (it['bajas'] as num?)?.toDouble() ?? 0.0;
      final double net = (it['stock_neto'] as num?)?.toDouble() ?? 0.0;

      tInicial += ini;
      tConsumos += con;
      tBajas += baj;
      tNeto += net;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value =
          TextCellValue(it['producto']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value =
          TextCellValue(it['principio_activo']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value =
          TextCellValue(it['concentracion']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value =
          TextCellValue(it['rubro']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value =
          DoubleCellValue(ini);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value =
          DoubleCellValue(con);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value =
          DoubleCellValue(baj);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx)).value =
          DoubleCellValue(net);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx)).value =
          TextCellValue(it['unidad']?.toString() ?? 'L/Kg');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIdx)).value =
          TextCellValue((it['depositos'] as List?)?.join(', ') ?? '');
      rowIdx++;
    }

    final cTot = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx));
    cTot.value = TextCellValue("TOTALES");
    cTot.cellStyle = estiloTotal;

    final cIni = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx));
    cIni.value = DoubleCellValue(tInicial);
    cIni.cellStyle = estiloTotal;

    final cCon = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx));
    cCon.value = DoubleCellValue(tConsumos);
    cCon.cellStyle = estiloTotal;

    final cBaj = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx));
    cBaj.value = DoubleCellValue(tBajas);
    cBaj.cellStyle = estiloTotal;

    final cNet = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx));
    cNet.value = DoubleCellValue(tNeto);
    cNet.cellStyle = estiloTotal;

    final fileBytes = excel.save();
    if (fileBytes == null) return;

    final String nomLimpio = nombreProductor.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final String nombreArchivo = 'Panol_Stock_${nomLimpio}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: Uint8List.fromList(fileBytes), filename: nombreArchivo);
    } else if (Platform.isWindows) {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/$nombreArchivo";
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);
      await OpenFilex.open(filePath);
    } else {
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(fileBytes),
            name: nombreArchivo,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        text: 'Stock de Pañol - $nombreProductor',
      );
    }
  }
}