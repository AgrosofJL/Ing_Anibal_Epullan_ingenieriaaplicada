// ignore_for_file: deprecated_member_use

import 'package:aplicaciones_foliares/servicios/exportar_orden_pdf.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../servicios/eliminar_orden.dart';
import '../constantes/tema.dart';
import '../widgets/agro_ui.dart';
import 'aplicaciones.dart';
import 'nueva_receta.dart';
import 'orden_cuadros.dart';

class OrdenesGeneradasScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;
  final String cuit;
  final String renspa;

  const OrdenesGeneradasScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
    required this.cuit,
    required this.renspa,
  });

  @override
  State<OrdenesGeneradasScreen> createState() => _OrdenesGeneradasScreenState();
}

class _OrdenesGeneradasScreenState extends State<OrdenesGeneradasScreen> {
  bool _cargando = true;
  String _userRol = "OPERARIO";
  List<Map<String, dynamic>> _todasLasOrdenes = [];
  String _filtroTexto = "";
  String _pestanaActiva = "ACTIVAS"; // 'ACTIVAS' | 'TERMINADAS' | 'HISTORICO'
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // LÓGICA (sin cambios de comportamiento)
  // ============================================================

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _userRol = (prefs.getString('userRole') ??
            prefs.getString('userRol') ??
            prefs.getString('rol') ??
            "OPERARIO")
        .toUpperCase()
        .trim();
    await _cargarOrdenes();
  }

  bool get _esIngenieroOAdmin =>
      _userRol == 'ADMIN' || _userRol == 'INGENIERO' || _userRol == 'ADM';

  Future<void> _cargarOrdenes() async {
    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> recetas = await db.query(
      'recetas_aplicaciones',
      where: 'cod_productor = ?',
      whereArgs: [widget.codProductor],
      orderBy: 'cod_orden DESC, orden_aplic ASC',
    );

    final List<Map<String, dynamic>> inventario = await db.query(
      'inventario_plantacion',
      columns: ['chacra', 'cuadro', 'ha', 'variedad', 'cultivo'],
      where: 'cod_productor = ?',
      whereArgs: [widget.codProductor],
    );

    final List<Map<String, dynamic>> parametrosList =
        await db.query('parametros_aplic');
    final Map<int, Map<String, dynamic>> mapaParametros = {};
    for (var p in parametrosList) {
      final int cOrden = int.tryParse(p['cod_orden']?.toString() ?? '0') ?? 0;
      if (cOrden > 0) mapaParametros[cOrden] = p;
    }

    // Caldo L/Ha de la cabecera de cada orden. En recetas_aplicaciones el
    // campo vol_aplic_ha de cada producto guarda la dosis/Ha (o 0), así que
    // el caldo real se toma de ordenes_aplicaciones o de parametros_aplic.
    final Map<int, double> caldoPorOrden = {};
    try {
      final cabeceras = await db.query(
        'ordenes_aplicaciones',
        columns: ['cod_orden', 'vol_aplic_ha'],
        where: 'cod_productor = ?',
        whereArgs: [widget.codProductor.toString()],
      );
      for (final c in cabeceras) {
        final int cOrden = int.tryParse(c['cod_orden']?.toString() ?? '') ?? 0;
        final double v = double.tryParse(c['vol_aplic_ha']?.toString() ?? '') ?? 0;
        if (cOrden > 0 && v > 0) caldoPorOrden[cOrden] = v;
      }
    } catch (_) {}

    final Map<int, List<Map<String, dynamic>>> mapaOrdenes = {};
    for (var r in recetas) {
      final int codOrden = r['cod_orden'] is int
          ? r['cod_orden']
          : int.tryParse(r['cod_orden']?.toString() ?? '0') ?? 0;

      if (!mapaOrdenes.containsKey(codOrden)) {
        mapaOrdenes[codOrden] = [];
      }
      mapaOrdenes[codOrden]!.add(r);
    }

    final List<Map<String, dynamic>> listaFinal = [];

    mapaOrdenes.forEach((codOrden, items) {
      final cabecera = items.first;
      final bool hayPendienteSync =
          items.any((i) => (i['sincronizado'] ?? 1) == 0);
      final String estado = cabecera['habilitado'] ?? 'ACTIVO';
      final String chacraOrden = (cabecera['chacra'] ?? '').toString().trim();

      // Soporta órdenes de una chacra (formato viejo) y de varias chacras.
      final refsCuadros =
          parsearCuadrosOrden(cabecera['chacra'], cabecera['cuadros']);
      final bool variasChacras =
          refsCuadros.map((r) => r.chacra).toSet().length > 1;

      // Cultivos / variedades a tratar (vacío = todos).
      final Set<String> cultivosOrden = parsearFiltroOrden(cabecera['cultivos']);
      final Set<String> variedadesOrden =
          parsearFiltroOrden(cabecera['variedades']);

      final List<Map<String, dynamic>> cuadrosDetalleRenglones = [];
      double supAcumulada = 0.0;

      for (final ref in refsCuadros) {
        final matches = inventario.where((inv) =>
            (inv['chacra'] ?? '').toString().trim() == ref.chacra &&
            normalizarCuadro(inv['cuadro']) == ref.cuadro &&
            coincideFiltroOrden(inv['cultivo'], inv['variedad'],
                cultivosOrden, variedadesOrden));

        if (matches.isNotEmpty) {
          for (var m in matches) {
            final double ha =
                double.tryParse(m['ha']?.toString() ?? '0') ?? 0.0;
            supAcumulada += ha;
            cuadrosDetalleRenglones.add({
              'chacra': ref.chacra,
              'cuadro': m['cuadro'],
              'ha': ha,
              'variedad': m['variedad'] ?? 'S/D',
              'cultivo': m['cultivo'] ?? '',
              'varias_chacras': variasChacras,
            });
          }
        } else {
          cuadrosDetalleRenglones.add({
            'chacra': ref.chacra,
            'cuadro': ref.cuadro,
            'ha': 0.0,
            'variedad': 'General',
            'cultivo': '',
            'varias_chacras': variasChacras,
          });
        }
      }

      final paramObj = mapaParametros[codOrden] ?? {};

      listaFinal.add({
        'cod_orden': codOrden,
        'fecha': cabecera['fecha'] ?? 'Sin Fecha',
        'chacra': chacraOrden,
        'cuadros': cabecera['cuadros'] ?? 'S/D',
        'cuadros_detalle': cuadrosDetalleRenglones,
        'cultivos': cabecera['cultivos'] ?? '',
        'variedades': cabecera['variedades'] ?? '',
        'sup_total_calculada': supAcumulada,
        'motivo': cabecera['motivo_aplic'] ?? 'Aplicación Foliar',
        'momento': cabecera['momento_aplic'] ?? '',
        'vol_ha': _caldoHa(
            paramObj, caldoPorOrden[codOrden], cabecera['vol_aplic_ha']),
        'responsable': cabecera['responsable'] ?? 'Técnico',
        'total_productos': items.length,
        'productos_detalle':
            items.map((i) => i['producto']?.toString() ?? '').toList(),
        'sincronizado': !hayPendienteSync,
        'estado': estado,
        'items': items,
        'parametros': paramObj,
      });
    });

    if (!mounted) return;
    setState(() {
      _todasLasOrdenes = listaFinal;
      _cargando = false;
    });
  }

  /// Caldo L/Ha: parámetros → cabecera de la orden → dato de la receta.
  double _caldoHa(Map<String, dynamic> params, double? cabecera, dynamic receta) {
    final m = RegExp(r'\d+(?:[.,]\d+)?')
        .firstMatch(params['Caudal_Ha']?.toString() ?? '');
    final double? deParams =
        m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
    if (deParams != null && deParams > 0) return deParams;
    if (cabecera != null && cabecera > 0) return cabecera;
    return double.tryParse(receta?.toString() ?? '') ?? 0.0;
  }

  List<Map<String, dynamic>> get _ordenesFiltradas {
    final now = DateTime.now();
    final mesActual = now.month;
    final anioActual = now.year;

    return _todasLasOrdenes.where((o) {
      final String estado = (o['estado'] ?? 'ACTIVO').toString().toUpperCase();
      final String fechaStr = o['fecha']?.toString() ?? '';
      DateTime? fechaOrden;
      try {
        fechaOrden = DateTime.parse(fechaStr);
      } catch (_) {}

      final bool esMesActual = fechaOrden != null &&
          fechaOrden.month == mesActual &&
          fechaOrden.year == anioActual;

      if (_pestanaActiva == "ACTIVAS") {
        if (estado != "ACTIVO") return false;
      } else if (_pestanaActiva == "TERMINADAS") {
        if (estado != "TERMINADO") return false;
      } else if (_pestanaActiva == "HISTORICO") {
        if (esMesActual && estado == "ACTIVO") return false;
      }

      if (_filtroTexto.isEmpty) return true;
      final query = _filtroTexto.toLowerCase();
      final cod = o['cod_orden'].toString();
      final chacra = (o['chacra'] ?? '').toString().toLowerCase();
      final motivo = (o['motivo'] ?? '').toString().toLowerCase();
      final fecha = (o['fecha'] ?? '').toString().toLowerCase();
      return cod.contains(query) ||
          chacra.contains(query) ||
          motivo.contains(query) ||
          fecha.contains(query);
    }).toList();
  }

  void _irAAplicaciones(Map<String, dynamic> orden) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AplicacionesScreen(
          orden: orden,
          codProductor: widget.codProductor,
          nombreProductor: widget.nombreProductor,
        ),
      ),
    ).then((_) => _cargarOrdenes());
  }

  void _abrirNuevaReceta() async {
    final bool? recargar = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NuevaRecetaScreen(
          codProductor: widget.codProductor,
          nombreProductor: widget.nombreProductor,
        ),
      ),
    );

    if (recargar == true) {
      _cargarOrdenes();
    }
  }

  void _editarOrden(Map<String, dynamic> orden) async {
    final bool? recargar = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NuevaRecetaScreen(
          codProductor: widget.codProductor,
          nombreProductor: widget.nombreProductor,
          ordenParaEditar: orden,
        ),
      ),
    );

    if (recargar == true) {
      _cargarOrdenes();
    }
  }

  void _cambiarEstadoTerminar(int codOrden, String estadoActual) async {
    final String nuevoEstado =
        estadoActual == 'TERMINADO' ? 'ACTIVO' : 'TERMINADO';

    if (nuevoEstado == 'TERMINADO') {
      final ok = await confirmarAgro(
        context: context,
        titulo: 'Terminar orden #$codOrden',
        mensaje:
            'La orden pasará a "Terminadas" y no se podrán registrar nuevas aplicaciones. Podés reactivarla cuando quieras.',
        confirmar: 'Terminar',
        icono: Icons.task_alt_rounded,
      );
      if (!ok) return;
    }

    final db = await DatabaseHelper.instance.database;

    await db.update(
      'recetas_aplicaciones',
      {'habilitado': nuevoEstado, 'sincronizado': 0},
      where: 'cod_orden = ? AND cod_productor = ?',
      whereArgs: [codOrden, widget.codProductor],
    );

    try {
      await Supabase.instance.client
          .from('recetas_aplicaciones')
          .update({'habilitado': nuevoEstado})
          .eq('cod_orden', codOrden)
          .eq('cod_productor', widget.codProductor);
    } catch (_) {}

    await _cargarOrdenes();

    if (mounted) {
      mostrarAgroSnack(
        context,
        nuevoEstado == 'TERMINADO'
            ? 'Orden #$codOrden archivada en Terminadas.'
            : 'Orden #$codOrden reactivada.',
        tipo: nuevoEstado == 'TERMINADO'
            ? AgroSnackTipo.info
            : AgroSnackTipo.ok,
      );
    }
  }

  Future<void> _confirmarBorrarOrden(int codOrden) async {
    // Qué se va a borrar (para que el ingeniero lo vea antes de confirmar).
    ResumenOrdenABorrar? r;
    try {
      r = await ServicioEliminarOrden.resumen(codOrden, widget.codProductor);
    } catch (_) {}
    if (!mounted) return;

    final partes = <String>[
      if (r != null) '• ${r.recetas} ${r.recetas == 1 ? 'producto' : 'productos'} de la receta',
      if (r != null && r.labores > 0)
        '• ${r.labores} ${r.labores == 1 ? 'labor registrada' : 'labores registradas'}',
      if (r != null && r.consumos > 0)
        '• ${r.consumos} consumos de insumos (vuelven ${r.stockDevuelto.toStringAsFixed(2)} L/Kg al stock)',
      '• Parámetros técnicos y cabecera de la orden',
    ];

    final ok = await confirmarAgro(
      context: context,
      titulo: 'Eliminar orden #$codOrden',
      mensaje: 'Se eliminará definitivamente:\n${partes.join('\n')}\n\n'
          'También se borra en el servidor. Esta acción no se puede deshacer.',
      confirmar: 'Eliminar todo',
      peligroso: true,
      icono: Icons.delete_forever_rounded,
    );
    if (!ok) return;

    try {
      await ServicioEliminarOrden.eliminar(codOrden, widget.codProductor);
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'No se pudo eliminar la orden: $e',
            tipo: AgroSnackTipo.error);
      }
      return;
    }

    if (!mounted) return;
    await _cargarOrdenes();
    if (mounted) {
      mostrarAgroSnack(
        context,
        'Orden #$codOrden eliminada con sus labores y consumos.',
        tipo: AgroSnackTipo.ok,
      );
    }
  }

  void _mostrarModalOpcionesPdf(Map<String, dynamic> orden) {
    final int codOrden = orden['cod_orden'];

    mostrarAgroPanel<void>(
      context: context,
      titulo: "Orden técnica #$codOrden",
      subtitulo: "Documento PDF de pulverización",
      icono: Icons.picture_as_pdf_outlined,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgroOptionTile(
            icono: Icons.share_outlined,
            titulo: "Compartir por WhatsApp / enviar",
            descripcion: "Envía la orden al productor o al tractorista.",
            color: AgroColors.ok,
            onTap: () async {
              Navigator.pop(ctx);
              await ServicioExportarOrdenPdf.compartirOrdenPdf(
                orden: orden,
                nombreProductor: widget.nombreProductor,
                cuit: widget.cuit,
                renspa: widget.renspa,
              );
            },
          ),
          AgroOptionTile(
            icono: Icons.download_rounded,
            titulo: "Descargar / imprimir",
            descripcion: "Abre el visor para guardar o imprimir el documento.",
            color: AgroColors.info,
            onTap: () async {
              Navigator.pop(ctx);
              await ServicioExportarOrdenPdf.guardarOImprimirPdf(
                orden: orden,
                nombreProductor: widget.nombreProductor,
                cuit: widget.cuit,
                renspa: widget.renspa,
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final esMovil = AgroBreakpoints.esMovil(context);

    final int cantActivas = _todasLasOrdenes
        .where((o) =>
            (o['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'ACTIVO')
        .length;
    final int cantTerminadas = _todasLasOrdenes
        .where((o) =>
            (o['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'TERMINADO')
        .length;
    final int cantPendientesSync =
        _todasLasOrdenes.where((o) => o['sincronizado'] == false).length;

    final filtradas = _ordenesFiltradas;

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: widget.nombreProductor,
        subtitulo: "CUIT ${widget.cuit} · RENSPA ${widget.renspa}",
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: "Recargar órdenes",
            onTap: _cargando ? null : _cargarOrdenes,
          ),
          if (_esIngenieroOAdmin && !esMovil) ...[
            const SizedBox(width: 8),
            AgroButton(
              label: "Nueva orden",
              icono: Icons.add_rounded,
              compacto: true,
              onTap: _abrirNuevaReceta,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado fijo: pestañas + buscador
            Container(
              color: AgroTheme.colorBg,
              padding: const EdgeInsets.only(top: 14, bottom: 10),
              child: AgroContent(
                maxWidth: 1180,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AgroSegmentedTabs(
                      seleccionado: _pestanaActiva,
                      onChanged: (id) => setState(() => _pestanaActiva = id),
                      items: [
                        AgroTabItem(
                          id: "ACTIVAS",
                          label: "Activas",
                          icono: Icons.pending_actions_rounded,
                          count: cantActivas,
                          color: AgroColors.primario,
                        ),
                        AgroTabItem(
                          id: "TERMINADAS",
                          label: "Terminadas",
                          icono: Icons.task_alt_rounded,
                          count: cantTerminadas,
                          color: AgroColors.neutral,
                        ),
                        AgroTabItem(
                          id: "HISTORICO",
                          label: esMovil ? "Histórico" : "Histórico / meses",
                          icono: Icons.folder_open_rounded,
                          count: _todasLasOrdenes.length,
                          color: AgroColors.warn,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AgroSearchField(
                      controller: _searchController,
                      hint: "Buscar por N° de orden, chacra, motivo o fecha…",
                      onChanged: (val) => setState(() => _filtroTexto = val),
                    ),
                    if (cantPendientesSync > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AgroColors.warnSoft,
                          borderRadius:
                              BorderRadius.circular(AgroTheme.radiusMd),
                          border: Border.all(
                              color: AgroColors.warn.withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_upload_outlined,
                                size: 18, color: AgroColors.warn),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cantPendientesSync == 1
                                    ? "1 orden pendiente de sincronizar con el servidor."
                                    : "$cantPendientesSync órdenes pendientes de sincronizar con el servidor.",
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AgroColors.warn,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Expanded(
              child: _cargando
                  ? const AgroLoading(mensaje: 'Cargando órdenes…')
                  : filtradas.isEmpty
                      ? AgroEmptyState(
                          icono: _filtroTexto.isNotEmpty
                              ? Icons.search_off_rounded
                              : Icons.inventory_2_outlined,
                          titulo: _filtroTexto.isNotEmpty
                              ? "Sin resultados para \"$_filtroTexto\""
                              : (_pestanaActiva == "ACTIVAS"
                                  ? "No hay órdenes activas"
                                  : (_pestanaActiva == "TERMINADAS"
                                      ? "No hay órdenes terminadas"
                                      : "No hay registros históricos")),
                          mensaje: _esIngenieroOAdmin &&
                                  _pestanaActiva == "ACTIVAS" &&
                                  _filtroTexto.isEmpty
                              ? "Creá una nueva orden técnica para empezar a registrar aplicaciones."
                              : "Las órdenes generadas se listarán en este panel.",
                          accion: _esIngenieroOAdmin &&
                                  _pestanaActiva == "ACTIVAS" &&
                                  _filtroTexto.isEmpty
                              ? AgroButton(
                                  label: "Nueva orden técnica",
                                  icono: Icons.add_rounded,
                                  onTap: _abrirNuevaReceta,
                                )
                              : null,
                        )
                      : RefreshIndicator(
                          color: AgroColors.primario,
                          onRefresh: _cargarOrdenes,
                          child: LayoutBuilder(
                            builder: (context, c) {
                              final cols = c.maxWidth >= 980 ? 2 : 1;
                              return ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(
                                    top: 4, bottom: 100),
                                children: [
                                  AgroContent(
                                    maxWidth: 1180,
                                    child: LayoutBuilder(
                                      builder: (context, c2) {
                                        const gap = 14.0;
                                        final w = ((c2.maxWidth -
                                                    gap * (cols - 1)) /
                                                cols)
                                            .floorToDouble();
                                        return Wrap(
                                          spacing: gap,
                                          runSpacing: gap,
                                          children: filtradas.map((orden) {
                                            return SizedBox(
                                              width: w,
                                              child: _OrdenCardItem(
                                                key: ValueKey(
                                                    orden['cod_orden']),
                                                orden: orden,
                                                esIngenieroOAdmin:
                                                    _esIngenieroOAdmin,
                                                onTapCard: () =>
                                                    _irAAplicaciones(orden),
                                                onRegistrar: () =>
                                                    _irAAplicaciones(orden),
                                                onEditar: () =>
                                                    _editarOrden(orden),
                                                onExportarPdf: () =>
                                                    _mostrarModalOpcionesPdf(
                                                        orden),
                                                onTerminar: () =>
                                                    _cambiarEstadoTerminar(
                                                  orden['cod_orden'] as int,
                                                  orden['estado'] as String,
                                                ),
                                                onBorrar: () =>
                                                    _confirmarBorrarOrden(
                                                  orden['cod_orden'] as int,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _esIngenieroOAdmin && esMovil
          ? FloatingActionButton.extended(
              backgroundColor: AgroColors.primario,
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              onPressed: _abrirNuevaReceta,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text(
                "Nueva orden",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            )
          : null,
    );
  }
}

// ============================================================
// TARJETA DE ORDEN
// ============================================================

enum _AccionOrden { terminar, editar, eliminar }

class _OrdenCardItem extends StatefulWidget {
  final Map<String, dynamic> orden;
  final bool esIngenieroOAdmin;
  final VoidCallback onTapCard;
  final VoidCallback onRegistrar;
  final VoidCallback onEditar;
  final VoidCallback onExportarPdf;
  final VoidCallback onTerminar;
  final VoidCallback onBorrar;

  const _OrdenCardItem({
    super.key,
    required this.orden,
    required this.esIngenieroOAdmin,
    required this.onTapCard,
    required this.onRegistrar,
    required this.onEditar,
    required this.onExportarPdf,
    required this.onTerminar,
    required this.onBorrar,
  });

  @override
  State<_OrdenCardItem> createState() => _OrdenCardItemState();
}

class _OrdenCardItemState extends State<_OrdenCardItem> {
  bool _cuadrosExpandidos = false;

  String _fechaLegible(String fecha) {
    try {
      final d = DateTime.parse(fecha);
      return DateFormat('dd/MM/yyyy').format(d);
    } catch (_) {
      return fecha;
    }
  }

  String _num(dynamic v, {int dec = 0}) {
    final d = double.tryParse(v?.toString() ?? '');
    if (d == null) return v?.toString() ?? '-';
    return d.toStringAsFixed(d == d.roundToDouble() ? 0 : dec);
  }

  @override
  Widget build(BuildContext context) {
    final int codOrden = widget.orden['cod_orden'];
    final String fecha = widget.orden['fecha']?.toString() ?? 'Sin fecha';
    final String chacra = widget.orden['chacra']?.toString() ?? '';
    final String motivo = widget.orden['motivo']?.toString() ?? '';
    final String momento = widget.orden['momento']?.toString() ?? '';
    final dynamic volHa = widget.orden['vol_ha'];
    final int totalProductos = widget.orden['total_productos'] ?? 0;
    final List<String> productos =
        (widget.orden['productos_detalle'] as List? ?? [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
    final bool sincronizado = widget.orden['sincronizado'] ?? true;
    final String estado = widget.orden['estado'] ?? 'ACTIVO';
    final bool estaTerminada = estado == 'TERMINADO';

    final List<Map<String, dynamic>> cuadrosDetalle =
        (widget.orden['cuadros_detalle'] as List? ?? [])
            .cast<Map<String, dynamic>>();
    final double supTotal =
        (widget.orden['sup_total_calculada'] as num?)?.toDouble() ?? 0.0;

    final Map<String, dynamic> parametros =
        (widget.orden['parametros'] as Map? ?? {}).cast<String, dynamic>();

    final Color colorEstado =
        estaTerminada ? AgroColors.neutral : AgroColors.primario;

    return AgroCard(
      padding: EdgeInsets.zero,
      accentColor: colorEstado,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------- CUERPO CLICKEABLE ----------
          InkWell(
            onTap: widget.onTapCard,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "ORDEN #$codOrden",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: colorEstado,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.calendar_today_rounded,
                          size: 12, color: AgroTheme.colorTextSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _fechaLegible(fecha),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AgroText.secundario.copyWith(fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      if (!sincronizado) ...[
                        const Tooltip(
                          message: 'Pendiente de sincronizar',
                          child: AgroBadge(
                            texto: 'Sin sync',
                            color: AgroColors.warn,
                            fondo: AgroColors.warnSoft,
                            icono: Icons.cloud_upload_outlined,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      AgroBadge.estado(estado),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    motivo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AgroText.tituloCard.copyWith(fontSize: 16),
                  ),
                  if (momento.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text("Momento: $momento",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.secundario),
                  ],
                  if (parsearFiltroOrden(widget.orden['cultivos']).isNotEmpty ||
                      parsearFiltroOrden(widget.orden['variedades'])
                          .isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...parsearFiltroOrden(widget.orden['cultivos']).map(
                            (c) => AgroTag(texto: c, icono: Icons.eco_outlined)),
                        ...parsearFiltroOrden(widget.orden['variedades']).map(
                            (v) => AgroTag(
                                texto: v, icono: Icons.local_florist_outlined)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  AgroStatGrid(
                    stats: [
                      AgroStat(
                          label: chacra.contains(',') ? "Chacras" : "Chacra",
                          valor: chacra.isEmpty ? '-' : chacra,
                          icono: Icons.map_outlined),
                      AgroStat(
                          label: "Caudal",
                          valor: "${_num(volHa)} L/ha",
                          icono: Icons.water_drop_outlined),
                      AgroStat(
                          label: "Superficie",
                          valor: "${supTotal.toStringAsFixed(2)} ha",
                          icono: Icons.crop_square_rounded),
                      AgroStat(
                          label: "Productos",
                          valor: "$totalProductos",
                          icono: Icons.science_outlined),
                    ],
                  ),
                  if (parametros.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _paramChip(Icons.air_rounded, "Viento",
                            parametros['vel_viento']),
                        _paramChip(Icons.thermostat_rounded, "Temp.",
                            parametros['Temperatura']),
                        _paramChip(Icons.grain_rounded, "Gota",
                            parametros['Tamano_gota']),
                        _paramChip(Icons.speed_rounded, "Avance",
                            parametros['Vel_Aplicacion']),
                      ],
                    ),
                  ],
                  if (productos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...productos.take(4).map((p) =>
                            AgroTag(texto: p, icono: Icons.circle_outlined)),
                        if (productos.length > 4)
                          AgroTag(texto: "+${productos.length - 4} más"),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ---------- CUADROS (desplegable) ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: AgroTheme.colorBg,
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
              child: InkWell(
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                onTap: cuadrosDetalle.isEmpty
                    ? null
                    : () => setState(
                        () => _cuadrosExpandidos = !_cuadrosExpandidos),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(
                    children: [
                      Icon(Icons.grid_view_rounded,
                          size: 16,
                          color: _cuadrosExpandidos
                              ? AgroColors.primario
                              : AgroTheme.colorTextSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cuadrosDetalle.isEmpty
                              ? "Sin cuadros asignados"
                              : "${cuadrosDetalle.length} ${cuadrosDetalle.length == 1 ? 'cuadro' : 'cuadros'} a tratar",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _cuadrosExpandidos
                                ? AgroColors.primario
                                : AgroTheme.colorText,
                          ),
                        ),
                      ),
                      if (cuadrosDetalle.isNotEmpty)
                        AnimatedRotation(
                          turns: _cuadrosExpandidos ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 20, color: AgroTheme.colorTextSecondary),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_cuadrosExpandidos
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AgroTheme.radiusMd),
                        border: Border.all(color: AgroTheme.colorBorder),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < cuadrosDetalle.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                  height: 1, color: AgroTheme.colorBorder),
                            _filaCuadro(cuadrosDetalle[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: AgroTheme.colorBorder),

          // ---------- ACCIONES ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: estaTerminada
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: AgroBadge(
                            texto: 'Orden finalizada',
                            color: AgroColors.neutral,
                            fondo: AgroColors.neutralSoft,
                            icono: Icons.lock_outline_rounded,
                            grande: true,
                          ),
                        )
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: AgroButton(
                            label: "Registrar aplicación",
                            icono: Icons.add_task_rounded,
                            compacto: true,
                            onTap: widget.onRegistrar,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                AgroButton(
                  label: "PDF",
                  icono: Icons.picture_as_pdf_outlined,
                  tipo: AgroButtonTipo.secundario,
                  compacto: true,
                  onTap: widget.onExportarPdf,
                ),
                if (widget.esIngenieroOAdmin) ...[
                  const SizedBox(width: 2),
                  PopupMenuButton<_AccionOrden>(
                    tooltip: 'Más acciones',
                    icon: const Icon(Icons.more_vert_rounded,
                        color: AgroTheme.colorTextSecondary),
                    color: AgroTheme.colorSurface,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AgroTheme.radiusMd)),
                    onSelected: (a) {
                      switch (a) {
                        case _AccionOrden.terminar:
                          widget.onTerminar();
                          break;
                        case _AccionOrden.editar:
                          widget.onEditar();
                          break;
                        case _AccionOrden.eliminar:
                          widget.onBorrar();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      _menuItem(
                        _AccionOrden.terminar,
                        estaTerminada
                            ? Icons.restart_alt_rounded
                            : Icons.task_alt_rounded,
                        estaTerminada ? 'Reactivar orden' : 'Terminar orden',
                        estaTerminada ? AgroColors.warn : AgroColors.ok,
                      ),
                      _menuItem(_AccionOrden.editar, Icons.edit_outlined,
                          'Editar orden', AgroTheme.colorText),
                      const PopupMenuDivider(),
                      _menuItem(
                          _AccionOrden.eliminar,
                          Icons.delete_outline_rounded,
                          'Eliminar',
                          AgroColors.danger),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_AccionOrden> _menuItem(
      _AccionOrden valor, IconData icono, String texto, Color color) {
    return PopupMenuItem<_AccionOrden>(
      value: valor,
      height: 44,
      child: Row(
        children: [
          Icon(icono, size: 19, color: color),
          const SizedBox(width: 12),
          Text(texto,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _paramChip(IconData icono, String label, dynamic valor) {
    final v = valor?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AgroColors.okSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: AgroColors.ok),
          const SizedBox(width: 4),
          Text(
            "$label: ${v.isEmpty ? '-' : v}",
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B5E20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaCuadro(Map<String, dynamic> c) {
    final double ha = (c['ha'] as num?)?.toDouble() ?? 0.0;
    final String variedad = c['variedad']?.toString() ?? 'S/D';
    final String cultivo = c['cultivo']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AgroColors.primarioSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              c['varias_chacras'] == true
                  ? "Ch ${c['chacra']} · C ${c['cuadro']}"
                  : "C ${c['cuadro']}",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                color: AgroColors.primario,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              cultivo.isNotEmpty ? "$variedad · $cultivo" : variedad,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AgroTheme.colorText,
              ),
            ),
          ),
          Text(
            "${ha.toStringAsFixed(2)} ha",
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AgroTheme.colorTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
