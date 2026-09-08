import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

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

  // 2. Cuadros e Inventario
  List<Map<String, dynamic>> _todosCuadrosInventario = [];
  Set<String> _cultivosEnChacra = {};
  final Set<String> _cultivosFiltroActivos = {};
  final Set<String> _cuadrosSeleccionados = {};
  double _superficieTotalSeleccionada = 0.0;

  // 3. Catálogo de Insumos y Receta Foliar
  List<Map<String, dynamic>> _catalogoInsumos = [];
  String? _idProductoSeleccionado;

  // Modalidad de Dosis
  String _modalidadDosis = "DOSIS_100"; // 'DOSIS_100' | 'DOSIS_HA'
  final TextEditingController _dosisEntradaController = TextEditingController();
  final TextEditingController _dosisMaquinaController = TextEditingController();
  double _dosisMaquinaCalculada = 0.0;
  final double _capacidadMaquinaLitros = 2000.0;

  final List<Map<String, dynamic>> _itemsRecetaTemporal = [];

  // Parámetros Técnicos de Aplicación (parametros_aplic)
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
    _dosisEntradaController.dispose();
    _dosisMaquinaController.dispose();
    _paramVientoCtrl.dispose();
    _paramTempCtrl.dispose();
    _paramGotaCtrl.dispose();
    _paramVelocidadCtrl.dispose();
    _paramCaudalCtrl.dispose();
    super.dispose();
  }

  Future<void> _inicializarFormulario() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();
    _responsable = prefs.getString('userName') ?? "Ingeniero Agrónomo";

    // 1. Configuración de Identificador Correlativo amarrado al cod_receta cabecera
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
      _paramCaudalCtrl.text = "${_volumenHaController.text} L/Ha";
    } else {
      // ACA ES LO NUEVO: El cod_orden toma el ID autoincremental de cod_receta
      final int siguienteRecetaId = await DatabaseHelper.instance
          .obtenerSiguienteId('recetas_aplicaciones', 'cod_receta');
      _numeroOrden = siguienteRecetaId;
      _codigoOrdenFormateado = _numeroOrden.toString();
    }

    // 2. Cargar parámetros técnicos existentes si es edición
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

    // 3. Tipos de Aplicación
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

    // 4. Traer Chacras
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

    // 5. Catálogo de Insumos
    await _recargarCatalogoInsumos();

    // 6. Pre-cargar productos de la receta en edición
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
            'dosis_entrada': it['dosis_100']?.toString() ?? '0',
            'modalidad_dosis': it['modalidad_dosis'] ?? 'DOSIS_100',
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

  Future<void> _recargarCatalogoInsumos() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('''
      SELECT * FROM catalogo_insumos 
      WHERE rubro IN (
        SELECT nombre FROM rubros_insumos WHERE macro_rubro = 'PRODUCTOS'
      )
      AND (Mostrar = 1 OR Mostrar IS NULL)
      ORDER BY Descripcion1 ASC
    ''');
    setState(() {
      _catalogoInsumos = res;
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

  void _calcularDosisMaquina(String valorEntrada) {
    final double valor = double.tryParse(valorEntrada.replaceAll(',', '.').trim()) ?? 0.0;
    final double volCaldoHa =
        double.tryParse(_volumenHaController.text.replaceAll(',', '.')) ?? 1000.0;

    setState(() {
      if (_modalidadDosis == "DOSIS_100") {
        final double factor = _capacidadMaquinaLitros / 100.0;
        _dosisMaquinaCalculada = valor * factor;
      } else {
        if (volCaldoHa > 0) {
          final double hectareasPorMaquina = _capacidadMaquinaLitros / volCaldoHa;
          _dosisMaquinaCalculada = valor * hectareasPorMaquina;
        } else {
          _dosisMaquinaCalculada = 0.0;
        }
      }
      _dosisMaquinaController.text = _dosisMaquinaCalculada.toStringAsFixed(2);
    });
  }

  // ESTO LO MODIFIQUE: Modal rápido de alta de producto al catálogo
  void _mostrarModalNuevoInsumoCatalogo() {
    final fKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    final activoCtrl = TextEditingController();
    final concentracionCtrl = TextEditingController();
    final tcCtrl = TextEditingController(text: "7");
    final tiCtrl = TextEditingController(text: "24");
    String rubroSel = "AGROQUIMICOS";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
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
            key: fKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Nuevo Insumo al Catálogo",
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AgroTheme.colorText),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(color: AgroTheme.colorBorder),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: nombreCtrl,
                          decoration: _inputDecoration(
                              "Nombre Comercial del Producto (Ej: Coragen)"),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? "Obligatorio" : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: rubroSel,
                          decoration: _inputDecoration("Rubro / Clasificación"),
                          items: const [
                            DropdownMenuItem(
                                value: "AGROQUIMICOS",
                                child: Text("Agroquímico (Insecticida / Fungicida)")),
                            DropdownMenuItem(
                                value: "FERTILIZANTES",
                                child: Text("Fertilizante Foliar")),
                            DropdownMenuItem(
                                value: "HERBICIDAS", child: Text("Herbicida")),
                            DropdownMenuItem(
                                value: "COADYUVANTES",
                                child: Text("Coadyuvante / Aceite")),
                          ],
                          onChanged: (v) => rubroSel = v ?? "AGROQUIMICOS",
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: activoCtrl,
                          decoration: _inputDecoration(
                              "Principio Activo (Ej: Clorantraniliprole)"),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: concentracionCtrl,
                          decoration: _inputDecoration(
                              "Concentración (Ej: 20% SC)"),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: tcCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _inputDecoration(
                                    "Tiempo Carencia (Días)"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: tiCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _inputDecoration(
                                    "Tiempo Reingreso (Horas)"),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: SoftButton(
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
                        'stock_real': 0,
                      };

                      await db.insert('catalogo_insumos', rowNuevo);
                      try {
                        await Supabase.instance.client
                            .from('catalogo_insumos')
                            .insert(rowNuevo);
                      } catch (_) {}

                      await _recargarCatalogoInsumos();

                      if (mounted) {
                        setState(() {
                          _idProductoSeleccionado = sigId.toString();
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              backgroundColor: AgroTheme.colorAccent,
                              content: Text('Insumo agregado al catálogo')),
                        );
                      }
                    },
                    child: const Center(
                      child: Text("Guardar Insumo",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
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

  void _agregarProductoATabla() {
    if (_idProductoSeleccionado == null ||
        _idProductoSeleccionado!.trim().isEmpty) {
      _mostrarAlerta('Por favor, selecciona un insumo del catálogo.');
      return;
    }

    Map<String, dynamic> prodMap = {};
    for (var p in _catalogoInsumos) {
      final String idActual = (p['cod_producto'] ??
              p['ID_Insumos'] ??
              p['id'] ??
              p['Descripcion1'] ??
              '')
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

    final cleanEntrada =
        _dosisEntradaController.text.trim().replaceAll(',', '.');
    final double dosisEntradaNum = double.tryParse(cleanEntrada) ?? 0.0;

    if (dosisEntradaNum <= 0) {
      _mostrarAlerta('Ingresa una dosis válida mayor a 0.');
      return;
    }

    final double volCaldoHa =
        double.tryParse(_volumenHaController.text.replaceAll(',', '.')) ?? 1000.0;
    double dosis100Final = 0.0;

    if (_modalidadDosis == "DOSIS_100") {
      dosis100Final = dosisEntradaNum;
    } else {
      dosis100Final =
          volCaldoHa > 0 ? (dosisEntradaNum / (volCaldoHa / 100.0)) : dosisEntradaNum;
    }

    final double dosisMaqNum = double.tryParse(
            _dosisMaquinaController.text.trim().replaceAll(',', '.')) ??
        _dosisMaquinaCalculada;

    setState(() {
      _itemsRecetaTemporal.add({
        'cod_producto': prodMap['cod_producto'] ??
            prodMap['ID_Insumos'] ??
            prodMap['id'] ??
            0,
        'producto':
            prodMap['Descripcion1'] ?? prodMap['descripcion'] ?? 'Insumo',
        'rubro': prodMap['rubro'] ?? 'General',
        'dosis_100': dosis100Final.toStringAsFixed(2),
        'dosis_entrada': cleanEntrada,
        'modalidad_dosis': _modalidadDosis,
        'dosis_maq': dosisMaqNum,
        'tc': prodMap['T_C'] ?? prodMap['tc'] ?? 0,
        'ti': prodMap['TRI'] ?? prodMap['ti'] ?? 0,
        'orden_aplic': _itemsRecetaTemporal.length + 1,
      });

      _idProductoSeleccionado = null;
      _dosisEntradaController.clear();
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

      // ACA ES LO NUEVO: Se define siguienteRecetaId como cod_orden cabecera
      final int siguienteRecetaId = _esEdicion
          ? _numeroOrden
          : await DatabaseHelper.instance
              .obtenerSiguienteId('recetas_aplicaciones', 'cod_receta');

      _numeroOrden = siguienteRecetaId;

      if (_esEdicion) {
        await db.delete(
          'recetas_aplicaciones',
          where: 'cod_orden = ? AND cod_productor = ?',
          whereArgs: [_numeroOrden, widget.codProductor],
        );
        await db.delete(
          'parametros_aplic',
          where: 'cod_orden = ?',
          whereArgs: [_numeroOrden],
        );
      }

      Batch batch = db.batch();

      // Guardar detalle de la receta
      for (int i = 0; i < _itemsRecetaTemporal.length; i++) {
        final item = _itemsRecetaTemporal[i];
        final int idActual = siguienteRecetaId + i;

        final rowReceta = {
          'cod_receta': idActual,
          'cod_orden': siguienteRecetaId,
          'cod_productor': widget.codProductor,
          'productor': widget.nombreProductor,
          'orden_aplic': i + 1,
          'ref': siguienteRecetaId,
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
          'tc': item['tc'].toString(),
          'ti': item['ti'].toString(),
          'habilitado': _esEdicion
              ? (widget.ordenParaEditar!['estado'] ?? 'ACTIVO')
              : 'ACTIVO',
          'sincronizado': 0,
        };

        batch.insert('recetas_aplicaciones', rowReceta);

        Supabase.instance.client
            .from('recetas_aplicaciones')
            .upsert(rowReceta)
            .catchError((_) {});
      }

      // ACA ES LO NUEVO: Guardar parámetros técnicos amarrados a cod_orden y cod_receta
      final rowParametros = {
        'cod_orden': siguienteRecetaId,
        'cod_receta': siguienteRecetaId,
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

      Supabase.instance.client.from('parametros_aplic').insert({
        'vel_viento': rowParametros['vel_viento'],
        'Temperatura': rowParametros['Temperatura'],
        'Tamano_gota': rowParametros['Tamano_gota'],
        'Vel_Aplicacion': rowParametros['Vel_Aplicacion'],
        'Caudal_Ha': rowParametros['Caudal_Ha'],
      }).catchError((_) {});

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
                  fontWeight: FontWeight.w800,
                  fontSize: 16.5,
                  color: AgroTheme.colorText),
            ),
            Text(
              widget.nombreProductor,
              style: const TextStyle(
                  fontSize: 11.5,
                  color: AgroTheme.colorTextSecondary,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: AgroTheme.colorAccent))
          : SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // SECCIÓN 1: CABECERA
                      _buildSeccionHeader(
                          "1. Datos de Cabecera", Icons.event_note_rounded),
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: AgroTheme.colorBg,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text(_fecha,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AgroTheme.colorText)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              value: _tipoAplicacionSeleccionado,
                              decoration:
                                  _inputDecoration("Tipo de Aplicación"),
                              items: _tiposAplicacion.map((tipo) {
                                return DropdownMenuItem<String>(
                                    value: tipo, child: Text(tipo));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(
                                      () => _tipoAplicacionSeleccionado = val);
                                  _cargarMotivosPorTipo(val);
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              value: _esMotivoPersonalizado
                                  ? "__OTRO__"
                                  : _motivoSeleccionado,
                              isExpanded: true,
                              decoration: _inputDecoration(
                                  "Motivo Técnico de Aplicación"),
                              items: [
                                ..._motivosDisponibles.map((mot) {
                                  return DropdownMenuItem<String>(
                                    value: mot,
                                    child: Text(mot,
                                        overflow: TextOverflow.ellipsis),
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
                                decoration: _inputDecoration(
                                    "Escribe el nuevo motivo técnico..."),
                                validator: (val) {
                                  if (_esMotivoPersonalizado &&
                                      (val == null || val.trim().isEmpty)) {
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
                                    decoration: _inputDecoration(
                                        "Momento (ej. Fruto 10mm)"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _volumenHaController,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration(
                                        "Volumen Caldo (L/Ha)"),
                                    validator: (val) =>
                                        val == null || val.isEmpty
                                            ? "Obligatorio"
                                            : null,
                                    onChanged: (v) {
                                      setState(() {
                                        _paramCaudalCtrl.text = "$v L/Ha";
                                        if (_dosisEntradaController
                                            .text.isNotEmpty) {
                                          _calcularDosisMaquina(
                                              _dosisEntradaController.text);
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // SECCIÓN 2: CUADROS Y CHACRA
                      _buildSeccionHeader(
                          "2. Ubicación y Cuadros", Icons.map_outlined),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: _boxDecorationSoft(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              value: _chacraSeleccionada,
                              decoration:
                                  _inputDecoration("Seleccionar Chacra"),
                              items: _chacrasDisponibles.map((chacra) {
                                return DropdownMenuItem<String>(
                                    value: chacra, child: Text("Chacra: $chacra"));
                              }).toList(),
                              onChanged: (nuevaChacra) {
                                if (nuevaChacra != null) {
                                  setState(
                                      () => _chacraSeleccionada = nuevaChacra);
                                  _cargarCuadrosDeInventario(nuevaChacra);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            if (_cultivosEnChacra.isNotEmpty) ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Filtrar por Cultivo:",
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color:
                                              AgroTheme.colorTextSecondary)),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (_cultivosFiltroActivos.length ==
                                            _cultivosEnChacra.length) {
                                          _cultivosFiltroActivos.clear();
                                        } else {
                                          _cultivosFiltroActivos
                                              .addAll(_cultivosEnChacra);
                                        }
                                      });
                                    },
                                    child: Text(
                                      _cultivosFiltroActivos.length ==
                                              _cultivosEnChacra.length
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
                                  final isSel =
                                      _cultivosFiltroActivos.contains(cul);
                                  return FilterChip(
                                    label: Text(cul),
                                    selected: isSel,
                                    selectedColor: AgroTheme.colorAccentDark,
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSel
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isSel
                                          ? Colors.white
                                          : AgroTheme.colorText,
                                    ),
                                    backgroundColor: AgroTheme.colorBg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                          color: isSel
                                              ? AgroTheme.colorAccentDark
                                              : AgroTheme.colorBorder),
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
                              const Divider(
                                  height: 1, color: AgroTheme.colorBorder),
                              const SizedBox(height: 12),
                            ],
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
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
                                              _cuadrosSeleccionados.contains(
                                                  c['cuadro']?.toString() ??
                                                      ''))
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
                                  borderRadius:
                                      BorderRadius.circular(AgroTheme.radiusMd),
                                ),
                                child: const Center(
                                  child: Text(
                                    "No hay cuadros con los cultivos seleccionados.",
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: AgroTheme.colorTextSecondary),
                                  ),
                                ),
                              )
                            else ...[
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: cuadrosParaMostrar.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, idx) {
                                  final item = cuadrosParaMostrar[idx];
                                  final String cuadroNom =
                                      item['cuadro']?.toString() ?? 'S/N';
                                  final double sup = double.tryParse(
                                          item['ha']?.toString() ?? '0') ??
                                      0.0;
                                  final String variedad =
                                      item['variedad']?.toString() ?? 'S/D';
                                  final String cultivo =
                                      item['cultivo']?.toString() ?? '';
                                  final bool isSelected =
                                      _cuadrosSeleccionados.contains(cuadroNom);

                                  return InkWell(
                                    onTap: () => _alternarSeleccionCuadro(
                                        cuadroNom, sup),
                                    borderRadius: BorderRadius.circular(
                                        AgroTheme.radiusMd),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 120),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AgroTheme.colorAccentSoft
                                            : AgroTheme.colorSurface,
                                        borderRadius: BorderRadius.circular(
                                            AgroTheme.radiusMd),
                                        border: Border.all(
                                          color: isSelected
                                              ? AgroTheme.colorAccent
                                              : AgroTheme.colorBorder,
                                          width: isSelected ? 1.4 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isSelected
                                                ? Icons.check_box_rounded
                                                : Icons
                                                    .check_box_outline_blank_rounded,
                                            size: 20,
                                            color: isSelected
                                                ? AgroTheme.colorAccentDark
                                                : AgroTheme
                                                    .colorTextSecondary,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              "Cuadro $cuadroNom",
                                              style: TextStyle(
                                                fontWeight: isSelected
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
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
                                                color: isSelected
                                                    ? AgroTheme.colorAccentDark
                                                    : AgroTheme.colorText,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              cultivo.isNotEmpty
                                                  ? "$variedad ($cultivo)"
                                                  : variedad,
                                              textAlign: TextAlign.right,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: AgroTheme
                                                    .colorTextSecondary,
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorGoldSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Superficie Total a Tratar:",
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF8A6A1E))),
                                    Text(
                                      "${_superficieTotalSeleccionada.toStringAsFixed(2)} Ha",
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF8A6A1E)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // SECCIÓN 3: RECETA FOLIAR + SELECTOR TIPO APLIC + BOTÓN NUEVO INSUMO
                      _buildSeccionHeader("3. Confección de Receta Foliar",
                          Icons.science_outlined),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: _boxDecorationSoft(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Modalidad de Dosificación:",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AgroTheme.colorTextSecondary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: AgroTheme.colorBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: AgroTheme.colorBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _modalidadDosis = "DOSIS_100";
                                            if (_dosisEntradaController
                                                .text.isNotEmpty) {
                                              _calcularDosisMaquina(
                                                  _dosisEntradaController.text);
                                            }
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _modalidadDosis == "DOSIS_100"
                                                ? AgroTheme.colorAccentDark
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            "Dosis / 100 L",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: _modalidadDosis ==
                                                      "DOSIS_100"
                                                  ? Colors.white
                                                  : AgroTheme
                                                      .colorTextSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _modalidadDosis = "DOSIS_HA";
                                            if (_dosisEntradaController
                                                .text.isNotEmpty) {
                                              _calcularDosisMaquina(
                                                  _dosisEntradaController.text);
                                            }
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _modalidadDosis == "DOSIS_HA"
                                                ? AgroTheme.colorGold
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            "Dosis / Ha",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: _modalidadDosis ==
                                                      "DOSIS_HA"
                                                  ? Colors.white
                                                  : AgroTheme
                                                      .colorTextSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final Map<String, Map<String, dynamic>>
                                          insumosUnicos = {};
                                      for (var prod in _catalogoInsumos) {
                                        final String id = (prod['cod_producto'] ??
                                                prod['ID_Insumos'] ??
                                                prod['id'] ??
                                                prod['Descripcion1'] ??
                                                '')
                                            .toString()
                                            .trim();
                                        if (id.isNotEmpty &&
                                            !insumosUnicos.containsKey(id)) {
                                          insumosUnicos[id] = prod;
                                        }
                                      }

                                      final bool existeSeleccionado =
                                          _idProductoSeleccionado != null &&
                                              insumosUnicos.containsKey(
                                                  _idProductoSeleccionado);
                                      final String? valorSeguro =
                                          existeSeleccionado
                                              ? _idProductoSeleccionado
                                              : null;

                                      return DropdownButtonFormField<String>(
                                        value: valorSeguro,
                                        isExpanded: true,
                                        decoration: _inputDecoration(
                                            "Buscar Insumo / Principio Activo"),
                                        hint: Text(
                                          insumosUnicos.isEmpty
                                              ? "Cargando catálogo..."
                                              : "Selecciona un insumo...",
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AgroTheme
                                                  .colorTextSecondary),
                                        ),
                                        items:
                                            insumosUnicos.values.map((prod) {
                                          final String idProd = (prod['cod_producto'] ??
                                                  prod['ID_Insumos'] ??
                                                  prod['id'] ??
                                                  prod['Descripcion1'])
                                              .toString()
                                              .trim();
                                          final String nombre =
                                              prod['Descripcion1'] ??
                                                  prod['descripcion'] ??
                                                  'Insumo';
                                          final String rubro =
                                              prod['rubro'] ?? 'General';

                                          return DropdownMenuItem<String>(
                                            value: idProd,
                                            child: Text(
                                              "$nombre ($rubro)",
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13),
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
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  height: 48,
                                  width: 48,
                                  decoration: BoxDecoration(
                                    color: AgroTheme.colorAccentDark,
                                    borderRadius: BorderRadius.circular(
                                        AgroTheme.radiusMd),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.add_rounded,
                                        color: Colors.white, size: 24),
                                    tooltip:
                                        "Dar de alta nuevo insumo en catálogo",
                                    onPressed: _mostrarModalNuevoInsumoCatalogo,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextFormField(
                                    controller: _dosisEntradaController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _inputDecoration(
                                      _modalidadDosis == "DOSIS_100"
                                          ? "Dosis / 100 L (cc o g)"
                                          : "Dosis / Ha (Lts o Kg)",
                                    ),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5),
                                    onChanged: _calcularDosisMaquina,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 5,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AgroTheme.colorBg,
                                      borderRadius: BorderRadius.circular(
                                          AgroTheme.radiusMd),
                                      border: Border.all(
                                          color: AgroTheme.colorBorder),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Dosis x Máquina (2000L):",
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                AgroTheme.colorTextSecondary,
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
                                        size: 18,
                                        color: AgroTheme.colorAccentDark),
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
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _itemsRecetaTemporal.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, idx) {
                                  final item = _itemsRecetaTemporal[idx];
                                  final bool esHa =
                                      item['modalidad_dosis'] == "DOSIS_HA";

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AgroTheme.colorBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: AgroTheme.colorBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AgroTheme.colorSurface,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                                color: AgroTheme.colorBorder),
                                          ),
                                          child: Text(
                                            "#${item['orden_aplic']}",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                                esHa
                                                    ? "Dosis Ha: ${item['dosis_entrada']} L/Kg  ·  Máq (2000L): ${item['dosis_maq']} L/Kg"
                                                    : "Dosis 100L: ${item['dosis_100']}  ·  Máq (2000L): ${item['dosis_maq']} L/Kg",
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: AgroTheme
                                                      .colorTextSecondary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: AgroTheme.colorDanger),
                                          onPressed: () =>
                                              _eliminarProductoDeReceta(idx),
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
                      const SizedBox(height: 24),

                      // SECCIÓN 4: PARÁMETROS TÉCNICOS DE PULVERIZACIÓN (parametros_aplic)
                      _buildSeccionHeader(
                          "4. Parámetros Técnicos de Pulverización",
                          Icons.speed_rounded),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: _boxDecorationSoft(),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _paramVientoCtrl,
                                    decoration: _inputDecoration(
                                        "Vel. Viento (ej: 5-8 km/h)"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _paramTempCtrl,
                                    decoration: _inputDecoration(
                                        "Temperatura (ej: 19 °C)"),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _paramGotaCtrl,
                                    decoration: _inputDecoration(
                                        "Tamaño Gota (ej: 250 µm)"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _paramVelocidadCtrl,
                                    decoration: _inputDecoration(
                                        "Vel. Avance (ej: 5.5 km/h)"),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _paramCaudalCtrl,
                              decoration: _inputDecoration(
                                  "Caudal por Hectárea (ej: 1000 L/Ha)"),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // BOTÓN FINAL GUARDAR
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
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AgroTheme.colorText)),
      ],
    );
  }

  BoxDecoration _boxDecorationSoft() {
    return BoxDecoration(
      color: AgroTheme.colorSurface,
      borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
      border: Border.all(color: AgroTheme.colorBorder),
      boxShadow: const [
        BoxShadow(
            color: Color(0x04141E18), blurRadius: 10, offset: Offset(0, 3)),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(fontSize: 13, color: AgroTheme.colorTextSecondary),
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