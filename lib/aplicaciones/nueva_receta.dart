import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

class NuevaRecetaScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;
  final Map<String, dynamic>? ordenParaEditar; // 💡 Parámetro opcional para edición

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

  // 1. Datos Cabecera
  String _fecha = "";
  int _numeroOrden = 0;
  String _codigoOrdenFormateado = "";
  String? _tipoAplicacionSeleccionado;

  // Motivos dinámicos
  List<String> _motivosDisponibles = [];
  String? _motivoSeleccionado;
  bool _esMotivoPersonalizado = false;
  final TextEditingController _motivoCustomController = TextEditingController();

  final TextEditingController _momentoController = TextEditingController();
  final TextEditingController _volumenHaController =
      TextEditingController(text: "1000");
  String _responsable = "Ingeniero Agrónomo";

  // Listas maestras desde SQLite
  List<String> _tiposAplicacion = [];
  List<String> _chacrasDisponibles = [];
  String? _chacraSeleccionada;

  // 2. Cuadros e Inventario con Filtro por Cultivos
  List<Map<String, dynamic>> _todosCuadrosInventario = [];
  Set<String> _cultivosEnChacra = {};
  final Set<String> _cultivosFiltroActivos = {};
  final Set<String> _cuadrosSeleccionados = {};
  double _superficieTotalSeleccionada = 0.0;

  // 3. Catálogo de Insumos y Receta Foliar
  List<Map<String, dynamic>> _catalogoInsumos = [];
  String? _idProductoSeleccionado;
  final TextEditingController _dosis100Controller = TextEditingController();
  final TextEditingController _dosisMaquinaController = TextEditingController();
  double _dosisMaquinaCalculada = 0.0;
  final double _capacidadMaquinaLitros = 2000.0;

  final List<Map<String, dynamic>> _itemsRecetaTemporal = [];

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
    _dosis100Controller.dispose();
    _dosisMaquinaController.dispose();
    super.dispose();
  }

  Future<void> _inicializarFormulario() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();
    _responsable = prefs.getString('userName') ?? "Ingeniero Agrónomo";

    final anioActual = DateTime.now().year;

    // 1. Configurar N° de Orden
    if (_esEdicion) {
      final ordenMap = widget.ordenParaEditar!;
      _numeroOrden = ordenMap['cod_orden'] is int
          ? ordenMap['cod_orden']
          : int.tryParse(ordenMap['cod_orden']?.toString() ?? '0') ?? 0;
      _codigoOrdenFormateado = _numeroOrden.toString();
      _fecha = ordenMap['fecha']?.toString() ?? _fecha;
      _momentoController.text = ordenMap['momento']?.toString() ?? '';
      _volumenHaController.text =
          (ordenMap['vol_ha']?.toString() ?? '1000').replaceAll('.0', '');
    } else {
      final resContador = await db.rawQuery(
        'SELECT COUNT(DISTINCT cod_orden) as total FROM recetas_aplicaciones WHERE cod_productor = ?',
        [widget.codProductor],
      );
      int totalOrdenesProd = (resContador.first['total'] as int?) ?? 0;
      int nuevoCorrelativo = totalOrdenesProd + 1;
      _codigoOrdenFormateado =
          "$anioActual${nuevoCorrelativo.toString().padLeft(4, '0')}";
      _numeroOrden = int.tryParse(_codigoOrdenFormateado) ??
          (anioActual * 10000 + nuevoCorrelativo);
    }

    // 2. Tipos de Aplicación
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

    // Si es edición, pre-cargar el motivo
    if (_esEdicion) {
      final motivoExistente = widget.ordenParaEditar!['motivo']?.toString() ?? '';
      if (_motivosDisponibles.contains(motivoExistente)) {
        _motivoSeleccionado = motivoExistente;
        _esMotivoPersonalizado = false;
      } else if (motivoExistente.isNotEmpty) {
        _motivoSeleccionado = "__OTRO__";
        _esMotivoPersonalizado = true;
        _motivoCustomController.text = motivoExistente;
      }
    }

    // 3. Traer Chacras
    final resChacras = await db.rawQuery('''
      SELECT DISTINCT chacra 
      FROM inventario_plantacion 
      WHERE cod_productor = ? AND chacra IS NOT NULL AND TRIM(chacra) != '' 
      ORDER BY chacra ASC
    ''', [widget.codProductor]);
    _chacrasDisponibles = resChacras.map((e) => e['chacra'].toString()).toList();

    if (_chacrasDisponibles.isEmpty) {
      final resChacrasCuadros = await db.rawQuery('''
        SELECT DISTINCT chacra 
        FROM cuadros 
        WHERE cod_productor = ? AND chacra IS NOT NULL AND TRIM(chacra) != '' 
        ORDER BY chacra ASC
      ''', [widget.codProductor]);
      _chacrasDisponibles =
          resChacrasCuadros.map((e) => e['chacra'].toString()).toList();
    }

    // Pre-cargar chacra y cuadros
    if (_esEdicion) {
      final chacraOrden = widget.ordenParaEditar!['chacra']?.toString() ?? '';
      if (_chacrasDisponibles.contains(chacraOrden)) {
        _chacraSeleccionada = chacraOrden;
      } else if (_chacrasDisponibles.isNotEmpty) {
        _chacraSeleccionada = _chacrasDisponibles.first;
      }
    } else if (_chacrasDisponibles.isNotEmpty) {
      _chacraSeleccionada = _chacrasDisponibles.first;
    }

    if (_chacraSeleccionada != null) {
      await _cargarCuadrosDeInventario(_chacraSeleccionada!);
    }

    // 💡 Pre-seleccionar los cuadros en edición
    if (_esEdicion) {
      final String cuadrosStr = widget.ordenParaEditar!['cuadros']?.toString() ?? '';
      final cuadrosGuardados = cuadrosStr
          .split(',')
          .map((e) => e.trim().replaceAll('Cuadro', '').trim())
          .where((e) => e.isNotEmpty)
          .toSet();

      _cuadrosSeleccionados.clear();
      double supAcum = 0.0;
      for (var c in _todosCuadrosInventario) {
        final nom = c['cuadro']?.toString() ?? '';
        if (cuadrosGuardados.contains(nom)) {
          _cuadrosSeleccionados.add(nom);
          supAcum += double.tryParse(c['ha']?.toString() ?? '0') ?? 0.0;
        }
      }
      _superficieTotalSeleccionada = supAcum;
    }

    // 4. Catálogo de productos
    _catalogoInsumos = await db.rawQuery('''
      SELECT * FROM catalogo_insumos 
      WHERE rubro IN (
        SELECT nombre FROM rubros_insumos WHERE macro_rubro = 'PRODUCTOS'
      )
      AND (Mostrar = 1 OR Mostrar IS NULL)
      ORDER BY Descripcion1 ASC
    ''');

    // 💡 Pre-cargar productos de la receta en edición
    if (_esEdicion) {
      final itemsRaw = widget.ordenParaEditar!['items'];
      if (itemsRaw is List) {
        _itemsRecetaTemporal.clear();
        for (var it in itemsRaw) {
          final double dMaq = double.tryParse(it['dosis_maq']?.toString() ?? '0') ?? 0.0;
          _itemsRecetaTemporal.add({
            'cod_producto': it['cod_producto'] ?? 0,
            'producto': it['producto'] ?? 'Insumo',
            'rubro': it['rubro'] ?? 'General',
            'dosis_100': it['dosis_100']?.toString() ?? '0',
            'dosis_maq': dMaq,
            'tc': it['tc'] ?? 0,
            'ti': it['ti'] ?? 0,
            'orden_aplic': it['orden_aplic'] ?? (_itemsRecetaTemporal.length + 1),
          });
        }
      }
    }

    if (!mounted) return;
    setState(() => _cargando = false);
  }

  Future<void> _cargarMotivosPorTipo(String tipo) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('''
      SELECT DISTINCT motivo 
      FROM motivos_aplicaciones 
      WHERE tipo_aplic = ? AND motivo IS NOT NULL AND TRIM(motivo) != ''
      ORDER BY motivo ASC
    ''', [tipo]);

    final List<String> motivos = res.map((e) => e['motivo'].toString()).toList();

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

  Future<void> _cargarCuadrosDeInventario(String chacra) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query(
      'inventario_plantacion',
      columns: ['cuadro', 'ha', 'variedad', 'cultivo'],
      where: 'cod_productor = ? AND chacra = ?',
      whereArgs: [widget.codProductor, chacra],
      orderBy: 'CAST(cuadro AS INTEGER) ASC',
    );

    final Set<String> cultivos = {};
    for (var c in res) {
      final cul = c['cultivo']?.toString().trim();
      if (cul != null && cul.isNotEmpty) {
        cultivos.add(cul);
      }
    }

    setState(() {
      _todosCuadrosInventario = res;
      _cultivosEnChacra = cultivos;
      _cultivosFiltroActivos.clear();
      _cultivosFiltroActivos.addAll(cultivos);
      if (!_esEdicion) {
        _cuadrosSeleccionados.clear();
        _superficieTotalSeleccionada = 0.0;
      }
    });
  }

  List<Map<String, dynamic>> get _cuadrosFiltradosPorCultivo {
    if (_cultivosFiltroActivos.isEmpty) return _todosCuadrosInventario;
    return _todosCuadrosInventario.where((c) {
      final cul = c['cultivo']?.toString().trim() ?? '';
      return _cultivosFiltroActivos.contains(cul);
    }).toList();
  }

  void _alternarSeleccionCuadro(String nombreCuadro, double ha) {
    setState(() {
      if (_cuadrosSeleccionados.contains(nombreCuadro)) {
        _cuadrosSeleccionados.remove(nombreCuadro);
        _superficieTotalSeleccionada -= ha;
      } else {
        _cuadrosSeleccionados.add(nombreCuadro);
        _superficieTotalSeleccionada += ha;
      }
      if (_superficieTotalSeleccionada < 0) _superficieTotalSeleccionada = 0.0;
    });
  }

  void _seleccionarTodosCuadrosVisibles() {
    final visibles = _cuadrosFiltradosPorCultivo;
    final bool todosMarcados =
        visibles.every((c) => _cuadrosSeleccionados.contains(c['cuadro']?.toString() ?? ''));

    setState(() {
      if (todosMarcados) {
        for (var c in visibles) {
          final nom = c['cuadro']?.toString() ?? '';
          final sup = double.tryParse(c['ha']?.toString() ?? '0') ?? 0.0;
          if (_cuadrosSeleccionados.remove(nom)) {
            _superficieTotalSeleccionada -= sup;
          }
        }
      } else {
        for (var c in visibles) {
          final nom = c['cuadro']?.toString() ?? '';
          final sup = double.tryParse(c['ha']?.toString() ?? '0') ?? 0.0;
          if (nom.isNotEmpty && !_cuadrosSeleccionados.contains(nom)) {
            _cuadrosSeleccionados.add(nom);
            _superficieTotalSeleccionada += sup;
          }
        }
      }
      if (_superficieTotalSeleccionada < 0) _superficieTotalSeleccionada = 0.0;
    });
  }

  void _calcularDosisMaquina(String valor100) {
    final double d100 = double.tryParse(valor100.replaceAll(',', '.').trim()) ?? 0.0;
    final double factorVolumen = _capacidadMaquinaLitros / 1000.0;
    setState(() {
      _dosisMaquinaCalculada = d100 * factorVolumen;
      _dosisMaquinaController.text = _dosisMaquinaCalculada.toStringAsFixed(2);
    });
  }

  void _agregarProductoATabla() {
    if (_idProductoSeleccionado == null || _idProductoSeleccionado!.trim().isEmpty) {
      _mostrarAlerta('Por favor, selecciona un insumo del catálogo.');
      return;
    }

    Map<String, dynamic> prodMap = {};
    for (var p in _catalogoInsumos) {
      final String idActual = (p['cod_producto'] ?? p['id'] ?? p['Descripcion1'] ?? '')
          .toString()
          .trim();
      if (idActual == _idProductoSeleccionado!.trim()) {
        prodMap = p;
        break;
      }
    }

    if (prodMap.isEmpty) {
      _mostrarAlerta('El producto seleccionado no es válido.');
      return;
    }

    final clean100 = _dosis100Controller.text.trim().replaceAll(',', '.');
    final double dosis100Num = double.tryParse(clean100) ?? 0.0;

    if (dosis100Num <= 0) {
      _mostrarAlerta('Ingresa una dosis cada 100 L mayor a 0.');
      return;
    }

    final double factorVolumen = _capacidadMaquinaLitros / 1000.0;
    final double dosisMaqNum = double.tryParse(
            _dosisMaquinaController.text.trim().replaceAll(',', '.')) ??
        (dosis100Num * factorVolumen);

    setState(() {
      _itemsRecetaTemporal.add({
        'cod_producto': prodMap['cod_producto'] ?? prodMap['id'] ?? 0,
        'producto': prodMap['Descripcion1'] ?? prodMap['descripcion'] ?? 'Insumo',
        'rubro': prodMap['rubro'] ?? 'General',
        'dosis_100': clean100,
        'dosis_maq': dosisMaqNum,
        'tc': prodMap['tc'] ?? 0,
        'ti': prodMap['ti'] ?? 0,
        'orden_aplic': _itemsRecetaTemporal.length + 1,
      });

      _idProductoSeleccionado = null;
      _dosis100Controller.clear();
      _dosisMaquinaController.clear();
      _dosisMaquinaCalculada = 0.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AgroTheme.colorAccent,
        content: Text('Insumo agregado a la receta exitosamente'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  void _eliminarProductoDeReceta(int index) {
    setState(() {
      _itemsRecetaTemporal.removeAt(index);
      for (int i = 0; i < _itemsRecetaTemporal.length; i++) {
        _itemsRecetaTemporal[i]['orden_aplic'] = i + 1;
      }
    });
  }

  Future<void> _guardarOrdenCompleta() async {
    if (!_formKey.currentState!.validate()) return;

    if (_chacraSeleccionada == null || _chacraSeleccionada!.isEmpty) {
      _mostrarAlerta("Debes seleccionar una chacra");
      return;
    }

    if (_cuadrosSeleccionados.isEmpty) {
      _mostrarAlerta("Debes seleccionar al menos un cuadro de la lista");
      return;
    }

    if (_itemsRecetaTemporal.isEmpty) {
      _mostrarAlerta("Debes agregar al menos un producto a la receta");
      return;
    }

    final String motivoFinal = _esMotivoPersonalizado
        ? _motivoCustomController.text.trim()
        : (_motivoSeleccionado ?? '');

    if (motivoFinal.isEmpty) {
      _mostrarAlerta("Debes especificar el motivo técnico de aplicación");
      return;
    }

    setState(() => _guardando = true);
    final db = await DatabaseHelper.instance.database;

    try {
      final String cuadrosConcatenados = _cuadrosSeleccionados.join(', ');
      final double volHa =
          double.tryParse(_volumenHaController.text.replaceAll(',', '.')) ??
              1000.0;

      // 💡 Si es edición, eliminamos las líneas previas para guardar la versión actualizada
      if (_esEdicion) {
        await db.delete(
          'recetas_aplicaciones',
          where: 'cod_orden = ? AND cod_productor = ?',
          whereArgs: [_numeroOrden, widget.codProductor],
        );
      }

      int siguienteRecetaId = await DatabaseHelper.instance
          .obtenerSiguienteId('recetas_aplicaciones', 'cod_receta');

      Batch batch = db.batch();

      for (int i = 0; i < _itemsRecetaTemporal.length; i++) {
        final item = _itemsRecetaTemporal[i];
        final int idActual = siguienteRecetaId + i;

        batch.insert('recetas_aplicaciones', {
          'cod_receta': idActual,
          'cod_orden': _numeroOrden,
          'cod_productor': widget.codProductor,
          'productor': widget.nombreProductor,
          'orden_aplic': i + 1,
          'ref': _numeroOrden,
          'fecha': _fecha,
          'chacra': _chacraSeleccionada,
          'cuadros': cuadrosConcatenados,
          'motivo_aplic': motivoFinal,
          'momento_aplic': _momentoController.text.trim(),
          'vol_aplic_ha': volHa,
          'responsable': _responsable,
          'cod_producto': item['cod_producto'],
          'producto': item['producto'],
          'dosis_100': item['dosis_100'],
          'dosis_maq': item['dosis_maq'],
          'tc': item['tc'],
          'ti': item['ti'],
          'habilitado': _esEdicion
              ? (widget.ordenParaEditar!['estado'] ?? 'ACTIVO')
              : 'ACTIVO',
          'sincronizado': 0,
        });
      }

      await batch.commit(noResult: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AgroTheme.colorAccent,
            content: Text(_esEdicion
                ? "Orden #$_codigoOrdenFormateado actualizada exitosamente."
                : "Orden #$_codigoOrdenFormateado guardada exitosamente."),
          ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AgroTheme.colorDanger, content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cuadrosParaMostrar = _cuadrosFiltradosPorCultivo;

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AppBar(
        backgroundColor: AgroTheme.colorSurface.withOpacity(0.90),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 22, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _esEdicion
                  ? "Editar Orden #$_codigoOrdenFormateado"
                  : "Orden de Aplicación #$_codigoOrdenFormateado",
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText),
            ),
            Text(
              widget.nombreProductor,
              style: const TextStyle(
                  fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AgroTheme.colorAccent))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSeccionHeader("1. Datos de Cabecera", Icons.event_note_rounded),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: _boxDecorationSoft(),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Fecha de Emisión:",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AgroTheme.colorTextSecondary)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: AgroTheme.colorBg, borderRadius: BorderRadius.circular(8)),
                                  child: Text(_fecha,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800, color: AgroTheme.colorText)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              value: _tipoAplicacionSeleccionado,
                              decoration: _inputDecoration("Tipo de Aplicación"),
                              items: _tiposAplicacion.map((tipo) {
                                return DropdownMenuItem<String>(value: tipo, child: Text(tipo));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _tipoAplicacionSeleccionado = val);
                                  _cargarMotivosPorTipo(val);
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              value: _esMotivoPersonalizado ? "__OTRO__" : _motivoSeleccionado,
                              isExpanded: true,
                              decoration: _inputDecoration("Motivo Técnico de Aplicación"),
                              items: [
                                ..._motivosDisponibles.map((mot) {
                                  return DropdownMenuItem<String>(
                                    value: mot,
                                    child: Text(mot, overflow: TextOverflow.ellipsis),
                                  );
                                }),
                                const DropdownMenuItem<String>(
                                  value: "__OTRO__",
                                  child: Text("+ Escribir otro motivo...",
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
                            if (_esMotivoPersonalizado) ...[
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _motivoCustomController,
                                decoration: _inputDecoration("Escribe el nuevo motivo técnico..."),
                                validator: (val) {
                                  if (_esMotivoPersonalizado && (val == null || val.trim().isEmpty)) {
                                    return "Ingresá el motivo técnico";
                                  }
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _momentoController,
                                    decoration: _inputDecoration("Momento (ej. Fruto 10mm)"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _volumenHaController,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration("Volumen Caldo (L/Ha)"),
                                    validator: (val) =>
                                        val == null || val.isEmpty ? "Obligatorio" : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSeccionHeader("2. Ubicación y Cuadros", Icons.map_outlined),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: _boxDecorationSoft(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              value: _chacraSeleccionada,
                              decoration: _inputDecoration("Seleccionar Chacra"),
                              items: _chacrasDisponibles.map((chacra) {
                                return DropdownMenuItem<String>(value: chacra, child: Text("Chacra: $chacra"));
                              }).toList(),
                              onChanged: (nuevaChacra) {
                                if (nuevaChacra != null) {
                                  setState(() => _chacraSeleccionada = nuevaChacra);
                                  _cargarCuadrosDeInventario(nuevaChacra);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            if (_cultivosEnChacra.isNotEmpty) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Filtrar por Cultivo:",
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AgroTheme.colorTextSecondary)),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (_cultivosFiltroActivos.length == _cultivosEnChacra.length) {
                                          _cultivosFiltroActivos.clear();
                                        } else {
                                          _cultivosFiltroActivos.addAll(_cultivosEnChacra);
                                        }
                                      });
                                    },
                                    child: Text(
                                      _cultivosFiltroActivos.length == _cultivosEnChacra.length
                                          ? "Deseleccionar todos"
                                          : "Todos",
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AgroTheme.colorAccentDark),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: _cultivosEnChacra.map((cul) {
                                  final isSel = _cultivosFiltroActivos.contains(cul);
                                  return FilterChip(
                                    label: Text(cul),
                                    selected: isSel,
                                    selectedColor: AgroTheme.colorAccentDark,
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                      color: isSel ? Colors.white : AgroTheme.colorText,
                                    ),
                                    backgroundColor: AgroTheme.colorBg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                          color: isSel ? AgroTheme.colorAccentDark : AgroTheme.colorBorder),
                                    ),
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _cultivosFiltroActivos.add(cul);
                                        } else {
                                          _cultivosFiltroActivos.remove(cul);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 14),
                              const Divider(height: 1, color: AgroTheme.colorBorder),
                              const SizedBox(height: 12),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Cuadros (${_cuadrosSeleccionados.length}/${cuadrosParaMostrar.length} selec.)",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: AgroTheme.colorText),
                                ),
                                if (cuadrosParaMostrar.isNotEmpty)
                                  InkWell(
                                    onTap: _seleccionarTodosCuadrosVisibles,
                                    child: Text(
                                      cuadrosParaMostrar.every((c) =>
                                              _cuadrosSeleccionados.contains(c['cuadro']?.toString() ?? ''))
                                          ? "Deseleccionar visibles"
                                          : "Seleccionar visibles",
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AgroTheme.colorAccentDark),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (cuadrosParaMostrar.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorBg,
                                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                                ),
                                child: const Center(
                                  child: Text(
                                    "No hay cuadros con los cultivos seleccionados.",
                                    style: TextStyle(
                                        fontSize: 12.5, color: AgroTheme.colorTextSecondary),
                                  ),
                                ),
                              )
                            else ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    SizedBox(width: 32),
                                    Expanded(
                                      flex: 2,
                                      child: Text("CUADRO",
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AgroTheme.colorTextSecondary)),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text("SUP (HA)",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AgroTheme.colorTextSecondary)),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text("VARIEDAD / CULTIVO",
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AgroTheme.colorTextSecondary)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: cuadrosParaMostrar.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, idx) {
                                  final item = cuadrosParaMostrar[idx];
                                  final String cuadroNom = item['cuadro']?.toString() ?? 'S/N';
                                  final double sup =
                                      double.tryParse(item['ha']?.toString() ?? '0') ?? 0.0;
                                  final String variedad = item['variedad']?.toString() ?? 'S/D';
                                  final String cultivo = item['cultivo']?.toString() ?? '';
                                  final bool isSelected = _cuadrosSeleccionados.contains(cuadroNom);

                                  return InkWell(
                                    onTap: () => _alternarSeleccionCuadro(cuadroNom, sup),
                                    borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 120),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? AgroTheme.colorAccentSoft : AgroTheme.colorSurface,
                                        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                                        border: Border.all(
                                          color: isSelected ? AgroTheme.colorAccent : AgroTheme.colorBorder,
                                          width: isSelected ? 1.4 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isSelected
                                                ? Icons.check_box_rounded
                                                : Icons.check_box_outline_blank_rounded,
                                            size: 20,
                                            color: isSelected
                                                ? AgroTheme.colorAccentDark
                                                : AgroTheme.colorTextSecondary,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              "Cuadro $cuadroNom",
                                              style: TextStyle(
                                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                                fontSize: 13,
                                                color: AgroTheme.colorText,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              "${sup.toStringAsFixed(2)} Ha",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12.5,
                                                color: isSelected ? AgroTheme.colorAccentDark : AgroTheme.colorText,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              cultivo.isNotEmpty ? "$variedad ($cultivo)" : variedad,
                                              textAlign: TextAlign.right,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: AgroTheme.colorTextSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorGoldSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Superficie Total a Tratar:",
                                        style: TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A6A1E))),
                                    Text(
                                      "${_superficieTotalSeleccionada.toStringAsFixed(2)} Ha",
                                      style: const TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF8A6A1E)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSeccionHeader("3. Confección de Receta Foliar", Icons.science_outlined),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: _boxDecorationSoft(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Builder(
                              builder: (context) {
                                final Map<String, Map<String, dynamic>> insumosUnicos = {};
                                for (var prod in _catalogoInsumos) {
                                  final String id = (prod['cod_producto'] ?? prod['id'] ?? prod['Descripcion1'] ?? '')
                                      .toString()
                                      .trim();
                                  if (id.isNotEmpty && !insumosUnicos.containsKey(id)) {
                                    insumosUnicos[id] = prod;
                                  }
                                }

                                final bool existeSeleccionado = _idProductoSeleccionado != null &&
                                    insumosUnicos.containsKey(_idProductoSeleccionado);
                                final String? valorSeguro = existeSeleccionado ? _idProductoSeleccionado : null;

                                return DropdownButtonFormField<String>(
                                  value: valorSeguro,
                                  isExpanded: true,
                                  decoration: _inputDecoration("Buscar Insumo / Principio Activo"),
                                  hint: Text(
                                    insumosUnicos.isEmpty
                                        ? "Cargando catálogo de insumos..."
                                        : "Selecciona un insumo...",
                                    style: const TextStyle(fontSize: 13, color: AgroTheme.colorTextSecondary),
                                  ),
                                  items: insumosUnicos.isEmpty
                                      ? null
                                      : insumosUnicos.values.map((prod) {
                                          final String idProd = (prod['cod_producto'] ?? prod['id'] ?? prod['Descripcion1'])
                                              .toString()
                                              .trim();
                                          final String nombre = prod['Descripcion1'] ?? prod['descripcion'] ?? 'Insumo';
                                          final String rubro = prod['rubro'] ?? 'General';

                                          return DropdownMenuItem<String>(
                                            value: idProd,
                                            child: Text(
                                              "$nombre ($rubro)",
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                            ),
                                          );
                                        }).toList(),
                                  onChanged: insumosUnicos.isEmpty
                                      ? null
                                      : (val) {
                                          setState(() {
                                            _idProductoSeleccionado = val;
                                          });
                                        },
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextFormField(
                                    controller: _dosis100Controller,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(decimal: true),
                                    decoration: _inputDecoration("Dosis / 100 L (cc o g)"),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                    onChanged: _calcularDosisMaquina,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 5,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AgroTheme.colorBg,
                                      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                                      border: Border.all(color: AgroTheme.colorBorder),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Dosis x Máquina (2000L):",
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: AgroTheme.colorTextSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          "${_dosisMaquinaCalculada.toStringAsFixed(2)} L/Kg",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: AgroTheme.colorAccentDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: SoftButton(
                                isSecondary: true,
                                borderRadius: 10,
                                onTap: _agregarProductoATabla,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.add_circle_outline_rounded,
                                        size: 18, color: AgroTheme.colorAccentDark),
                                    SizedBox(width: 8),
                                    Text(
                                      "Agregar a la Receta",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: AgroTheme.colorAccentDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_itemsRecetaTemporal.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              const Divider(color: AgroTheme.colorBorder),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Caldo Foliar Compuesto:",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: AgroTheme.colorText,
                                    ),
                                  ),
                                  Text(
                                    "${_itemsRecetaTemporal.length} productos agregados",
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AgroTheme.colorTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _itemsRecetaTemporal.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, idx) {
                                  final item = _itemsRecetaTemporal[idx];
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AgroTheme.colorBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AgroTheme.colorBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AgroTheme.colorSurface,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AgroTheme.colorBorder),
                                          ),
                                          child: Text(
                                            "#${item['orden_aplic']}",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800, fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['producto'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                  color: AgroTheme.colorText,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                "Dosis 100L: ${item['dosis_100']}  ·  Máq: ${item['dosis_maq']} L/Kg",
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: AgroTheme.colorTextSecondary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded,
                                              size: 20, color: AgroTheme.colorDanger),
                                          onPressed: () => _eliminarProductoDeReceta(idx),
                                          tooltip: "Quitar de la receta",
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: SoftButton(
                          onTap: _guardando ? null : _guardarOrdenCompleta,
                          child: Center(
                            child: _guardando
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.2))
                                : Text(
                                    _esEdicion
                                        ? "Actualizar Orden Técnica"
                                        : "Generar y Guardar Orden Técnica",
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSeccionHeader(String titulo, IconData icono) {
    return Row(
      children: [
        Icon(icono, size: 18, color: AgroTheme.colorAccentDark),
        const SizedBox(width: 8),
        Text(titulo,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 15, color: AgroTheme.colorText)),
      ],
    );
  }

  BoxDecoration _boxDecorationSoft() {
    return BoxDecoration(
      color: AgroTheme.colorSurface,
      borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
      border: Border.all(color: AgroTheme.colorBorder),
      boxShadow: const [
        BoxShadow(color: Color(0x04141E18), blurRadius: 10, offset: Offset(0, 3)),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AgroTheme.colorTextSecondary),
      filled: true,
      fillColor: AgroTheme.colorBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: AgroTheme.colorBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: AgroTheme.colorBorder),
      ),
    );
  }
}