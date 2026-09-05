import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../widgets/soft_button.dart';

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

  // 💡 Agrupamos por Tirada: FECHA | CUADROS | SUP TOTAL | TRACTORISTA | MAQUINA | LITROS
  Future<void> _cargarRegistrosAplicaciones() async {
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

    // Agrupamos filas en conjuntos de labor para condensar la tabla
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

      // Consolidar cuadros únicos y superficie total
      final Set<String> cuadrosSet = {};
      final Set<String> clavesCuartelUnico = {};
      double supTotalTirada = 0.0;
      double litrosTotalTirada = 0.0;

      for (var reg in lista) {
        final cd = reg['cuadros']?.toString() ?? '';
        final vr = reg['variedad']?.toString() ?? '';
        if (cd.isNotEmpty) cuadrosSet.add(cd);

        // Sumar hectáreas y litros una sola vez por combinación cuadro+variedad (evitar duplicar por cada producto)
        final String cKey = "${cd}__$vr";
        if (!clavesCuartelUnico.contains(cKey)) {
          clavesCuartelUnico.add(cKey);
          supTotalTirada += double.tryParse(reg['sup_aplic']?.toString() ?? '0') ?? 0.0;
          litrosTotalTirada += double.tryParse(reg['litros']?.toString() ?? '0') ?? 0.0;
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

  // ==========================================================================
  // 💡 MODAL CON FILTRO EN CASCADA: CULTIVO ➔ VARIEDAD ➔ CUADROS
  // ==========================================================================
  void _abrirModalRegistrarAplicacion() async {
    final db = await DatabaseHelper.instance.database;
    final String chacra = widget.orden['chacra'] ?? '';
    final String cuadrosStr = widget.orden['cuadros'] ?? '';

    // Cuadros autorizados por el ingeniero en la orden
    final List<String> cuadrosAutorizados = cuadrosStr
        .split(',')
        .map((e) => e.trim().replaceAll('Cuadro', '').trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (cuadrosAutorizados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La orden no tiene cuadros asignados')),
      );
      return;
    }

    final placeholders = List.filled(cuadrosAutorizados.length, '?').join(', ');
    final List<Map<String, dynamic>> cuartelesInventarioRaw = await db.rawQuery('''
      SELECT id, cuadro, ha, variedad, cultivo 
      FROM inventario_plantacion 
      WHERE cod_productor = ? AND chacra = ? AND cuadro IN ($placeholders)
      ORDER BY CAST(cuadro AS INTEGER) ASC, variedad ASC
    ''', [widget.codProductor, chacra, ...cuadrosAutorizados]);

    final List<Map<String, dynamic>> cuartelesInventario =
        List<Map<String, dynamic>>.from(cuartelesInventarioRaw);

    if (cuartelesInventario.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron cuadros en el inventario para esta chacra.')),
        );
      }
      return;
    }

    // Extraer Cultivos y Variedades únicas disponibles en estos cuadros
    final Set<String> todosCultivos = {};
    for (var c in cuartelesInventario) {
      final cul = c['cultivo']?.toString().trim();
      if (cul != null && cul.isNotEmpty) todosCultivos.add(cul);
    }

    // Filtros activos en el modal (inicialmente todos activos)
    final Set<String> cultivosFiltro = Set<String>.from(todosCultivos);
    final Set<String> variedadesFiltro = {};

    void actualizarVariedadesFiltro() {
      variedadesFiltro.clear();
      for (var c in cuartelesInventario) {
        final cul = c['cultivo']?.toString().trim() ?? '';
        final vr = c['variedad']?.toString().trim() ?? '';
        if (cultivosFiltro.contains(cul) && vr.isNotEmpty) {
          variedadesFiltro.add(vr);
        }
      }
    }

    actualizarVariedadesFiltro();

    // Selección de cuarteles por id
    final Set<int> seleccionIds = {};
    for (var c in cuartelesInventario) {
      seleccionIds.add(c['id'] as int);
    }

    final fechaCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final tractoristaCtrl = TextEditingController(text: _userName);
    final maquinaCtrl = TextEditingController(text: "Pulverizadora 1");
    final litrosCtrl = TextEditingController(text: "2000");

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Filtrar lista visual de cuarteles según los filtros de Cultivo y Variedad
            final cuartelesVisibles = cuartelesInventario.where((c) {
              final cul = c['cultivo']?.toString().trim() ?? '';
              final vr = c['variedad']?.toString().trim() ?? '';
              final bool matchCul = cultivosFiltro.isEmpty || cultivosFiltro.contains(cul);
              final bool matchVr = variedadesFiltro.isEmpty || variedadesFiltro.contains(vr);
              return matchCul && matchVr;
            }).toList();

            // Variedades posibles para los cultivos actualmente activos
            final Set<String> variedadesDisponibles = {};
            for (var c in cuartelesInventario) {
              final cul = c['cultivo']?.toString().trim() ?? '';
              final vr = c['variedad']?.toString().trim() ?? '';
              if (cultivosFiltro.contains(cul) && vr.isNotEmpty) {
                variedadesDisponibles.add(vr);
              }
            }

            // Cálculo dinámico de hectáreas seleccionadas
            double supTotal = 0.0;
            for (var c in cuartelesInventario) {
              if (seleccionIds.contains(c['id'])) {
                supTotal += double.tryParse(c['ha']?.toString() ?? '0') ?? 0.0;
              }
            }

            final double litrosTotales = double.tryParse(litrosCtrl.text.replaceAll(',', '.')) ?? 0.0;
            final double ltrsSup = supTotal > 0 ? (litrosTotales / supTotal) : 0.0;

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: const BoxDecoration(
                color: AgroTheme.colorSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Registrar Labor de Aplicación",
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: AgroTheme.colorText),
                          ),
                          Text(
                            "Orden #${widget.orden['cod_orden']} · Chacra $chacra",
                            style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary),
                          ),
                        ],
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Datos de Maquinaria y Labor
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: fechaCtrl,
                                  decoration: InputDecoration(
                                    labelText: "Fecha",
                                    filled: true,
                                    fillColor: AgroTheme.colorBg,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none),
                                    prefixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 4,
                                child: TextFormField(
                                  controller: tractoristaCtrl,
                                  decoration: InputDecoration(
                                    labelText: "Tractorista",
                                    filled: true,
                                    fillColor: AgroTheme.colorBg,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: TextFormField(
                                  controller: maquinaCtrl,
                                  decoration: InputDecoration(
                                    labelText: "Máquina / Pulverizadora",
                                    filled: true,
                                    fillColor: AgroTheme.colorBg,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: litrosCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => setModalState(() {}),
                                  decoration: InputDecoration(
                                    labelText: "Litros Caldo (L)",
                                    filled: true,
                                    fillColor: AgroTheme.colorBg,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    prefixIcon: const Icon(Icons.water_drop_outlined, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // =========================================================
                          // 💡 FILTROS EN CASCADA: CULTIVO Y VARIEDAD
                          // =========================================================
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AgroTheme.colorBg,
                              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                              border: Border.all(color: AgroTheme.colorBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Filtrar por Cultivo:",
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        setModalState(() {
                                          if (cultivosFiltro.length == todosCultivos.length) {
                                            cultivosFiltro.clear();
                                          } else {
                                            cultivosFiltro.addAll(todosCultivos);
                                          }
                                          actualizarVariedadesFiltro();
                                        });
                                      },
                                      child: Text(
                                        cultivosFiltro.length == todosCultivos.length ? "Desmarcar todos" : "Marcar todos",
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AgroTheme.colorAccentDark),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: todosCultivos.map((cul) {
                                    final bool isSel = cultivosFiltro.contains(cul);
                                    return FilterChip(
                                      label: Text(cul),
                                      selected: isSel,
                                      selectedColor: AgroTheme.colorAccentDark,
                                      checkmarkColor: Colors.white,
                                      labelStyle: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                                        color: isSel ? Colors.white : AgroTheme.colorText,
                                      ),
                                      backgroundColor: AgroTheme.colorSurface,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: isSel ? AgroTheme.colorAccentDark : AgroTheme.colorBorder),
                                      ),
                                      onSelected: (val) {
                                        setModalState(() {
                                          if (val) {
                                            cultivosFiltro.add(cul);
                                          } else {
                                            cultivosFiltro.remove(cul);
                                          }
                                          actualizarVariedadesFiltro();
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),

                                if (variedadesDisponibles.length > 1) ...[
                                  const SizedBox(height: 10),
                                  const Divider(height: 1, color: AgroTheme.colorBorder),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "Filtrar por Variedad:",
                                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          setModalState(() {
                                            if (variedadesFiltro.length == variedadesDisponibles.length) {
                                              variedadesFiltro.clear();
                                            } else {
                                              variedadesFiltro.addAll(variedadesDisponibles);
                                            }
                                          });
                                        },
                                        child: Text(
                                          variedadesFiltro.length == variedadesDisponibles.length ? "Desmarcar todas" : "Marcar todas",
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AgroTheme.colorAccentDark),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: variedadesDisponibles.map((vr) {
                                      final bool isSel = variedadesFiltro.contains(vr);
                                      return FilterChip(
                                        label: Text(vr),
                                        selected: isSel,
                                        selectedColor: AgroTheme.colorGoldSoft,
                                        checkmarkColor: const Color(0xFF8A6A1E),
                                        labelStyle: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                                          color: isSel ? const Color(0xFF8A6A1E) : AgroTheme.colorText,
                                        ),
                                        backgroundColor: AgroTheme.colorSurface,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(color: isSel ? const Color(0xFF8A6A1E) : AgroTheme.colorBorder),
                                        ),
                                        onSelected: (val) {
                                          setModalState(() {
                                            if (val) {
                                              variedadesFiltro.add(vr);
                                            } else {
                                              variedadesFiltro.remove(vr);
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // =========================================================
                          // LISTA MULTISELECT DE CUADROS FILTRADOS
                          // =========================================================
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Cuadros Filtrados (${cuartelesVisibles.length}):",
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AgroTheme.colorText),
                              ),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        final visiblesIds = cuartelesVisibles.map((c) => c['id'] as int).toSet();
                                        final bool todosVisiblesMarcados = visiblesIds.every((id) => seleccionIds.contains(id));
                                        if (todosVisiblesMarcados) {
                                          seleccionIds.removeAll(visiblesIds);
                                        } else {
                                          seleccionIds.addAll(visiblesIds);
                                        }
                                      });
                                    },
                                    child: const Text(
                                      "Marcar Visibles",
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AgroTheme.colorAccentDark),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    "${supTotal.toStringAsFixed(2)} Ha",
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AgroTheme.colorAccentDark),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          if (cuartelesVisibles.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AgroTheme.colorBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Text(
                                  "No hay cuadros que coincidan con los filtros seleccionados.",
                                  style: TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: cuartelesVisibles.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, i) {
                                final c = cuartelesVisibles[i];
                                final int id = c['id'] as int;
                                final double ha = double.tryParse(c['ha']?.toString() ?? '0') ?? 0.0;
                                final bool isSelected = seleccionIds.contains(id);

                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      if (isSelected) {
                                        seleccionIds.remove(id);
                                      } else {
                                        seleccionIds.add(id);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AgroTheme.colorAccentSoft : AgroTheme.colorBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected ? AgroTheme.colorAccentDark : AgroTheme.colorBorder,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_outlined,
                                          size: 20,
                                          color: isSelected ? AgroTheme.colorAccentDark : Colors.grey,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Cuadro ${c['cuadro']} · ${c['variedad']}",
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                              ),
                                              Text(
                                                "${c['cultivo'] ?? 'Frutal'}",
                                                style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          "${ha.toStringAsFixed(2)} Ha",
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AgroTheme.colorText),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 14),

                          // Indicador de Caldo L/Ha
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AgroTheme.colorGoldSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Volumen Proporcional (LtrsSup):",
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A6A1E))),
                                Text("${ltrsSup.toStringAsFixed(1)} L/Ha",
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF8A6A1E))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Botón Guardar Registros Multiplicados
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: SoftButton(
                      onTap: () async {
                        if (seleccionIds.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Seleccioná al menos un cuadro para registrar la aplicación')),
                          );
                          return;
                        }

                        final List<Map<String, dynamic>> itemsReceta =
                            (widget.orden['items'] as List).cast<Map<String, dynamic>>();

                        final cuartelesSeleccionados =
                            cuartelesInventario.where((c) => seleccionIds.contains(c['id'])).toList();

                        int siguienteRegId =
                            await DatabaseHelper.instance.obtenerSiguienteId('aplicaciones_registros', 'registro');
                        Batch batch = db.batch();
                        int contador = 0;

                        // Iteración: Cuartel x Producto
                        for (var cuartel in cuartelesSeleccionados) {
                          final double supCuartel = double.tryParse(cuartel['ha']?.toString() ?? '0') ?? 0.0;
                          final double litrosCuartel = ltrsSup * supCuartel;

                          for (var prod in itemsReceta) {
                            final double dosisMaq = double.tryParse(prod['dosis_maq']?.toString() ?? '0') ?? 0.0;
                            final double consumoProd = (litrosCuartel / 2000.0) * dosisMaq;

                            batch.insert('aplicaciones_registros', {
                              'registro': '${siguienteRegId + contador}',
                              'cod_receta': prod['cod_receta'],
                              'cod_orden': widget.orden['cod_orden'],
                              'cod_productor': widget.codProductor,
                              'productor': widget.nombreProductor,
                              'orden_aplic': prod['orden_aplic'] ?? 1,
                              'ref': widget.orden['cod_orden'],
                              'fecha': fechaCtrl.text.trim(),
                              'chacra': chacra,
                              'cuadros': cuartel['cuadro']?.toString() ?? '',
                              'variedad': cuartel['variedad']?.toString() ?? '',
                              'sup_aplic': supCuartel,
                              'motivo_aplic': widget.orden['motivo'],
                              'momento_aplic': widget.orden['momento'],
                              'vol_aplic_ha': ltrsSup,
                              'tractorista': tractoristaCtrl.text.trim(),
                              'pulverizadora': maquinaCtrl.text.trim(),
                              'litros': litrosCuartel,
                              'cod_producto': prod['cod_producto'],
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
                            contador++;
                          }
                        }

                        await batch.commit(noResult: true);
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _cargarRegistrosAplicaciones();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AgroTheme.colorAccent,
                              content: Text('¡Se guardaron $contador registros de aplicación!'),
                            ),
                          );
                        }
                      },
                      child: const Center(
                        child: Text(
                          "Guardar Aplicaciones Desglosadas",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // 💡 MODAL DE DETALLE Y MODIFICACIÓN
  // ==========================================================================
  void _mostrarDetalleYModificarRegistro(Map<String, dynamic> tirada) {
    final bool ordenActiva = (widget.orden['estado'] ?? 'ACTIVO') == 'ACTIVO';
    final List<Map<String, dynamic>> filas = (tirada['filas'] as List).cast<Map<String, dynamic>>();

    final tractoristaCtrl = TextEditingController(text: tirada['tractorista']);
    final maquinaCtrl = TextEditingController(text: tirada['pulverizadora']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: AgroTheme.colorSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Detalle de Aplicación Agrupada",
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AgroTheme.colorText)),
                      Text(
                        "Fecha: ${tirada['fecha']} · Total Caldo: ${tirada['litros'].toStringAsFixed(0)} L · ${tirada['sup_total'].toStringAsFixed(2)} Ha",
                        style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary),
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: AgroTheme.colorBorder),
              const SizedBox(height: 10),

              if (ordenActiva) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: tractoristaCtrl,
                        decoration: const InputDecoration(labelText: "Tractorista", isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: maquinaCtrl,
                        decoration: const InputDecoration(labelText: "Máquina", isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              const Text("Sub-registros generados por variedad y producto:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AgroTheme.colorTextSecondary)),
              const SizedBox(height: 8),

              Expanded(
                child: ListView.separated(
                  itemCount: filas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final f = filas[idx];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AgroTheme.colorBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AgroTheme.colorBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Cuadro ${f['cuadros']} · ${f['variedad']}",
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AgroTheme.colorAccentDark),
                              ),
                              Text(
                                "${f['sup_aplic']} Ha",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AgroTheme.colorTextSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${f['producto']}  ·  Consumo: ${(double.tryParse(f['consumo_prod']?.toString() ?? '0') ?? 0.0).toStringAsFixed(2)} L/Kg",
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              if (ordenActiva) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: SoftButton(
                    onTap: () async {
                      final db = await DatabaseHelper.instance.database;
                      for (var f in filas) {
                        await db.update(
                          'aplicaciones_registros',
                          {
                            'tractorista': tractoristaCtrl.text.trim(),
                            'pulverizadora': maquinaCtrl.text.trim(),
                            'sincronizado': 0,
                          },
                          where: 'registro = ?',
                          whereArgs: [f['registro']],
                        );
                      }
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        _cargarRegistrosAplicaciones();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AgroTheme.colorAccent,
                            content: Text('Labor actualizada correctamente'),
                          ),
                        );
                      }
                    },
                    child: const Center(
                      child: Text("Actualizar Datos de Labor",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> itemsReceta =
        (widget.orden['items'] as List).cast<Map<String, dynamic>>();

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
            Text("Orden #${widget.orden['cod_orden']}",
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText)),
            Text(widget.nombreProductor,
                style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =========================================================
              // CARD SUPERIOR: RECETA TÉCNICA
              // =========================================================
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
                  border: Border.all(color: AgroTheme.colorBorder),
                  boxShadow: [
                    BoxShadow(color: const Color(0x06141E18), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Receta Técnica Asignada",
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AgroTheme.colorText)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AgroTheme.colorAccentSoft, borderRadius: BorderRadius.circular(10)),
                          child: Text(
                            widget.orden['chacra'] ?? '',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AgroTheme.colorAccentDark),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${widget.orden['motivo']} · ${widget.orden['momento']}",
                      style: const TextStyle(fontSize: 12.5, color: AgroTheme.colorTextSecondary),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AgroTheme.colorBorder),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: const BoxDecoration(
                              color: AgroTheme.colorBg,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                            ),
                            child: const Row(
                              children: [
                                Expanded(flex: 3, child: Text("PRODUCTO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                                Expanded(flex: 2, child: Text("DOSIS 100L", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                                Expanded(flex: 2, child: Text("DOSIS MÁQ", textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                              ],
                            ),
                          ),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: itemsReceta.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: AgroTheme.colorBorder),
                            itemBuilder: (context, idx) {
                              final it = itemsReceta[idx];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                child: Row(
                                  children: [
                                    Expanded(flex: 3, child: Text(it['producto'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                    Expanded(flex: 2, child: Text("${it['dosis_100']} L/Kg", textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary))),
                                    Expanded(flex: 2, child: Text("${it['dosis_maq']} L/Kg", textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AgroTheme.colorAccentDark))),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // =========================================================
              // 💡 TABLA CONDENSADA SOLICITADA:
              // FECHA | CUADRO | SUP | TRACTORISTA | MAQUINA | LITROS
              // =========================================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Labores Registradas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AgroTheme.colorText)),
                  Text("${_registrosAgrupados.length} tiradas (${_registrosAgrupadasCount()} reg.)",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AgroTheme.colorTextSecondary)),
                ],
              ),
              const SizedBox(height: 10),

              // Encabezado de la tabla
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AgroTheme.colorBg, borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: Text("FECHA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                    Expanded(flex: 2, child: Text("CUADRO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                    Expanded(flex: 2, child: Text("SUP", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                    Expanded(flex: 3, child: Text("TRACTORISTA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                    Expanded(flex: 2, child: Text("MAQ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                    Expanded(flex: 2, child: Text("LITROS", textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AgroTheme.colorTextSecondary))),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              _cargando
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AgroTheme.colorAccent)))
                  : _registrosAgrupados.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(24),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AgroTheme.colorSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AgroTheme.colorBorder),
                          ),
                          child: const Center(
                            child: Text(
                              "No se registraron labores de aplicación aún.",
                              style: TextStyle(color: AgroTheme.colorTextSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _registrosAgrupados.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final tirada = _registrosAgrupados[index];
                            final double sup = tirada['sup_total'] as double;
                            final double litros = tirada['litros'] as double;

                            return InkWell(
                              onTap: () => _mostrarDetalleYModificarRegistro(tirada),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AgroTheme.colorSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AgroTheme.colorBorder),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0x04141E18), blurRadius: 6, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        tirada['fecha'],
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        "Cd. ${tirada['cuadros_resumen']}",
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: AgroTheme.colorAccentDark),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        "${sup.toStringAsFixed(1)} Ha",
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        tirada['tractorista'],
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        tirada['pulverizadora'],
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: AgroTheme.colorTextSecondary),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        "${litros.toStringAsFixed(0)} L",
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AgroTheme.colorAccentDark),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButton: SoftButton(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        borderRadius: 28,
        onTap: _abrirModalRegistrarAplicacion,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add_task_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text("Registrar Aplicación", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  int _registrosAgrupadasCount() {
    int total = 0;
    for (var r in _registrosAgrupados) {
      total += (r['filas'] as List).length;
    }
    return total;
  }
}