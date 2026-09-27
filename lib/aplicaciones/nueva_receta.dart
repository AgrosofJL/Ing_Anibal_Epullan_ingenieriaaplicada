// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/agro_ui.dart';
import 'calculo_dosis.dart';
import 'orden_cuadros.dart';

class NuevaRecetaScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;
  final Map<String, dynamic>? ordenParaEditar;

  const NuevaRecetaScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
    this.ordenParaEditar,
  });

  @override
  State<NuevaRecetaScreen> createState() => _NuevaRecetaScreenState();
}

class _NuevaRecetaScreenState extends State<NuevaRecetaScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _cargando = true;
  bool _guardando = false;

  bool get _esEdicion => widget.ordenParaEditar != null;

  // Controladores de scroll propios (evita conflictos con PrimaryScrollController
  // cuando en web/escritorio conviven dos columnas desplazables).
  final ScrollController _scrollFormulario = ScrollController();
  final ScrollController _scrollResumen = ScrollController();

  // 1. Datos Cabecera
  String _fecha = "";
  int _numeroOrden = 0;
  String _codigoOrdenFormateado = "";
  String? _tipoAplicacionSeleccionado;

  List<String> _motivosDisponibles = [];
  String? _motivoSeleccionado;
  bool _esMotivoPersonalizado = false;
  final TextEditingController _motivoCustomController = TextEditingController();

  final TextEditingController _momentoController = TextEditingController();
  final TextEditingController _volumenHaController =
      TextEditingController(text: "1000");
  String _responsable = "Ingeniero Agrónomo";

  List<String> _tiposAplicacion = [];
  List<String> _chacrasDisponibles = [];
  // Una orden puede abarcar varias chacras (multiselección).
  final Set<String> _chacrasSeleccionadas = {};
  bool _verTodasChacras = false;

  // 2. Cuadros e Inventario (todas las chacras del productor)
  List<Map<String, dynamic>> _todosCuadrosInventario = [];
  // Cultivos / variedades A TRATAR: se guardan con la orden y el operario
  // solo verá esas variedades al registrar. Vacío = todos.
  final Set<String> _cultivosFiltro = {};
  final Set<String> _variedadesFiltro = {};
  String _busquedaCuadro = '';
  final TextEditingController _buscarCuadroCtrl = TextEditingController();
  // Claves "chacra::cuadro" (ver orden_cuadros.dart)
  final Set<String> _cuadrosSeleccionados = {};

  // 3. Catálogo de Insumos y Receta Foliar
  List<Map<String, dynamic>> _catalogoInsumos = [];
  List<String> _rubrosInsumosDisponibles = [];
  String? _idProductoSeleccionado;
  String _metodoDosis = "DOSIS_100"; // 'DOSIS_100' o 'DOSIS_HA'
  final TextEditingController _dosisInputController = TextEditingController();
  final TextEditingController _dosisMaquinaController = TextEditingController();
  double _dosisMaquinaCalculada = 0.0;
  final double _capacidadMaquinaLitros = 2000.0;

  final List<Map<String, dynamic>> _itemsRecetaTemporal = [];

  // 4. Parámetros Técnicos de Pulverización
  final TextEditingController _paramVientoCtrl =
      TextEditingController(text: "5-10 km/h");
  final TextEditingController _paramTempCtrl =
      TextEditingController(text: "18-22 °C");
  final TextEditingController _paramGotaCtrl =
      TextEditingController(text: "Media (200-300 µm)");
  final TextEditingController _paramVelocidadCtrl =
      TextEditingController(text: "5.5 km/h");
  final TextEditingController _paramCaudalCtrl =
      TextEditingController(text: "1000 L/Ha");

  @override
  void initState() {
    super.initState();
    _fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _inicializarFormulario();
  }

  @override
  void dispose() {
    _motivoCustomController.dispose();
    _momentoController.dispose();
    _volumenHaController.dispose();
    _dosisInputController.dispose();
    _dosisMaquinaController.dispose();
    _paramVientoCtrl.dispose();
    _paramTempCtrl.dispose();
    _paramGotaCtrl.dispose();
    _paramVelocidadCtrl.dispose();
    _paramCaudalCtrl.dispose();
    _scrollFormulario.dispose();
    _scrollResumen.dispose();
    _buscarCuadroCtrl.dispose();
    super.dispose();
  }

  // ===========================================================================
  // CARGA DE DATOS (lógica original sin cambios)
  // ===========================================================================

  Future<void> _inicializarFormulario() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();
    _responsable = prefs.getString('userName') ?? "Ingeniero Agrónomo";

    if (_esEdicion) {
      final ordenMap = widget.ordenParaEditar!;
      _numeroOrden = ordenMap['cod_orden'] is int
          ? ordenMap['cod_orden']
          : int.tryParse(ordenMap['cod_orden']?.toString() ?? '0') ?? 0;
      _codigoOrdenFormateado = _numeroOrden.toString();
      _fecha = ordenMap['fecha']?.toString() ?? _fecha;
      _momentoController.text = ordenMap['momento']?.toString() ??
          ordenMap['momento_aplic']?.toString() ??
          '';
      _volumenHaController.text = (ordenMap['vol_ha']?.toString() ??
              ordenMap['vol_aplic_ha']?.toString() ??
              '1000')
          .replaceAll('.0', '');
      _paramCaudalCtrl.text = "${_volumenHaController.text} L/Ha";
    } else {
      final int sigId = await DatabaseHelper.instance
          .obtenerSiguienteId('recetas_aplicaciones', 'cod_receta');
      _numeroOrden = sigId;
      _codigoOrdenFormateado = _numeroOrden.toString();
    }

    if (_esEdicion) {
      try {
        final resParams = await db.query(
          'parametros_aplic',
          where: 'cod_orden = ?',
          whereArgs: [_numeroOrden],
          limit: 1,
        );
        if (resParams.isNotEmpty) {
          final p = resParams.first;
          _paramVientoCtrl.text = (p['vel_viento'] ?? '').toString();
          _paramTempCtrl.text = (p['Temperatura'] ?? '').toString();
          _paramGotaCtrl.text = (p['Tamano_gota'] ?? '').toString();
          _paramVelocidadCtrl.text = (p['Vel_Aplicacion'] ?? '').toString();
          _paramCaudalCtrl.text = (p['Caudal_Ha'] ?? '').toString();
        }
      } catch (_) {}
    }

    final resTipos = await db.rawQuery('''
      SELECT DISTINCT tipo_aplic
      FROM motivos_aplicaciones
      WHERE tipo_aplic IS NOT NULL AND TRIM(tipo_aplic) != ''
      ORDER BY tipo_aplic ASC
    ''');
    _tiposAplicacion = resTipos.map((e) => e['tipo_aplic'].toString()).toList();
    if (_tiposAplicacion.isNotEmpty) {
      _tipoAplicacionSeleccionado = _tiposAplicacion.first;
      await _cargarMotivosPorTipo(_tipoAplicacionSeleccionado!);
    }

    if (_esEdicion) {
      final motivoExistente = widget.ordenParaEditar!['motivo']?.toString() ??
          widget.ordenParaEditar!['motivo_aplic']?.toString() ??
          '';
      if (_motivosDisponibles.contains(motivoExistente)) {
        _motivoSeleccionado = motivoExistente;
        _esMotivoPersonalizado = false;
      } else if (motivoExistente.isNotEmpty) {
        _motivoSeleccionado = "__OTRO__";
        _esMotivoPersonalizado = true;
        _motivoCustomController.text = motivoExistente;
      }
    }

    await _recargarChacrasDisponibles();
    await _cargarInventarioProductor();

    if (_esEdicion) {
      _cultivosFiltro
        ..clear()
        ..addAll(parsearFiltroOrden(widget.ordenParaEditar!['cultivos']));
      _variedadesFiltro
        ..clear()
        ..addAll(parsearFiltroOrden(widget.ordenParaEditar!['variedades']));

      // Soporta órdenes viejas (una chacra) y nuevas (varias chacras).
      final refs = parsearCuadrosOrden(
        widget.ordenParaEditar!['chacra'],
        widget.ordenParaEditar!['cuadros'],
      );
      final clavesInventario = _cuadrosInventario.map((c) => c.clave).toSet();
      _cuadrosSeleccionados.clear();
      // Órdenes sin cuadros: igual se restauran sus chacras.
      if (refs.isEmpty) {
        for (final ch in (widget.ordenParaEditar!['chacra'] ?? '')
            .toString()
            .split(',')) {
          if (ch.trim().isNotEmpty) _chacrasSeleccionadas.add(ch.trim());
        }
      }
      for (final r in refs) {
        if (r.chacra.isNotEmpty) _chacrasSeleccionadas.add(r.chacra);
        if (clavesInventario.contains(r.clave)) {
          _cuadrosSeleccionados.add(r.clave);
        }
      }
    } else if (_chacrasDisponibles.length == 1) {
      _chacrasSeleccionadas.add(_chacrasDisponibles.first);
    }

    await _recargarCatalogoInsumos();

    if (_esEdicion) {
      List<Map<String, dynamic>> itemsParaCargar = [];
      final itemsRaw = widget.ordenParaEditar!['items'];

      if (itemsRaw is List && itemsRaw.isNotEmpty) {
        itemsParaCargar = itemsRaw.cast<Map<String, dynamic>>();
      } else {
        itemsParaCargar = await db.query(
          'recetas_aplicaciones',
          where: 'cod_orden = ? AND cod_productor = ?',
          whereArgs: [_numeroOrden, widget.codProductor],
          orderBy: 'orden_aplic ASC, cod_receta ASC',
        );
      }

      _itemsRecetaTemporal.clear();
      for (var it in itemsParaCargar) {
        final double dMaq =
            double.tryParse(it['dosis_maq']?.toString() ?? '0') ?? 0.0;
        // Las filas guardadas traen 'dosis_x' (dosis_ha / vol_100) y, si es
        // por Ha, la dosis va en 'vol_aplic_ha'.
        final bool esHaGuardado = CalculoDosis.esPorHa(it);
        final String met = it['metodo_dosis']?.toString() ??
            (esHaGuardado ? 'DOSIS_HA' : 'DOSIS_100');
        _itemsRecetaTemporal.add({
          'cod_producto': it['cod_producto'] ?? it['ID_Insumos'] ?? 0,
          'producto': it['producto'] ?? it['Descripcion1'] ?? 'Insumo',
          'rubro': it['rubro'] ?? 'General',
          'metodo_dosis': met,
          'dosis_valor': esHaGuardado
              ? CalculoDosis.dosisPorHa(it).toString()
              : (it['dosis_100']?.toString() ?? '0'),
          'dosis_100': it['dosis_100']?.toString() ?? '0',
          'dosis_maq': dMaq,
          'tc': it['tc'] ?? it['T_C'] ?? 0,
          'ti': it['ti'] ?? it['TRI'] ?? 0,
          'orden_aplic': it['orden_aplic'] ?? (_itemsRecetaTemporal.length + 1),
        });
      }
    }

    if (!mounted) return;
    setState(() => _cargando = false);
  }

  Future<void> _recargarChacrasDisponibles() async {
    final db = await DatabaseHelper.instance.database;

    final resChacras = await db.rawQuery('''
      SELECT DISTINCT chacra
      FROM inventario_plantacion
      WHERE cod_productor = ? AND chacra IS NOT NULL AND TRIM(chacra) != ''
      ORDER BY chacra ASC
    ''', [widget.codProductor]);

    final Set<String> lista =
        resChacras.map((e) => e['chacra'].toString().trim()).toSet();

    final resChacrasCuadros = await db.rawQuery('''
      SELECT DISTINCT chacra
      FROM cuadros
      WHERE cod_productor = ? AND chacra IS NOT NULL AND TRIM(chacra) != ''
      ORDER BY chacra ASC
    ''', [widget.codProductor]);

    for (var r in resChacrasCuadros) {
      final ch = r['chacra']?.toString().trim();
      if (ch != null && ch.isNotEmpty) lista.add(ch);
    }

    final ordenadas = lista.toList()..sort(compararNatural);

    if (!mounted) return;
    setState(() => _chacrasDisponibles = ordenadas);
  }

  Future<void> _recargarCatalogoInsumos() async {
    final db = await DatabaseHelper.instance.database;

    // Traer solo insumos que tienen stock real en insumos_detalles para este productor
    final List<Map<String, dynamic>> movimientosProd = await db.rawQuery('''
      SELECT ID_Insumos, producto, concetracion, cantidad, movimiento, deposito
      FROM insumos_detalles
      WHERE cod_productor = ?
    ''', [widget.codProductor]);

    // Calcular el stock neto acumulado por ID_Insumos
    final Map<int, double> stockPorInsumo = {};
    for (var m in movimientosProd) {
      final int idIns = (m['ID_Insumos'] is int)
          ? m['ID_Insumos']
          : int.tryParse(m['ID_Insumos']?.toString() ?? '0') ?? 0;
      if (idIns <= 0) continue;

      final double cant =
          double.tryParse(m['cantidad']?.toString() ?? '0') ?? 0.0;
      final String mov =
          (m['movimiento'] ?? '').toString().trim().toUpperCase();

      if (mov == 'INGRESO' || mov == 'STOCK INICIAL') {
        stockPorInsumo[idIns] = (stockPorInsumo[idIns] ?? 0.0) + cant;
      } else if (mov == 'CONSUMO' ||
          mov == 'SALIDA' ||
          mov == 'DESPACHO' ||
          mov == 'BAJA' ||
          mov == 'MERMA') {
        stockPorInsumo[idIns] = (stockPorInsumo[idIns] ?? 0.0) - cant.abs();
      }
    }

    // Filtrar catálogo técnico uniendo con el balance de stock disponible (> 0)
    final resInsumos = await db.rawQuery('''
      SELECT * FROM catalogo_insumos
      WHERE rubro IN (
        SELECT nombre FROM rubros_insumos WHERE macro_rubro = 'PRODUCTOS'
      )
      AND (Mostrar = 1 OR Mostrar IS NULL)
      ORDER BY Descripcion1 ASC
    ''');

    final List<Map<String, dynamic>> insumosConStock = [];
    for (var prod in resInsumos) {
      final Object? idIns = (prod['ID_Insumos'] is int)
          ? prod['ID_Insumos']
          : int.tryParse(prod['ID_Insumos']?.toString() ?? '0') ?? 0;
      final double stockDisponible = stockPorInsumo[idIns] ?? 0.0;

      if (stockDisponible > 0) {
        final itemMap = Map<String, dynamic>.from(prod);
        itemMap['stock_productor_disponible'] = stockDisponible;
        insumosConStock.add(itemMap);
      }
    }

    final resRubros = await db.rawQuery('''
      SELECT DISTINCT nombre FROM rubros_insumos
      WHERE macro_rubro = 'PRODUCTOS' AND nombre IS NOT NULL AND TRIM(nombre) != ''
      ORDER BY nombre ASC
    ''');

    setState(() {
      _catalogoInsumos = insumosConStock;
      _rubrosInsumosDisponibles = resRubros
          .map((e) => e['nombre'].toString().trim().toUpperCase())
          .toList();
    });
  }

  Future<void> _cargarMotivosPorTipo(String tipo) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('''
      SELECT DISTINCT motivo
      FROM motivos_aplicaciones
      WHERE tipo_aplic = ? AND motivo IS NOT NULL AND TRIM(motivo) != ''
      ORDER BY motivo ASC
    ''', [tipo]);

    final List<String> motivos =
        res.map((e) => e['motivo'].toString()).toList();

    setState(() {
      _motivosDisponibles = motivos;
      if (_motivosDisponibles.isNotEmpty) {
        _motivoSeleccionado = _motivosDisponibles.first;
        _esMotivoPersonalizado = false;
      } else {
        _motivoSeleccionado = "__OTRO__";
        _esMotivoPersonalizado = true;
      }
    });
  }

  /// Carga el inventario de TODAS las chacras del productor.
  Future<void> _cargarInventarioProductor() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query(
      'inventario_plantacion',
      columns: ['chacra', 'cuadro', 'ha', 'variedad', 'cultivo'],
      where: 'cod_productor = ?',
      whereArgs: [widget.codProductor],
    );

    final lista = List<Map<String, dynamic>>.from(res)
      ..sort((a, b) {
        final c = compararNatural((a['chacra'] ?? '').toString().trim(),
            (b['chacra'] ?? '').toString().trim());
        if (c != 0) return c;
        return compararNatural(normalizarCuadro(a['cuadro']),
            normalizarCuadro(b['cuadro']));
      });

    if (!mounted) return;
    setState(() => _todosCuadrosInventario = lista);
  }

  /// Inventario agrupado por cuadro (un cuadro puede tener varias variedades).
  List<_CuadroInv> get _cuadrosInventario {
    final Map<String, _CuadroInv> m = {};
    for (final r in _todosCuadrosInventario) {
      final String ch = (r['chacra'] ?? '').toString().trim();
      final String cd = normalizarCuadro(r['cuadro']);
      if (cd.isEmpty) continue;
      final String k = claveCuadro(ch, cd);
      final item = m.putIfAbsent(k, () => _CuadroInv(ch, cd));
      final double haFila = double.tryParse(r['ha']?.toString() ?? '0') ?? 0.0;
      item.ha += haFila;
      final vr = (r['variedad'] ?? '').toString().trim();
      final cul = (r['cultivo'] ?? '').toString().trim();
      item.filas.add((cultivo: cul, variedad: vr, ha: haFila));
      if (vr.isNotEmpty) item.variedades.add(vr);
      if (cul.isNotEmpty) item.cultivos.add(cul);
    }
    return m.values.toList();
  }

  List<_CuadroInv> get _cuadrosDeChacrasSel => _cuadrosInventario
      .where((c) => _chacrasSeleccionadas.contains(c.chacra))
      .toList();

  bool _matchCultivo(_CuadroInv c) =>
      _cultivosFiltro.isEmpty || c.tieneFilasCon(_cultivosFiltro, const <String>{});

  bool _matchVariedad(_CuadroInv c) =>
      c.tieneFilasCon(_cultivosFiltro, _variedadesFiltro);

  Map<String, int> get _conteoCultivos {
    final Map<String, int> m = {};
    for (final c in _cuadrosDeChacrasSel) {
      for (final cul in c.cultivos) {
        m[cul] = (m[cul] ?? 0) + 1;
      }
    }
    final claves = m.keys.toList()..sort();
    return {for (final k in claves) k: m[k]!};
  }

  Map<String, int> get _conteoVariedades {
    final Map<String, int> m = {};
    for (final c in _cuadrosDeChacrasSel) {
      for (final v in c.variedadesCon(_cultivosFiltro, const <String>{})) {
        m[v] = (m[v] ?? 0) + 1;
      }
    }
    final claves = m.keys.toList()..sort();
    return {for (final k in claves) k: m[k]!};
  }


  List<_CuadroInv> get _cuadrosVisibles {
    final q = _busquedaCuadro.toLowerCase().trim();
    return _cuadrosDeChacrasSel.where((c) {
      if (!_matchCultivo(c) || !_matchVariedad(c)) return false;
      if (q.isEmpty) return true;
      final t = 'chacra ${c.chacra} cuadro ${c.cuadro} '
              '${c.variedades.join(' ')} ${c.cultivos.join(' ')}'
          .toLowerCase();
      return t.contains(q);
    }).toList();
  }

  bool get _hayFiltrosCuadros =>
      _cultivosFiltro.isNotEmpty ||
      _variedadesFiltro.isNotEmpty ||
      _busquedaCuadro.isNotEmpty;

  void _limpiarFiltrosCuadros() {
    _buscarCuadroCtrl.clear();
    setState(() {
      _cultivosFiltro.clear();
      _variedadesFiltro.clear();
      _busquedaCuadro = '';
    });
  }

  /// Superficie total de los cuadros seleccionados (se calcula siempre
  /// desde el inventario para que nunca quede desfasada).
  /// Solo cuenta las filas (variedades) del cultivo/variedad a tratar.
  double get _superficieTotalSeleccionada => _cuadrosInventario
      .where((c) => _cuadrosSeleccionados.contains(c.clave))
      .fold(0.0,
          (s, c) => s + c.haFiltrada(_cultivosFiltro, _variedadesFiltro));

  /// Cuadros seleccionados que tienen al menos una fila del cultivo/variedad
  /// a tratar (los demás no se guardan en la orden).
  List<CuadroRef> get _refsSeleccionadas {
    final validos = {
      for (final c in _cuadrosInventario)
        if (c.tieneFilasCon(_cultivosFiltro, _variedadesFiltro)) c.clave
    };
    final refs = <CuadroRef>[];
    for (final k in _cuadrosSeleccionados) {
      if (!validos.contains(k)) continue;
      final i = k.indexOf('::');
      if (i < 0) continue;
      refs.add(CuadroRef(k.substring(0, i), k.substring(i + 2)));
    }
    return refs;
  }

  void _alternarSeleccionCuadro(String clave) {
    setState(() {
      if (!_cuadrosSeleccionados.remove(clave)) _cuadrosSeleccionados.add(clave);
    });
  }

  void _alternarLista(List<_CuadroInv> lista) {
    final claves = lista.map((c) => c.clave).toSet();
    setState(() {
      if (claves.isNotEmpty && claves.every(_cuadrosSeleccionados.contains)) {
        _cuadrosSeleccionados.removeAll(claves);
      } else {
        _cuadrosSeleccionados.addAll(claves);
      }
    });
  }

  void _alternarChacra(String chacra) {
    setState(() {
      if (!_chacrasSeleccionadas.remove(chacra)) {
        _chacrasSeleccionadas.add(chacra);
      } else {
        // Al quitar una chacra se quitan sus cuadros de la selección.
        _cuadrosSeleccionados.removeWhere((k) => k.startsWith('$chacra::'));
      }
      _ajustarFiltrosCuadros();
    });
  }

  void _seleccionarChacras(Iterable<String> chacras) {
    setState(() {
      final nuevas = chacras.toSet();
      _cuadrosSeleccionados.removeWhere((k) {
        final i = k.indexOf('::');
        return i >= 0 && !nuevas.contains(k.substring(0, i));
      });
      _chacrasSeleccionadas
        ..clear()
        ..addAll(nuevas);
      _ajustarFiltrosCuadros();
    });
  }

  void _ajustarFiltrosCuadros() {
    final culs = _conteoCultivos;
    _cultivosFiltro.removeWhere((c) => !culs.containsKey(c));
    final vars = _conteoVariedades;
    _variedadesFiltro.removeWhere((v) => !vars.containsKey(v));
  }

  void _calcularDosisMaquina(String valor) {
    final double valorNum =
        double.tryParse(valor.replaceAll(',', '.').trim()) ?? 0.0;
    final double volCaldoHa = double.tryParse(
            _volumenHaController.text.replaceAll(',', '.').trim()) ??
        1000.0;

    double calculada = 0.0;
    if (_metodoDosis == "DOSIS_100") {
      // Dosis cada 100 litros -> para tanque de 2000 L son 20 partes de 100
      final double factorVolumen = _capacidadMaquinaLitros / 100.0;
      calculada = valorNum * factorVolumen;
    } else {
      // Dosis por hectárea -> cuántas hectáreas cubre la máquina de 2000 L
      final double haPorMaquina =
          volCaldoHa > 0 ? (_capacidadMaquinaLitros / volCaldoHa) : 2.0;
      calculada = valorNum * haPorMaquina;
    }

    setState(() {
      _dosisMaquinaCalculada = calculada;
      _dosisMaquinaController.text = _dosisMaquinaCalculada.toStringAsFixed(2);
    });
  }

  // ===========================================================================
  // PANEL 1: NUEVA CHACRA / CUARTEL
  // ===========================================================================
  void _mostrarModalNuevaChacra() {
    final fKey = GlobalKey<FormState>();
    final nombreChacraCtrl = TextEditingController();
    final primerCuadroCtrl = TextEditingController(text: "1");
    final supHaCtrl = TextEditingController(text: "5.0");
    final variedadCtrl = TextEditingController(text: "Gala");
    final cultivoCtrl = TextEditingController(text: "Manzano");

    mostrarAgroPanel<void>(
      context: context,
      titulo: "Nueva chacra",
      subtitulo: widget.nombreProductor,
      icono: Icons.add_location_alt_outlined,
      builder: (ctx) {
        return Form(
          key: fKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: nombreChacraCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: agroInputDecoration(
                  label: "Nombre de la chacra",
                  hint: "Ej: Chacra Norte / Lote 12",
                  icono: Icons.agriculture_outlined,
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? "Ingresá el nombre de la chacra"
                    : null,
              ),
              const SizedBox(height: 12),
              _filaResponsive(
                anchoMinimo: 150,
                hijos: [
                  TextFormField(
                    controller: primerCuadroCtrl,
                    decoration: agroInputDecoration(
                      label: "Cuadro inicial",
                      hint: "Ej: 1",
                      icono: Icons.grid_view_rounded,
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? "Obligatorio" : null,
                  ),
                  TextFormField(
                    controller: supHaCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: agroInputDecoration(
                      label: "Superficie",
                      sufijo: "Ha",
                      icono: Icons.straighten_rounded,
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? "Obligatorio" : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _filaResponsive(
                anchoMinimo: 150,
                hijos: [
                  TextFormField(
                    controller: cultivoCtrl,
                    decoration: agroInputDecoration(
                      label: "Cultivo",
                      hint: "Ej: Manzano",
                      icono: Icons.park_outlined,
                    ),
                  ),
                  TextFormField(
                    controller: variedadCtrl,
                    decoration: agroInputDecoration(
                      label: "Variedad",
                      hint: "Ej: Gala / Williams",
                      icono: Icons.eco_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AgroButton(
                label: "Guardar chacra",
                icono: Icons.check_rounded,
                expandido: true,
                onTap: () async {
                  if (!fKey.currentState!.validate()) return;
                  final db = await DatabaseHelper.instance.database;

                  final String nombreChacra = nombreChacraCtrl.text.trim();
                  final String nombreCuadro = primerCuadroCtrl.text.trim();
                  final double supHa = double.tryParse(
                          supHaCtrl.text.replaceAll(',', '.').trim()) ??
                      0.0;
                  final String cultivo = cultivoCtrl.text.trim();
                  final String variedad = variedadCtrl.text.trim();

                  final int sigInvId = await DatabaseHelper.instance
                      .obtenerSiguienteId('inventario_plantacion', 'id');
                  final int sigCuadroId = await DatabaseHelper.instance
                      .obtenerSiguienteId('cuadros', 'cod_cuadro');

                  final rowInventario = {
                    'id': sigInvId,
                    'cod_productor': widget.codProductor,
                    'productor': widget.nombreProductor,
                    'chacra': nombreChacra,
                    'cod_cuadro': sigCuadroId,
                    'cuadro': nombreCuadro,
                    'cultivo': cultivo,
                    'variedad': variedad,
                    'ha': supHa,
                    'ano_plantacion': DateTime.now().year,
                    'plantas': 0,
                    'marco_plantacion': 0,
                    'up': '',
                    'dist_arbol': 0.0,
                    'dist_fila': 0.0,
                    'orientacion': '',
                    'sitema_riego': 'Goteo',
                    'sistema_def': 'Malla',
                  };

                  final rowCuadro = {
                    'cod_cuadro': sigCuadroId,
                    'cod_productor': widget.codProductor,
                    'productor': widget.nombreProductor,
                    'chacra': nombreChacra,
                    'cuadro': nombreCuadro,
                    'sitema_riego': 'Goteo',
                    'sistema_def': 'Malla',
                    'ubicacion': '',
                    'sup': supHa,
                  };

                  await db.insert('inventario_plantacion', rowInventario);
                  await db.insert('cuadros', rowCuadro);

                  try {
                    await Supabase.instance.client
                        .from('inventario_plantacion')
                        .insert(rowInventario);
                    await Supabase.instance.client
                        .from('cuadros')
                        .insert(rowCuadro);
                  } catch (e) {
                    debugPrint("Aviso sync chacra: $e");
                  }

                  if (!mounted) return;
                  Navigator.pop(ctx);

                  await _recargarChacrasDisponibles();
                  await _cargarInventarioProductor();
                  if (!mounted) return;
                  setState(() => _chacrasSeleccionadas.add(nombreChacra));

                  if (!mounted) return;
                  mostrarAgroSnack(
                    context,
                    "Chacra '$nombreChacra' creada correctamente",
                    tipo: AgroSnackTipo.ok,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // PANEL 2: NUEVO RUBRO / NUEVO INSUMO AL CATÁLOGO
  // ===========================================================================
  void _mostrarModalNuevoRubroRapido(Function(String) onCreado) {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    String macroRubro = "PRODUCTOS";

    mostrarAgroPanel<void>(
      context: context,
      titulo: "Nuevo rubro de insumo",
      subtitulo: "Clasificación para el catálogo",
      icono: Icons.category_outlined,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (_, setModalState) {
            return Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Macro rubro", style: AgroText.label),
                  const SizedBox(height: 6),
                  AgroSegmentedTabs(
                    seleccionado: macroRubro,
                    items: const [
                      AgroTabItem(
                        id: "PRODUCTOS",
                        label: "Productos",
                        icono: Icons.science_outlined,
                      ),
                      AgroTabItem(
                        id: "INSUMOS VARIOS",
                        label: "Insumos varios",
                        icono: Icons.inventory_2_outlined,
                        color: AgroColors.warn,
                      ),
                    ],
                    onChanged: (val) => setModalState(() => macroRubro = val),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: nombreCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: agroInputDecoration(
                      label: "Nombre del rubro",
                      hint: "Ej: BIOESTIMULANTES",
                      icono: Icons.label_outline_rounded,
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? "Ingresá un nombre" : null,
                  ),
                  const SizedBox(height: 18),
                  AgroButton(
                    label: "Guardar rubro",
                    icono: Icons.check_rounded,
                    expandido: true,
                    onTap: () async {
                      if (!formKey.currentState!.validate()) return;
                      final db = await DatabaseHelper.instance.database;

                      final int sigCodigo = await DatabaseHelper.instance
                          .obtenerSiguienteId('rubros_insumos', 'codigo');
                      final resRubro = await db.rawQuery(
                        'SELECT MAX(CAST(cod_rubro AS INTEGER)) as max_cr FROM rubros_insumos WHERE macro_rubro = ?',
                        [macroRubro],
                      );
                      final int maxCr = (resRubro.first['max_cr'] as int?) ?? 0;
                      final int sigCodRubro = maxCr + 1;

                      final String nuevoNom =
                          nombreCtrl.text.trim().toUpperCase();
                      final rowRubro = {
                        'codigo': sigCodigo,
                        'cod_rubro': sigCodRubro,
                        'nombre': nuevoNom,
                        'macro_rubro': macroRubro,
                      };

                      await db.insert('rubros_insumos', rowRubro);

                      try {
                        await Supabase.instance.client
                            .from('rubros_insumos')
                            .insert(rowRubro);
                      } catch (e) {
                        debugPrint("Aviso sync rubro: $e");
                      }

                      await _recargarCatalogoInsumos();
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      onCreado(nuevoNom);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _mostrarModalNuevoInsumoCatalogo() {
    final fKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    final activoCtrl = TextEditingController();
    final concentracionCtrl = TextEditingController();
    final tcCtrl = TextEditingController(text: "7");
    final tiCtrl = TextEditingController(text: "24");
    final stockCtrl = TextEditingController(text: "0");

    List<String> opcionesRubros = _rubrosInsumosDisponibles.isNotEmpty
        ? _rubrosInsumosDisponibles
        : ["AGROQUIMICOS", "FERTILIZANTES", "HERBICIDAS", "COADYUVANTES"];

    String rubroSel = opcionesRubros.first;

    mostrarAgroPanel<void>(
      context: context,
      titulo: "Nuevo insumo al catálogo",
      subtitulo: "Alta técnica del producto",
      icono: Icons.add_box_outlined,
      maxWidth: 580,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (_, setModalState) {
            return Form(
              key: fKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: agroInputDecoration(
                      label: "Nombre comercial",
                      hint: "Ej: Coragen / Captan",
                      icono: Icons.science_outlined,
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? "Obligatorio" : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: opcionesRubros.contains(rubroSel)
                              ? rubroSel
                              : null,
                          isExpanded: true,
                          decoration: agroInputDecoration(
                            label: "Rubro / clasificación",
                            icono: Icons.category_outlined,
                          ),
                          items: opcionesRubros.map((r) {
                            return DropdownMenuItem<String>(
                              value: r,
                              child: Text(r, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => rubroSel = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      AgroIconButton(
                        icono: Icons.add_rounded,
                        tooltip: "Crear nuevo rubro",
                        color: AgroTheme.colorAccentDark,
                        size: 48,
                        onTap: () {
                          _mostrarModalNuevoRubroRapido((nuevoR) {
                            setModalState(() {
                              if (!opcionesRubros.contains(nuevoR)) {
                                opcionesRubros.add(nuevoR);
                              }
                              rubroSel = nuevoR;
                            });
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: activoCtrl,
                    decoration: agroInputDecoration(
                      label: "Principio activo",
                      hint: "Ej: Clorantraniliprole",
                      icono: Icons.biotech_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _filaResponsive(
                    anchoMinimo: 150,
                    hijos: [
                      TextFormField(
                        controller: concentracionCtrl,
                        decoration: agroInputDecoration(
                          label: "Concentración",
                          hint: "Ej: 20% SC",
                        ),
                      ),
                      TextFormField(
                        controller: stockCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: agroInputDecoration(label: "Stock inicial"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _filaResponsive(
                    anchoMinimo: 150,
                    hijos: [
                      TextFormField(
                        controller: tcCtrl,
                        keyboardType: TextInputType.number,
                        decoration: agroInputDecoration(
                          label: "T. carencia",
                          sufijo: "días",
                        ),
                      ),
                      TextFormField(
                        controller: tiCtrl,
                        keyboardType: TextInputType.number,
                        decoration: agroInputDecoration(
                          label: "T. reingreso",
                          sufijo: "horas",
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  AgroButton(
                    label: "Guardar insumo",
                    icono: Icons.check_rounded,
                    expandido: true,
                    onTap: () async {
                      if (!fKey.currentState!.validate()) return;
                      final db = await DatabaseHelper.instance.database;

                      final int sigId = await DatabaseHelper.instance
                          .obtenerSiguienteId('catalogo_insumos', 'ID_Insumos');

                      final rowNuevo = {
                        'ID_Insumos': sigId,
                        'rubro': rubroSel,
                        'Descripcion1': nombreCtrl.text.trim(),
                        'Descripcion2': activoCtrl.text.trim(),
                        'principio_activo': activoCtrl.text.trim(),
                        'Concentracion': concentracionCtrl.text.trim(),
                        'T_C': int.tryParse(tcCtrl.text.trim()) ?? 0,
                        'TRI': int.tryParse(tiCtrl.text.trim()) ?? 0,
                        'Mostrar': 1,
                        'stock_real': int.tryParse(stockCtrl.text.trim()) ?? 0,
                      };

                      await db.insert('catalogo_insumos', rowNuevo);
                      try {
                        await Supabase.instance.client
                            .from('catalogo_insumos')
                            .insert(rowNuevo);
                      } catch (_) {}

                      await _recargarCatalogoInsumos();

                      if (!mounted) return;
                      setState(() {
                        _idProductoSeleccionado = sigId.toString();
                      });
                      Navigator.pop(ctx);

                      // El selector solo lista insumos con stock del productor:
                      // avisamos si el nuevo insumo todavía no aparece.
                      final bool visible = _idsCatalogo.contains(sigId.toString());
                      mostrarAgroSnack(
                        context,
                        visible
                            ? 'Insumo agregado al catálogo'
                            : 'Insumo agregado al catálogo. Aparecerá en el selector cuando tenga stock para este productor.',
                        tipo: visible ? AgroSnackTipo.ok : AgroSnackTipo.aviso,
                        duracion: Duration(seconds: visible ? 3 : 5),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // RECETA: AGREGAR / QUITAR PRODUCTOS (lógica original)
  // ===========================================================================

  void _agregarProductoATabla() {
    if (_idProductoSeleccionado == null ||
        _idProductoSeleccionado!.trim().isEmpty) {
      _mostrarAlerta(
          'Por favor, seleccioná un insumo del catálogo con stock disponible.');
      return;
    }

    Map<String, dynamic> prodMap = {};
    for (var p in _catalogoInsumos) {
      final String idActual =
          (p['cod_producto'] ?? p['ID_Insumos'] ?? p['id'] ?? '')
              .toString()
              .trim();
      if (idActual == _idProductoSeleccionado!.trim()) {
        prodMap = p;
        break;
      }
    }

    if (prodMap.isEmpty) {
      _mostrarAlerta('El producto seleccionado no cuenta con stock.');
      return;
    }

    final cleanInput = _dosisInputController.text.trim().replaceAll(',', '.');
    final double dosisInput = double.tryParse(cleanInput) ?? 0.0;

    if (dosisInput <= 0) {
      _mostrarAlerta('Ingresá una dosis mayor a 0.');
      return;
    }

    final double stockDisp =
        (prodMap['stock_productor_disponible'] as num?)?.toDouble() ?? 0.0;
    final double volCaldoHa = double.tryParse(
            _volumenHaController.text.replaceAll(',', '.').trim()) ??
        1000.0;

    double dosis100Final = 0.0;
    double dosisMaqFinal = 0.0;
    double consumoEstimado = 0.0;

    if (_metodoDosis == "DOSIS_100") {
      dosis100Final = dosisInput;
      dosisMaqFinal = dosisInput * (_capacidadMaquinaLitros / 100.0);
      // cantMaq = Sup × caldo ÷ 2000 · cantProd = cantMaq × dosisMaq
      consumoEstimado = CalculoDosis.cantidadMaquinas(
              _superficieTotalSeleccionada, volCaldoHa) *
          dosisMaqFinal;
    } else {
      dosis100Final =
          volCaldoHa > 0 ? ((dosisInput / volCaldoHa) * 100.0) : dosisInput;
      final double haPorMaquina =
          volCaldoHa > 0 ? (_capacidadMaquinaLitros / volCaldoHa) : 2.0;
      dosisMaqFinal = dosisInput * haPorMaquina;
      consumoEstimado = dosisInput * _superficieTotalSeleccionada;
    }

    if (consumoEstimado > stockDisp) {
      _mostrarAlerta(
          'El consumo estimado (${consumoEstimado.toStringAsFixed(1)} L/Kg) supera el stock disponible (${stockDisp.toStringAsFixed(1)} L/Kg).');
      return;
    }

    setState(() {
      _itemsRecetaTemporal.add({
        'cod_producto': prodMap['cod_producto'] ??
            prodMap['ID_Insumos'] ??
            prodMap['id'] ??
            0,
        'producto':
            prodMap['Descripcion1'] ?? prodMap['descripcion'] ?? 'Insumo',
        'rubro': prodMap['rubro'] ?? 'General',
        'metodo_dosis': _metodoDosis,
        'dosis_valor': cleanInput,
        // Sin redondear a 2 decimales (0.0125 no debe quedar como 0.01).
        'dosis_100': _numTexto(dosis100Final),
        'dosis_maq': dosisMaqFinal,
        'tc': prodMap['T_C'] ?? prodMap['tc'] ?? 0,
        'ti': prodMap['TRI'] ?? prodMap['ti'] ?? 0,
        'orden_aplic': _itemsRecetaTemporal.length + 1,
      });

      _idProductoSeleccionado = null;
      _dosisInputController.clear();
      _dosisMaquinaController.clear();
      _dosisMaquinaCalculada = 0.0;
    });

    mostrarAgroSnack(
      context,
      'Insumo verificado con stock y agregado a la receta',
      tipo: AgroSnackTipo.ok,
      duracion: const Duration(milliseconds: 1400),
    );
  }

  /// Número con hasta 4 decimales, sin ceros de más: 0.0125 → "0.0125", 2.0 → "2".
  String _numTexto(double v) {
    var t = v.toStringAsFixed(4);
    if (t.contains('.')) {
      t = t.replaceFirst(RegExp(r'0+$'), '');
      if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    }
    return t;
  }

  void _eliminarProductoDeReceta(int index) {
    setState(() {
      _itemsRecetaTemporal.removeAt(index);
      for (int i = 0; i < _itemsRecetaTemporal.length; i++) {
        _itemsRecetaTemporal[i]['orden_aplic'] = i + 1;
      }
    });
  }

  // ===========================================================================
  // GUARDADO (lógica original; solo cambian los mensajes visuales)
  // ===========================================================================

  Future<void> _guardarOrdenCompleta() async {
    if (!_formKey.currentState!.validate()) {
      _mostrarAlerta("Revisá los campos obligatorios marcados en rojo");
      return;
    }

    if (_chacrasSeleccionadas.isEmpty) {
      _mostrarAlerta("Debés seleccionar al menos una chacra");
      return;
    }

    if (_cuadrosSeleccionados.isEmpty) {
      _mostrarAlerta("Debés seleccionar al menos un cuadro de la lista");
      return;
    }

    if (_itemsRecetaTemporal.isEmpty) {
      _mostrarAlerta("Debés agregar al menos un producto a la receta");
      return;
    }

    final String motivoFinal = _esMotivoPersonalizado
        ? _motivoCustomController.text.trim()
        : (_motivoSeleccionado ?? '');

    if (motivoFinal.isEmpty) {
      _mostrarAlerta("Debés especificar el motivo técnico de aplicación");
      return;
    }

    setState(() => _guardando = true);
    final db = await DatabaseHelper.instance.database;

    try {
      // Una chacra → formato de siempre. Varias → "chacra:cuadro".
      final campos = serializarCuadrosOrden(_refsSeleccionadas);
      final String chacraCampo = campos.chacra;
      final String cuadrosConcatenados = campos.cuadros;
      final double volHa =
          double.tryParse(_volumenHaController.text.replaceAll(',', '.')) ??
              1000.0;

      final int ordenIdFinal = _esEdicion
          ? _numeroOrden
          : await DatabaseHelper.instance
              .obtenerSiguienteId('recetas_aplicaciones', 'cod_receta');

      _numeroOrden = ordenIdFinal;
      // Mantener sincronizado el número mostrado en el mensaje final.
      _codigoOrdenFormateado = ordenIdFinal.toString();

      // Lógica de guardado segura para evitar errores de tipo en Web
      if (_esEdicion) {
        await db.delete(
          'recetas_aplicaciones',
          where: 'cod_orden = ? AND cod_productor = ?',
          whereArgs: [ordenIdFinal, widget.codProductor],
        );
        await db.delete(
          'parametros_aplic',
          where: 'cod_orden = ?',
          whereArgs: [ordenIdFinal],
        );
      }

      int siguienteRecetaId = await DatabaseHelper.instance
          .obtenerSiguienteId('recetas_aplicaciones', 'cod_receta');

      Batch batch = db.batch();

      for (int i = 0; i < _itemsRecetaTemporal.length; i++) {
        final item = _itemsRecetaTemporal[i];
        final int idActual = siguienteRecetaId + i;

        final rowReceta = {
          'cod_receta': idActual,
          'cod_orden': ordenIdFinal,
          'cod_productor': widget.codProductor,
          'productor': widget.nombreProductor,
          'orden_aplic': i + 1,
          'ref': ordenIdFinal,
          'fecha': _fecha,
          'chacra': chacraCampo,
          'cuadros': cuadrosConcatenados,
          'cultivos': serializarFiltroOrden(_cultivosFiltro),
          'variedades': serializarFiltroOrden(_variedadesFiltro),
          'motivo_aplic': motivoFinal,
          'momento_aplic': _momentoController.text.trim(),
          'vol_aplic_ha': volHa,
          'responsable': _responsable,
          'cod_producto': item['cod_producto'],
          'producto': item['producto'],
          'dosis_100': item['dosis_100'],
          'dosis_maq': item['dosis_maq'],
          'tc': item['tc'].toString(),
          'ti': item['ti'].toString(),
          'habilitado': _esEdicion
              ? (widget.ordenParaEditar!['estado'] ?? 'ACTIVO')
              : 'ACTIVO',
          'sincronizado':
              1, // Marcado como sincronizado para evitar reintentos fallidos en web
        };

        batch.insert('recetas_aplicaciones', rowReceta);

        // Envío seguro a Supabase protegiendo el scope del cliente web
        try {
          await Supabase.instance.client
              .from('recetas_aplicaciones')
              .upsert(rowReceta);
        } catch (supaErr) {
          debugPrint("Aviso sync receta web: $supaErr");
        }
      }

      // ----------------------------------------------------------------------
      // Cabecera en ordenes_aplicaciones
      // ----------------------------------------------------------------------
      final rowCabeceraOrden = {
        'cod_orden': ordenIdFinal.toString(),
        'cod_productor': widget.codProductor.toString(),
        'productor': widget.nombreProductor,
        'orden_aplic': 1,
        'ref': ordenIdFinal,
        'fecha': _fecha,
        'chacra': chacraCampo,
        'cuadros': cuadrosConcatenados,
        'cultivos': serializarFiltroOrden(_cultivosFiltro),
        'variedades': serializarFiltroOrden(_variedadesFiltro),
        'motivo_aplic': motivoFinal,
        'momento_aplic': _momentoController.text.trim(),
        'vol_aplic_ha': volHa,
        'responsable': _responsable,
        'estado': _esEdicion
            ? (widget.ordenParaEditar!['estado'] ?? 'ACTIVO')
            : 'ACTIVO',
        'vol_100': volHa > 0 ? (volHa / 10.0) : 100.0,
        'sincronizado': 0,
      };

      await db.insert(
        'ordenes_aplicaciones',
        rowCabeceraOrden,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      try {
        final payloadOrden = Map<String, dynamic>.from(rowCabeceraOrden)
          ..remove('sincronizado');
        await Supabase.instance.client
            .from('ordenes_aplicaciones')
            .upsert(payloadOrden);
      } catch (_) {}

      // ----------------------------------------------------------------------
      // Detalle en recetas_aplicaciones con regla dosis_x
      // ----------------------------------------------------------------------
      for (int i = 0; i < _itemsRecetaTemporal.length; i++) {
        final item = _itemsRecetaTemporal[i];
        final int idActual = siguienteRecetaId + i;

        final bool esDosisHa = item['metodo_dosis'] == "DOSIS_HA";
        final String dosisX = esDosisHa ? "dosis_ha" : "vol_100";
        final double dosisValor =
            double.tryParse(item['dosis_valor']?.toString() ?? '0') ?? 0.0;

        // Regla:
        // Si es dosis_ha: vol_aplic_ha guarda la dosis por Ha, y dosis_100 / dosis_maq van en 0.
        // Si es vol_100: vol_aplic_ha va en 0, y se guardan dosis_100 y dosis_maq.
        final double volAplicHaFila = esDosisHa ? dosisValor : 0.0;
        final double d100Fila = esDosisHa
            ? 0.0
            : (double.tryParse(item['dosis_100']?.toString() ?? '0') ?? 0.0);
        final double dMaqFila = esDosisHa
            ? 0.0
            : (double.tryParse(item['dosis_maq']?.toString() ?? '0') ?? 0.0);

        final rowReceta = {
          'cod_receta': idActual,
          'cod_orden': ordenIdFinal,
          'cod_productor': widget.codProductor,
          'productor': widget.nombreProductor,
          'orden_aplic': i + 1,
          'ref': ordenIdFinal,
          'fecha': _fecha,
          'chacra': chacraCampo,
          'cuadros': cuadrosConcatenados,
          'cultivos': serializarFiltroOrden(_cultivosFiltro),
          'variedades': serializarFiltroOrden(_variedadesFiltro),
          'motivo_aplic': motivoFinal,
          'momento_aplic': _momentoController.text.trim(),
          'vol_aplic_ha': volAplicHaFila, // Según la regla solicitada
          'responsable': _responsable,
          'cod_producto': item['cod_producto'],
          'producto': item['producto'],
          'dosis_100': d100Fila,
          'dosis_maq': dMaqFila,
          'tc': item['tc'].toString(),
          'ti': item['ti'].toString(),
          'habilitado': _esEdicion
              ? (widget.ordenParaEditar!['estado'] ?? 'ACTIVO')
              : 'ACTIVO',
          'dosis_x': dosisX, // dosis_ha o vol_100
          'sincronizado': 0,
        };

        batch.insert('recetas_aplicaciones', rowReceta,
            conflictAlgorithm: ConflictAlgorithm.replace);

        try {
          final payloadReceta = Map<String, dynamic>.from(rowReceta)
            ..remove('sincronizado');
          await Supabase.instance.client
              .from('recetas_aplicaciones')
              .upsert(payloadReceta);
        } catch (_) {}
      }

      final rowParametros = {
        'cod_orden': ordenIdFinal,
        'cod_receta': ordenIdFinal,
        'vel_viento': _paramVientoCtrl.text.trim(),
        'Temperatura': _paramTempCtrl.text.trim(),
        'Tamano_gota': _paramGotaCtrl.text.trim(),
        'Vel_Aplicacion': _paramVelocidadCtrl.text.trim(),
        'Caudal_Ha': _paramCaudalCtrl.text.trim(),
      };

      batch.insert(
        'parametros_aplic',
        rowParametros,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      try {
        await Supabase.instance.client
            .from('parametros_aplic')
            .upsert(rowParametros);
      } catch (_) {}

      await batch.commit(noResult: true);

      if (mounted) {
        mostrarAgroSnack(
          context,
          _esEdicion
              ? "Orden #$_codigoOrdenFormateado actualizada correctamente."
              : "Orden #$_codigoOrdenFormateado guardada correctamente.",
          tipo: AgroSnackTipo.ok,
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _mostrarAlerta("Error al guardar la orden: $e");
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarAlerta(String msg) {
    if (!mounted) return;
    mostrarAgroSnack(
      context,
      msg,
      tipo: AgroSnackTipo.error,
      duracion: const Duration(seconds: 4),
    );
  }

  // ===========================================================================
  // DATOS DERIVADOS SOLO PARA LA VISTA (no afectan el guardado)
  // ===========================================================================

  double get _volHaVista =>
      double.tryParse(_volumenHaController.text.replaceAll(',', '.').trim()) ??
      1000.0;

  double get _caldoTotalLitros => _superficieTotalSeleccionada * _volHaVista;

  double get _tanquesEstimados => _capacidadMaquinaLitros > 0
      ? _caldoTotalLitros / _capacidadMaquinaLitros
      : 0.0;

  String get _motivoVista => _esMotivoPersonalizado
      ? _motivoCustomController.text.trim()
      : (_motivoSeleccionado ?? '');

  String get _fechaVisible {
    final d = DateTime.tryParse(_fecha);
    return d == null ? _fecha : DateFormat('dd/MM/yyyy').format(d);
  }

  List<String> get _idsCatalogo => _catalogoInsumos
      .map((p) =>
          (p['cod_producto'] ?? p['ID_Insumos'] ?? p['id']).toString().trim())
      .toList();

  String _fmtLitros(double v) => NumberFormat('#,##0', 'es').format(v.round());

  String _fmtNum(dynamic v) {
    final double? d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return v?.toString() ?? '-';
    return d.toStringAsFixed(2);
  }

  String get _textoAyudaDosis {
    final String cap = _capacidadMaquinaLitros.toStringAsFixed(0);
    if (_metodoDosis == "DOSIS_100") {
      return 'Tanque de $cap L = ${(_capacidadMaquinaLitros / 100.0).toStringAsFixed(0)} × la dosis cada 100 L';
    }
    final double vol = _volHaVista;
    if (vol <= 0) return 'Sin volumen de caldo: se asumen 2 Ha por tanque';
    return 'Un tanque de $cap L cubre ${(_capacidadMaquinaLitros / vol).toStringAsFixed(2)} Ha';
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final bool esAncho =
        AgroBreakpoints.ancho(context) >= AgroBreakpoints.tablet;

    final String titulo = _esEdicion
        ? "Editar orden${_codigoOrdenFormateado.isNotEmpty ? ' #$_codigoOrdenFormateado' : ''}"
        : "Nueva orden de aplicación";

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: titulo,
        subtitulo: widget.nombreProductor,
        leading: IconButton(
          tooltip: 'Cerrar',
          icon: const Icon(Icons.close_rounded,
              size: 22, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar:
          (!esAncho && !_cargando) ? _barraAccionesMovil() : null,
      body: _cargando
          ? const AgroLoading(mensaje: 'Cargando datos de la orden…')
          : Form(
              key: _formKey,
              child: esAncho ? _layoutAncho() : _layoutAngosto(),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layouts
  // ---------------------------------------------------------------------------

  /// Web / escritorio: formulario a la izquierda y resumen fijo a la derecha.
  Widget _layoutAncho() {
    return AgroContent(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollFormulario,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: _columnaFormulario(),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 360,
            child: SingleChildScrollView(
              controller: _scrollResumen,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: _panelResumen(),
            ),
          ),
        ],
      ),
    );
  }

  /// Celular / tablet: una sola columna con barra de acciones fija abajo.
  Widget _layoutAngosto() {
    return SingleChildScrollView(
      controller: _scrollFormulario,
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      child: AgroContent(
        maxWidth: 860,
        child: _columnaFormulario(),
      ),
    );
  }

  Widget _columnaFormulario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tarjetaEncabezado(),
        const SizedBox(height: 16),
        _seccionDatosGenerales(),
        const SizedBox(height: 16),
        _seccionLote(),
        const SizedBox(height: 16),
        _seccionCaldo(),
        const SizedBox(height: 16),
        _seccionProductos(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Encabezado de la orden
  // ---------------------------------------------------------------------------

  Widget _tarjetaEncabezado() {
    final String estado = _esEdicion
        ? (widget.ordenParaEditar!['estado']?.toString() ?? 'ACTIVO')
        : '';
    return AgroCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const AgroIconBox(icono: Icons.assignment_outlined, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        "Orden de aplicación #$_codigoOrdenFormateado",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.titulo.copyWith(fontSize: 17),
                      ),
                    ),
                    if (_esEdicion && estado.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      AgroBadge.estado(estado),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AgroTag(texto: _fechaVisible, icono: Icons.event_outlined),
                    AgroTag(
                        texto: _responsable,
                        icono: Icons.person_outline_rounded),
                    AgroTag(
                        texto: widget.nombreProductor,
                        icono: Icons.storefront_outlined),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sección 1: Datos generales
  // ---------------------------------------------------------------------------

  Widget _seccionDatosGenerales() {
    final String? valorTipo =
        _tiposAplicacion.contains(_tipoAplicacionSeleccionado)
            ? _tipoAplicacionSeleccionado
            : null;
    final String? valorMotivo = _esMotivoPersonalizado
        ? "__OTRO__"
        : (_motivosDisponibles.contains(_motivoSeleccionado)
            ? _motivoSeleccionado
            : null);

    return _seccion(
      numero: 1,
      titulo: "Datos generales",
      subtitulo: "Tipo, motivo técnico y momento de la aplicación",
      icono: Icons.event_note_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filaResponsive(
            anchoMinimo: 280,
            hijos: [
              DropdownButtonFormField<String>(
                value: valorTipo,
                isExpanded: true,
                decoration: agroInputDecoration(
                  label: "Tipo de aplicación",
                  icono: Icons.category_outlined,
                ),
                items: _tiposAplicacion.map((tipo) {
                  return DropdownMenuItem<String>(
                    value: tipo,
                    child: Text(tipo, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _tipoAplicacionSeleccionado = val);
                    _cargarMotivosPorTipo(val);
                  }
                },
              ),
              DropdownButtonFormField<String>(
                value: valorMotivo,
                isExpanded: true,
                decoration: agroInputDecoration(
                  label: "Motivo técnico",
                  icono: Icons.bug_report_outlined,
                ),
                items: [
                  ..._motivosDisponibles.map((mot) {
                    return DropdownMenuItem<String>(
                      value: mot,
                      child: Text(mot, overflow: TextOverflow.ellipsis),
                    );
                  }),
                  const DropdownMenuItem<String>(
                    value: "__OTRO__",
                    child: Text("+ Escribir otro motivo…",
                        style: TextStyle(
                            color: AgroTheme.colorAccentDark,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
                onChanged: (val) {
                  setState(() {
                    if (val == "__OTRO__") {
                      _esMotivoPersonalizado = true;
                    } else {
                      _esMotivoPersonalizado = false;
                      _motivoSeleccionado = val;
                    }
                  });
                },
              ),
            ],
          ),
          if (_esMotivoPersonalizado) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _motivoCustomController,
              decoration: agroInputDecoration(
                label: "Nuevo motivo técnico",
                hint: "Escribí el motivo de la aplicación",
                icono: Icons.edit_note_rounded,
              ),
              onChanged: (_) => setState(() {}),
              validator: (val) {
                if (_esMotivoPersonalizado &&
                    (val == null || val.trim().isEmpty)) {
                  return "Ingresá el motivo técnico";
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _momentoController,
            decoration: agroInputDecoration(
              label: "Momento fenológico",
              hint: "Ej: Fruto 10 mm",
              icono: Icons.schedule_rounded,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sección 2: Lote / cuadros
  // ---------------------------------------------------------------------------

  Widget _seccionLote() {
    return _seccion(
      numero: 2,
      titulo: "Chacras y cuadros",
      subtitulo: "Marcá una o varias chacras y después los cuadros a tratar",
      icono: Icons.map_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bloqueChacras(),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AgroTheme.colorBorder),
          const SizedBox(height: 16),
          _bloqueFiltrosCuadros(),
          _bloqueCuadros(),
        ],
      ),
    );
  }

  // ---------------------------- Chacras (multiselección) ---------------------

  Widget _bloqueChacras() {
    final cuadrosPorChacra = <String, List<_CuadroInv>>{};
    for (final c in _cuadrosInventario) {
      cuadrosPorChacra.putIfAbsent(c.chacra, () => []).add(c);
    }
    final todas = {..._chacrasDisponibles, ...cuadrosPorChacra.keys}.toList()
      ..sort(compararNatural);

    const int limite = 5;
    final bool recortar = !_verTodasChacras && todas.length > limite + 1;
    final visibles = recortar
        ? [
            ...todas.take(limite),
            ...todas.skip(limite).where(_chacrasSeleccionadas.contains),
          ]
        : todas;
    final int ocultas = todas.length - visibles.length;
    final bool todasSel =
        todas.isNotEmpty && todas.every(_chacrasSeleccionadas.contains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CHACRAS", style: AgroText.overline),
                  const SizedBox(height: 2),
                  Text(
                    _chacrasSeleccionadas.isEmpty
                        ? "Ninguna seleccionada"
                        : "${_chacrasSeleccionadas.length} de ${todas.length} seleccionadas",
                    style: AgroText.secundario.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            _botonCuadrado(
              icono: Icons.add_location_alt_outlined,
              tooltip: "Crear nueva chacra para este productor",
              onTap: _mostrarModalNuevaChacra,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (todas.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AgroTheme.colorBg,
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
            ),
            child: const Text(
              "Este productor no tiene chacras. Creá una con el botón +.",
              textAlign: TextAlign.center,
              style: AgroText.secundario,
            ),
          )
        else ...[
          if (todas.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AgroButton(
                label: todasSel ? "Quitar todas" : "Marcar todas las chacras",
                icono: todasSel
                    ? Icons.remove_done_rounded
                    : Icons.done_all_rounded,
                tipo: AgroButtonTipo.secundario,
                compacto: true,
                expandido: true,
                onTap: () => _seleccionarChacras(
                    todasSel ? const <String>[] : todas),
              ),
            ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
              border: Border.all(color: AgroTheme.colorBorder),
            ),
            child: Column(
              children: [
                for (int i = 0; i < visibles.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: AgroTheme.colorBorder),
                  _tileChacra(
                      visibles[i], cuadrosPorChacra[visibles[i]] ?? const []),
                ],
              ],
            ),
          ),
          if (ocultas > 0 || (_verTodasChacras && todas.length > limite + 1))
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _verTodasChacras = !_verTodasChacras),
                style: TextButton.styleFrom(
                  foregroundColor: AgroColors.primario,
                  minimumSize: const Size(0, 44),
                ),
                icon: Icon(
                  ocultas > 0
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  size: 20,
                ),
                label: Text(
                  ocultas > 0
                      ? "Ver $ocultas ${ocultas == 1 ? 'chacra más' : 'chacras más'}"
                      : "Ver menos",
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _tileChacra(String chacra, List<_CuadroInv> cuadros) {
    final bool sel = _chacrasSeleccionadas.contains(chacra);
    final double ha = cuadros.fold(0.0, (s, c) => s + c.ha);
    final int marcados =
        cuadros.where((c) => _cuadrosSeleccionados.contains(c.clave)).length;
    final vars = <String>{for (final c in cuadros) ...c.variedades}.toList()
      ..sort();
    final bool hayFiltroVar =
        _cultivosFiltro.isNotEmpty || _variedadesFiltro.isNotEmpty;
    final int coinciden = hayFiltroVar
        ? cuadros.where((c) => _matchCultivo(c) && _matchVariedad(c)).length
        : 0;

    return Material(
      color: sel ? AgroColors.primarioSoft : AgroTheme.colorSurface,
      child: InkWell(
        onTap: () => _alternarChacra(chacra),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              _casilla(sel),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Chacra $chacra",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: sel ? AgroColors.primario : AgroTheme.colorText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cuadros.isEmpty
                          ? "Sin cuadros en el inventario"
                          : "${cuadros.length} ${cuadros.length == 1 ? 'cuadro' : 'cuadros'} · ${ha.toStringAsFixed(2)} Ha",
                      style: AgroText.secundario.copyWith(fontSize: 12),
                    ),
                    if (vars.isNotEmpty)
                      Text(
                        vars.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.secundario.copyWith(fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (marcados > 0)
                AgroBadge(
                  texto: "$marcados ✓",
                  color: AgroColors.ok,
                  fondo: AgroColors.okSoft,
                )
              else if (!sel && hayFiltroVar && coinciden > 0)
                Tooltip(
                  message:
                      "Cuadros de esta chacra con el cultivo/variedad elegidos",
                  child: AgroBadge(
                    texto: "$coinciden coinciden",
                    color: AgroColors.warn,
                    fondo: AgroColors.warnSoft,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _casilla(bool marcada, {bool parcial = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: marcada || parcial ? AgroColors.primario : AgroTheme.colorSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: marcada || parcial
              ? AgroColors.primario
              : AgroTheme.colorTextSecondary.withOpacity(0.5),
          width: 1.6,
        ),
      ),
      child: marcada
          ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
          : (parcial
              ? const Icon(Icons.remove_rounded, size: 17, color: Colors.white)
              : null),
    );
  }

  // ---------------------------- Filtros ------------------------------------

  Widget _bloqueFiltrosCuadros() {
    if (_chacrasSeleccionadas.isEmpty) return const SizedBox.shrink();
    final cultivos = _conteoCultivos;
    final variedades = _conteoVariedades;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text("FILTRAR CUADROS", style: AgroText.overline),
            ),
            if (_hayFiltrosCuadros)
              TextButton.icon(
                onPressed: _limpiarFiltrosCuadros,
                style: TextButton.styleFrom(
                  foregroundColor: AgroColors.primario,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: const Text("Limpiar",
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AgroSearchField(
          controller: _buscarCuadroCtrl,
          hint: "Buscar cuadro, variedad o cultivo…",
          onChanged: (v) => setState(() => _busquedaCuadro = v),
        ),
        if (cultivos.length > 1) ...[
          const SizedBox(height: 14),
          const Text("CULTIVOS A TRATAR · podés elegir varios",
              style: AgroText.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipLote(
                texto: "Todos",
                seleccionado: _cultivosFiltro.isEmpty,
                onTap: () => setState(() {
                  _cultivosFiltro.clear();
                  _variedadesFiltro.clear();
                }),
              ),
              ...cultivos.entries.map((e) => _chipLote(
                    texto: e.key,
                    cantidad: e.value,
                    seleccionado: _cultivosFiltro.contains(e.key),
                    conCheck: true,
                    onTap: () => setState(() {
                      if (!_cultivosFiltro.remove(e.key)) {
                        _cultivosFiltro.add(e.key);
                      }
                      _ajustarFiltrosCuadros();
                    }),
                  )),
            ],
          ),
        ],
        if (variedades.length > 1) ...[
          const SizedBox(height: 14),
          const Text("VARIEDAD · podés elegir varias", style: AgroText.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipLote(
                texto: "Todas",
                seleccionado: _variedadesFiltro.isEmpty,
                color: AgroColors.warn,
                onTap: () => setState(() => _variedadesFiltro.clear()),
              ),
              ...variedades.entries.map((e) => _chipLote(
                    texto: e.key,
                    cantidad: e.value,
                    seleccionado: _variedadesFiltro.contains(e.key),
                    color: AgroColors.warn,
                    conCheck: true,
                    onTap: () => setState(() {
                      if (!_variedadesFiltro.remove(e.key)) {
                        _variedadesFiltro.add(e.key);
                      }
                    }),
                  )),
            ],
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _chipLote({
    required String texto,
    int? cantidad,
    required bool seleccionado,
    required VoidCallback onTap,
    Color color = AgroColors.primario,
    bool conCheck = false,
  }) {
    return Material(
      color: seleccionado ? color : AgroTheme.colorSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: seleccionado ? color : AgroTheme.colorBorder),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (conCheck && seleccionado) ...[
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 5),
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
                    "$cantidad",
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

  // ---------------------------- Cuadros ------------------------------------

  Widget _bloqueCuadros() {
    if (_chacrasSeleccionadas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AgroColors.primarioSoft,
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        ),
        child: const Row(
          children: [
            Icon(Icons.touch_app_outlined, color: AgroColors.primario),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "Marcá una o más chacras de la lista para ver sus cuadros.",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AgroColors.primario,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final visibles = _cuadrosVisibles;
    final double haVis = visibles.fold(
        0.0, (s, c) => s + c.haFiltrada(_cultivosFiltro, _variedadesFiltro));
    final bool todosVis = visibles.isNotEmpty &&
        visibles.every((c) => _cuadrosSeleccionados.contains(c.clave));

    final Map<String, List<_CuadroInv>> grupos = {};
    for (final c in visibles) {
      grupos.putIfAbsent(c.chacra, () => []).add(c);
    }
    final clavesGrupos = grupos.keys.toList()..sort(compararNatural);
    final bool variasChacras = clavesGrupos.length > 1;

    final int nSel = _cuadrosSeleccionados.length;
    final int nChacrasSel = _refsSeleccionadas.map((r) => r.chacra).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${visibles.length} ${visibles.length == 1 ? 'cuadro' : 'cuadros'}",
                    style: AgroText.tituloCard,
                  ),
                  Text(
                    "${haVis.toStringAsFixed(2)} Ha${variasChacras ? ' · ${clavesGrupos.length} chacras' : ''}",
                    style: AgroText.secundario.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            AgroButton(
              label: todosVis ? "Quitar todos" : "Marcar todos",
              icono: todosVis
                  ? Icons.remove_done_rounded
                  : Icons.done_all_rounded,
              tipo: todosVis
                  ? AgroButtonTipo.secundario
                  : AgroButtonTipo.primario,
              compacto: true,
              onTap: visibles.isEmpty ? null : () => _alternarLista(visibles),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (visibles.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AgroTheme.colorBg,
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
            ),
            child: const Column(
              children: [
                Icon(Icons.search_off_rounded,
                    size: 28, color: AgroTheme.colorTextSecondary),
                SizedBox(height: 8),
                Text(
                  "No hay cuadros con esos filtros en las chacras elegidas.",
                  textAlign: TextAlign.center,
                  style: AgroText.secundario,
                ),
              ],
            ),
          )
        else
          for (final ch in clavesGrupos) ...[
            if (variasChacras) _encabezadoGrupoChacra(ch, grupos[ch]!),
            _grillaCuadros(grupos[ch]!),
            const SizedBox(height: 12),
          ],
        // Pie con totales de la selección
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: nSel == 0 ? AgroTheme.colorBg : AgroColors.warnSoft,
            borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
          ),
          child: Row(
            children: [
              Icon(
                nSel == 0
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_rounded,
                size: 18,
                color: nSel == 0
                    ? AgroTheme.colorTextSecondary
                    : AgroColors.warn,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nSel == 0
                      ? "Todavía no marcaste cuadros"
                      : "$nSel ${nSel == 1 ? 'cuadro' : 'cuadros'} en $nChacrasSel ${nChacrasSel == 1 ? 'chacra' : 'chacras'}",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: nSel == 0
                        ? AgroTheme.colorTextSecondary
                        : AgroColors.warn,
                  ),
                ),
              ),
              Text(
                "${_superficieTotalSeleccionada.toStringAsFixed(2)} Ha",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: nSel == 0
                      ? AgroTheme.colorTextSecondary
                      : AgroColors.warn,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _encabezadoGrupoChacra(String chacra, List<_CuadroInv> items) {
    final int n =
        items.where((c) => _cuadrosSeleccionados.contains(c.clave)).length;
    final bool todos = n == items.length;
    return InkWell(
      onTap: () => _alternarLista(items),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Row(
          children: [
            _casilla(todos && n > 0, parcial: n > 0 && !todos),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Chacra $chacra",
                style: AgroText.tituloCard.copyWith(fontSize: 14),
              ),
            ),
            Text(
              "$n/${items.length}",
              style: AgroText.label,
            ),
          ],
        ),
      ),
    );
  }

  Widget _grillaCuadros(List<_CuadroInv> items) {
    return LayoutBuilder(
      builder: (context, c) {
        final int cols = c.maxWidth >= 720 ? 3 : (c.maxWidth >= 430 ? 2 : 1);
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

  Widget _tileCuadro(_CuadroInv c) {
    final bool sel = _cuadrosSeleccionados.contains(c.clave);
    final vars = c.variedadesCon(_cultivosFiltro, _variedadesFiltro);
    final double haTile = c.haFiltrada(_cultivosFiltro, _variedadesFiltro);
    final String detalle = [
      vars.isEmpty ? 'Sin variedad' : vars.join(' / '),
      if (c.cultivos.isNotEmpty)
        (_cultivosFiltro.isEmpty
                ? c.cultivos
                : c.cultivos.where(_cultivosFiltro.contains))
            .join(' / '),
    ].where((t) => t.isNotEmpty).join(' · ');

    return Material(
      color: sel ? AgroColors.okSoft : AgroTheme.colorSurface,
      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      child: InkWell(
        onTap: () => _alternarSeleccionCuadro(c.clave),
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
            border: Border.all(
              color: sel ? AgroColors.ok : AgroTheme.colorBorder,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                sel
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: sel
                    ? AgroColors.ok
                    : AgroTheme.colorTextSecondary.withOpacity(0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Cuadro ${c.cuadro}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w700,
                        color: AgroTheme.colorText,
                      ),
                    ),
                    Text(
                      detalle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.secundario.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${haTile.toStringAsFixed(2)} Ha",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: sel ? AgroColors.ok : AgroTheme.colorText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sección 3: Caldo y parámetros técnicos
  // ---------------------------------------------------------------------------

  Widget _seccionCaldo() {
    return _seccion(
      numero: 3,
      titulo: "Caldo y parámetros",
      subtitulo: "Volumen por hectárea y condiciones de pulverización",
      icono: Icons.water_drop_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filaResponsive(
            anchoMinimo: 220,
            hijos: [
              TextFormField(
                controller: _volumenHaController,
                keyboardType: TextInputType.number,
                decoration: agroInputDecoration(
                  label: "Volumen de caldo",
                  sufijo: "L/Ha",
                  icono: Icons.opacity_rounded,
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
                validator: (val) =>
                    val == null || val.isEmpty ? "Obligatorio" : null,
                onChanged: (v) {
                  setState(() {
                    _paramCaudalCtrl.text = "$v L/Ha";
                  });
                  if (_dosisInputController.text.isNotEmpty) {
                    _calcularDosisMaquina(_dosisInputController.text);
                  }
                },
              ),
              TextFormField(
                controller: _paramCaudalCtrl,
                decoration: agroInputDecoration(
                  label: "Caudal por hectárea",
                  hint: "Ej: 1000 L/Ha",
                  icono: Icons.shower_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AgroStatGrid(
            fondo: AgroColors.infoSoft,
            stats: [
              AgroStat(
                label: "Superficie",
                valor:
                    "${_superficieTotalSeleccionada.toStringAsFixed(2)} Ha",
                icono: Icons.crop_square_rounded,
                color: AgroColors.info,
              ),
              AgroStat(
                label: "Caldo total",
                valor: "${_fmtLitros(_caldoTotalLitros)} L",
                icono: Icons.water_drop_outlined,
                color: AgroColors.info,
              ),
              AgroStat(
                label:
                    "Tanques ${_capacidadMaquinaLitros.toStringAsFixed(0)} L",
                valor: _tanquesEstimados.toStringAsFixed(1),
                icono: Icons.local_shipping_outlined,
                color: AgroColors.info,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text("CONDICIONES DE PULVERIZACIÓN",
              style: AgroText.overline),
          const SizedBox(height: 10),
          _filaResponsive(
            anchoMinimo: 220,
            hijos: [
              TextFormField(
                controller: _paramVientoCtrl,
                decoration: agroInputDecoration(
                  label: "Velocidad del viento",
                  hint: "Ej: 5-8 km/h",
                  icono: Icons.air_rounded,
                ),
              ),
              TextFormField(
                controller: _paramTempCtrl,
                decoration: agroInputDecoration(
                  label: "Temperatura",
                  hint: "Ej: 19 °C",
                  icono: Icons.thermostat_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _filaResponsive(
            anchoMinimo: 220,
            hijos: [
              TextFormField(
                controller: _paramGotaCtrl,
                decoration: agroInputDecoration(
                  label: "Tamaño de gota",
                  hint: "Ej: 250 µm",
                  icono: Icons.grain_rounded,
                ),
              ),
              TextFormField(
                controller: _paramVelocidadCtrl,
                decoration: agroInputDecoration(
                  label: "Velocidad de avance",
                  hint: "Ej: 5.5 km/h",
                  icono: Icons.speed_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sección 4: Productos de la receta
  // ---------------------------------------------------------------------------

  Widget _seccionProductos() {
    final List<String> ids = _idsCatalogo;
    final String? valorProducto = (_idProductoSeleccionado != null &&
            ids.contains(_idProductoSeleccionado!.trim()))
        ? _idProductoSeleccionado!.trim()
        : null;
    final bool esDosis100 = _metodoDosis == "DOSIS_100";

    return _seccion(
      numero: 4,
      titulo: "Productos",
      subtitulo: "Armá la receta con insumos que tengan stock",
      icono: Icons.science_outlined,
      trailing: AgroBadge(
        texto:
            "${_itemsRecetaTemporal.length} ${_itemsRecetaTemporal.length == 1 ? 'producto' : 'productos'}",
        grande: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selector de producto + alta rápida
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: valorProducto,
                  isExpanded: true,
                  menuMaxHeight: 420,
                  decoration: agroInputDecoration(
                    label: "Insumo con stock en finca",
                    icono: Icons.inventory_2_outlined,
                  ),
                  hint: Text(
                    _catalogoInsumos.isEmpty
                        ? "Sin productos con stock para este productor"
                        : "Seleccioná un insumo disponible",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AgroTheme.colorTextSecondary),
                  ),
                  items: _catalogoInsumos.map((prod) {
                    final String idProd =
                        (prod['cod_producto'] ?? prod['ID_Insumos'] ?? prod['id'])
                            .toString()
                            .trim();
                    final String nombre = (prod['Descripcion1'] ??
                            prod['descripcion'] ??
                            'Insumo')
                        .toString();
                    final double stockDisp =
                        (prod['stock_productor_disponible'] as num?)
                                ?.toDouble() ??
                            0.0;

                    return DropdownMenuItem<String>(
                      value: idProd,
                      child: Text(
                        "$nombre · Stock: ${stockDisp.toStringAsFixed(1)} L/Kg",
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: _catalogoInsumos.isEmpty
                      ? null
                      : (val) => setState(() => _idProductoSeleccionado = val),
                ),
              ),
              const SizedBox(width: 8),
              _botonCuadrado(
                icono: Icons.add_rounded,
                tooltip: "Dar de alta un nuevo insumo en el catálogo",
                onTap: _mostrarModalNuevoInsumoCatalogo,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Método de dosis
          const Text("MÉTODO DE DOSIS", style: AgroText.overline),
          const SizedBox(height: 8),
          AgroSegmentedTabs(
            seleccionado: _metodoDosis,
            items: const [
              AgroTabItem(
                id: "DOSIS_100",
                label: "Dosis / 100 L",
                icono: Icons.water_drop_outlined,
              ),
              AgroTabItem(
                id: "DOSIS_HA",
                label: "Dosis / Ha",
                icono: Icons.grid_on_rounded,
                color: AgroColors.warn,
              ),
            ],
            onChanged: (id) {
              setState(() => _metodoDosis = id);
              if (_dosisInputController.text.isNotEmpty) {
                _calcularDosisMaquina(_dosisInputController.text);
              }
            },
          ),
          const SizedBox(height: 14),

          // Dosis + resultado por máquina
          _filaResponsive(
            anchoMinimo: 220,
            hijos: [
              TextFormField(
                controller: _dosisInputController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: agroInputDecoration(
                  label: esDosis100
                      ? "Dosis cada 100 L"
                      : "Dosis por hectárea",
                  sufijo: esDosis100 ? "cc / g" : "L / Kg",
                  icono: Icons.colorize_rounded,
                ),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                onChanged: _calcularDosisMaquina,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AgroColors.primarioSoft,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border:
                      Border.all(color: AgroColors.primario.withOpacity(0.18)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.agriculture_rounded,
                        size: 20, color: AgroColors.primario),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Dosis por máquina (${_capacidadMaquinaLitros.toStringAsFixed(0)} L)",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AgroText.label.copyWith(fontSize: 10.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${_dosisMaquinaCalculada.toStringAsFixed(2)} L/Kg",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: AgroColors.primario,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AgroTheme.colorTextSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_textoAyudaDosis,
                    style: AgroText.secundario.copyWith(fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AgroButton(
            label: "Agregar a la receta",
            icono: Icons.add_circle_outline_rounded,
            tipo: AgroButtonTipo.secundario,
            expandido: true,
            onTap: _agregarProductoATabla,
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AgroTheme.colorBorder),
          const SizedBox(height: 14),
          Text(
            "PRODUCTOS EN LA RECETA (${_itemsRecetaTemporal.length})",
            style: AgroText.overline,
          ),
          const SizedBox(height: 10),
          if (_itemsRecetaTemporal.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
              decoration: BoxDecoration(
                color: AgroTheme.colorBg,
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                border: Border.all(color: AgroTheme.colorBorder),
              ),
              child: const Column(
                children: [
                  Icon(Icons.playlist_add_rounded,
                      size: 28, color: AgroTheme.colorTextSecondary),
                  SizedBox(height: 6),
                  Text(
                    "Todavía no agregaste productos.\nElegí un insumo, cargá la dosis y tocá «Agregar a la receta».",
                    textAlign: TextAlign.center,
                    style: AgroText.secundario,
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < _itemsRecetaTemporal.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _itemProducto(i),
            ],
        ],
      ),
    );
  }

  Widget _itemProducto(int idx) {
    final item = _itemsRecetaTemporal[idx];
    final bool esDosisHa = item['metodo_dosis'] == "DOSIS_HA";
    final double consumoTotalLote = CalculoDosis.cantidadProducto(
        item, _superficieTotalSeleccionada, _volHaVista);
    final double dosisMaqVista =
        CalculoDosis.dosisMaquina(item, _volHaVista);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        border: Border.all(color: AgroTheme.colorBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AgroTheme.colorSurface,
              shape: BoxShape.circle,
              border: Border.all(color: AgroTheme.colorBorder),
            ),
            child: Text(
              "${item['orden_aplic']}",
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: AgroTheme.colorText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        "${item['producto']}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: AgroTheme.colorText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AgroBadge(
                      texto: esDosisHa ? "Por Ha" : "Por 100 L",
                      color: esDosisHa ? AgroColors.warn : AgroColors.ok,
                      fondo: esDosisHa ? AgroColors.warnSoft : AgroColors.okSoft,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    _datoItem(
                      esDosisHa ? "Dosis/Ha" : "Dosis/100 L",
                      esDosisHa
                          ? "${item['dosis_valor']}"
                          : "${item['dosis_100']}",
                    ),
                    _datoItem("Máquina", "${_fmtNum(dosisMaqVista)} L/Kg"),
                    _datoItem("Total lote",
                        "${consumoTotalLote.toStringAsFixed(2)} L/Kg"),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Quitar de la receta",
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AgroColors.danger),
            onPressed: () => _eliminarProductoDeReceta(idx),
          ),
        ],
      ),
    );
  }

  Widget _datoItem(String clave, String valor) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: "$clave: ",
            style: const TextStyle(
                fontSize: 11.5, color: AgroTheme.colorTextSecondary),
          ),
          TextSpan(
            text: valor,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AgroTheme.colorText),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Resumen lateral (web / escritorio)
  // ---------------------------------------------------------------------------

  Widget _panelResumen() {
    final String motivo = _motivoVista;
    final bool okChacra = _chacrasSeleccionadas.isNotEmpty;
    final bool okCuadros = _cuadrosSeleccionados.isNotEmpty;
    final bool okProductos = _itemsRecetaTemporal.isNotEmpty;
    final bool okMotivo = motivo.isNotEmpty;

    return AgroCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgroSectionHeader(
            titulo: "Resumen de la orden",
            icono: Icons.fact_check_outlined,
          ),
          const SizedBox(height: 14),
          AgroStatGrid(
            stats: [
              AgroStat(
                label: "Superficie",
                valor:
                    "${_superficieTotalSeleccionada.toStringAsFixed(2)} Ha",
                icono: Icons.crop_square_rounded,
              ),
              AgroStat(
                label: "Caldo total",
                valor: "${_fmtLitros(_caldoTotalLitros)} L",
                icono: Icons.water_drop_outlined,
              ),
              AgroStat(
                label: "Tanques",
                valor: _tanquesEstimados.toStringAsFixed(1),
                icono: Icons.local_shipping_outlined,
              ),
              AgroStat(
                label: "Productos",
                valor: "${_itemsRecetaTemporal.length}",
                icono: Icons.science_outlined,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AgroKeyValue(clave: "Orden", valor: "#$_codigoOrdenFormateado"),
          AgroKeyValue(clave: "Fecha", valor: _fechaVisible),
          AgroKeyValue(
            clave: _chacrasSeleccionadas.length > 1 ? "Chacras" : "Chacra",
            valor: _chacrasSeleccionadas.isEmpty
                ? "—"
                : (_chacrasSeleccionadas.toList()..sort(compararNatural))
                    .join(', '),
          ),
          AgroKeyValue(
            clave: "Cultivos",
            valor: _cultivosFiltro.isEmpty
                ? "Todos"
                : (_cultivosFiltro.toList()..sort()).join(', '),
          ),
          if (_variedadesFiltro.isNotEmpty)
            AgroKeyValue(
              clave: "Variedades",
              valor: (_variedadesFiltro.toList()..sort()).join(', '),
            ),
          AgroKeyValue(
            clave: "Cuadros",
            valor: _cuadrosSeleccionados.isEmpty
                ? "—"
                : cuadrosLegibles(_refsSeleccionadas),
          ),
          AgroKeyValue(
              clave: "Tipo", valor: _tipoAplicacionSeleccionado ?? "—"),
          AgroKeyValue(clave: "Motivo", valor: okMotivo ? motivo : "—"),
          AgroKeyValue(
            clave: "Caldo",
            valor: "${_volumenHaController.text} L/Ha",
          ),
          if (_itemsRecetaTemporal.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: AgroTheme.colorBorder),
            const SizedBox(height: 10),
            const Text("ORDEN DE MEZCLA", style: AgroText.overline),
            const SizedBox(height: 6),
            for (final it in _itemsRecetaTemporal)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text("${it['orden_aplic']}.",
                          style: AgroText.label),
                    ),
                    Expanded(
                      child: Text(
                        "${it['producto']}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.cuerpo.copyWith(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AgroTheme.colorBorder),
          const SizedBox(height: 12),
          const Text("ANTES DE GUARDAR", style: AgroText.overline),
          const SizedBox(height: 6),
          _itemChequeo("Chacra seleccionada", okChacra),
          _itemChequeo("Al menos un cuadro", okCuadros),
          _itemChequeo("Motivo técnico definido", okMotivo),
          _itemChequeo("Al menos un producto", okProductos),
          const SizedBox(height: 16),
          AgroButton(
            label: _esEdicion ? "Actualizar orden" : "Guardar orden",
            icono: Icons.save_rounded,
            expandido: true,
            cargando: _guardando,
            onTap: _guardando ? null : _guardarOrdenCompleta,
          ),
          const SizedBox(height: 10),
          AgroButton(
            label: "Cancelar",
            tipo: AgroButtonTipo.secundario,
            expandido: true,
            onTap: _guardando ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _itemChequeo(String texto, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 17,
            color: ok ? AgroColors.ok : AgroTheme.colorTextSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: AgroText.secundario.copyWith(
                color: ok ? AgroTheme.colorText : AgroTheme.colorTextSecondary,
                fontWeight: ok ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Barra de acciones fija (celular / tablet)
  // ---------------------------------------------------------------------------

  Widget _barraAccionesMovil() {
    final double g = AgroBreakpoints.gutter(context);
    final int nCuadros = _cuadrosSeleccionados.length;
    final int nProd = _itemsRecetaTemporal.length;

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
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: EdgeInsets.fromLTRB(g, 10, g, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "$nCuadros ${nCuadros == 1 ? 'cuadro' : 'cuadros'} · ${_superficieTotalSeleccionada.toStringAsFixed(2)} Ha · $nProd ${nProd == 1 ? 'producto' : 'productos'}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AgroText.secundario
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.water_drop_outlined,
                          size: 14, color: AgroColors.info),
                      const SizedBox(width: 3),
                      Text(
                        "${_fmtLitros(_caldoTotalLitros)} L",
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AgroColors.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: AgroButton(
                          label: "Cancelar",
                          tipo: AgroButtonTipo.secundario,
                          expandido: true,
                          onTap:
                              _guardando ? null : () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: AgroButton(
                          label: _esEdicion ? "Actualizar" : "Guardar orden",
                          icono: Icons.save_rounded,
                          expandido: true,
                          cargando: _guardando,
                          onTap: _guardando ? null : _guardarOrdenCompleta,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers visuales
  // ---------------------------------------------------------------------------

  /// Tarjeta de sección numerada.
  Widget _seccion({
    required int numero,
    required String titulo,
    String? subtitulo,
    required IconData icono,
    Widget? trailing,
    required Widget child,
  }) {
    return AgroCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: AgroSectionHeader(
              titulo: "$numero. $titulo",
              subtitulo: subtitulo,
              icono: icono,
              trailing: trailing,
            ),
          ),
          const Divider(height: 1, color: AgroTheme.colorBorder),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  /// Coloca los campos lado a lado cuando hay espacio y apilados en pantallas
  /// angostas.
  Widget _filaResponsive({
    required List<Widget> hijos,
    double anchoMinimo = 240,
    double espacio = 12,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        if (hijos.isEmpty) return const SizedBox.shrink();
        final int cols =
            (c.maxWidth / anchoMinimo).floor().clamp(1, hijos.length).toInt();
        if (cols <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < hijos.length; i++) ...[
                if (i > 0) SizedBox(height: espacio),
                hijos[i],
              ],
            ],
          );
        }
        final double ancho =
            ((c.maxWidth - (cols - 1) * espacio) / cols).floorToDouble();
        return Wrap(
          spacing: espacio,
          runSpacing: espacio,
          children:
              hijos.map((h) => SizedBox(width: ancho, child: h)).toList(),
        );
      },
    );
  }

  /// Botón cuadrado de 48 px para acciones de alta junto a un selector.
  Widget _botonCuadrado({
    required IconData icono,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AgroColors.primario,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icono, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Cuadro del inventario agrupado (un cuadro puede tener varias variedades).
class _CuadroInv {
  final String chacra;
  final String cuadro;
  double ha = 0.0;
  final Set<String> variedades = {};
  final Set<String> cultivos = {};

  /// Filas del inventario (cultivo, variedad, ha) de este cuadro.
  final List<({String cultivo, String variedad, double ha})> filas = [];

  _CuadroInv(this.chacra, this.cuadro);

  String get clave => claveCuadro(chacra, cuadro);

  /// Superficie de las filas que entran en el filtro de cultivo/variedad.
  double haFiltrada(Set<String> cultivos, Set<String> variedades) => filas
      .where((f) => coincideFiltroOrden(f.cultivo, f.variedad, cultivos, variedades))
      .fold(0.0, (s, f) => s + f.ha);

  bool tieneFilasCon(Set<String> cultivos, Set<String> variedades) => filas
      .any((f) => coincideFiltroOrden(f.cultivo, f.variedad, cultivos, variedades));

  /// Variedades que entran en el filtro.
  List<String> variedadesCon(Set<String> cultivos, Set<String> variedades) =>
      filas
          .where((f) =>
              coincideFiltroOrden(f.cultivo, f.variedad, cultivos, variedades))
          .map((f) => f.variedad)
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
}
