import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

class CatalogoInsumosScreen extends StatefulWidget {
  const CatalogoInsumosScreen({super.key});

  @override
  State<CatalogoInsumosScreen> createState() => _CatalogoInsumosScreenState();
}

class _CatalogoInsumosScreenState extends State<CatalogoInsumosScreen> {
  bool _cargando = true;
  List<Map<String, dynamic>> _insumos = [];
  String _filtroTexto = "";
  String _rubroSeleccionado = "TODOS";
  List<String> _rubrosDisponibles = ["TODOS"];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> listaRubros = await db.rawQuery('''
      SELECT DISTINCT nombre FROM rubros_insumos 
      WHERE macro_rubro = 'PRODUCTOS' AND nombre IS NOT NULL AND TRIM(nombre) != ''
      ORDER BY nombre ASC
    ''');

    final List<Map<String, dynamic>> listaInsumos = await db.rawQuery('''
      SELECT * FROM catalogo_insumos
      WHERE rubro IN (
        SELECT nombre FROM rubros_insumos WHERE macro_rubro = 'PRODUCTOS'
      )
      AND (Mostrar = 1 OR Mostrar IS NULL)
      GROUP BY ID_Insumos
      ORDER BY Descripcion1 ASC
    ''');

    final Set<String> rubrosSet = {"TODOS"};
    for (var r in listaRubros) {
      final nom = r['nombre']?.toString();
      if (nom != null && nom.trim().isNotEmpty) {
        rubrosSet.add(nom.trim().toUpperCase());
      }
    }
    for (var i in listaInsumos) {
      final r = i['rubro']?.toString();
      if (r != null && r.trim().isNotEmpty) {
        rubrosSet.add(r.trim().toUpperCase());
      }
    }

    if (!mounted) return;
    setState(() {
      _insumos = listaInsumos;
      _rubrosDisponibles = rubrosSet.toList()..sort();
      if (!_rubrosDisponibles.contains(_rubroSeleccionado)) {
        _rubroSeleccionado = "TODOS";
      }
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _insumosFiltrados {
    return _insumos.where((item) {
      final itemRubro = (item['rubro'] ?? '').toString().trim().toUpperCase();
      final matchesRubro =
          _rubroSeleccionado == "TODOS" || itemRubro == _rubroSeleccionado;

      if (!matchesRubro) return false;

      if (_filtroTexto.isEmpty) return true;
      final q = _filtroTexto.toLowerCase();
      final nom = (item['Descripcion1'] ?? '').toString().toLowerCase();
      final pa = (item['principio_activo'] ?? item['Descripcion2'] ?? '')
          .toString()
          .toLowerCase();
      final conc = (item['Concentracion'] ?? '').toString().toLowerCase();

      return nom.contains(q) || pa.contains(q) || conc.contains(q);
    }).toList();
  }

  // 💡 Modal flotante para Ver Detalles y Editar Producto
  void _mostrarModalDetalleYEdicion(Map<String, dynamic> itemOriginal) {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl =
        TextEditingController(text: itemOriginal['Descripcion1'] ?? '');
    final activoCtrl = TextEditingController(
        text: itemOriginal['principio_activo'] ??
            itemOriginal['Descripcion2'] ??
            '');
    final concentracionCtrl =
        TextEditingController(text: itemOriginal['Concentracion'] ?? '');
    final tcCtrl =
        TextEditingController(text: (itemOriginal['T_C'] ?? 0).toString());
    final triCtrl =
        TextEditingController(text: (itemOriginal['TRI'] ?? 0).toString());
    final stockCtrl = TextEditingController(
        text: (itemOriginal['stock_real'] ?? 0).toString());

    List<String> rubrosOpciones = _rubrosDisponibles
        .where((r) => r != "TODOS")
        .toList();
    if (rubrosOpciones.isEmpty) {
      rubrosOpciones = ["AGROQUIMICOS", "FERTILIZANTES", "HERBICIDAS", "COADYUVANTES"];
    }

    String rubroSeleccionado =
        (itemOriginal['rubro'] ?? '').toString().trim().toUpperCase();
    if (!rubrosOpciones.contains(rubroSeleccionado)) {
      rubroSeleccionado = rubrosOpciones.first;
    }

    bool guardando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.90,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 22,
                right: 22,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
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
                                itemOriginal['Descripcion1'] ?? 'Detalle del Insumo',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  color: AgroTheme.colorText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "ID Insumo: #${itemOriginal['ID_Insumos']}",
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
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: AgroTheme.colorBorder),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "INFORMACIÓN DEL PRODUCTO",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: nombreCtrl,
                              decoration: _inputDecoration(
                                "Nombre Comercial",
                                Icons.medication_liquid_rounded,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? "Obligatorio"
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: rubroSeleccionado,
                              decoration: _inputDecoration(
                                "Rubro / Clasificación",
                                Icons.category_rounded,
                              ),
                              items: rubrosOpciones.map((r) {
                                return DropdownMenuItem<String>(
                                  value: r,
                                  child: Text(r, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setModalState(() => rubroSeleccionado = v);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: activoCtrl,
                              decoration: _inputDecoration(
                                "Principio Activo",
                                Icons.biotech_rounded,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: concentracionCtrl,
                                    decoration: _inputDecoration(
                                      "Concentración",
                                      Icons.opacity_rounded,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: stockCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _inputDecoration(
                                      "Stock Actual",
                                      Icons.inventory_2_outlined,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: tcCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration(
                                      "T. Carencia (Días)",
                                      Icons.timer_outlined,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: triCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration(
                                      "T. Reingreso (Horas)",
                                      Icons.health_and_safety_outlined,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: SoftButton(
                        onTap: guardando
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => guardando = true);
                                final db = await DatabaseHelper.instance.database;

                                final rowActualizada = {
                                  'ID_Insumos': itemOriginal['ID_Insumos'],
                                  'rubro': rubroSeleccionado,
                                  'Descripcion1': nombreCtrl.text.trim(),
                                  'Descripcion2': activoCtrl.text.trim(),
                                  'principio_activo': activoCtrl.text.trim(),
                                  'Concentracion': concentracionCtrl.text.trim(),
                                  'T_C': int.tryParse(tcCtrl.text.trim()) ?? 0,
                                  'TRI': int.tryParse(triCtrl.text.trim()) ?? 0,
                                  'Mostrar': itemOriginal['Mostrar'] ?? 1,
                                  'stock_real':
                                      int.tryParse(stockCtrl.text.trim()) ?? 0,
                                };

                                await db.update(
                                  'catalogo_insumos',
                                  rowActualizada,
                                  where: 'ID_Insumos = ?',
                                  whereArgs: [itemOriginal['ID_Insumos']],
                                );

                                try {
                                  await Supabase.instance.client
                                      .from('catalogo_insumos')
                                      .upsert(rowActualizada);
                                } catch (e) {
                                  debugPrint("Aviso sync update insumo: $e");
                                }

                                if (!mounted) return;
                                Navigator.pop(ctx);
                                await _cargarCatalogo();

                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: AgroTheme.colorAccent,
                                    content: Text("Insumo actualizado con éxito"),
                                  ),
                                );
                              },
                        child: Center(
                          child: guardando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.2),
                                )
                              : const Text(
                                  "Guardar Modificaciones",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
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
      },
    );
  }

  void _mostrarModalNuevoRubro() {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    // 💡 ACA ES LO NUEVO: Selector de Macro-Rubro ('PRODUCTOS' o 'INSUMOS VARIOS')
    String macroRubroSeleccionado = "PRODUCTOS";

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Nuevo Rubro de Insumo",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                            color: AgroTheme.colorText,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: AgroTheme.colorBorder),
                    const SizedBox(height: 12),
                    const Text(
                      "Tipo de Clasificación (Macro-Rubro):",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AgroTheme.colorTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 💡 Selector Pastel Suave: PRODUCTOS vs INSUMOS VARIOS
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.science_outlined, size: 16),
                                SizedBox(width: 6),
                                Text("PRODUCTOS"),
                              ],
                            ),
                            selected: macroRubroSeleccionado == "PRODUCTOS",
                            selectedColor: const Color(0xFFE8F5E9),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: macroRubroSeleccionado == "PRODUCTOS"
                                  ? const Color(0xFF2E7D32)
                                  : AgroTheme.colorTextSecondary,
                            ),
                            backgroundColor: AgroTheme.colorBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: macroRubroSeleccionado == "PRODUCTOS"
                                    ? const Color(0xFFA5D6A7)
                                    : AgroTheme.colorBorder,
                              ),
                            ),
                            onSelected: (val) {
                              if (val) {
                                setModalState(() => macroRubroSeleccionado = "PRODUCTOS");
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 16),
                                SizedBox(width: 6),
                                Text("INSUMOS VARIOS"),
                              ],
                            ),
                            selected: macroRubroSeleccionado == "INSUMOS VARIOS",
                            selectedColor: const Color(0xFFFFF8E1),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: macroRubroSeleccionado == "INSUMOS VARIOS"
                                  ? const Color(0xFF8A6A1E)
                                  : AgroTheme.colorTextSecondary,
                            ),
                            backgroundColor: AgroTheme.colorBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: macroRubroSeleccionado == "INSUMOS VARIOS"
                                    ? const Color(0xFFFFE082)
                                    : AgroTheme.colorBorder,
                              ),
                            ),
                            onSelected: (val) {
                              if (val) {
                                setModalState(() => macroRubroSeleccionado = "INSUMOS VARIOS");
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nombreCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _inputDecoration(
                        "Nombre del Rubro (Ej: BIOESTIMULANTE o REP_HERRA_TRAB)",
                        Icons.category_rounded,
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? "Ingresá un nombre" : null,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: SoftButton(
                        onTap: () async {
                          if (!formKey.currentState!.validate()) return;
                          final db = await DatabaseHelper.instance.database;

                          // 💡 Max(codigo) + 1 para el identificador único global
                          final int sigCodigo = await DatabaseHelper.instance
                              .obtenerSiguienteId('rubros_insumos', 'codigo');

                          // 💡 Max(cod_rubro) + 1 relativo al macro_rubro seleccionado
                          final resRubro = await db.rawQuery(
                            'SELECT MAX(CAST(cod_rubro AS INTEGER)) as max_cr FROM rubros_insumos WHERE macro_rubro = ?',
                            [macroRubroSeleccionado],
                          );
                          final int maxCr = (resRubro.first['max_cr'] as int?) ?? 0;
                          final int sigCodRubro = maxCr + 1;

                          final rowRubro = {
                            'codigo': sigCodigo,
                            'cod_rubro': sigCodRubro,
                            'nombre': nombreCtrl.text.trim().toUpperCase(),
                            'macro_rubro': macroRubroSeleccionado,
                          };

                          await db.insert('rubros_insumos', rowRubro);

                          try {
                            await Supabase.instance.client
                                .from('rubros_insumos')
                                .insert(rowRubro);
                          } catch (e) {
                            debugPrint("Aviso sync rubro: $e");
                          }

                          if (!mounted) return;
                          Navigator.pop(ctx);

                          if (macroRubroSeleccionado == 'PRODUCTOS') {
                            _rubroSeleccionado = rowRubro['nombre'] as String;
                          }
                          await _cargarCatalogo();

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AgroTheme.colorAccent,
                              content: Text(
                                "Rubro creado exitosamente en $macroRubroSeleccionado",
                              ),
                            ),
                          );
                        },
                        child: const Center(
                          child: Text(
                            "Guardar Rubro",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
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
      },
    );
  }

  void _mostrarModalNuevoInsumo() {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    final activoCtrl = TextEditingController();
    final concentracionCtrl = TextEditingController();
    final tcCtrl = TextEditingController(text: "7");
    final triCtrl = TextEditingController(text: "24");
    final stockCtrl = TextEditingController(text: "0");

    List<String> rubrosOpciones = _rubrosDisponibles
        .where((r) => r != "TODOS")
        .toList();
    if (rubrosOpciones.isEmpty) {
      rubrosOpciones = ["AGROQUIMICOS", "FERTILIZANTES", "HERBICIDAS", "COADYUVANTES"];
    }

    String rubroSeleccionado = (_rubroSeleccionado != "TODOS" &&
            rubrosOpciones.contains(_rubroSeleccionado))
        ? _rubroSeleccionado
        : rubrosOpciones.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.88,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
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
                            fontSize: 16.5,
                            color: AgroTheme.colorText,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: AgroTheme.colorBorder),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: nombreCtrl,
                              decoration: _inputDecoration(
                                "Nombre Comercial (Ej: Coragen / Captan)",
                                Icons.medication_liquid_rounded,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? "Obligatorio" : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: rubroSeleccionado,
                                    decoration: _inputDecoration(
                                      "Rubro Asignado",
                                      Icons.category_rounded,
                                    ),
                                    items: rubrosOpciones.map((r) {
                                      return DropdownMenuItem<String>(
                                        value: r,
                                        child: Text(r, overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setModalState(() => rubroSeleccionado = v);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  height: 48,
                                  width: 48,
                                  decoration: BoxDecoration(
                                    color: AgroTheme.colorBg,
                                    borderRadius:
                                        BorderRadius.circular(AgroTheme.radiusMd),
                                    border: Border.all(color: AgroTheme.colorBorder),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.add_rounded,
                                        color: AgroTheme.colorAccentDark),
                                    tooltip: "Crear nuevo rubro",
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _mostrarModalNuevoRubro();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: activoCtrl,
                              decoration: _inputDecoration(
                                "Principio Activo (Ej: Clorantraniliprole)",
                                Icons.biotech_rounded,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: concentracionCtrl,
                                    decoration: _inputDecoration(
                                      "Concentración (Ej: 20% SC)",
                                      Icons.opacity_rounded,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: stockCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _inputDecoration(
                                      "Stock Inicial",
                                      Icons.inventory_2_outlined,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: tcCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration(
                                      "T. Carencia (Días)",
                                      Icons.timer_outlined,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: triCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: _inputDecoration(
                                      "T. Reingreso (Horas)",
                                      Icons.health_and_safety_outlined,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: SoftButton(
                        onTap: () async {
                          if (!formKey.currentState!.validate()) return;
                          final db = await DatabaseHelper.instance.database;

                          final int sigId = await DatabaseHelper.instance
                              .obtenerSiguienteId('catalogo_insumos', 'ID_Insumos');

                          final rowInsumo = {
                            'ID_Insumos': sigId,
                            'rubro': rubroSeleccionado,
                            'Descripcion1': nombreCtrl.text.trim(),
                            'Descripcion2': activoCtrl.text.trim(),
                            'principio_activo': activoCtrl.text.trim(),
                            'Concentracion': concentracionCtrl.text.trim(),
                            'T_C': int.tryParse(tcCtrl.text.trim()) ?? 0,
                            'TRI': int.tryParse(triCtrl.text.trim()) ?? 0,
                            'Mostrar': 1,
                            'stock_real':
                                int.tryParse(stockCtrl.text.trim()) ?? 0,
                          };

                          await db.insert('catalogo_insumos', rowInsumo);

                          try {
                            await Supabase.instance.client
                                .from('catalogo_insumos')
                                .insert(rowInsumo);
                          } catch (e) {
                            debugPrint("Aviso sync insumo: $e");
                          }

                          if (!mounted) return;
                          Navigator.pop(ctx);
                          await _cargarCatalogo();

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AgroTheme.colorAccent,
                              content: Text("Insumo agregado al catálogo"),
                            ),
                          );
                        },
                        child: const Center(
                          child: Text(
                            "Guardar Insumo",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
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
      },
    );
  }

  InputDecoration _inputDecoration(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontSize: 12.5,
        color: AgroTheme.colorTextSecondary,
      ),
      prefixIcon: Icon(
        icono,
        size: 18,
        color: AgroTheme.colorTextSecondary,
      ),
      filled: true,
      fillColor: AgroTheme.colorBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: AgroTheme.colorBorder, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: const BorderSide(color: AgroTheme.colorAccentDark, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double ancho = MediaQuery.of(context).size.width;
    final bool esCompu = ancho >= 880;

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AppBar(
        backgroundColor: AgroTheme.colorSurface.withOpacity(0.92),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Catálogo de Insumos",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: AgroTheme.colorText,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined,
                color: AgroTheme.colorTextSecondary),
            tooltip: "Nuevo Rubro",
            onPressed: _mostrarModalNuevoRubro,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: esCompu ? _buildLayoutDesktop() : _buildLayoutMobile(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AgroTheme.colorAccentDark,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: _mostrarModalNuevoInsumo,
        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
        label: const Text(
          "Nuevo Insumo",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBuscador() {
    return Container(
      decoration: BoxDecoration(
        color: AgroTheme.colorSurface,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        border: Border.all(color: AgroTheme.colorBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04141E18),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (val) => setState(() => _filtroTexto = val),
        style: const TextStyle(color: AgroTheme.colorText, fontSize: 13.5),
        decoration: const InputDecoration(
          hintText: "Buscar por nombre comercial, principio activo o concentración...",
          hintStyle: TextStyle(color: AgroTheme.colorTextSecondary, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded,
              color: AgroTheme.colorTextSecondary, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }

  Widget _buildLayoutDesktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 250,
          decoration: const BoxDecoration(
            color: AgroTheme.colorSurface,
            border: Border(
              right: BorderSide(color: AgroTheme.colorBorder, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "RUBROS",
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AgroTheme.colorTextSecondary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 18, color: AgroTheme.colorAccentDark),
                      tooltip: "Agregar Rubro",
                      onPressed: _mostrarModalNuevoRubro,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AgroTheme.colorBorder),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  itemCount: _rubrosDisponibles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, idx) {
                    final rubro = _rubrosDisponibles[idx];
                    final isSelected = _rubroSeleccionado == rubro;

                    int count = 0;
                    if (rubro == "TODOS") {
                      count = _insumos.length;
                    } else {
                      count = _insumos.where((i) =>
                          (i['rubro'] ?? '').toString().toUpperCase() == rubro).length;
                    }

                    return InkWell(
                      onTap: () => setState(() => _rubroSeleccionado = rubro),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AgroTheme.colorAccentSoft
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AgroTheme.colorAccentDark.withOpacity(0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              rubro == "TODOS"
                                  ? Icons.apps_rounded
                                  : Icons.folder_outlined,
                              size: 16,
                              color: isSelected
                                  ? AgroTheme.colorAccentDark
                                  : AgroTheme.colorTextSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                rubro,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? AgroTheme.colorAccentDark
                                      : AgroTheme.colorText,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : AgroTheme.colorBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "$count",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? AgroTheme.colorAccentDark
                                      : AgroTheme.colorTextSecondary,
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
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
                child: _buildBuscador(),
              ),
              Expanded(
                child: _cargando
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AgroTheme.colorAccent))
                    : _insumosFiltrados.isEmpty
                        ? _buildEstadoVacio()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(24, 6, 24, 80),
                            itemCount: _insumosFiltrados.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, idx) {
                              return _buildInsumoListItem(_insumosFiltrados[idx]);
                            },
                          ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutMobile() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _buildBuscador(),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _rubrosDisponibles.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              if (idx == _rubrosDisponibles.length) {
                return ActionChip(
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 16, color: AgroTheme.colorAccentDark),
                      SizedBox(width: 4),
                      Text("Rubro", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  backgroundColor: AgroTheme.colorSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: AgroTheme.colorBorder),
                  ),
                  onPressed: _mostrarModalNuevoRubro,
                );
              }

              final rubro = _rubrosDisponibles[idx];
              final isSelected = _rubroSeleccionado == rubro;

              return ChoiceChip(
                label: Text(rubro),
                selected: isSelected,
                selectedColor: AgroTheme.colorAccentDark,
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : AgroTheme.colorText,
                ),
                backgroundColor: AgroTheme.colorSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: isSelected
                        ? AgroTheme.colorAccentDark
                        : AgroTheme.colorBorder,
                  ),
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _rubroSeleccionado = rubro);
                  }
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: AgroTheme.colorAccent))
              : _insumosFiltrados.isEmpty
                  ? _buildEstadoVacio()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                      itemCount: _insumosFiltrados.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, idx) {
                        return _buildInsumoListItem(_insumosFiltrados[idx]);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEstadoVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AgroTheme.colorAccentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.science_outlined,
                size: 40, color: AgroTheme.colorAccentDark),
          ),
          const SizedBox(height: 14),
          const Text(
            "No se encontraron insumos",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
              color: AgroTheme.colorText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Podés dar de alta un producto o crear un rubro nuevo.",
            style: TextStyle(fontSize: 12.5, color: AgroTheme.colorTextSecondary),
          ),
        ],
      ),
    );
  }

  // 💡 Fila limpia de lista compacta: al tocar abre el modal flotante para ver y editar
  Widget _buildInsumoListItem(Map<String, dynamic> item) {
    final rubro = (item['rubro'] ?? 'GENERAL').toString();
    final pa = (item['principio_activo'] ?? item['Descripcion2'] ?? 'S/D').toString();
    final concentracion = (item['Concentracion'] ?? '').toString();
    final tc = item['T_C'] ?? 'S/D';
    final tri = item['TRI'] ?? 'S/D';

    return InkWell(
      onTap: () => _mostrarModalDetalleYEdicion(item),
      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
          border: Border.all(color: AgroTheme.colorBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x03141E18),
              blurRadius: 4,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AgroTheme.colorAccentSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.science_outlined,
                color: AgroTheme.colorAccentDark,
                size: 18,
              ),
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
                          item['Descripcion1'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: AgroTheme.colorText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: Text(
                          rubro,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AgroTheme.colorTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          concentracion.isNotEmpty ? "$pa ($concentracion)" : pa,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AgroTheme.colorTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "TC: ${tc}d  ·  TRI: ${tri}hs",
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AgroTheme.colorAccentDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AgroTheme.colorTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}