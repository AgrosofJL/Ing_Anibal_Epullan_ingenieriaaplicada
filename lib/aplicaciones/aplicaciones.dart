// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../servicios/labores_servicio.dart';
import '../widgets/agro_ui.dart';
import 'calculo_dosis.dart';
import 'orden_cuadros.dart';

class AplicacionesScreen extends StatefulWidget {
  final Map<String, dynamic> orden;
  final int codProductor;
  final String nombreProductor;

  const AplicacionesScreen({
    super.key,
    required this.orden,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<AplicacionesScreen> createState() => _AplicacionesScreenState();
}

class _AplicacionesScreenState extends State<AplicacionesScreen> {
  bool _cargando = true;
  bool _exportando = false;
  String _userName = "Operario";
  List<Map<String, dynamic>> _registrosAgrupados = [];

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('userName') ?? "Operario";
    await _cargarRegistrosAplicaciones();
  }

  Future<void> _cargarRegistrosAplicaciones() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;
    final int codOrden = widget.orden['cod_orden'] is int
        ? widget.orden['cod_orden']
        : int.tryParse(widget.orden['cod_orden'].toString()) ?? 0;

    final List<Map<String, dynamic>> filas = await db.query(
      'aplicaciones_registros',
      where: 'cod_orden = ? AND cod_productor = ?',
      whereArgs: [codOrden, widget.codProductor],
      orderBy: 'registro DESC',
    );

    final Map<String, List<Map<String, dynamic>>> mapaTiradas = {};
    for (var f in filas) {
      final key =
          "${f['fecha']}__${f['tractorista']}__${f['pulverizadora']}__${f['vol_aplic_ha']}";
      if (!mapaTiradas.containsKey(key)) {
        mapaTiradas[key] = [];
      }
      mapaTiradas[key]!.add(f);
    }

    final List<Map<String, dynamic>> listaResumen = [];
    mapaTiradas.forEach((k, lista) {
      final cab = lista.first;

      final Set<String> cuadrosSet = {};
      final Set<String> clavesCuartelUnico = {};
      double supTotalTirada = 0.0;
      double litrosTotalTirada = 0.0;

      final String chacraOrden =
          (widget.orden['chacra'] ?? '').toString().trim();
      for (var reg in lista) {
        final ch = reg['chacra']?.toString().trim() ?? '';
        final cd = reg['cuadros']?.toString() ?? '';
        final vr = reg['variedad']?.toString() ?? '';
        // Si el cuadro es de otra chacra, se muestra "Ch X · C Y"
        if (cd.isNotEmpty) {
          cuadrosSet.add(
              ch.isEmpty || ch == chacraOrden ? cd : 'Ch $ch · C $cd');
        }

        final String cKey = "${ch}__${cd}__$vr";
        if (!clavesCuartelUnico.contains(cKey)) {
          clavesCuartelUnico.add(cKey);
          supTotalTirada +=
              double.tryParse(reg['sup_aplic']?.toString() ?? '0') ?? 0.0;
          litrosTotalTirada +=
              double.tryParse(reg['litros']?.toString() ?? '0') ?? 0.0;
        }
      }

      final List<String> cuadrosOrdenados = cuadrosSet.toList()
        ..sort((a, b) {
          final int? na = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
          final int? nb = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));
          if (na != null && nb != null) return na.compareTo(nb);
          return a.compareTo(b);
        });

      listaResumen.add({
        'fecha': cab['fecha'] ?? '',
        'cuadros_resumen': cuadrosOrdenados.join(', '),
        'sup_total': supTotalTirada,
        'tractorista': cab['tractorista'] ?? '',
        'pulverizadora': cab['pulverizadora'] ?? '',
        'litros': litrosTotalTirada > 0
            ? litrosTotalTirada
            : (double.tryParse(cab['litros']?.toString() ?? '0') ?? 0.0),
        'vol_ha': cab['vol_aplic_ha'] ?? 0.0,
        'filas': lista,
      });
    });

    if (!mounted) return;
    setState(() {
      _registrosAgrupados = listaResumen;
      _cargando = false;
    });
  }

  // ===========================================================================
  // EXPORTACIÓN EXCEL
  // ===========================================================================

  Future<void> _onExportar() async {
    if (_exportando) return;
    setState(() => _exportando = true);
    await _exportarExcelLabor();
    if (mounted) setState(() => _exportando = false);
  }

  Future<void> _exportarExcelLabor() async {
    try {
      final excel = Excel.createExcel();

      // Estilos de encabezados
      final headerVerde = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#1E6B4C'),
        horizontalAlign: HorizontalAlign.Center,
      );

      final headerAzul = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
        horizontalAlign: HorizontalAlign.Center,
      );

      final headerDorado = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#1A2E22'),
        backgroundColorHex: ExcelColor.fromHexString('#FFE082'),
        horizontalAlign: HorizontalAlign.Center,
      );

      final estiloTotal = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#1E6B4C'),
        backgroundColorHex: ExcelColor.fromHexString('#E8F5E9'),
      );

      // =======================================================================
      // HOJA 1: REGISTROS_DETALLE (Tiradas y labores individuales)
      // =======================================================================
      final sheetDetalle = excel['Registros_Detalle'];
      excel.delete('Sheet1');

      final headersDetalle = [
        'Registro',
        'Fecha',
        'Chacra',
        'Cuadro',
        'Variedad',
        'Sup (Ha)',
        'Tractorista',
        'Pulverizadora',
        'Caldo (L)',
        'Vol/Ha (L/Ha)',
        'Producto',
        'Dosis / 100L',
        'Dosis Máq. (2000L)',
        'Máquinas (Caldo ÷ 2000)',
        'Consumo Insumo (L/Kg)'
      ];

      for (int i = 0; i < headersDetalle.length; i++) {
        final cell = sheetDetalle
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headersDetalle[i]);
        cell.cellStyle = headerVerde;
      }

      int rowIdx1 = 1;
      final List<Map<String, dynamic>> todasLasFilas = [];

      for (var tirada in _registrosAgrupados) {
        final List<Map<String, dynamic>> filas =
            (tirada['filas'] as List).cast<Map<String, dynamic>>();

        for (var f in filas) {
          todasLasFilas.add(f);

          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx1))
              .value = TextCellValue(f['registro']?.toString() ?? '');
          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx1))
              .value = TextCellValue(f['fecha']?.toString() ?? '');
          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx1))
              .value = TextCellValue(f['chacra']?.toString() ?? '');
          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx1))
              .value = TextCellValue(f['cuadros']?.toString() ?? '');
          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx1))
              .value = TextCellValue(f['variedad']?.toString() ?? '');
          sheetDetalle
                  .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx1))
                  .value =
              DoubleCellValue(
                  double.tryParse(f['sup_aplic']?.toString() ?? '0') ?? 0.0);
          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx1))
              .value = TextCellValue(f['tractorista']?.toString() ?? '');
          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx1))
              .value = TextCellValue(f['pulverizadora']?.toString() ?? '');
          sheetDetalle
                  .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx1))
                  .value =
              DoubleCellValue(
                  double.tryParse(f['litros']?.toString() ?? '0') ?? 0.0);
          sheetDetalle
                  .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIdx1))
                  .value =
              DoubleCellValue(
                  double.tryParse(f['vol_aplic_ha']?.toString() ?? '0') ?? 0.0);
          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIdx1))
              .value = TextCellValue(f['producto']?.toString() ?? '');
          sheetDetalle
              .cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIdx1))
              .value = TextCellValue(f['dosis_100']?.toString() ?? '');
          sheetDetalle
                  .cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIdx1))
                  .value =
              DoubleCellValue(
                  double.tryParse(f['dosis_maq']?.toString() ?? '0') ?? 0.0);
          sheetDetalle
                  .cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIdx1))
                  .value =
              DoubleCellValue((double.tryParse(f['litros']?.toString() ?? '0') ??
                      0.0) /
                  CalculoDosis.volumenMaquina);
          sheetDetalle
                  .cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIdx1))
                  .value =
              DoubleCellValue(
                  double.tryParse(f['consumo_prod']?.toString() ?? '0') ?? 0.0);
          rowIdx1++;
        }
      }

      // =======================================================================
      // HOJA 2: APLICACION_CUADRO (Acumulado por Cuadro y Variedad)
      // =======================================================================
      final sheetCuadros = excel['Aplicacion_Cuadro'];

      final headersCuadros = [
        'Chacra',
        'Cuadro',
        'Variedad',
        'Superficie Total (Ha)',
        'Total Caldo Aplicado (L)',
        'Promedio Vol/Ha (L/Ha)',
        'Cantidad Labores'
      ];

      for (int i = 0; i < headersCuadros.length; i++) {
        final cell = sheetCuadros
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headersCuadros[i]);
        cell.cellStyle = headerAzul;
      }

      // Agrupación por clave única: Chacra + Cuadro + Variedad + Fecha/Labor
      final Map<String, Map<String, dynamic>> acumuladoCuadros = {};
      final Set<String> combinacionesTiradaCuartel = {};

      for (var f in todasLasFilas) {
        final ch = f['chacra']?.toString() ?? '';
        final cd = f['cuadros']?.toString() ?? '';
        final vr = f['variedad']?.toString() ?? '';
        final keyCuartel = "${ch}__${cd}__$vr";

        if (!acumuladoCuadros.containsKey(keyCuartel)) {
          acumuladoCuadros[keyCuartel] = {
            'chacra': ch,
            'cuadro': cd,
            'variedad': vr,
            'sup_total': 0.0,
            'litros_total': 0.0,
            'labores_count': 0,
          };
        }

        // Sumar superficie y litros únicamente una vez por tirada para evitar multiplicar por la cantidad de productos
        final tiradaId =
            "${f['fecha']}__${f['tractorista']}__${f['pulverizadora']}__$keyCuartel";
        if (!combinacionesTiradaCuartel.contains(tiradaId)) {
          combinacionesTiradaCuartel.add(tiradaId);
          acumuladoCuadros[keyCuartel]!['sup_total'] +=
              double.tryParse(f['sup_aplic']?.toString() ?? '0') ?? 0.0;
          acumuladoCuadros[keyCuartel]!['litros_total'] +=
              double.tryParse(f['litros']?.toString() ?? '0') ?? 0.0;
          acumuladoCuadros[keyCuartel]!['labores_count'] += 1;
        }
      }

      int rowIdx2 = 1;
      double granTotalSup = 0.0;
      double granTotalCaldo = 0.0;

      for (var item in acumuladoCuadros.values) {
        final double s = item['sup_total'];
        final double l = item['litros_total'];
        final int c = item['labores_count'];
        final double promLHa = s > 0 ? (l / s) : 0.0;

        granTotalSup += s;
        granTotalCaldo += l;

        sheetCuadros
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx2))
            .value = TextCellValue(item['chacra']);
        sheetCuadros
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx2))
            .value = TextCellValue(item['cuadro']);
        sheetCuadros
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx2))
            .value = TextCellValue(item['variedad']);
        sheetCuadros
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx2))
            .value = DoubleCellValue(s);
        sheetCuadros
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx2))
            .value = DoubleCellValue(l);
        sheetCuadros
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx2))
            .value = DoubleCellValue(promLHa);
        sheetCuadros
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx2))
            .value = IntCellValue(c);
        rowIdx2++;
      }

      // Fila de Total Acumulado en Hoja 2
      final cellTotLabel = sheetCuadros
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx2));
      cellTotLabel.value = TextCellValue("TOTAL GENERAL");
      cellTotLabel.cellStyle = estiloTotal;

      final cellTotSup = sheetCuadros
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx2));
      cellTotSup.value = DoubleCellValue(granTotalSup);
      cellTotSup.cellStyle = estiloTotal;

      final cellTotCaldo = sheetCuadros
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx2));
      cellTotCaldo.value = DoubleCellValue(granTotalCaldo);
      cellTotCaldo.cellStyle = estiloTotal;

      // =======================================================================
      // HOJA 3: CONSUMOS_ORDEN (Total de Insumos gastados en la orden)
      // =======================================================================
      final sheetConsumos = excel['Consumos_Orden'];

      final headersConsumos = [
        'Producto / Insumo',
        'Dosis Prescripta / 100L',
        'Dosis Máquina (2000L)',
        'Total Aplicado (L / Kg)',
        'Carencia (Días)',
        'Reingreso (Horas)'
      ];

      for (int i = 0; i < headersConsumos.length; i++) {
        final cell = sheetConsumos
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headersConsumos[i]);
        cell.cellStyle = headerDorado;
      }

      // Agrupación y suma total por producto
      final Map<String, Map<String, dynamic>> acumuladoProductos = {};

      for (var f in todasLasFilas) {
        final prod = (f['producto'] ?? 'Insumo').toString().trim();
        final consumo =
            double.tryParse(f['consumo_prod']?.toString() ?? '0') ?? 0.0;

        if (!acumuladoProductos.containsKey(prod)) {
          acumuladoProductos[prod] = {
            'producto': prod,
            'dosis_100': f['dosis_100']?.toString() ?? '',
            'dosis_maq': f['dosis_maq']?.toString() ?? '',
            'total_consumido': 0.0,
            'tc': f['tc']?.toString() ?? '-',
            'ti': f['ti']?.toString() ?? '-',
          };
        }
        acumuladoProductos[prod]!['total_consumido'] += consumo;
      }

      int rowIdx3 = 1;
      for (var item in acumuladoProductos.values) {
        sheetConsumos
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx3))
            .value = TextCellValue(item['producto']);
        sheetConsumos
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx3))
            .value = TextCellValue(item['dosis_100']);
        sheetConsumos
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx3))
            .value = TextCellValue("${item['dosis_maq']} L/Kg");
        sheetConsumos
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx3))
            .value = DoubleCellValue(item['total_consumido']);
        sheetConsumos
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx3))
            .value = TextCellValue("${item['tc']}d");
        sheetConsumos
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx3))
            .value = TextCellValue("${item['ti']}hs");
        rowIdx3++;
      }

      // =======================================================================
      // GUARDADO Y APERTURA MULTIPLATAFORMA
      // =======================================================================
      final codOrden = widget.orden['cod_orden'];
      final String cleanProd =
          widget.nombreProductor.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final String fileName = "Reporte_Orden_${codOrden}_$cleanProd.xlsx";

      // En web no existe el sistema de archivos (dart:io): el paquete excel
      // dispara la descarga del navegador al llamar a save(fileName: ...).
      if (kIsWeb) {
        final bytesWeb = excel.save(fileName: fileName);
        if (bytesWeb == null) return;
        if (mounted) {
          mostrarAgroSnack(
            context,
            "Libro Excel descargado: $fileName",
            tipo: AgroSnackTipo.ok,
            duracion: const Duration(seconds: 4),
          );
        }
        return;
      }

      final fileBytes = excel.save();
      if (fileBytes == null) return;

      Directory dir;
      if (Platform.isWindows) {
        dir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      } else {
        dir = await getTemporaryDirectory();
      }

      final String filePath = "${dir.path}/$fileName";

      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      if (Platform.isWindows) {
        await OpenFilex.open(filePath);

        if (mounted) {
          mostrarAgroSnack(
            context,
            "Libro Excel generado con 3 hojas (Detalle, Cuadros y Consumos):\n$filePath",
            tipo: AgroSnackTipo.ok,
            duracion: const Duration(seconds: 4),
          );
        }
      } else {
        await Share.shareXFiles(
          [XFile(filePath)],
          subject:
              "Resumen Completo Orden #$codOrden - ${widget.nombreProductor}",
        );
      }
    } catch (e) {
      if (!mounted) return;
      mostrarAgroSnack(
        context,
        "Error al generar el libro Excel: $e",
        tipo: AgroSnackTipo.error,
      );
    }
  }

  // ===========================================================================
  // REGISTRAR APLICACIÓN
  // ===========================================================================

  Future<void> _abrirModalRegistrarAplicacion() async {
    final int? guardadas = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => _RegistrarAplicacionPage(
          orden: widget.orden,
          codProductor: widget.codProductor,
          nombreProductor: widget.nombreProductor,
          userName: _userName,
          aplicados: _ultimaAplicacionPorCuartel(),
        ),
      ),
    );
    if (guardadas == null || !mounted) return;
    await _cargarRegistrosAplicaciones();
    if (!mounted) return;
    mostrarAgroSnack(
      context,
      '¡Se guardaron $guardadas labores y se descontó el stock de insumos!',
      tipo: AgroSnackTipo.ok,
    );
  }


  // ===========================================================================
  // ELIMINAR LABOR (desde el menú de la tarjeta)
  // ===========================================================================

  Future<void> _eliminarLabor(Map<String, dynamic> tirada) async {
    if (!_ordenActiva) return;
    final List<Map<String, dynamic>> filas = _filasDe(tirada);
    final List<String> registros = _registrosDe(filas);
    final int nCuadros = _agruparPorCuartel(filas).length;

    if (registros.isEmpty) {
      mostrarAgroSnack(context, 'No se encontraron registros para esta labor.',
          tipo: AgroSnackTipo.error);
      return;
    }

    final bool ok = await confirmarAgro(
      context: context,
      titulo: 'Eliminar labor',
      mensaje:
          'Se eliminará la labor del ${_fmtFecha(tirada['fecha'])}: $nCuadros ${nCuadros == 1 ? 'cuadro' : 'cuadros'} y ${registros.length} registros. '
          'Los consumos de producto vuelven al stock de insumos. Esta acción no se puede deshacer.',
      confirmar: 'Eliminar',
      peligroso: true,
      icono: Icons.delete_forever_rounded,
    );
    if (!ok || !mounted) return;

    try {
      final double devuelto = await ServicioLabores.eliminar(registros);
      if (!mounted) return;
      await _cargarRegistrosAplicaciones();
      if (!mounted) return;
      mostrarAgroSnack(
        context,
        'Labor eliminada · ${devuelto.toStringAsFixed(2)} L/Kg de producto devueltos al stock',
        tipo: AgroSnackTipo.ok,
      );
    } catch (e) {
      if (!mounted) return;
      mostrarAgroSnack(context, 'No se pudo eliminar la labor: $e',
          tipo: AgroSnackTipo.error);
    }
  }

  // ===========================================================================
  // DETALLE / MODIFICAR TIRADA
  // ===========================================================================

  void _mostrarDetalleYModificarRegistro(Map<String, dynamic> tirada) {
    final bool ordenActiva = _ordenActiva;
    final List<Map<String, dynamic>> filas = _filasDe(tirada);
    final List<Map<String, dynamic>> itemsReceta = _itemsReceta();
    final Map<String, List<Map<String, dynamic>>> porCuartel =
        _agruparPorCuartel(filas);
    final List<String> registrosTodos = _registrosDe(filas);

    final double litrosTirada = _num(tirada['litros']);
    final double supTirada = _num(tirada['sup_total']);
    final double volHa = _num(tirada['vol_ha']);
    final double maquinas = CalculoDosis.volumenMaquina > 0
        ? litrosTirada / CalculoDosis.volumenMaquina
        : 0.0;

    final String fechaRaw = _txt(tirada['fecha']);
    final DateTime? fechaDt = DateTime.tryParse(fechaRaw);

    final fechaCtrl = TextEditingController(
        text: fechaDt != null
            ? DateFormat('yyyy-MM-dd').format(fechaDt)
            : fechaRaw);
    final tractoristaCtrl =
        TextEditingController(text: _txt(tirada['tractorista']));
    final maquinaCtrl =
        TextEditingController(text: _txt(tirada['pulverizadora']));
    // El operario corrige los LITROS TOTALES de la tanda; el caldo/Ha sale
    // de litros ÷ Sup. total (y con eso se recalcula y reparte el producto).
    final caldoCtrl = TextEditingController(
        text: _fmtNum(litrosTirada > 0 ? litrosTirada : volHa * supTirada));

    bool guardando = false;
    String? errorForm;

    mostrarAgroPanel(
      context: context,
      titulo: ordenActiva ? 'Ver / editar labor' : 'Detalle de la labor',
      subtitulo:
          '${_fmtFecha(fechaRaw)} · ${porCuartel.length} ${porCuartel.length == 1 ? 'cuadro' : 'cuadros'} · ${filas.length} registros',
      icono: ordenActiva ? Icons.edit_rounded : Icons.fact_check_rounded,
      maxWidth: 680,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sbContext, setModalState) {
            // Caldo/Ha resultante = litros totales ÷ Sup. de la tanda.
            double caldoActual() {
              final double litros = double.tryParse(
                      caldoCtrl.text.replaceAll(',', '.').trim()) ??
                  0.0;
              return supTirada > 0 ? litros / supTirada : 0.0;
            }

            // Ejecuta una acción de guardado/borrado: cierra el panel,
            // recarga la pantalla y muestra el mensaje devuelto.
            Future<void> ejecutar(Future<String> Function() accion) async {
              setModalState(() {
                guardando = true;
              });
              String mensaje;
              try {
                mensaje = await accion();
              } catch (e) {
                if (sbContext.mounted) {
                  setModalState(() {
                    guardando = false;
                  });
                }
                if (mounted) {
                  mostrarAgroSnack(context, 'No se pudo completar: $e',
                      tipo: AgroSnackTipo.error);
                }
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (!mounted) return;
              await _cargarRegistrosAplicaciones();
              if (!mounted) return;
              mostrarAgroSnack(context, mensaje, tipo: AgroSnackTipo.ok);
            }

            Future<void> elegirFecha() async {
              DateTime inicial =
                  DateTime.tryParse(fechaCtrl.text.trim()) ?? DateTime.now();
              if (inicial.isBefore(DateTime(2000)) ||
                  inicial.isAfter(DateTime(2100))) {
                inicial = DateTime.now();
              }
              final DateTime? elegida = await showDatePicker(
                context: ctx,
                initialDate: inicial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                helpText: 'Fecha de aplicación',
                cancelText: 'Cancelar',
                confirmText: 'Aceptar',
              );
              if (elegida != null && sbContext.mounted) {
                setModalState(() {
                  fechaCtrl.text = DateFormat('yyyy-MM-dd').format(elegida);
                });
              }
            }

            Future<void> guardar() async {
              final String fecha = fechaCtrl.text.trim();
              final double caldo = caldoActual();
              String? err;
              if (fecha.isEmpty) {
                err = 'Indicá la fecha de la labor.';
              } else if (caldo <= 0) {
                err = 'Los litros totales deben ser mayores a 0.';
              }
              if (err != null) {
                final String msg = err;
                setModalState(() {
                  errorForm = msg;
                });
                return;
              }
              setModalState(() {
                errorForm = null;
              });
              await ejecutar(() async {
                await ServicioLabores.actualizar(
                  filas: filas,
                  fecha: fecha,
                  tractorista: tractoristaCtrl.text.trim(),
                  maquina: maquinaCtrl.text.trim(),
                  caldoHa: caldo,
                  itemsReceta: itemsReceta,
                );
                return 'Labor actualizada y consumos recalculados';
              });
            }

            Future<void> eliminarTodo() async {
              if (registrosTodos.isEmpty) return;
              final bool ok = await confirmarAgro(
                context: ctx,
                titulo: 'Eliminar labor completa',
                mensaje:
                    'Se eliminará la labor del ${_fmtFecha(fechaRaw)}: ${porCuartel.length} ${porCuartel.length == 1 ? 'cuadro' : 'cuadros'} y ${registrosTodos.length} registros. '
                    'Todo el producto consumido vuelve al stock de insumos. Esta acción no se puede deshacer.',
                confirmar: 'Eliminar',
                peligroso: true,
                icono: Icons.delete_forever_rounded,
              );
              if (!ok || !ctx.mounted) return;
              await ejecutar(() async {
                final double dev =
                    await ServicioLabores.eliminar(registrosTodos);
                return 'Labor eliminada · ${dev.toStringAsFixed(2)} L/Kg de producto devueltos al stock';
              });
            }

            Future<void> quitarGrupo(
                List<Map<String, dynamic>> grupo, String nombre) async {
              final List<String> regs = _registrosDe(grupo);
              if (regs.isEmpty) return;
              final bool unico = porCuartel.length == 1;
              final bool ok = await confirmarAgro(
                context: ctx,
                titulo: 'Quitar cuadro de la labor',
                mensaje: 'Se quitará "$nombre" de esta labor (${regs.length} registros). '
                    '${unico ? 'Es el único cuadro: la labor quedará eliminada. ' : ''}'
                    'Sus consumos de producto vuelven al stock.',
                confirmar: 'Quitar',
                peligroso: true,
                icono: Icons.remove_circle_outline_rounded,
              );
              if (!ok || !ctx.mounted) return;
              await ejecutar(() async {
                final double dev = await ServicioLabores.eliminar(regs);
                return '$nombre quitado · ${dev.toStringAsFixed(2)} L/Kg devueltos al stock';
              });
            }

            return LayoutBuilder(
              builder: (lbContext, constraints) {
                final bool angosto = constraints.maxWidth < 440;
                final double caldo = caldoActual();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _grillaTiles(
                      [
                        _KpiTile(
                          icono: Icons.event_rounded,
                          color: _kTeal,
                          valor: _fmtFecha(fechaRaw),
                          label: 'Fecha',
                          compacto: true,
                        ),
                        _KpiTile(
                          icono: Icons.grid_view_rounded,
                          color: AgroColors.primario,
                          valor: '${porCuartel.length}',
                          label: porCuartel.length == 1 ? 'Cuadro' : 'Cuadros',
                          compacto: true,
                        ),
                        _KpiTile(
                          icono: Icons.square_foot_rounded,
                          color: AgroColors.ok,
                          valor: '${supTirada.toStringAsFixed(2)} Ha',
                          label: 'Superficie',
                          compacto: true,
                        ),
                        _KpiTile(
                          icono: Icons.water_drop_rounded,
                          color: _kAzul,
                          valor: '${litrosTirada.toStringAsFixed(0)} L',
                          label: 'Caldo total',
                          detalle: '${volHa.toStringAsFixed(0)} L/Ha',
                          compacto: true,
                        ),
                        _KpiTile(
                          icono: Icons.local_shipping_rounded,
                          color: AgroColors.warn,
                          valor: maquinas.toStringAsFixed(2),
                          label: 'Máquinas',
                          detalle:
                              'de ${CalculoDosis.volumenMaquina.toStringAsFixed(0)} L',
                          compacto: true,
                        ),
                      ],
                      minAncho: 112,
                      gap: 10,
                    ),
                    const SizedBox(height: 18),
                    if (ordenActiva) ...[
                      _tituloPanel(Icons.tune_rounded, 'Datos de la labor'),
                      const SizedBox(height: 10),
                      _filaCampos(
                        angosto: angosto,
                        a: TextFormField(
                          controller: fechaCtrl,
                          readOnly: true,
                          onTap: guardando ? null : elegirFecha,
                          style: AgroText.cuerpo,
                          decoration: agroInputDecoration(
                            label: 'Fecha',
                            icono: Icons.event_rounded,
                          ).copyWith(
                            suffixIcon: const Icon(
                                Icons.calendar_month_rounded,
                                size: 18,
                                color: AgroColors.primario),
                          ),
                        ),
                        b: TextFormField(
                          controller: caldoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: AgroText.cuerpo,
                          onChanged: (_) => setModalState(() {}),
                          decoration: agroInputDecoration(
                            label: 'Litros totales aplicados',
                            icono: Icons.water_drop_outlined,
                            sufijo: 'L',
                            helper:
                                '${_fmtNum(caldoActual())} L/Ha en ${supTirada.toStringAsFixed(2)} ha',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _filaCampos(
                        angosto: angosto,
                        a: TextFormField(
                          controller: tractoristaCtrl,
                          style: AgroText.cuerpo,
                          textCapitalization: TextCapitalization.words,
                          decoration: agroInputDecoration(
                            label: 'Tractorista',
                            icono: Icons.person_rounded,
                          ),
                        ),
                        b: TextFormField(
                          controller: maquinaCtrl,
                          style: AgroText.cuerpo,
                          decoration: agroInputDecoration(
                            label: 'Máquina / pulverizadora',
                            icono: Icons.agriculture_rounded,
                          ),
                        ),
                      ),
                      if (errorForm != null) ...[
                        const SizedBox(height: 10),
                        _avisoPanel(
                          icono: Icons.error_outline_rounded,
                          texto: errorForm ?? '',
                          color: AgroColors.danger,
                          fondo: AgroColors.dangerSoft,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _previewDescuento(
                        items: itemsReceta,
                        filas: filas,
                        caldo: caldo,
                      ),
                    ] else ...[
                      _avisoPanel(
                        icono: Icons.lock_outline_rounded,
                        texto:
                            'La orden no está activa: la labor es de solo lectura y no se puede modificar ni eliminar.',
                        color: AgroColors.neutral,
                        fondo: AgroColors.neutralSoft,
                      ),
                      const SizedBox(height: 6),
                      AgroKeyValue(
                        clave: 'Tractorista',
                        valor: _txt(tirada['tractorista']).isEmpty
                            ? '-'
                            : _txt(tirada['tractorista']),
                        icono: Icons.person_rounded,
                      ),
                      AgroKeyValue(
                        clave: 'Máquina',
                        valor: _txt(tirada['pulverizadora']).isEmpty
                            ? '-'
                            : _txt(tirada['pulverizadora']),
                        icono: Icons.agriculture_rounded,
                      ),
                      AgroKeyValue(
                        clave: 'Caldo aplicado',
                        valor: '${volHa.toStringAsFixed(1)} L/Ha',
                        icono: Icons.water_drop_outlined,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _tituloPanel(
                              Icons.grid_view_rounded, 'Cuadros de la labor'),
                        ),
                        const SizedBox(width: 8),
                        AgroBadge(
                          texto: '${filas.length} reg.',
                          color: AgroColors.neutral,
                          fondo: AgroColors.neutralSoft,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...porCuartel.values.map((grupo) {
                      final Map<String, dynamic> cab = grupo.first;
                      final double supCab = _num(cab['sup_aplic']);
                      final String nombre = _nombreGrupo(cab);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AgroTheme.colorSurface,
                            borderRadius:
                                BorderRadius.circular(AgroTheme.radiusMd),
                            border: Border.all(color: AgroTheme.colorBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: EdgeInsets.fromLTRB(
                                    12, ordenActiva ? 4 : 10, 4,
                                    ordenActiva ? 4 : 10),
                                decoration: BoxDecoration(
                                  color: AgroColors.primarioSoft,
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(
                                          AgroTheme.radiusMd - 1)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.grid_view_rounded,
                                        size: 16, color: AgroColors.primario),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        nombre,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: AgroColors.primario,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AgroTheme.colorSurface,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '${supCab.toStringAsFixed(2)} Ha',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11.5,
                                          color: AgroColors.primario,
                                        ),
                                      ),
                                    ),
                                    if (ordenActiva)
                                      IconButton(
                                        tooltip:
                                            'Quitar este cuadro de la labor',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          size: 20,
                                          color: AgroColors.danger,
                                        ),
                                        onPressed: guardando
                                            ? null
                                            : () => quitarGrupo(grupo, nombre),
                                      )
                                    else
                                      const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              ...grupo.map((f) {
                                final double consumo = _num(f['consumo_prod']);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.science_outlined,
                                          size: 15,
                                          color: AgroTheme.colorTextSecondary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _txt(f['producto']),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AgroText.cuerpo.copyWith(
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${consumo.toStringAsFixed(2)} L/Kg',
                                        style: AgroText.valor
                                            .copyWith(fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (ordenActiva) ...[
                      const SizedBox(height: 10),
                      AgroButton(
                        label: 'Guardar cambios',
                        icono: Icons.save_rounded,
                        expandido: true,
                        cargando: guardando,
                        onTap: guardando ? null : guardar,
                      ),
                      const SizedBox(height: 10),
                      AgroButton(
                        label: 'Eliminar labor completa',
                        icono: Icons.delete_forever_rounded,
                        tipo: AgroButtonTipo.peligro,
                        expandido: true,
                        onTap: guardando ? null : eliminarTodo,
                      ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Vista previa del producto a descontar con el caldo ingresado.
  Widget _previewDescuento({
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> filas,
    required double caldo,
  }) {
    final int n = items.length;
    final List<double> actual = List<double>.filled(n, 0.0);
    final List<double> nuevo = List<double>.filled(n, 0.0);
    final List<bool> tiene = List<bool>.filled(n, false);

    // Sup. de cada producto = suma de las Ha de sus filas (una por
    // cuadro/variedad). Total = mismo cálculo que al registrar la tanda.
    final List<double> supProd = List<double>.filled(n, 0.0);
    for (final f in filas) {
      final int i = _indiceItemDeFila(f, items);
      if (i < 0) continue;
      tiene[i] = true;
      actual[i] += _num(f['consumo_prod']);
      supProd[i] += _num(f['sup_aplic']);
    }
    if (caldo > 0) {
      for (int i = 0; i < n; i++) {
        if (!tiene[i]) continue;
        nuevo[i] = CalculoDosis.totalProductoTanda(
            items[i], supProd[i], caldo * supProd[i]);
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAzul.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        border: Border.all(color: _kAzul.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, size: 17, color: _kAzul),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Producto a descontar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _kAzul,
                  ),
                ),
              ),
              if (caldo > 0)
                Text(
                  'con ${_fmtNum(caldo)} L/Ha',
                  style: AgroText.label.copyWith(color: _kAzul),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (caldo <= 0)
            const Text('Ingresá un caldo válido para ver el cálculo.',
                style: AgroText.secundario)
          else if (n == 0)
            const Text('La orden no tiene productos cargados.',
                style: AgroText.secundario)
          else
            for (int i = 0; i < n; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _colorProducto(i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _txt(items[i]['producto']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.cuerpo
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!tiene[i])
                      const Text('Sin registros en esta labor',
                          style: AgroText.secundario)
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${nuevo[i].toStringAsFixed(2)} L/Kg',
                            style: AgroText.valor.copyWith(fontSize: 13),
                          ),
                          _textoDiferencia(nuevo[i] - actual[i]),
                        ],
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _textoDiferencia(double d) {
    if (d.abs() < 0.005) {
      return const Text('sin cambios',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AgroTheme.colorTextSecondary,
          ));
    }
    final bool sube = d > 0;
    final Color c = sube ? AgroColors.danger : AgroColors.ok;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(sube ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 13, color: c),
        const SizedBox(width: 3),
        Text(
          sube
              ? '+${d.toStringAsFixed(2)} a descontar'
              : '${d.abs().toStringAsFixed(2)} vuelve al stock',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c,
          ),
        ),
      ],
    );
  }

  Widget _tituloPanel(IconData icono, String texto) {
    return Row(
      children: [
        Icon(icono, size: 17, color: AgroColors.primario),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AgroText.tituloCard,
          ),
        ),
      ],
    );
  }

  Widget _avisoPanel({
    required IconData icono,
    required String texto,
    required Color color,
    required Color fondo,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: AgroText.secundario
                  .copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPERS DE PRESENTACIÓN
  // ===========================================================================

  String _txt(dynamic v) {
    if (v == null) return '';
    final s = v.toString().trim();
    return s == 'null' ? '' : s;
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v?.toString() ?? '').replaceAll(',', '.').trim()) ??
        0.0;
  }

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _fmtFecha(dynamic v) {
    final s = _txt(v);
    final d = DateTime.tryParse(s);
    if (d == null) return s.isEmpty ? '-' : s;
    return DateFormat('dd/MM/yyyy').format(d);
  }

  bool get _ordenActiva {
    final e = _txt(widget.orden['estado']).toUpperCase();
    return e.isEmpty || e == 'ACTIVO';
  }

  /// Productos de la receta de la orden.
  List<Map<String, dynamic>> _itemsReceta() {
    final raw = widget.orden['items'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  List<Map<String, dynamic>> _filasDe(Map<String, dynamic> tirada) {
    final raw = tirada['filas'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.cast<Map<String, dynamic>>();
  }

  List<String> _registrosDe(List<Map<String, dynamic>> filas) => filas
      .map((f) => _txt(f['registro']))
      .where((r) => r.isNotEmpty)
      .toList();

  /// Agrupa las filas por chacra + cuadro + variedad.
  Map<String, List<Map<String, dynamic>>> _agruparPorCuartel(
      List<Map<String, dynamic>> filas) {
    final Map<String, List<Map<String, dynamic>>> res = {};
    for (final f in filas) {
      final key = "${f['chacra']}__${f['cuadros']}__${f['variedad']}";
      res.putIfAbsent(key, () => []).add(f);
    }
    return res;
  }

  String _nombreGrupo(Map<String, dynamic> cab) {
    final String ch = _txt(cab['chacra']);
    final bool otraChacra = ch.isNotEmpty && ch != _txt(widget.orden['chacra']);
    final String variedad = _txt(cab['variedad']);
    return "${otraChacra ? 'Ch $ch · ' : ''}Cuadro ${_txt(cab['cuadros'])}"
        "${variedad.isEmpty ? '' : ' · $variedad'}";
  }

  /// Índice del producto de la receta al que corresponde una fila
  /// (misma prioridad que ServicioLabores: cod_receta, cod_producto, nombre).
  int _indiceItemDeFila(
      Map<String, dynamic> f, List<Map<String, dynamic>> items) {
    final String cr = _txt(f['cod_receta']);
    if (cr.isNotEmpty) {
      for (int i = 0; i < items.length; i++) {
        if (_txt(items[i]['cod_receta']) == cr) return i;
      }
    }
    final String cp = _txt(f['cod_producto']);
    if (cp.isNotEmpty) {
      for (int i = 0; i < items.length; i++) {
        if (_txt(items[i]['cod_producto']) == cp) return i;
      }
    }
    final String pf = _txt(f['producto']).toUpperCase();
    if (pf.isNotEmpty) {
      for (int i = 0; i < items.length; i++) {
        if (_txt(items[i]['producto']).toUpperCase() == pf) return i;
      }
    }
    return -1;
  }

  Color _colorProducto(int i) => _kPaleta[i % _kPaleta.length];

  /// Cuadros asignados a la orden (una o varias chacras).
  List<CuadroRef> _cuadrosOrden() =>
      parsearCuadrosOrden(widget.orden['chacra'], widget.orden['cuadros']);

  /// Chacra a usar para registros viejos que no guardaron la chacra.
  String get _chacraPorDefecto {
    final ch = chacrasDeOrden(widget.orden['chacra'], widget.orden['cuadros']);
    return ch.isEmpty ? '' : ch.first;
  }

  /// Claves "chacra::cuadro" que ya tienen alguna aplicación en esta orden.
  Set<String> _cuadrosConAplicacion() {
    final Set<String> res = {};
    for (var t in _registrosAgrupados) {
      for (var f in (t['filas'] as List)) {
        final m = f as Map;
        final ch = _txt(m['chacra']).isEmpty ? _chacraPorDefecto : _txt(m['chacra']);
        final cd = _txt(m['cuadros']);
        if (cd.isNotEmpty) res.add(claveCuadro(ch, cd));
      }
    }
    return res;
  }

  /// "chacra::cuadro__variedad" → fecha de la última aplicación registrada.
  Map<String, String> _ultimaAplicacionPorCuartel() {
    final Map<String, String> res = {};
    for (var t in _registrosAgrupados) {
      for (var f in (t['filas'] as List)) {
        final m = f as Map;
        final ch = _txt(m['chacra']).isEmpty ? _chacraPorDefecto : _txt(m['chacra']);
        final cd = _txt(m['cuadros']);
        if (cd.isEmpty) continue;
        final key = '${claveCuadro(ch, cd)}__${_txt(m['variedad'])}';
        final fecha = _txt(m['fecha']);
        final previa = res[key];
        if (previa == null || fecha.compareTo(previa) > 0) res[key] = fecha;
      }
    }
    return res;
  }

  int _registrosAgrupadasCount() {
    int total = 0;
    for (var r in _registrosAgrupados) {
      total += (r['filas'] as List).length;
    }
    return total;
  }

  Widget _filaCampos({
    required bool angosto,
    required Widget a,
    required Widget b,
    int flexA = 1,
    int flexB = 1,
  }) {
    if (angosto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a, const SizedBox(height: 12), b],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: flexA, child: a),
        const SizedBox(width: 12),
        Expanded(flex: flexB, child: b),
      ],
    );
  }

  /// Grilla responsive de tiles con anchos enteros (sin desbordes).
  Widget _grillaTiles(List<Widget> tiles,
      {double minAncho = 160, double gap = 12}) {
    return LayoutBuilder(
      builder: (context, c) {
        if (tiles.isEmpty) return const SizedBox.shrink();
        final double w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
        int cols = ((w + gap) / (minAncho + gap)).floor();
        if (cols < 2) cols = 2;
        if (cols > tiles.length) cols = tiles.length;
        // Evita filas con un solo tile "huérfano".
        if (tiles.length == 4 && cols == 3) cols = 2;
        if (tiles.length == 5 && cols == 4) cols = 3;
        final double anchoTile = ((w - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: tiles
              .map((t) => SizedBox(width: anchoTile, child: t))
              .toList(),
        );
      },
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> itemsReceta = _itemsReceta();

    final bool movil = AgroBreakpoints.esMovil(context);
    final bool ancho =
        AgroBreakpoints.ancho(context) >= AgroBreakpoints.tablet;

    final Widget receta = _buildReceta(itemsReceta);
    final Widget labores = _buildLabores(movil);

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: "Orden N° ${widget.orden['cod_orden']}",
        subtitulo: widget.nombreProductor,
        acciones: [
          if (_exportando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: AgroColors.primario),
                ),
              ),
            )
          else
            Center(
              child: AgroIconButton(
                icono: Icons.table_view_rounded,
                tooltip: 'Exportar labores a Excel',
                color: AgroColors.ok,
                size: 44,
                onTap: _registrosAgrupados.isEmpty ? null : _onExportar,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AgroColors.primario,
          onRefresh: _cargarRegistrosAplicaciones,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(top: 16, bottom: movil ? 96 : 32),
            child: AgroContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildResumenOrden(itemsReceta),
                  const SizedBox(height: 14),
                  _buildKpis(),
                  const SizedBox(height: 20),
                  if (ancho)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: receta),
                        const SizedBox(width: 20),
                        Expanded(flex: 7, child: labores),
                      ],
                    )
                  else ...[
                    receta,
                    const SizedBox(height: 24),
                    labores,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: movil
          ? FloatingActionButton.extended(
              onPressed: _abrirModalRegistrarAplicacion,
              backgroundColor: AgroColors.primario,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_task_rounded, size: 20),
              label: const Text(
                'Registrar aplicación',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            )
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Encabezado (hero) de la orden
  // ---------------------------------------------------------------------------
  Widget _buildResumenOrden(List<Map<String, dynamic>> itemsReceta) {
    final String estado = _txt(widget.orden['estado']).isEmpty
        ? 'ACTIVO'
        : _txt(widget.orden['estado']);
    final bool activa = _ordenActiva;
    final String chacra = _txt(widget.orden['chacra']);
    final String fechaOrden = _txt(widget.orden['fecha']);
    final String motivoMomento = [
      _txt(widget.orden['motivo']),
      _txt(widget.orden['momento']),
    ].where((s) => s.isNotEmpty).join(' · ');

    final List<CuadroRef> cuadros = _cuadrosOrden();
    final Set<String> aplicados = _cuadrosConAplicacion();
    final bool variasChacras = cuadros.map((r) => r.chacra).toSet().length > 1;
    final int nAplicados =
        cuadros.where((r) => aplicados.contains(r.clave)).length;
    final double avance = cuadros.isEmpty ? 0.0 : nAplicados / cuadros.length;

    return LayoutBuilder(
      builder: (context, c) {
        final bool angosto = c.maxWidth < 560;

        final Widget info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ORDEN DE APLICACIÓN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.overline
                            .copyWith(color: Colors.white.withOpacity(0.75)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Orden N° ${widget.orden['cod_orden']}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (motivoMomento.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                motivoMomento,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: Colors.white.withOpacity(0.92),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _pillHero(
                  activa ? Icons.circle : Icons.lock_rounded,
                  estado,
                  iconoChico: activa,
                ),
                _pillHero(
                  Icons.place_rounded,
                  chacra.isEmpty
                      ? 'Sin chacra'
                      : '${chacra.contains(',') ? 'Chacras' : 'Chacra'} $chacra',
                ),
                if (fechaOrden.isNotEmpty)
                  _pillHero(Icons.event_rounded, _fmtFecha(fechaOrden)),
                _pillHero(
                  Icons.science_rounded,
                  '${itemsReceta.length} ${itemsReceta.length == 1 ? 'producto' : 'productos'}',
                ),
              ],
            ),
          ],
        );

        final Widget progreso = _anilloAvance(avance, nAplicados, cuadros.length);

        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AgroColors.primario, _kVerdeOscuro],
            ),
            borderRadius: BorderRadius.circular(AgroTheme.radiusLg + 4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x331E6B4C),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: EdgeInsets.all(angosto ? 16 : 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (angosto) ...[
                info,
                const SizedBox(height: 16),
                progreso,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 20),
                    progreso,
                  ],
                ),
              if (cuadros.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.grid_view_rounded,
                              size: 15, color: Colors.white.withOpacity(0.8)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'CUADROS DE LA ORDEN',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AgroText.overline.copyWith(
                                  color: Colors.white.withOpacity(0.8)),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              '$nAplicados aplicados · ${cuadros.length - nAplicados} pendientes',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: cuadros
                            .map((r) => _CuadroChip(
                                  cuadro: variasChacras
                                      ? '${r.cuadro} (Ch ${r.chacra})'
                                      : r.cuadro,
                                  aplicado: aplicados.contains(r.clave),
                                  claro: true,
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _pillHero(IconData icono, String texto, {bool iconoChico = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono,
              size: iconoChico ? 8 : 13,
              color: iconoChico ? const Color(0xFF9BE7B4) : Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _anilloAvance(double avance, int nAplicados, int total) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 70,
          height: 70,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: avance.clamp(0.0, 1.0).toDouble(),
                strokeWidth: 7,
                backgroundColor: Colors.white.withOpacity(0.18),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              Center(
                child: Text(
                  '${(avance * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '% aplicado',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              total == 0 ? 'Sin cuadros' : '$nAplicados/$total cuadros',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // KPIs de avance
  // ---------------------------------------------------------------------------
  Widget _buildKpis() {
    double supAplicada = 0.0;
    double caldoAplicado = 0.0;
    for (var t in _registrosAgrupados) {
      supAplicada += _num(t['sup_total']);
      caldoAplicado += _num(t['litros']);
    }
    final double volProm = supAplicada > 0 ? caldoAplicado / supAplicada : 0.0;
    final double maquinas = CalculoDosis.volumenMaquina > 0
        ? caldoAplicado / CalculoDosis.volumenMaquina
        : 0.0;
    final int nRegistros = _registrosAgrupadasCount();

    return _grillaTiles(
      [
        _KpiTile(
          icono: Icons.square_foot_rounded,
          color: AgroColors.primario,
          valor: '${supAplicada.toStringAsFixed(2)} Ha',
          label: 'Superficie aplicada',
        ),
        _KpiTile(
          icono: Icons.water_drop_rounded,
          color: _kAzul,
          valor: '${caldoAplicado.toStringAsFixed(0)} L',
          label: 'Caldo aplicado',
          detalle: volProm > 0 ? '${volProm.toStringAsFixed(0)} L/Ha prom.' : null,
        ),
        _KpiTile(
          icono: Icons.local_shipping_rounded,
          color: AgroColors.warn,
          valor: maquinas.toStringAsFixed(2),
          label: 'Máquinas',
          detalle: 'de ${CalculoDosis.volumenMaquina.toStringAsFixed(0)} L',
        ),
        _KpiTile(
          icono: Icons.assignment_turned_in_rounded,
          color: _kVioleta,
          valor: '${_registrosAgrupados.length}',
          label: 'Labores',
          detalle: '$nRegistros registros',
        ),
      ],
      minAncho: 170,
    );
  }

  // ---------------------------------------------------------------------------
  // Tarjeta receta técnica
  // ---------------------------------------------------------------------------
  Widget _buildReceta(List<Map<String, dynamic>> itemsReceta) {
    final double supTotal = _num(widget.orden['sup_total_calculada']);
    final double caldoHa = _num(widget.orden['vol_ha']);
    final double cantMaq = CalculoDosis.cantidadMaquinas(supTotal, caldoHa);

    return AgroCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgroSectionHeader(
            titulo: 'Receta técnica',
            subtitulo: 'Cantidades para toda la superficie de la orden',
            icono: Icons.science_rounded,
            trailing: AgroBadge(
              texto: '${itemsReceta.length} prod.',
              color: AgroColors.primario,
              fondo: AgroColors.primarioSoft,
            ),
          ),
          const SizedBox(height: 14),
          if (itemsReceta.isEmpty)
            _avisoPanel(
              icono: Icons.info_outline_rounded,
              texto: 'La orden no tiene productos cargados.',
              color: AgroColors.neutral,
              fondo: AgroColors.neutralSoft,
            )
          else
            for (int i = 0; i < itemsReceta.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _itemProducto(itemsReceta[i], i, supTotal, caldoHa),
              ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AgroColors.primarioSoft,
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _datoPie(Icons.square_foot_rounded,
                    '${supTotal.toStringAsFixed(2)} Ha'),
                _datoPie(Icons.water_drop_rounded,
                    '${caldoHa.toStringAsFixed(0)} L/Ha'),
                _datoPie(Icons.local_shipping_rounded,
                    '${cantMaq.toStringAsFixed(2)} máq. de ${CalculoDosis.volumenMaquina.toStringAsFixed(0)} L'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Máquinas = Sup. × caldo ÷ ${CalculoDosis.volumenMaquina.toStringAsFixed(0)} L · '
            'Producto (por 100 L) = máquinas × dosis máq. · Producto (por Ha) = dosis × Sup.',
            style: AgroText.secundario.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _datoPie(IconData icono, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 15, color: AgroColors.primario),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AgroColors.primario,
            ),
          ),
        ),
      ],
    );
  }

  Widget _itemProducto(
    Map<String, dynamic> it,
    int indice,
    double supTotal,
    double caldoHa,
  ) {
    final String tc = _txt(it['tc']);
    final String ti = _txt(it['ti']);
    final bool porHa = CalculoDosis.esPorHa(it);
    final double dosisMaq = CalculoDosis.dosisMaquina(it, caldoHa);
    final double total = CalculoDosis.cantidadProducto(it, supTotal, caldoHa);
    final Color color = _colorProducto(indice);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.science_rounded, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _txt(it['producto']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AgroTheme.colorText,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AgroBadge(
                      texto: porHa ? 'Por Ha' : 'Por 100 L',
                      color: porHa ? AgroColors.warn : AgroColors.ok,
                      fondo: porHa ? AgroColors.warnSoft : AgroColors.okSoft,
                    ),
                    Text(
                      'Dosis ${CalculoDosis.textoDosis(it)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.secundario.copyWith(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Por máquina: ${dosisMaq.toStringAsFixed(2)} L/Kg',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.secundario.copyWith(fontSize: 12),
                ),
                if (tc.isNotEmpty || ti.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (tc.isNotEmpty)
                        AgroTag(
                            texto: 'Carencia ${tc}d',
                            icono: Icons.hourglass_bottom_rounded),
                      if (ti.isNotEmpty)
                        AgroTag(
                            texto: 'Reingreso ${ti}hs',
                            icono: Icons.timer_outlined),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('TOTAL', style: AgroText.overline),
              const SizedBox(height: 2),
              Text(
                total.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AgroColors.primario,
                ),
              ),
              const Text(
                'L/Kg',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AgroTheme.colorTextSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Labores registradas (línea de tiempo)
  // ---------------------------------------------------------------------------
  Widget _buildLabores(bool movil) {
    final List<Widget> contenido = [];

    if (_cargando) {
      contenido.add(const AgroCard(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: AgroLoading(mensaje: 'Cargando labores…'),
      ));
    } else if (_registrosAgrupados.isEmpty) {
      contenido.add(AgroCard(
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 320,
          child: AgroEmptyState(
            icono: Icons.agriculture_rounded,
            titulo: 'Sin labores registradas',
            mensaje:
                'Todavía no se registraron labores de aplicación para esta orden.',
            accion: AgroButton(
              label: 'Registrar aplicación',
              icono: Icons.add_task_rounded,
              onTap: _abrirModalRegistrarAplicacion,
            ),
          ),
        ),
      ));
    } else {
      contenido.add(_listaLabores());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _encabezadoLabores(movil),
        if (!_ordenActiva) ...[
          const SizedBox(height: 10),
          _avisoPanel(
            icono: Icons.lock_outline_rounded,
            texto: 'Orden no activa: las labores son de solo lectura.',
            color: AgroColors.neutral,
            fondo: AgroColors.neutralSoft,
          ),
        ],
        const SizedBox(height: 12),
        ...contenido,
      ],
    );
  }

  Widget _encabezadoLabores(bool movil) {
    final int n = _registrosAgrupados.length;
    return Row(
      children: [
        const AgroIconBox(
            icono: Icons.history_rounded, color: _kVioleta, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: Text(
                      'Labores registradas',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: AgroTheme.colorText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kVioleta,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$n',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _cargando
                    ? 'Actualizando…'
                    : (n == 0
                        ? 'Todavía no hay tiradas registradas'
                        : '${_registrosAgrupadasCount()} registros · tocá una labor para ver el detalle'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AgroText.secundario,
              ),
            ],
          ),
        ),
        if (!movil) ...[
          const SizedBox(width: 10),
          AgroButton(
            label: 'Registrar aplicación',
            icono: Icons.add_task_rounded,
            compacto: true,
            onTap: _abrirModalRegistrarAplicacion,
          ),
        ],
      ],
    );
  }

  Widget _listaLabores() {
    return LayoutBuilder(
      builder: (context, c) {
        final double w = c.maxWidth.isFinite ? c.maxWidth : 600.0;
        const double gap = 12;
        if (w < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < _registrosAgrupados.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _tarjetaLabor(_registrosAgrupados[i]),
              ],
            ],
          );
        }
        final double anchoCard = ((w - gap) / 2).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _registrosAgrupados
              .map((t) => SizedBox(width: anchoCard, child: _tarjetaLabor(t)))
              .toList(),
        );
      },
    );
  }

  Widget _menuLabor(Map<String, dynamic> tirada) {
    final bool activa = _ordenActiva;
    return PopupMenuButton<String>(
      tooltip: 'Opciones de la labor',
      icon: const Icon(Icons.more_vert_rounded,
          size: 20, color: AgroTheme.colorTextSecondary),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd)),
      onSelected: (v) {
        if (v == 'ver') {
          _mostrarDetalleYModificarRegistro(tirada);
        } else if (v == 'eliminar') {
          _eliminarLabor(tirada);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'ver',
          child: Row(
            children: [
              Icon(activa ? Icons.edit_rounded : Icons.visibility_rounded,
                  size: 18, color: AgroColors.primario),
              const SizedBox(width: 10),
              Text(
                activa ? 'Ver / editar' : 'Ver detalle',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AgroTheme.colorText,
                ),
              ),
            ],
          ),
        ),
        if (activa)
          const PopupMenuItem<String>(
            value: 'eliminar',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded,
                    size: 18, color: AgroColors.danger),
                SizedBox(width: 10),
                Text(
                  'Eliminar labor',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AgroColors.danger,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _burbujaFecha(dynamic fecha) {
    final String raw = _txt(fecha);
    final DateTime? d = DateTime.tryParse(raw);
    String dia;
    String mes;
    String anio;
    if (d == null) {
      dia = '--';
      mes = raw.isEmpty ? '' : raw;
      anio = '';
    } else {
      dia = d.day.toString().padLeft(2, '0');
      anio = '${d.year}';
      try {
        mes = DateFormat('MMM', 'es').format(d).toUpperCase().replaceAll('.', '');
      } catch (_) {
        mes = DateFormat('MM').format(d);
      }
    }

    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AgroColors.primario.withOpacity(0.14),
            AgroColors.primario.withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgroColors.primario.withOpacity(0.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dia,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 21,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: AgroColors.primario,
            ),
          ),
          if (mes.isNotEmpty)
            Text(
              mes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AgroColors.primario,
              ),
            ),
          if (anio.isNotEmpty)
            Text(
              anio,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AgroTheme.colorTextSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chipCuadroLabor(String texto, {bool extra = false}) {
    final Color c = extra ? AgroColors.neutral : AgroColors.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: extra ? AgroColors.neutralSoft : AgroColors.okSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: c,
        ),
      ),
    );
  }

  Widget _miniDato(IconData icono, String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaIcono(IconData icono, String texto,
      {bool fuerte = false, bool vacio = false}) {
    return Row(
      children: [
        Icon(icono,
            size: 15,
            color: fuerte ? AgroColors.primario : AgroTheme.colorTextSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fuerte ? 14 : 12.5,
              fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
              fontStyle: vacio ? FontStyle.italic : FontStyle.normal,
              color: fuerte
                  ? AgroTheme.colorText
                  : (vacio
                      ? AgroTheme.colorTextSecondary
                      : AgroTheme.colorText),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaLabor(Map<String, dynamic> tirada) {
    final double sup = _num(tirada['sup_total']);
    final double litros = _num(tirada['litros']);
    final double volHa = _num(tirada['vol_ha']);
    final String tractorista = _txt(tirada['tractorista']);
    final String maquina = _txt(tirada['pulverizadora']);

    final List<String> cuadros = _txt(tirada['cuadros_resumen'])
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final List<String> visibles = cuadros.take(3).toList();
    final int resto = cuadros.length - visibles.length;

    return AgroCard(
      onTap: () => _mostrarDetalleYModificarRegistro(tirada),
      padding: const EdgeInsets.fromLTRB(12, 12, 2, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _burbujaFecha(tirada['fecha']),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 2),
                _lineaIcono(
                  Icons.person_rounded,
                  tractorista.isEmpty ? 'Sin tractorista' : tractorista,
                  fuerte: tractorista.isNotEmpty,
                  vacio: tractorista.isEmpty,
                ),
                const SizedBox(height: 4),
                _lineaIcono(
                  Icons.agriculture_rounded,
                  maquina.isEmpty ? 'Sin máquina' : maquina,
                  vacio: maquina.isEmpty,
                ),
                if (cuadros.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final cd in visibles)
                        _chipCuadroLabor(cd.startsWith('Ch ') ? cd : 'C $cd'),
                      if (resto > 0) _chipCuadroLabor('+$resto', extra: true),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _miniDato(Icons.square_foot_rounded,
                        '${sup.toStringAsFixed(2)} Ha', AgroColors.primario),
                    _miniDato(Icons.water_drop_rounded,
                        '${litros.toStringAsFixed(0)} L', _kAzul),
                    _miniDato(Icons.speed_rounded,
                        '${volHa.toStringAsFixed(0)} L/Ha', AgroColors.warn),
                  ],
                ),
              ],
            ),
          ),
          _menuLabor(tirada),
        ],
      ),
    );
  }
}

// =============================================================================
// WIDGETS PRIVADOS
// =============================================================================

const Color _kAzul = Color(0xFF1565C0);
const Color _kVioleta = Color(0xFF6A1B9A);
const Color _kTeal = Color(0xFF00838F);
const Color _kVerdeOscuro = Color(0xFF14503A);

const List<Color> _kPaleta = [
  AgroColors.primario,
  _kAzul,
  _kVioleta,
  AgroColors.warn,
  _kTeal,
  Color(0xFFAD1457),
];

/// Tile de indicador con color propio (fondo teñido + ícono).
class _KpiTile extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String valor;
  final String label;
  final String? detalle;
  final bool compacto;

  const _KpiTile({
    required this.icono,
    required this.color,
    required this.valor,
    required this.label,
    this.detalle,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    final double s = compacto ? 30 : 40;

    final Widget iconoBox = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(s * 0.32),
      ),
      child: Icon(icono, size: s * 0.55, color: color),
    );

    final List<Widget> textos = [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          valor,
          maxLines: 1,
          style: TextStyle(
            fontSize: compacto ? 15 : 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: color,
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        maxLines: compacto ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compacto ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: AgroTheme.colorTextSecondary,
        ),
      ),
      if (detalle != null)
        Text(
          detalle ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: color.withOpacity(0.85),
          ),
        ),
    ];

    return Container(
      padding: EdgeInsets.all(compacto ? 10 : 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd + 2),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: compacto
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                iconoBox,
                const SizedBox(height: 8),
                ...textos,
              ],
            )
          : Row(
              children: [
                iconoBox,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: textos,
                  ),
                ),
              ],
            ),
    );
  }
}

class _CuadroChip extends StatelessWidget {
  final String cuadro;
  final bool aplicado;

  /// Variante para fondos oscuros (encabezado con degradé).
  final bool claro;

  const _CuadroChip({
    required this.cuadro,
    required this.aplicado,
    this.claro = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color fondo;
    final Color borde;
    final Color colorTexto;
    final Color colorIcono;
    if (claro) {
      fondo = aplicado ? Colors.white : Colors.white.withOpacity(0.10);
      borde = aplicado ? Colors.white : Colors.white.withOpacity(0.30);
      colorTexto = aplicado ? AgroColors.primario : Colors.white;
      colorIcono = aplicado ? AgroColors.ok : Colors.white70;
    } else {
      fondo = aplicado ? AgroColors.okSoft : AgroTheme.colorBg;
      borde = aplicado ? AgroColors.ok.withOpacity(0.35) : AgroTheme.colorBorder;
      colorTexto = aplicado ? AgroColors.ok : AgroTheme.colorText;
      colorIcono = aplicado ? AgroColors.ok : AgroTheme.colorTextSecondary;
    }

    return Tooltip(
      message: aplicado ? 'Cuadro con aplicación registrada' : 'Cuadro pendiente',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borde),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              aplicado
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 13,
              color: colorIcono,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'C. $cuadro',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: colorTexto,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PANTALLA: REGISTRAR APLICACIÓN
// Selector de cuadros por cultivo / variedad en TODAS las chacras del productor
// =============================================================================

class _CuartelInv {
  final int id;
  final String chacra;
  final String cuadro;
  final double ha;
  final String variedad;
  final String cultivo;

  /// Fecha de la última aplicación registrada para esta orden (null = pendiente).
  final String? aplicadoEl;

  const _CuartelInv({
    required this.id,
    required this.chacra,
    required this.cuadro,
    required this.ha,
    required this.variedad,
    required this.cultivo,
    required this.aplicadoEl,
  });

  bool get aplicado => aplicadoEl != null;
}

// =============================================================================
// PANTALLA: REGISTRAR APLICACIÓN
// El operario ve SOLO los cuadros que el ingeniero puso en la orden.
// Puede marcar todos, o solo algunos si la aplicación se hace por tandas.
// =============================================================================

class _RegistrarAplicacionPage extends StatefulWidget {
  final Map<String, dynamic> orden;
  final int codProductor;
  final String nombreProductor;
  final String userName;

  /// clave "chacra::cuadro__variedad" → fecha de la última aplicación.
  final Map<String, String> aplicados;

  const _RegistrarAplicacionPage({
    required this.orden,
    required this.codProductor,
    required this.nombreProductor,
    required this.userName,
    required this.aplicados,
  });

  @override
  State<_RegistrarAplicacionPage> createState() =>
      _RegistrarAplicacionPageState();
}

class _RegistrarAplicacionPageState extends State<_RegistrarAplicacionPage> {
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  List<_CuartelInv> _cuarteles = [];
  final Set<int> _sel = {};
  final Set<String> _variedades = {}; // filtro (vacío = todas)
  bool _soloPendientes = false;

  late final List<CuadroRef> _refsOrden;
  late final bool _variasChacras;

  late final TextEditingController _fechaCtrl;
  late final TextEditingController _tractoristaCtrl;
  late final TextEditingController _maquinaCtrl;
  /// Caldo L/Ha: viene de la orden; el operario lo corrige si aplicó otro.
  /// Litros TOTALES de caldo aplicados en la tanda (lo carga el operario).
  /// Si queda vacío se usa lo sugerido por la orden (Sup × caldo L/Ha).
  late final TextEditingController _litrosCtrl;
  late final double _caldoOrden;
  bool _verReparto = false;

  @override
  void initState() {
    super.initState();
    _refsOrden =
        parsearCuadrosOrden(widget.orden['chacra'], widget.orden['cuadros']);
    _variasChacras = _refsOrden.map((r) => r.chacra).toSet().length > 1;

    _fechaCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    _tractoristaCtrl = TextEditingController(text: widget.userName);
    _maquinaCtrl = TextEditingController(text: "Pulverizadora 1");
    final double caldoOrden =
        double.tryParse(widget.orden['vol_ha']?.toString() ?? '') ?? 0.0;
    _caldoOrden = caldoOrden > 0 ? caldoOrden : 1000.0;
    _litrosCtrl = TextEditingController();

    _cargarInventario();
  }

  @override
  void dispose() {
    _fechaCtrl.dispose();
    _tractoristaCtrl.dispose();
    _maquinaCtrl.dispose();
    _litrosCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // DATOS
  // ---------------------------------------------------------------------------

  Future<void> _cargarInventario() async {
    // Evita setState durante initState (primera carga).
    if (!_cargando || _error != null) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final db = await DatabaseHelper.instance.database;
      final Set<String> clavesOrden = _refsOrden.map((r) => r.clave).toSet();
      final Set<String> chacrasOrden = _refsOrden.map((r) => r.chacra).toSet();
      if (clavesOrden.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cuarteles = [];
          _cargando = false;
        });
        return;
      }

      final placeholders = List.filled(chacrasOrden.length, '?').join(', ');
      final rows = await db.rawQuery('''
        SELECT id, chacra, cuadro, ha, variedad, cultivo
        FROM inventario_plantacion
        WHERE cod_productor = ? AND TRIM(chacra) IN ($placeholders)
      ''', [widget.codProductor, ...chacrasOrden]);

      // Regla: por cada combinación chacra + cuadro + variedad se SUMA la
      // superficie (el inventario puede tener varias filas iguales).
      // Solo las variedades de los cultivos/variedades que eligió el
      // ingeniero en la orden (vacío = todas).
      final Set<String> cultivosOrden =
          parsearFiltroOrden(widget.orden['cultivos']);
      final Set<String> variedadesOrden =
          parsearFiltroOrden(widget.orden['variedades']);

      final Map<String, Map<String, dynamic>> combos = {};
      for (final r in rows) {
        final String ch = (r['chacra'] ?? '').toString().trim();
        final String cd = normalizarCuadro(r['cuadro']);
        if (!clavesOrden.contains(claveCuadro(ch, cd))) continue;
        if (!coincideFiltroOrden(
            r['cultivo'], r['variedad'], cultivosOrden, variedadesOrden)) {
          continue;
        }

        final String vr = (r['variedad'] ?? '').toString().trim();
        final String k = '${claveCuadro(ch, cd)}__${vr.toLowerCase()}';
        final double ha = double.tryParse(r['ha']?.toString() ?? '0') ?? 0.0;
        final existente = combos[k];
        if (existente == null) {
          combos[k] = {
            'chacra': ch,
            'cd': cd,
            'cuadro': (r['cuadro'] ?? '').toString().trim(),
            'variedad': vr,
            'cultivo': (r['cultivo'] ?? '').toString().trim(),
            'ha': ha,
          };
        } else {
          existente['ha'] = (existente['ha'] as double) + ha;
        }
      }

      final List<_CuartelInv> lista = [];
      int idCombo = 0;
      for (final c in combos.values) {
        final String ch = c['chacra'] as String;
        final String cd = c['cd'] as String;
        final String vr = c['variedad'] as String;
        lista.add(_CuartelInv(
          id: idCombo++,
          chacra: ch,
          cuadro: c['cuadro'] as String,
          ha: c['ha'] as double,
          variedad: vr,
          cultivo: c['cultivo'] as String,
          aplicadoEl: widget.aplicados['${claveCuadro(ch, cd)}__$vr'],
        ));
      }

      lista.sort((a, b) {
        final c1 = compararNatural(a.chacra, b.chacra);
        if (c1 != 0) return c1;
        final c2 = compararNatural(a.cuadro, b.cuadro);
        if (c2 != 0) return c2;
        return a.variedad.compareTo(b.variedad);
      });

      if (!mounted) return;
      setState(() {
        _cuarteles = lista;
        // Por defecto: los pendientes. Si todos ya tienen aplicación
        // (segunda pasada), arrancamos con todos marcados.
        final pendientes = lista.where((c) => !c.aplicado).map((c) => c.id);
        _sel
          ..clear()
          ..addAll(pendientes.isNotEmpty ? pendientes : lista.map((c) => c.id));
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // CÁLCULOS
  // ---------------------------------------------------------------------------

  Map<String, int> get _conteoVariedades {
    final Map<String, int> m = {};
    for (final c in _cuarteles) {
      final k = c.variedad.isEmpty ? 'Sin variedad' : c.variedad;
      m[k] = (m[k] ?? 0) + 1;
    }
    final claves = m.keys.toList()..sort();
    return {for (final k in claves) k: m[k]!};
  }

  List<_CuartelInv> get _visibles => _cuarteles.where((c) {
        if (_soloPendientes && c.aplicado) return false;
        if (_variedades.isEmpty) return true;
        final k = c.variedad.isEmpty ? 'Sin variedad' : c.variedad;
        return _variedades.contains(k);
      }).toList();

  Map<String, List<_CuartelInv>> _agrupar(List<_CuartelInv> lista) {
    final Map<String, List<_CuartelInv>> m = {};
    for (final c in lista) {
      m.putIfAbsent(c.chacra, () => []).add(c);
    }
    final claves = m.keys.toList()..sort(compararNatural);
    return {for (final k in claves) k: m[k]!};
  }

  List<_CuartelInv> get _seleccionados =>
      _cuarteles.where((c) => _sel.contains(c.id)).toList();

  double get _supSeleccion => _seleccionados.fold(0.0, (s, c) => s + c.ha);

  /// Litros sugeridos según la orden para la selección actual.
  double get _litrosSugeridos => _supSeleccion * _caldoOrden;

  bool get _litrosCargados =>
      (double.tryParse(_litrosCtrl.text.replaceAll(',', '.').trim()) ?? 0) > 0;

  /// Litros totales de la tanda (cargados o sugeridos).
  double get _litrosTotales {
    final v =
        double.tryParse(_litrosCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
    return v > 0 ? v : _litrosSugeridos;
  }

  /// Caldo por hectárea resultante = litros totales ÷ Sup. total.
  double get _caldoHa {
    final sup = _supSeleccion;
    return sup > 0 ? _litrosTotales / sup : 0.0;
  }

  /// Litros totales de caldo para una superficie (Sup × caldo L/Ha).
  double _litrosPara(double sup) => sup * _caldoHa;

  String _ha(double v) => v.toStringAsFixed(2);

  String _fechaCorta(String? f) {
    final d = DateTime.tryParse(f ?? '');
    return d == null ? (f ?? '') : DateFormat('dd/MM').format(d);
  }

  // ---------------------------------------------------------------------------
  // ACCIONES
  // ---------------------------------------------------------------------------

  Future<void> _elegirFecha() async {
    DateTime inicial = DateTime.tryParse(_fechaCtrl.text.trim()) ?? DateTime.now();
    if (inicial.isBefore(DateTime(2000)) || inicial.isAfter(DateTime(2100))) {
      inicial = DateTime.now();
    }
    final DateTime? elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Fecha de aplicación',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (elegida != null && mounted) {
      setState(() =>
          _fechaCtrl.text = DateFormat('yyyy-MM-dd').format(elegida));
    }
  }

  void _toggleCuartel(_CuartelInv c) {
    setState(() {
      if (!_sel.remove(c.id)) _sel.add(c.id);
    });
  }

  void _toggleLista(List<_CuartelInv> items) {
    final ids = items.map((c) => c.id).toSet();
    setState(() {
      if (ids.isNotEmpty && ids.every(_sel.contains)) {
        _sel.removeAll(ids);
      } else {
        _sel.addAll(ids);
      }
    });
  }

  void _seleccionRapida(String modo) {
    setState(() {
      _sel.clear();
      if (modo == 'TODOS') {
        _sel.addAll(_cuarteles.map((c) => c.id));
      } else if (modo == 'PENDIENTES') {
        _sel.addAll(_cuarteles.where((c) => !c.aplicado).map((c) => c.id));
      }
    });
  }

  void _verSeleccion() {
    mostrarAgroPanel<void>(
      context: context,
      titulo: 'Cuadros de esta tanda',
      subtitulo: 'Tocá la X para quitar un cuadro',
      icono: Icons.checklist_rounded,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setPanel) {
            final grupos = _agrupar(_seleccionados);
            if (grupos.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No hay cuadros seleccionados.',
                    textAlign: TextAlign.center, style: AgroText.secundario),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in grupos.entries) ...[
                  if (_variasChacras)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: Text(
                        'CHACRA ${e.key}  ·  ${e.value.length} cuadros  ·  ${_ha(e.value.fold(0.0, (s, c) => s + c.ha))} ha',
                        style: AgroText.overline,
                      ),
                    ),
                  ...e.value.map((c) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorBg,
                          borderRadius:
                              BorderRadius.circular(AgroTheme.radiusMd),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Cuadro ${c.cuadro} · ${c.variedad.isEmpty ? 'Sin variedad' : c.variedad}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AgroText.cuerpo
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text('${_ha(c.ha)} ha', style: AgroText.label),
                            IconButton(
                              tooltip: 'Quitar',
                              icon: const Icon(Icons.close_rounded,
                                  size: 18, color: AgroColors.danger),
                              onPressed: () {
                                setState(() => _sel.remove(c.id));
                                setPanel(() {});
                              },
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _guardar() async {
    final cuartelesSeleccionados = _seleccionados;

    if (cuartelesSeleccionados.isEmpty) {
      mostrarAgroSnack(context,
          'Seleccioná al menos un cuadro para registrar la aplicación',
          tipo: AgroSnackTipo.aviso);
      return;
    }
    if (_fechaCtrl.text.trim().isEmpty) {
      mostrarAgroSnack(context, 'Indicá la fecha de aplicación',
          tipo: AgroSnackTipo.aviso);
      return;
    }
    if (_litrosTotales <= 0) {
      mostrarAgroSnack(context, 'Indicá los litros totales aplicados',
          tipo: AgroSnackTipo.aviso);
      return;
    }

    final List<Map<String, dynamic>> itemsReceta =
        ((widget.orden['items'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
    if (itemsReceta.isEmpty) {
      mostrarAgroSnack(context, 'La orden no tiene productos en la receta',
          tipo: AgroSnackTipo.aviso);
      return;
    }

    final double supTotal =
        cuartelesSeleccionados.fold(0.0, (s, c) => s + c.ha);
    final double litrosTotales = _litrosTotales;
    final double caldoHa = supTotal > 0 ? litrosTotales / supTotal : 0.0;

    // Total de cada producto para TODA la tanda, repartido por Ha entre las
    // combinaciones (cuadro + variedad). La suma de lo repartido = total.
    final List<double> hasCombos =
        cuartelesSeleccionados.map((c) => c.ha).toList();
    final Map<int, List<double>> repartoPorProducto = {};
    for (int p = 0; p < itemsReceta.length; p++) {
      final double totalProd = CalculoDosis.totalProductoTanda(
          itemsReceta[p], supTotal, litrosTotales);
      repartoPorProducto[p] = CalculoDosis.repartirPorHa(totalProd, hasCombos);
    }
    final int repetidos = cuartelesSeleccionados.where((c) => c.aplicado).length;

    final bool confirmado = await confirmarAgro(
      context: context,
      titulo: 'Confirmar registro',
      mensaje:
          'Se registrarán ${cuartelesSeleccionados.length * itemsReceta.length} labores '
          '(${cuartelesSeleccionados.length} cuadros × ${itemsReceta.length} productos) '
          'sobre ${_ha(supTotal)} ha y se descontará el consumo del stock de insumos.'
          '${repetidos > 0 ? '\n\n⚠ $repetidos ${repetidos == 1 ? 'cuadro ya tiene' : 'cuadros ya tienen'} una aplicación registrada en esta orden.' : ''}',
      confirmar: 'Guardar',
      icono: Icons.inventory_2_rounded,
    );
    if (!confirmado || !mounted) return;

    setState(() => _guardando = true);

    int contador = 0;
    try {
      final db = await DatabaseHelper.instance.database;
      int siguienteRegId = await DatabaseHelper.instance
          .obtenerSiguienteId('aplicaciones_registros', 'registro');
      Batch batch = db.batch();
      final String fechaAplic = _fechaCtrl.text.trim();

      final List<Map<String, dynamic>> consumosParaRemoto = [];

      // Iteración: combinación (chacra + cuadro + variedad) × producto.
      //  • Sup. de la combinación = suma de sus filas de inventario.
      //  • Litros de la combinación = (litros totales ÷ Sup. total) × Ha.
      //  • Producto: total de la tanda repartido según Ha (ver arriba).
      for (int ci = 0; ci < cuartelesSeleccionados.length; ci++) {
        final cuartel = cuartelesSeleccionados[ci];
        final double supCuartel = cuartel.ha;
        final double litrosCuartel = supCuartel * caldoHa;

        for (int pi = 0; pi < itemsReceta.length; pi++) {
          final prod = itemsReceta[pi];
          final String regAplicId = '${siguienteRegId + contador}';
          final double dosisMaq = CalculoDosis.dosisMaquina(prod, caldoHa);
          final double consumoProd = repartoPorProducto[pi]![ci];

          final int idInsumos = prod['cod_producto'] is int
              ? prod['cod_producto']
              : int.tryParse(prod['cod_producto']?.toString() ?? '0') ?? 0;

          batch.insert('aplicaciones_registros', {
            'registro': regAplicId,
            'cod_receta': prod['cod_receta'],
            'cod_orden': widget.orden['cod_orden'],
            'cod_productor': widget.codProductor,
            'productor': widget.nombreProductor,
            'orden_aplic': prod['orden_aplic'] ?? 1,
            'ref': widget.orden['cod_orden'],
            'fecha': fechaAplic,
            // Chacra real del cuadro (la orden puede tener varias chacras)
            'chacra': cuartel.chacra,
            'cuadros': cuartel.cuadro,
            'variedad': cuartel.variedad,
            'sup_aplic': supCuartel,
            'motivo_aplic': widget.orden['motivo'],
            'momento_aplic': widget.orden['momento'],
            'vol_aplic_ha': caldoHa,
            'tractorista': _tractoristaCtrl.text.trim(),
            'pulverizadora': _maquinaCtrl.text.trim(),
            'litros': litrosCuartel,
            'cod_producto': idInsumos,
            'producto': prod['producto'],
            'dosis_100': prod['dosis_100'],
            'dosis_maq': dosisMaq,
            'tc': prod['tc'],
            'ti': prod['ti'],
            'habilitado': 'ACTIVO',
            'consumo_prod': consumoProd,
            'mostrar': 'SI',
            'sincronizado': 0,
          });

          // Descuento en insumos_detalles con ID de aplicación en reg_aplic
          final String codMovConsumo =
              "CON_${regAplicId}_${DateTime.now().millisecondsSinceEpoch}_$contador";
          final rowConsumoStock = {
            'cod_mov': codMovConsumo,
            'reg_ingreso': null,
            'reg_aplic': regAplicId,
            'cod_productor': widget.codProductor,
            'productor': widget.nombreProductor,
            'deposito': 'PAÑOL',
            'ID_Insumos': idInsumos,
            'producto': prod['producto'],
            'concetracion': '',
            'movimiento': 'CONSUMO',
            'cantidad': -consumoProd, // Consumo en negativo
            'unidad': 'L/Kg',
            'fec_vencimiento': null,
            'fecha_ingreso': fechaAplic,
            'reg_consumo': 'APLICACION_ORDEN_${widget.orden['cod_orden']}',
            'sincronizado': 0,
          };

          batch.insert('insumos_detalles', rowConsumoStock);
          consumosParaRemoto.add(rowConsumoStock);

          contador++;
        }
      }

      await batch.commit(noResult: true);

      // Sincronización a Supabase
      for (var c in consumosParaRemoto) {
        try {
          final rowSync = Map<String, dynamic>.from(c)..remove('sincronizado');
          await Supabase.instance.client.from('insumos_detalles').upsert(rowSync);
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      mostrarAgroSnack(context, 'Error al guardar la aplicación: $e',
          tipo: AgroSnackTipo.error);
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, contador);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool sinCuadros = !_cargando && _error == null && _cuarteles.isEmpty;
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: 'Registrar aplicación',
        subtitulo:
            "Orden N° ${widget.orden['cod_orden']} · ${widget.nombreProductor}",
      ),
      body: _cargando
          ? const AgroLoading(mensaje: 'Cargando cuadros de la orden…')
          : _error != null
              ? AgroEmptyState(
                  icono: Icons.error_outline_rounded,
                  titulo: 'No se pudieron cargar los cuadros',
                  mensaje: _error,
                  accion: AgroButton(
                    label: 'Reintentar',
                    icono: Icons.refresh_rounded,
                    onTap: _cargarInventario,
                  ),
                )
              : sinCuadros
                  ? const AgroEmptyState(
                      icono: Icons.grid_off_rounded,
                      titulo: 'La orden no tiene cuadros válidos',
                      mensaje:
                          'Los cuadros de la orden no se encontraron en el inventario de plantación. Pedile al ingeniero que revise la orden.',
                    )
                  : LayoutBuilder(
                      builder: (context, c) =>
                          c.maxWidth >= AgroBreakpoints.tablet
                              ? _layoutAncho()
                              : _layoutMovil(),
                    ),
      bottomNavigationBar: (_cargando || _error != null || sinCuadros)
          ? null
          : _barraInferior(),
    );
  }

  Widget _layoutMovil() {
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        AgroContent(child: _cardDatos(conResumen: false)),
        const SizedBox(height: 14),
        AgroContent(child: _cardCuadros()),
      ],
    );
  }

  Widget _layoutAncho() {
    return AgroContent(
      maxWidth: 1320,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 360,
            child: ListView(
              padding: const EdgeInsets.only(top: 20, bottom: 24),
              children: [_cardDatos(conResumen: true)],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 20, bottom: 24),
              children: [_cardCuadros()],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------- 1. Datos -----------------------------------

  Widget _cardDatos({required bool conResumen}) {
    final sel = _seleccionados;
    final double sup = sel.fold(0.0, (s, c) => s + c.ha);
    final double litros = _litrosTotales;
    final double maquinas = litros / CalculoDosis.volumenMaquina;

    Widget campo(Widget w) =>
        Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

    return AgroCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) {
          final bool dosCol = c.maxWidth >= 520;
          Widget par(Widget a, Widget b) => dosCol
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 12),
                    Expanded(child: b),
                  ],
                )
              : Column(children: [a, b]);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PasoHeader(
                numero: 1,
                titulo: 'Datos de la labor',
                subtitulo: 'Cuándo, quién y con qué máquina',
              ),
              const SizedBox(height: 16),
              par(
                campo(TextFormField(
                  controller: _fechaCtrl,
                  readOnly: true,
                  onTap: _elegirFecha,
                  style: AgroText.cuerpo,
                  decoration: agroInputDecoration(
                    label: 'Fecha de aplicación',
                    icono: Icons.calendar_today_rounded,
                  ).copyWith(
                    suffixIcon: const Icon(Icons.edit_calendar_rounded,
                        size: 20, color: AgroColors.primario),
                  ),
                )),
                campo(TextFormField(
                  controller: _tractoristaCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: AgroText.cuerpo,
                  decoration: agroInputDecoration(
                    label: 'Tractorista',
                    icono: Icons.person_outline_rounded,
                  ),
                )),
              ),
              par(
                campo(TextFormField(
                  controller: _maquinaCtrl,
                  style: AgroText.cuerpo,
                  decoration: agroInputDecoration(
                    label: 'Máquina / pulverizadora',
                    icono: Icons.agriculture_rounded,
                  ),
                )),
                campo(TextFormField(
                  controller: _litrosCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: AgroText.cuerpo,
                  decoration: agroInputDecoration(
                    label: 'Litros totales aplicados',
                    hint: _litrosSugeridos > 0
                        ? 'Sugerido: ${_litrosSugeridos.toStringAsFixed(0)}'
                        : null,
                    icono: Icons.water_drop_outlined,
                    sufijo: 'L',
                    helper: sup <= 0
                        ? 'Marcá los cuadros de la tanda'
                        : '${_litrosCargados ? '' : 'Sin cargar: se usa lo de la orden. '}'
                            '${_caldoHa.toStringAsFixed(0)} L/Ha · ${maquinas.toStringAsFixed(2)} máq. de ${CalculoDosis.volumenMaquina.toStringAsFixed(0)} L',
                  ),
                )),
              ),
              if (conResumen) ...[
                const SizedBox(height: 4),
                const Text('RESUMEN DE LA TANDA', style: AgroText.overline),
                const SizedBox(height: 8),
                AgroStatGrid(
                  stats: [
                    AgroStat(
                        label: 'Cuadros',
                        valor: '${sel.length}',
                        icono: Icons.grid_view_rounded),
                    AgroStat(
                        label: 'Superficie',
                        valor: '${_ha(sup)} ha',
                        icono: Icons.square_foot_rounded),
                    AgroStat(
                        label: 'Caldo total',
                        valor: '${litros.toStringAsFixed(0)} L',
                        icono: Icons.water_drop_outlined),
                    AgroStat(
                        label: 'Máquinas',
                        valor: maquinas.toStringAsFixed(2),
                        icono: Icons.local_shipping_outlined),
                  ],
                ),
                const SizedBox(height: 12),
                const _AyudaTexto(
                  'Caldo/Ha = litros totales ÷ Sup. total. Producto total: por 100 L = '
                  '(litros ÷ 2000) × dosis máq.; por Ha = dosis × Sup. '
                  'Ese total se reparte entre cada cuadro y variedad según sus Ha.',
                ),
                const SizedBox(height: 12),
                _previewConsumos(sup),
              ],
              if (!conResumen) _previewConsumos(sup),
            ],
          );
        },
      ),
    );
  }

  /// Total de cada producto para la tanda y cómo se reparte por cuadro y
  /// variedad según sus Ha (igual que al guardar).
  Widget _previewConsumos(double supSel) {
    final List<Map<String, dynamic>> items =
        ((widget.orden['items'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
    if (items.isEmpty || supSel <= 0) return const SizedBox.shrink();
    final sel = _seleccionados;
    final double litros = _litrosTotales;
    final List<double> has = sel.map((c) => c.ha).toList();

    const colores = [
      AgroColors.primario,
      Color(0xFF1565C0),
      Color(0xFF6A1B9A),
      AgroColors.warn,
      Color(0xFFC62828),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        border: Border.all(color: AgroTheme.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded,
                  size: 18, color: AgroColors.primario),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('PRODUCTO A DESCONTAR', style: AgroText.overline),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _verReparto = !_verReparto),
                style: TextButton.styleFrom(
                  foregroundColor: AgroColors.primario,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(
                    _verReparto
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18),
                label: Text(_verReparto ? 'Ocultar reparto' : 'Ver reparto',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (int p = 0; p < items.length; p++) ...[
            Builder(builder: (context) {
              final it = items[p];
              final Color color = colores[p % colores.length];
              final double total =
                  CalculoDosis.totalProductoTanda(it, supSel, litros);
              final List<double> reparto =
                  CalculoDosis.repartirPorHa(total, has);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border: Border.all(color: color.withOpacity(0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.science_rounded, size: 16, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${it['producto'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AgroText.cuerpo.copyWith(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${total.toStringAsFixed(2)} L/Kg',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CalculoDosis.esPorHa(it)
                          ? '${CalculoDosis.textoDosis(it)} × ${_ha(supSel)} ha'
                          : '${(litros / CalculoDosis.volumenMaquina).toStringAsFixed(2)} máq. × ${CalculoDosis.dosisMaquina(it, _caldoHa).toStringAsFixed(2)} por máq.',
                      style: AgroText.secundario.copyWith(fontSize: 11.5),
                    ),
                    if (_verReparto) ...[
                      const SizedBox(height: 6),
                      for (int i = 0; i < sel.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const SizedBox(width: 22),
                              Expanded(
                                child: Text(
                                  'C ${sel[i].cuadro} · ${sel[i].variedad.isEmpty ? 'Sin variedad' : sel[i].variedad} (${_ha(sel[i].ha)} ha)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AgroText.secundario
                                      .copyWith(fontSize: 11.5),
                                ),
                              ),
                              Text(
                                reparto[i].toStringAsFixed(3),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AgroTheme.colorText,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ----------------------------- 2. Cuadros ---------------------------------

  Widget _cardCuadros() {
    final int total = _cuarteles.length;
    final int nAplicados = _cuarteles.where((c) => c.aplicado).length;
    final int nPendientes = total - nAplicados;
    final variedades = _conteoVariedades;
    final visibles = _visibles;
    final grupos = _agrupar(visibles);

    final bool esTodos = _sel.length == total && total > 0;
    final Set<int> idsPend =
        _cuarteles.where((c) => !c.aplicado).map((c) => c.id).toSet();
    final bool esPendientes = nPendientes > 0 &&
        nPendientes < total &&
        _sel.length == idsPend.length &&
        idsPend.every(_sel.contains);

    return AgroCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PasoHeader(
            numero: 2,
            titulo: '¿Qué cuadros aplicaste?',
            subtitulo: _variasChacras
                ? 'Cuadros de la orden en ${grupos.length} chacras. Si trabajás por tandas, marcá solo los de hoy.'
                : 'Cuadros de la orden. Si trabajás por tandas, marcá solo los de hoy.',
          ),
          const SizedBox(height: 14),

          // Cultivos / variedades de la orden
          if (parsearFiltroOrden(widget.orden['cultivos']).isNotEmpty ||
              parsearFiltroOrden(widget.orden['variedades']).isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AgroColors.okSoft,
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.eco_rounded, size: 20, color: AgroColors.ok),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Esta orden es solo para:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AgroColors.ok,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ...parsearFiltroOrden(widget.orden['cultivos']).map(
                                (c) => AgroTag(
                                    texto: c, icono: Icons.eco_outlined)),
                            ...parsearFiltroOrden(widget.orden['variedades'])
                                .map((v) => AgroTag(
                                    texto: v,
                                    icono: Icons.local_florist_outlined)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Avance de la orden
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AgroTheme.colorBg,
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child:
                          Text('AVANCE DE LA ORDEN', style: AgroText.overline),
                    ),
                    Text(
                      '$nAplicados de $total aplicados',
                      style: AgroText.label.copyWith(
                        color: nPendientes == 0
                            ? AgroColors.ok
                            : AgroTheme.colorText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : nAplicados / total,
                    minHeight: 8,
                    backgroundColor: AgroTheme.colorSurface,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AgroColors.primario),
                  ),
                ),
                if (nPendientes == 0) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Todos los cuadros ya tienen una aplicación. Si es una nueva pasada, registrala igual.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AgroColors.ok,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Selección rápida
          const Text('SELECCIÓN RÁPIDA', style: AgroText.overline),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                texto: 'Todos',
                cantidad: total,
                seleccionado: esTodos,
                icono: Icons.done_all_rounded,
                onTap: () => _seleccionRapida('TODOS'),
              ),
              if (nPendientes > 0 && nAplicados > 0)
                _chip(
                  texto: 'Solo pendientes',
                  cantidad: nPendientes,
                  seleccionado: esPendientes,
                  icono: Icons.pending_actions_rounded,
                  color: AgroColors.warn,
                  onTap: () => _seleccionRapida('PENDIENTES'),
                ),
              _chip(
                texto: 'Ninguno',
                seleccionado: _sel.isEmpty,
                icono: Icons.remove_done_rounded,
                color: AgroColors.neutral,
                onTap: () => _seleccionRapida('NINGUNO'),
              ),
            ],
          ),

          // Filtros de vista
          if (variedades.length > 1 || nAplicados > 0) ...[
            const SizedBox(height: 16),
            const Text('MOSTRAR', style: AgroText.overline),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (nAplicados > 0 && nPendientes > 0)
                  _chip(
                    texto: 'Ocultar aplicados',
                    seleccionado: _soloPendientes,
                    icono: Icons.visibility_off_outlined,
                    color: AgroColors.neutral,
                    onTap: () =>
                        setState(() => _soloPendientes = !_soloPendientes),
                  ),
                if (variedades.length > 1)
                  ...variedades.entries.map((e) => _chip(
                        texto: e.key,
                        cantidad: e.value,
                        seleccionado: _variedades.contains(e.key),
                        color: AgroColors.warn,
                        onTap: () => setState(() {
                          if (!_variedades.remove(e.key)) {
                            _variedades.add(e.key);
                          }
                        }),
                      )),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AgroTheme.colorBorder),
          const SizedBox(height: 12),

          // Lista de cuadros
          if (visibles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  const Icon(Icons.filter_alt_off_outlined,
                      size: 30, color: AgroTheme.colorTextSecondary),
                  const SizedBox(height: 8),
                  const Text('No hay cuadros con ese filtro',
                      textAlign: TextAlign.center,
                      style: AgroText.secundario),
                  const SizedBox(height: 10),
                  AgroButton(
                    label: 'Mostrar todos',
                    tipo: AgroButtonTipo.secundario,
                    compacto: true,
                    onTap: () => setState(() {
                      _variedades.clear();
                      _soloPendientes = false;
                    }),
                  ),
                ],
              ),
            )
          else
            for (final e in grupos.entries) ...[
              if (_variasChacras) _encabezadoChacra(e.key, e.value),
              _grilla(e.value),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _encabezadoChacra(String chacra, List<_CuartelInv> items) {
    final int n = items.where((c) => _sel.contains(c.id)).length;
    final bool todos = n == items.length && n > 0;
    final double ha = items.fold(0.0, (s, c) => s + c.ha);
    return InkWell(
      onTap: () => _toggleLista(items),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
        child: Row(
          children: [
            Checkbox(
              value: todos ? true : (n == 0 ? false : null),
              tristate: true,
              activeColor: AgroColors.primario,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5)),
              onChanged: (_) => _toggleLista(items),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chacra $chacra', style: AgroText.tituloCard),
                  Text(
                    '$n de ${items.length} marcados · ${_ha(ha)} ha',
                    style: AgroText.secundario.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grilla(List<_CuartelInv> items) {
    return LayoutBuilder(
      builder: (context, c) {
        final int cols = c.maxWidth >= 760 ? 3 : (c.maxWidth >= 440 ? 2 : 1);
        const gap = 8.0;
        final double w =
            ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map((cu) => SizedBox(width: w, child: _tileCuadro(cu)))
              .toList(),
        );
      },
    );
  }

  Widget _tileCuadro(_CuartelInv c) {
    final bool sel = _sel.contains(c.id);

    return Material(
      color: sel ? AgroColors.primarioSoft : AgroTheme.colorSurface,
      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      child: InkWell(
        onTap: () => _toggleCuartel(c),
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
            border: Border.all(
              color: sel ? AgroColors.primario : AgroTheme.colorBorder,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                sel
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: sel
                    ? AgroColors.primario
                    : AgroTheme.colorTextSecondary.withOpacity(0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Cuadro ${c.cuadro}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AgroTheme.colorText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${c.variedad.isEmpty ? 'Sin variedad' : c.variedad} · ${_ha(c.ha)} ha',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.secundario.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              c.aplicado
                  ? AgroBadge(
                      texto: 'Aplicado ${_fechaCorta(c.aplicadoEl)}',
                      color: AgroColors.ok,
                      fondo: AgroColors.okSoft,
                      icono: Icons.check_rounded,
                    )
                  : const AgroBadge(
                      texto: 'Pendiente',
                      color: AgroColors.warn,
                      fondo: AgroColors.warnSoft,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required String texto,
    int? cantidad,
    required bool seleccionado,
    required VoidCallback onTap,
    Color color = AgroColors.primario,
    IconData? icono,
  }) {
    return Material(
      color: seleccionado ? color : AgroTheme.colorSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
            color: seleccionado ? color : AgroTheme.colorBorder, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null) ...[
                Icon(icono,
                    size: 16,
                    color: seleccionado ? Colors.white : color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        seleccionado ? FontWeight.w800 : FontWeight.w600,
                    color: seleccionado ? Colors.white : AgroTheme.colorText,
                  ),
                ),
              ),
              if (cantidad != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: seleccionado
                        ? Colors.white.withOpacity(0.25)
                        : AgroTheme.colorBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$cantidad',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: seleccionado
                          ? Colors.white
                          : AgroTheme.colorTextSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------- Barra inferior -----------------------------

  Widget _barraInferior() {
    final sel = _seleccionados;
    final double sup = sel.fold(0.0, (s, c) => s + c.ha);
    final double maquinas = _litrosPara(sup) / CalculoDosis.volumenMaquina;
    final int repetidos = sel.where((c) => c.aplicado).length;
    final bool movil = AgroBreakpoints.esMovil(context);

    final List<String> detalles = [
      if (sel.isNotEmpty)
        '${_litrosPara(sup).toStringAsFixed(0)} L · ${maquinas.toStringAsFixed(2)} máq.',
      if (sel.isNotEmpty && _variasChacras)
        '${sel.map((c) => c.chacra).toSet().length} chacras',
      if (sel.length < _cuarteles.length && sel.isNotEmpty)
        'tanda parcial (${sel.length}/${_cuarteles.length})',
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AgroTheme.colorSurface,
        border: Border(top: BorderSide(color: AgroTheme.colorBorder)),
        boxShadow: [
          BoxShadow(
              color: Color(0x14141E18), blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AgroContent(
          maxWidth: 1320,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (repetidos > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 15, color: AgroColors.warn),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$repetidos ${repetidos == 1 ? 'cuadro ya fue aplicado' : 'cuadros ya fueron aplicados'} en esta orden',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AgroColors.warn,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: sel.isEmpty ? null : _verSeleccion,
                        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      sel.isEmpty
                                          ? 'Ningún cuadro marcado'
                                          : '${sel.length} ${sel.length == 1 ? 'cuadro' : 'cuadros'} · ${_ha(sup)} ha',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: sel.isEmpty
                                            ? AgroTheme.colorTextSecondary
                                            : AgroTheme.colorText,
                                      ),
                                    ),
                                  ),
                                  if (sel.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.expand_less_rounded,
                                        size: 18, color: AgroColors.primario),
                                  ],
                                ],
                              ),
                              if (detalles.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  detalles.join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AgroText.secundario
                                      .copyWith(fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AgroButton(
                      label: movil ? 'Guardar' : 'Guardar y descontar stock',
                      icono: Icons.save_rounded,
                      cargando: _guardando,
                      onTap: sel.isEmpty ? null : _guardar,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasoHeader extends StatelessWidget {
  final int numero;
  final String titulo;
  final String? subtitulo;

  const _PasoHeader({required this.numero, required this.titulo, this.subtitulo});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AgroColors.primario,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$numero',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: AgroText.tituloCard),
              if (subtitulo != null) ...[
                const SizedBox(height: 2),
                Text(subtitulo!, style: AgroText.secundario),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AyudaTexto extends StatelessWidget {
  final String texto;
  const _AyudaTexto(this.texto);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded,
            size: 15, color: AgroTheme.colorTextSecondary),
        const SizedBox(width: 6),
        Expanded(
            child: Text(texto,
                style: AgroText.secundario.copyWith(fontSize: 12))),
      ],
    );
  }
}
