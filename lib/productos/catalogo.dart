// lib/aplicaciones/catalogo.dart

import 'package:aplicaciones_foliares/productos/servicio_exporStock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import 'servicio_exporStock.dart';
import '../widgets/soft_button.dart';

class CatalogoInsumosScreen extends StatefulWidget {
  final int? codProductor;
  final String? nombreProductor;

  const CatalogoInsumosScreen({
    super.key,
    this.codProductor,
    this.nombreProductor,
  });

  @override
  State<CatalogoInsumosScreen> createState() => _CatalogoInsumosScreenState();
}

class _CatalogoInsumosScreenState extends State<CatalogoInsumosScreen> {
  bool _cargando = true;
  String _vistaActiva = "STOCK"; // 'STOCK' o 'CATALOGO'

  List<Map<String, dynamic>> _insumosCatalogo = [];
  String _rubroSeleccionado = "TODOS";
  List<String> _rubrosDisponibles = ["TODOS"];

  List<Map<String, dynamic>> _stockAgrupado = [];
  List<String> _depositosDisponibles = ["TODOS"];
  String _depositoSeleccionado = "TODOS";

  String _filtroTexto = "";
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    // 1. Maestro de Catálogo
    final List<Map<String, dynamic>> listaInsumos = await db.rawQuery('''
      SELECT * FROM catalogo_insumos
      WHERE (Mostrar = 1 OR Mostrar IS NULL)
      GROUP BY ID_Insumos
      ORDER BY Descripcion1 ASC
    ''');
    _insumosCatalogo = List<Map<String, dynamic>>.from(listaInsumos);

    final Set<String> rubrosSet = {"TODOS"};
    for (var i in listaInsumos) {
      final r = i['rubro']?.toString().trim().toUpperCase();
      if (r != null && r.isNotEmpty) rubrosSet.add(r);
    }
    _rubrosDisponibles = rubrosSet.toList()..sort();

    // 2. Movimientos exclusivamente desde insumos_detalles
    String whereProductor = '';
    List<dynamic> argsProductor = [];
    if (widget.codProductor != null && widget.codProductor! > 0) {
      whereProductor = 'WHERE cod_productor = ?';
      argsProductor = [widget.codProductor];
    }

    final List<Map<String, dynamic>> movimientos = await db.rawQuery('''
      SELECT * FROM insumos_detalles
      $whereProductor
      ORDER BY fecha_ingreso DESC, cod_mov DESC
    ''', argsProductor);

    final Set<String> depsSet = {"TODOS"};
    for (var m in movimientos) {
      final d = m['deposito']?.toString().trim().toUpperCase();
      if (d != null && d.isNotEmpty) depsSet.add(d);
    }
    _depositosDisponibles = depsSet.toList()..sort();

    // 3. Agrupación matemática estricta por ID_Insumos sobre insumos_detalles
    final Map<int, List<Map<String, dynamic>>> movsPorInsumo = {};
    for (var m in movimientos) {
      final int idIns = (m['ID_Insumos'] is int)
          ? m['ID_Insumos']
          : int.tryParse(m['ID_Insumos']?.toString() ?? '0') ?? 0;
      if (idIns <= 0) continue;
      if (!movsPorInsumo.containsKey(idIns)) movsPorInsumo[idIns] = [];
      movsPorInsumo[idIns]!.add(m);
    }

    final List<Map<String, dynamic>> resultadoStock = [];

    movsPorInsumo.forEach((idInsumo, movs) {
      // Buscar información del artículo por ID_Insumos
      Map<String, dynamic> infoCat = {};
      for (var c in _insumosCatalogo) {
        final int cId = (c['ID_Insumos'] is int)
            ? c['ID_Insumos']
            : int.tryParse(c['ID_Insumos']?.toString() ?? '0') ?? 0;
        if (cId == idInsumo) {
          infoCat = c;
          break;
        }
      }

      final primerMov = movs.first;
      final String nombreProd = infoCat['Descripcion1'] ?? primerMov['producto'] ?? 'Insumo #$idInsumo';
      final String pActivo = infoCat['principio_activo'] ?? infoCat['Descripcion2'] ?? primerMov['concetracion'] ?? 'S/D';
      final String conc = infoCat['Concentracion'] ?? primerMov['concetracion'] ?? '';
      final String rubro = (infoCat['rubro'] ?? 'GENERAL').toString().toUpperCase();
      final String unidad = primerMov['unidad'] ?? 'L/Kg';

      double stInicial = 0.0;
      double consumos = 0.0;
      double bajas = 0.0;
      final Set<String> depositosDelItem = {};

      for (var m in movs) {
        final double cant = double.tryParse(m['cantidad']?.toString() ?? '0') ?? 0.0;
        final String mov = (m['movimiento'] ?? '').toString().trim().toUpperCase();
        final String dep = (m['deposito'] ?? 'PAÑOL').toString().trim().toUpperCase();
        depositosDelItem.add(dep);

        if (mov == 'INGRESO' || mov == 'STOCK INICIAL') {
          stInicial += cant;
        } else if (mov == 'CONSUMO' || mov == 'SALIDA' || mov == 'DESPACHO') {
          consumos += cant.abs();
        } else if (mov == 'BAJA' || mov == 'MERMA' || mov == 'ROTURA' || mov == 'VENCIDO') {
          bajas += cant.abs();
        }
      }

      final double stockNeto = stInicial - consumos - bajas;

      resultadoStock.add({
        'ID_Insumos': idInsumo,
        'producto': nombreProd,
        'principio_activo': pActivo,
        'concentracion': conc,
        'rubro': rubro,
        'unidad': unidad,
        'stock_inicial': stInicial,
        'consumos': consumos,
        'bajas': bajas,
        'stock_neto': stockNeto,
        'depositos': depositosDelItem.toList(),
        'movimientos': movs,
      });
    });

    resultadoStock.sort((a, b) => (a['producto'] as String).compareTo(b['producto'] as String));

    if (!mounted) return;
    setState(() {
      _stockAgrupado = resultadoStock;
      if (!_rubrosDisponibles.contains(_rubroSeleccionado)) _rubroSeleccionado = "TODOS";
      if (!_depositosDisponibles.contains(_depositoSeleccionado)) _depositoSeleccionado = "TODOS";
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _stockFiltrado {
    return _stockAgrupado.where((item) {
      if (_depositoSeleccionado != "TODOS") {
        final List<String> deps = (item['depositos'] as List).cast<String>();
        if (!deps.contains(_depositoSeleccionado)) return false;
      }
      if (_rubroSeleccionado != "TODOS" && item['rubro'] != _rubroSeleccionado) {
        return false;
      }
      if (_filtroTexto.isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final nom = (item['producto'] ?? '').toString().toLowerCase();
      final pa = (item['principio_activo'] ?? '').toString().toLowerCase();
      final conc = (item['concentracion'] ?? '').toString().toLowerCase();
      return nom.contains(q) || pa.contains(q) || conc.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _catalogoFiltrado {
    return _insumosCatalogo.where((item) {
      final r = (item['rubro'] ?? '').toString().trim().toUpperCase();
      if (_rubroSeleccionado != "TODOS" && r != _rubroSeleccionado) return false;
      if (_filtroTexto.isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final nom = (item['Descripcion1'] ?? '').toString().toLowerCase();
      final pa = (item['principio_activo'] ?? item['Descripcion2'] ?? '').toString().toLowerCase();
      return nom.contains(q) || pa.contains(q);
    }).toList();
  }

  // ===========================================================================
  // MODAL DE INGRESO POSITIVO (insumos_detalles)
  // ===========================================================================
  void _mostrarModalIngresoArticulo({required int idInsumos, required String nombreProducto, String? concentracion}) {
    final formKey = GlobalKey<FormState>();
    final cantidadCtrl = TextEditingController();
    final remitoCtrl = TextEditingController();
    final vencimientoCtrl = TextEditingController();
    final nuevoDepositoCtrl = TextEditingController();
    final fechaCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));

    final opcionesDepositos = _depositosDisponibles.where((d) => d != "TODOS").toList();
    if (opcionesDepositos.isEmpty) opcionesDepositos.add("PAÑOL CENTRAL");
    String depositoSeleccionado = opcionesDepositos.first;
    bool crearNuevoDeposito = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Ingresar: $nombreProducto",
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  "ID Insumo #$idInsumos · Ingreso Positivo al Pañol",
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E6B4C), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const Divider(color: AgroTheme.colorBorder),
                      const SizedBox(height: 10),

                      // Selector de Depósito Existente o Nuevo
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Depósito de Almacenamiento:",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AgroTheme.colorTextSecondary)),
                          InkWell(
                            onTap: () => setModalState(() => crearNuevoDeposito = !crearNuevoDeposito),
                            child: Text(
                              crearNuevoDeposito ? "Elegir existente" : "+ Crear nuevo",
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF1E6B4C)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (crearNuevoDeposito)
                        TextFormField(
                          controller: nuevoDepositoCtrl,
                          autofocus: true,
                          textCapitalization: TextCapitalization.characters,
                          decoration: _inputDecoration("Nombre del Nuevo Depósito (Ej: GALPON 2)", Icons.add_home_work_outlined),
                          validator: (v) => (crearNuevoDeposito && (v == null || v.trim().isEmpty)) ? "Ingresá el depósito" : null,
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: depositoSeleccionado,
                          decoration: _inputDecoration("Depósito", Icons.warehouse_outlined),
                          items: opcionesDepositos.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => depositoSeleccionado = v);
                          },
                        ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: cantidadCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: _inputDecoration("Cantidad Ingresada (L/Kg)", Icons.numbers_rounded),
                              validator: (v) => (v == null || (double.tryParse(v.replaceAll(',', '.')) ?? 0) <= 0) ? "Cantidad mayor a 0" : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: remitoCtrl,
                              decoration: _inputDecoration("N° Remito / Vale", Icons.receipt_long_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: fechaCtrl,
                              readOnly: true,
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (d != null) fechaCtrl.text = DateFormat('yyyy-MM-dd').format(d);
                              },
                              decoration: _inputDecoration("Fecha Ingreso", Icons.calendar_today_outlined),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: vencimientoCtrl,
                              readOnly: true,
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now().add(const Duration(days: 365)),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2038),
                                );
                                if (d != null) vencimientoCtrl.text = DateFormat('yyyy-MM-dd').format(d);
                              },
                              decoration: _inputDecoration("Vencimiento (Opcional)", Icons.event_busy_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: SoftButton(
                          onTap: () async {
                            if (!formKey.currentState!.validate()) return;
                            final db = await DatabaseHelper.instance.database;

                            final String depFinal = (crearNuevoDeposito
                                    ? nuevoDepositoCtrl.text.trim().toUpperCase()
                                    : depositoSeleccionado)
                                .trim();
                            final double cant = double.parse(cantidadCtrl.text.replaceAll(',', '.').trim());
                            final String codMov = "ING_${DateTime.now().millisecondsSinceEpoch}";
                            final String remito = remitoCtrl.text.trim().toUpperCase();

                            final rowIngreso = {
                              'cod_mov': codMov,
                              'reg_ingreso': remito.isNotEmpty ? remito : codMov,
                              'reg_aplic': null,
                              'cod_productor': widget.codProductor ?? 0,
                              'productor': widget.nombreProductor ?? '',
                              'deposito': depFinal,
                              'ID_Insumos': idInsumos,
                              'producto': nombreProducto,
                              'concetracion': concentracion ?? '',
                              'movimiento': 'INGRESO',
                              'cantidad': cant,
                              'unidad': 'L/Kg',
                              'fec_vencimiento': vencimientoCtrl.text.trim().isNotEmpty ? vencimientoCtrl.text.trim() : null,
                              'fecha_ingreso': fechaCtrl.text.trim(),
                              'reg_consumo': null,
                              'sincronizado': 0,
                            };

                            await db.insert('insumos_detalles', rowIngreso);
                            try {
                              final rowSync = Map<String, dynamic>.from(rowIngreso)..remove('sincronizado');
                              await Supabase.instance.client.from('insumos_detalles').upsert(rowSync);
                            } catch (_) {}

                            if (!mounted) return;
                            Navigator.pop(ctx);
                            await _cargarTodo();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF1E6B4C),
                                content: Text("Ingreso de $cant L/Kg registrado en $depFinal"),
                              ),
                            );
                          },
                          child: const Center(
                            child: Text(
                              "Registrar Ingreso al Stock",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // MODAL DE REGISTRO DE BAJA (CON MOTIVO: PÉRDIDA, ROTURA, MERMA, ETC.)
  // ===========================================================================
  void _mostrarModalBajaArticulo(Map<String, dynamic> item) {
    final formKey = GlobalKey<FormState>();
    final cantidadCtrl = TextEditingController();
    final motivoCtrl = TextEditingController(text: "PÉRDIDA / ROTURA");
    final fechaCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));

    final List<String> deps = (item['depositos'] as List).cast<String>();
    String depSeleccionado = deps.isNotEmpty ? deps.first : "PAÑOL";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AgroTheme.colorSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Dar de Baja: ${item['producto']}",
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AgroTheme.colorText),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            "Disponible en Pañol: ${item['stock_neto'].toStringAsFixed(2)} ${item['unidad']}",
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFC62828), fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(color: AgroTheme.colorBorder),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: depSeleccionado,
                  decoration: _inputDecoration("Depósito Afectado", Icons.warehouse_outlined),
                  items: deps.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) {
                    if (v != null) depSeleccionado = v;
                  },
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: cantidadCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration("Cantidad de Baja", Icons.remove_circle_outline_rounded),
                        validator: (v) {
                          final cant = double.tryParse(v?.replaceAll(',', '.') ?? '') ?? 0.0;
                          if (cant <= 0) return "Cantidad mayor a 0";
                          if (cant > (item['stock_neto'] as double)) return "Supera stock actual";
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: fechaCtrl,
                        readOnly: true,
                        decoration: _inputDecoration("Fecha", Icons.calendar_today_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: motivoCtrl,
                  decoration: _inputDecoration("Motivo de Baja (Pérdida, Vencimiento, Merma...)", Icons.assignment_late_outlined),
                  validator: (v) => v == null || v.trim().isEmpty ? "Ingresá el motivo" : null,
                ),
                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: SoftButton(
                    onTap: () async {
                      if (!formKey.currentState!.validate()) return;
                      final db = await DatabaseHelper.instance.database;

                      final double cant = double.parse(cantidadCtrl.text.replaceAll(',', '.').trim());
                      final String codMov = "BAJ_${DateTime.now().millisecondsSinceEpoch}";
                      final String motivo = motivoCtrl.text.trim().toUpperCase();

                      // En insumos_detalles guardamos la baja ligada al ID_Insumos
                      final rowBaja = {
                        'cod_mov': codMov,
                        'reg_ingreso': null,
                        'reg_aplic': null,
                        'cod_productor': widget.codProductor ?? 0,
                        'productor': widget.nombreProductor ?? '',
                        'deposito': depSeleccionado,
                        'ID_Insumos': item['ID_Insumos'],
                        'producto': item['producto'],
                        'concetracion': item['concentracion'],
                        'movimiento': 'BAJA',
                        'cantidad': -cant,
                        'unidad': item['unidad'],
                        'fec_vencimiento': null,
                        'fecha_ingreso': fechaCtrl.text.trim(),
                        'reg_consumo': motivo, // Columna de motivo
                        'sincronizado': 0,
                      };

                      await db.insert('insumos_detalles', rowBaja);
                      try {
                        final rowSync = Map<String, dynamic>.from(rowBaja)..remove('sincronizado');
                        await Supabase.instance.client.from('insumos_detalles').upsert(rowSync);
                      } catch (_) {}

                      if (!mounted) return;
                      Navigator.pop(ctx);
                      await _cargarTodo();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFFC62828),
                          content: Text("Baja de $cant ${item['unidad']} registrada por $motivo"),
                        ),
                      );
                    },
                    child: const Center(
                      child: Text(
                        "Confirmar Baja de Stock",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12.5, color: AgroTheme.colorTextSecondary),
      prefixIcon: Icon(icono, size: 18, color: AgroTheme.colorTextSecondary),
      filled: true,
      fillColor: AgroTheme.colorBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AgroTheme.radiusMd), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: AgroTheme.colorBorder, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: Color(0xFF1E6B4C), width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double ancho = MediaQuery.of(context).size.width;
    final bool esDesktop = ancho >= 920;

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
            const Text("Pañol & Stock Fitosanitario",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText)),
            Text(widget.nombreProductor ?? "Administración Central",
                style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_rounded, color: Color(0xFF2E7D32)),
            tooltip: "Exportar Stock a Excel (Pañolero)",
            onPressed: () {
              ServicioExportarStock.exportarStockPanolero(
                items: _stockFiltrado,
                nombreProductor: widget.nombreProductor ?? 'Productor',
                depositoFiltro: _depositoSeleccionado,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E6B4C)),
            tooltip: "Recargar",
            onPressed: _cargarTodo,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ARCHIVERO DE SOLAPAS: STOCK (PAÑOLERO) VS CATÁLOGO
            Container(
              padding: EdgeInsets.fromLTRB(esDesktop ? 24 : 16, 8, esDesktop ? 24 : 16, 6),
              color: AgroTheme.colorSurface,
              child: Row(
                children: [
                  _buildArchiveroTab(
                    label: "Stock en Pañol (insumos_detalles)",
                    icono: Icons.inventory_2_outlined,
                    id: "STOCK",
                    total: _stockAgrupado.length,
                    color: const Color(0xFF1E6B4C),
                    fondo: const Color(0xFFE8F5E9),
                  ),
                  const SizedBox(width: 10),
                  _buildArchiveroTab(
                    label: "Catálogo de Productos",
                    icono: Icons.science_outlined,
                    id: "CATALOGO",
                    total: _insumosCatalogo.length,
                    color: const Color(0xFF1565C0),
                    fondo: const Color(0xFFE3F2FD),
                  ),
                ],
              ),
            ),

            // FILTROS: DEPÓSITOS Y RUBROS
            Container(
              padding: EdgeInsets.fromLTRB(esDesktop ? 24 : 16, 4, esDesktop ? 24 : 16, 8),
              color: AgroTheme.colorSurface,
              child: Column(
                children: [
                  if (_vistaActiva == "STOCK" && _depositosDisponibles.length > 1) ...[
                    SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _depositosDisponibles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, idx) {
                          final dep = _depositosDisponibles[idx];
                          final isSel = _depositoSeleccionado == dep;
                          return ChoiceChip(
                            label: Text(dep == "TODOS" ? "Todos los Depósitos" : dep),
                            selected: isSel,
                            selectedColor: const Color(0xFF1E6B4C),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                              color: isSel ? Colors.white : AgroTheme.colorText,
                            ),
                            backgroundColor: AgroTheme.colorBg,
                            onSelected: (val) {
                              if (val) setState(() => _depositoSeleccionado = dep);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (_rubrosDisponibles.length > 1) ...[
                    SizedBox(
                      height: 30,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _rubrosDisponibles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, idx) {
                          final rubro = _rubrosDisponibles[idx];
                          final isSel = _rubroSeleccionado == rubro;
                          return ChoiceChip(
                            label: Text(rubro == "TODOS" ? "Todos los Rubros" : rubro),
                            selected: isSel,
                            selectedColor: const Color(0xFF8A6A1E),
                            labelStyle: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                              color: isSel ? Colors.white : AgroTheme.colorTextSecondary,
                            ),
                            backgroundColor: AgroTheme.colorBg,
                            onSelected: (val) {
                              if (val) setState(() => _rubroSeleccionado = rubro);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // BUSCADOR
            Padding(
              padding: EdgeInsets.fromLTRB(esDesktop ? 24 : 16, 8, esDesktop ? 24 : 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border: Border.all(color: AgroTheme.colorBorder),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (val) => setState(() => _filtroTexto = val),
                  style: const TextStyle(color: AgroTheme.colorText, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: "Buscar por insumo, principio activo o concentración...",
                    hintStyle: TextStyle(color: AgroTheme.colorTextSecondary, fontSize: 12.5),
                    prefixIcon: Icon(Icons.search_rounded, color: AgroTheme.colorTextSecondary, size: 18),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),

            // CONTENIDO PRINCIPAL
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E6B4C)))
                  : _vistaActiva == "STOCK"
                      ? _buildVistaStockPanolero(esDesktop)
                      : _buildVistaCatalogo(esDesktop),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchiveroTab({
    required String label,
    required IconData icono,
    required String id,
    required int total,
    required Color color,
    required Color fondo,
  }) {
    final bool isSelected = _vistaActiva == id;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _vistaActiva = id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? fondo : AgroTheme.colorBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color.withOpacity(0.4) : AgroTheme.colorBorder,
              width: isSelected ? 1.3 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 16, color: isSelected ? color : AgroTheme.colorTextSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? color : AgroTheme.colorText,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "$total",
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : AgroTheme.colorTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // VISTA TABLA FORMATO PAÑOLERO:
  // Insumos | Principio Activo | Concentración | Stock Inicial | Consumos | Bajas | Stock
  // ===========================================================================
  Widget _buildVistaStockPanolero(bool esDesktop) {
    final items = _stockFiltrado;

    if (items.isEmpty) {
      return const Center(
        child: Text("Sin existencias registradas en insumos_detalles.",
            style: TextStyle(color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500)),
      );
    }

    return Column(
      children: [
        // CABECERA INMOVILIZADA
        Padding(
          padding: EdgeInsets.fromLTRB(esDesktop ? 24 : 16, 0, esDesktop ? 24 : 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F8E9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(bottom: BorderSide(color: AgroTheme.colorBorder)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text("INSUMO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                ),
                if (esDesktop) ...[
                  const Expanded(
                    flex: 3,
                    child: Text("PRINCIPIO ACTIVO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                  ),
                  const Expanded(
                    flex: 2,
                    child: Text("CONCENTRACIÓN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                  ),
                ],
                const Expanded(
                  flex: 2,
                  child: Text("ST. INICIAL", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                ),
                const Expanded(
                  flex: 2,
                  child: Text("CONSUMOS", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                ),
                const Expanded(
                  flex: 2,
                  child: Text("BAJAS", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                ),
                const Expanded(
                  flex: 2,
                  child: Text("STOCK", textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                ),
              ],
            ),
          ),
        ),

        // RENGLONES DE LA MATRIZ CON ACCIÓN DIRECTA
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(esDesktop ? 24 : 16, 0, esDesktop ? 24 : 16, 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, idx) {
              final it = items[idx];
              final double stInicial = it['stock_inicial'];
              final double consumos = it['consumos'];
              final double bajas = it['bajas'];
              final double stockNeto = it['stock_neto'];
              final bool alertaStock = stockNeto <= 0;

              return InkWell(
                onTap: () => _mostrarModalAccionesArticulo(it),
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorSurface,
                    borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                    border: Border.all(
                      color: alertaStock ? const Color(0xFFEF9A9A) : AgroTheme.colorBorder,
                      width: alertaStock ? 1.2 : 1.0,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x03141E18), blurRadius: 4, offset: Offset(0, 1.5)),
                    ],
                  ),
                  child: Row(
                    children: [
                      // INSUMO
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it['producto'],
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AgroTheme.colorText),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!esDesktop) ...[
                              Text(
                                "${it['principio_activo']} ${it['concentracion']}",
                                style: const TextStyle(fontSize: 10.5, color: AgroTheme.colorTextSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // PRINCIPIO ACTIVO & CONCENTRACIÓN EN PC
                      if (esDesktop) ...[
                        Expanded(
                          flex: 3,
                          child: Text(
                            it['principio_activo'],
                            style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            it['concentracion'].toString().isNotEmpty ? it['concentracion'] : '-',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AgroTheme.colorTextSecondary),
                          ),
                        ),
                      ],

                      // STOCK INICIAL
                      Expanded(
                        flex: 2,
                        child: Text(
                          stInicial.toStringAsFixed(1),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AgroTheme.colorText),
                        ),
                      ),

                      // CONSUMOS
                      Expanded(
                        flex: 2,
                        child: Text(
                          consumos > 0 ? "-${consumos.toStringAsFixed(1)}" : "0.0",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
                        ),
                      ),

                      // BAJAS
                      Expanded(
                        flex: 2,
                        child: Text(
                          bajas > 0 ? "-${bajas.toStringAsFixed(1)}" : "0.0",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFC62828)),
                        ),
                      ),

                      // STOCK NETO FINAL
                      Expanded(
                        flex: 2,
                        child: Text(
                          "${stockNeto.toStringAsFixed(1)} ${it['unidad']}",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: stockNeto > 0 ? const Color(0xFF2E7D32) : (stockNeto < 0 ? const Color(0xFFC62828) : Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MODAL DE ELECCIÓN: INGRESAR MÁS O DAR DE BAJA
  // ===========================================================================
  void _mostrarModalAccionesArticulo(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      backgroundColor: AgroTheme.colorSurface,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['producto'],
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AgroTheme.colorText),
              ),
              const SizedBox(height: 2),
              Text(
                "Stock Neto: ${item['stock_neto'].toStringAsFixed(2)} ${item['unidad']} · ID #${item['ID_Insumos']}",
                style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w600),
              ),
              const Divider(color: AgroTheme.colorBorder, height: 22),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFFE8F5E9),
                leading: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF2E7D32), size: 24),
                title: const Text("Ingresar más cantidad a depósito", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text("Suma stock positivo al depósito elegido con fecha de vencimiento.", style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarModalIngresoArticulo(
                    idInsumos: item['ID_Insumos'],
                    nombreProducto: item['producto'],
                    concentracion: item['concentracion'],
                  );
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFFFFEBEE),
                leading: const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFFC62828), size: 24),
                title: const Text("Dar de baja del stock (Pérdida / Rotura / Merma)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text("Descuenta cantidad del depósito indicando el motivo.", style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarModalBajaArticulo(item);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // VISTA CATÁLOGO (TOCAR UN PRODUCTO PERMITE INGRESARLO DIRECTAMENTE AL PAÑOL)
  // ===========================================================================
  Widget _buildVistaCatalogo(bool esDesktop) {
    final items = _catalogoFiltrado;

    if (items.isEmpty) {
      return const Center(child: Text("Sin coincidencias en el catálogo técnico."));
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(esDesktop ? 24 : 16, 4, esDesktop ? 24 : 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final it = items[idx];
        final int idIns = (it['ID_Insumos'] is int) ? it['ID_Insumos'] : int.tryParse(it['ID_Insumos']?.toString() ?? '0') ?? 0;
        final String nombre = (it['Descripcion1'] ?? 'Insumo').toString();
        final String pa = (it['principio_activo'] ?? it['Descripcion2'] ?? 'S/D').toString();
        final String conc = (it['Concentracion'] ?? '').toString();
        final String rubro = (it['rubro'] ?? 'GENERAL').toString();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AgroTheme.colorSurface,
            borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
            border: Border.all(color: AgroTheme.colorBorder),
            boxShadow: const [
              BoxShadow(color: Color(0x03141E18), blurRadius: 4, offset: Offset(0, 1.5)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.science_outlined, color: Color(0xFF1565C0), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nombre,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AgroTheme.colorText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AgroTheme.colorBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AgroTheme.colorBorder),
                          ),
                          child: Text(
                            rubro,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AgroTheme.colorTextSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      conc.isNotEmpty ? "$pa ($conc)" : pa,
                      style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SoftButton(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
                borderRadius: 8,
                onTap: () => _mostrarModalIngresoArticulo(
                  idInsumos: idIns,
                  nombreProducto: nombre,
                  concentracion: conc,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 4),
                    Text("Ingresar", style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}