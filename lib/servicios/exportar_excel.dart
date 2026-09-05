import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
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
    
    // 💡 ACA ES LO NUEVO: Eliminar la hoja por defecto 'Sheet1' si existe
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final Sheet sheet = excel['Recetas'];
    excel.setDefaultSheet('Recetas');

    // 🛠️ ESTO LO MODIFIQUE: Uso de TextCellValue en lugar de CellValue.text
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

    final List<int>? bytes = excel.save();
    if (bytes != null) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/reporte_aplicaciones_foliares.xlsx');
      await file.writeAsBytes(bytes, flush: true);

      // Compartir nativamente sin requerir permisos de almacenamiento en Android 13+
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        text: 'Reporte de Recetas de Aplicación Foliar',
      );
    }
  }
}