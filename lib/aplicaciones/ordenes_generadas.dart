import 'package:aplicaciones_foliares/servicios/exportar_orden_pdf.dart' show ServicioExportarOrdenPdf;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
import '../servicios/servicio_exportar_orden_pdf.dart';
import '../widgets/soft_button.dart';
import 'aplicaciones.dart';
import 'nueva_receta.dart';

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
  List<Map<String, dynamic>> _ordenesAgrupadas = [];
  String _filtroTexto = "";
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

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _userRol = (prefs.getString('userRole') ??
            prefs.getString('userRol') ??
            prefs.getString('rol') ??
            "OPERARIO")
        .toUpperCase();
    await _cargarOrdenes();
  }

  bool get _esIngenieroOAdmin =>
      _userRol == 'ADMIN' || _userRol == 'INGENIERO';

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

      final List<String> cuadrosNombres = (cabecera['cuadros']?.toString() ?? '')
          .split(',')
          .map((e) => e.trim().replaceAll('Cuadro', '').trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final List<Map<String, dynamic>> cuadrosDetalleRenglones = [];
      double supAcumulada = 0.0;

      for (var cuadroNom in cuadrosNombres) {
        final matches = inventario.where((inv) =>
            (inv['chacra'] ?? '').toString().trim() == chacraOrden &&
            (inv['cuadro'] ?? '').toString().trim() == cuadroNom);

        if (matches.isNotEmpty) {
          for (var m in matches) {
            final double ha = double.tryParse(m['ha']?.toString() ?? '0') ?? 0.0;
            supAcumulada += ha;
            cuadrosDetalleRenglones.add({
              'cuadro': m['cuadro'],
              'ha': ha,
              'variedad': m['variedad'] ?? 'S/D',
              'cultivo': m['cultivo'] ?? '',
            });
          }
        } else {
          cuadrosDetalleRenglones.add({
            'cuadro': cuadroNom,
            'ha': 0.0,
            'variedad': 'General',
            'cultivo': '',
          });
        }
      }

      listaFinal.add({
        'cod_orden': codOrden,
        'fecha': cabecera['fecha'] ?? 'Sin Fecha',
        'chacra': chacraOrden,
        'cuadros': cabecera['cuadros'] ?? 'S/D',
        'cuadros_detalle': cuadrosDetalleRenglones,
        'sup_total_calculada': supAcumulada,
        'motivo': cabecera['motivo_aplic'] ?? 'Aplicación Foliar',
        'momento': cabecera['momento_aplic'] ?? '',
        'vol_ha': cabecera['vol_aplic_ha'] ?? 0,
        'responsable': cabecera['responsable'] ?? 'Técnico',
        'total_productos': items.length,
        'productos_detalle':
            items.map((i) => i['producto']?.toString() ?? '').toList(),
        'sincronizado': !hayPendienteSync,
        'estado': estado,
        'items': items,
      });
    });

    if (!mounted) return;
    setState(() {
      _ordenesAgrupadas = listaFinal;
      _cargando = false;
    });
  }

  List<Map<String, dynamic>> get _ordenesFiltradas {
    if (_filtroTexto.isEmpty) return _ordenesAgrupadas;
    final query = _filtroTexto.toLowerCase();
    return _ordenesAgrupadas.where((o) {
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
        ),
      ),
    );

    if (recargar == true) {
      _cargarOrdenes();
    }
  }

  void _cambiarEstadoTerminar(int codOrden, String estadoActual) async {
    final String nuevoEstado = estadoActual == 'TERMINADO' ? 'ACTIVO' : 'TERMINADO';
    final db = await DatabaseHelper.instance.database;

    await db.update(
      'recetas_aplicaciones',
      {'habilitado': nuevoEstado, 'sincronizado': 0},
      where: 'cod_orden = ? AND cod_productor = ?',
      whereArgs: [codOrden, widget.codProductor],
    );

    _cargarOrdenes();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: nuevoEstado == 'TERMINADO' ? Colors.grey.shade800 : AgroTheme.colorAccent,
          content: Text(nuevoEstado == 'TERMINADO'
              ? 'La orden #$codOrden ha sido dada por terminada.'
              : 'La orden #$codOrden se ha reactivado.'),
        ),
      );
    }
  }

  void _confirmarBorrarOrden(int codOrden) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Eliminar Orden Técnica"),
        content: Text("¿Seguro que deseas eliminar la orden #$codOrden?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.delete(
                'recetas_aplicaciones',
                where: 'cod_orden = ? AND cod_productor = ?',
                whereArgs: [codOrden, widget.codProductor],
              );
              if (mounted) {
                Navigator.pop(ctx);
                _cargarOrdenes();
              }
            },
            child: const Text("Eliminar",
                style: TextStyle(color: AgroTheme.colorDanger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AppBar(
        backgroundColor: AgroTheme.colorSurface.withOpacity(0.85),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.nombreProductor,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16.5,
                  color: AgroTheme.colorText),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "CUIT: ${widget.cuit} · RENSPA: ${widget.renspa}",
              style: const TextStyle(
                  fontSize: 11,
                  color: AgroTheme.colorTextSecondary,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AgroTheme.colorAccent),
            tooltip: "Recargar órdenes",
            onPressed: _cargarOrdenes,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  border: Border.all(color: AgroTheme.colorBorder),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x06141E18),
                        blurRadius: 8,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _filtroTexto = val),
                  style: const TextStyle(color: AgroTheme.colorText, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Buscar por N° de orden, chacra, motivo o fecha...",
                    hintStyle: const TextStyle(
                        color: AgroTheme.colorTextSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AgroTheme.colorTextSecondary, size: 20),
                    suffixIcon: _filtroTexto.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                size: 18, color: AgroTheme.colorTextSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _filtroTexto = "");
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _cargando
                  ? const Center(
                      child: CircularProgressIndicator(color: AgroTheme.colorAccent))
                  : _ordenesFiltradas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: const BoxDecoration(
                                  color: AgroTheme.colorAccentSoft,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.description_outlined,
                                    size: 44, color: AgroTheme.colorAccentDark),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No hay órdenes confeccionadas",
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AgroTheme.colorText,
                                    fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Presioná en '+ Nueva Orden' para confeccionar la primera.",
                                style: TextStyle(
                                    color: AgroTheme.colorTextSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                          itemCount: _ordenesFiltradas.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final orden = _ordenesFiltradas[index];
                            return _OrdenCardItem(
                              orden: orden,
                              nombreProductor: widget.nombreProductor,
                              cuit: widget.cuit,
                              renspa: widget.renspa,
                              esIngenieroOAdmin: _esIngenieroOAdmin,
                              onTapCard: () => _irAAplicaciones(orden),
                              onRegistrar: () => _irAAplicaciones(orden),
                              onEditar: () => _editarOrden(orden),
                              onTerminar: () => _cambiarEstadoTerminar(
                                  orden['cod_orden'] as int,
                                  orden['estado'] as String),
                              onBorrar: () => _confirmarBorrarOrden(
                                  orden['cod_orden'] as int),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _esIngenieroOAdmin
          ? SoftButton(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              borderRadius: 28,
              onTap: _abrirNuevaReceta,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add_task_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Nueva Orden Técnica",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

// ============================================================================
// CARD CON CUADROS EXPANDIBLES / COLAPSABLES, BOTÓN PDF Y BLOQUEO
// ============================================================================
class _OrdenCardItem extends StatefulWidget {
  final Map<String, dynamic> orden;
  final String nombreProductor;
  final String cuit;
  final String renspa;
  final bool esIngenieroOAdmin;
  final VoidCallback onTapCard;
  final VoidCallback onRegistrar;
  final VoidCallback onEditar;
  final VoidCallback onTerminar;
  final VoidCallback onBorrar;

  const _OrdenCardItem({
    required this.orden,
    required this.nombreProductor,
    required this.cuit,
    required this.renspa,
    required this.esIngenieroOAdmin,
    required this.onTapCard,
    required this.onRegistrar,
    required this.onEditar,
    required this.onTerminar,
    required this.onBorrar,
  });

  @override
  State<_OrdenCardItem> createState() => _OrdenCardItemState();
}

class _OrdenCardItemState extends State<_OrdenCardItem> {
  bool _isPressed = false;
  bool _cuadrosExpandidos = false; // 💡 Control de colapso/despliegue

  @override
  Widget build(BuildContext context) {
    final int codOrden = widget.orden['cod_orden'];
    final String fecha = widget.orden['fecha'];
    final String chacra = widget.orden['chacra'];
    final String motivo = widget.orden['motivo'];
    final String momento = widget.orden['momento'];
    final dynamic volHa = widget.orden['vol_ha'];
    final int totalProductos = widget.orden['total_productos'];
    final List<String> productos =
        (widget.orden['productos_detalle'] as List).cast<String>();
    final bool sincronizado = widget.orden['sincronizado'] ?? true;
    final String estado = widget.orden['estado'] ?? 'ACTIVO';
    final bool estaTerminada = estado == 'TERMINADO';

    final List<Map<String, dynamic>> cuadrosDetalle =
        (widget.orden['cuadros_detalle'] as List? ?? []).cast<Map<String, dynamic>>();
    final double supTotal = widget.orden['sup_total_calculada'] ?? 0.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTapCard,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.identity()..scale(_isPressed ? 0.985 : 1.0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _isPressed ? AgroTheme.colorActiveBg : AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
          border: Border.all(
            color: _isPressed ? AgroTheme.colorActiveBorder : AgroTheme.colorBorder,
            width: 1.2,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                      color: const Color(0xFFFBC02D).withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ]
              : const [
                  BoxShadow(
                      color: Color(0x06141E18),
                      blurRadius: 10,
                      offset: Offset(0, 4)),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera: Orden + Badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: estaTerminada ? Colors.grey.shade700 : AgroTheme.colorAccentDark,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "ORDEN #$codOrden",
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fecha,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AgroTheme.colorTextSecondary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (!sincronizado)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorGoldSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.cloud_upload_outlined, size: 12, color: Color(0xFF8A6A1E)),
                            SizedBox(width: 4),
                            Text("Pendiente",
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF8A6A1E))),
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: estaTerminada
                            ? Colors.grey.shade200
                            : AgroTheme.colorAccentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        estado,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: estaTerminada
                              ? Colors.grey.shade800
                              : AgroTheme.colorAccentDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Motivo y Momento
            Text(
              motivo,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: AgroTheme.colorText),
            ),
            if (momento.isNotEmpty)
              Text(
                "Momento: $momento",
                style: const TextStyle(
                    fontSize: 12,
                    color: AgroTheme.colorTextSecondary,
                    fontWeight: FontWeight.w500),
              ),
            const SizedBox(height: 12),

            // Resumen de Datos
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AgroTheme.colorBg,
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                border: Border.all(color: AgroTheme.colorBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMiniDato("Chacra", chacra),
                  _buildMiniDato("Vol/Ha", "$volHa L/Ha"),
                  _buildMiniDato("Superficie", "${supTotal.toStringAsFixed(2)} Ha"),
                  _buildMiniDato("Insumos", "$totalProductos prod."),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // =========================================================
            // 💡 CUADROS CON DESPLIEGUE / COMPACTACIÓN (ACCORDION)
            // =========================================================
            InkWell(
              onTap: () {
                setState(() {
                  _cuadrosExpandidos = !_cuadrosExpandidos;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AgroTheme.colorBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AgroTheme.colorBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.crop_landscape_rounded,
                          size: 16,
                          color: _cuadrosExpandidos
                              ? AgroTheme.colorAccentDark
                              : AgroTheme.colorTextSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Cuadros asignados (${cuadrosDetalle.length})",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _cuadrosExpandidos
                                ? AgroTheme.colorAccentDark
                                : AgroTheme.colorText,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          _cuadrosExpandidos ? "Compactar" : "Desplegar",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AgroTheme.colorTextSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _cuadrosExpandidos
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AgroTheme.colorTextSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Lista desglosada (visible solo al desplegar)
            if (_cuadrosExpandidos) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AgroTheme.colorBorder),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cuadrosDetalle.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AgroTheme.colorBorder),
                  itemBuilder: (context, cIdx) {
                    final c = cuadrosDetalle[cIdx];
                    final double ha = c['ha'] ?? 0.0;
                    final String variedad = c['variedad'] ?? 'S/D';
                    final String cultivo = c['cultivo'] ?? '';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AgroTheme.colorSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AgroTheme.colorBorder),
                            ),
                            child: Text(
                              "Cd. ${c['cuadro']}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                  color: AgroTheme.colorAccentDark),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cultivo.isNotEmpty ? "$variedad ($cultivo)" : variedad,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "${ha.toStringAsFixed(2)} Ha",
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AgroTheme.colorTextSecondary),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Chips con productos
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: productos.take(3).map((prod) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AgroTheme.colorBorder),
                  ),
                  child: Text(
                    prod,
                    style: const TextStyle(
                        fontSize: 11, color: AgroTheme.colorText, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AgroTheme.colorBorder),
            const SizedBox(height: 10),

            // Botones de acción
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (!estaTerminada)
                      SoftButton(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        borderRadius: 10,
                        onTap: widget.onRegistrar,
                        child: Row(
                          children: const [
                            Icon(Icons.add_task_rounded, color: Colors.white, size: 15),
                            SizedBox(width: 5),
                            Text(
                              "Registrar",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.lock_outline_rounded, size: 14, color: Colors.grey),
                            SizedBox(width: 4),
                            Text("Orden Finalizada",
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey)),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => ServicioExportarOrdenPdf.compartirOrdenPdf(
                        orden: widget.orden,
                        nombreProductor: widget.nombreProductor,
                        cuit: widget.cuit,
                        renspa: widget.renspa,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.picture_as_pdf_outlined,
                                size: 16, color: AgroTheme.colorAccentDark),
                            SizedBox(width: 4),
                            Text(
                              "PDF",
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: AgroTheme.colorAccentDark),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.esIngenieroOAdmin)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          estaTerminada
                              ? Icons.restart_alt_rounded
                              : Icons.check_circle_outline,
                          color: estaTerminada
                              ? Colors.orange.shade800
                              : AgroTheme.colorAccentDark,
                          size: 20,
                        ),
                        tooltip: estaTerminada ? "Reactivar Orden" : "Terminar Orden",
                        onPressed: widget.onTerminar,
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: AgroTheme.colorText, size: 20),
                        tooltip: "Editar Orden",
                        onPressed: widget.onEditar,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AgroTheme.colorDanger, size: 20),
                        tooltip: "Eliminar Orden",
                        onPressed: widget.onBorrar,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniDato(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AgroTheme.colorTextSecondary)),
        const SizedBox(height: 1),
        Text(value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: AgroTheme.colorText)),
      ],
    );
  }
}