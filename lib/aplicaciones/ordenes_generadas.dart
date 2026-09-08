import 'package:aplicaciones_foliares/servicios/exportar_orden_pdf.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../base/base.dart';
import '../constantes/tema.dart';
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
          .map((e) => e
              .trim()
              .replaceAll(RegExp(r'cuadro', caseSensitive: false), '')
              .replaceAll('C.', '')
              .trim())
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

      final paramObj = mapaParametros[codOrden] ?? {};

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
        'parametros': paramObj,
      });
    });

    if (!mounted) return;
    setState(() {
      _todasLasOrdenes = listaFinal;
      _cargando = false;
    });
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

      // Filtro de Pestañas / Archivero
      if (_pestanaActiva == "ACTIVAS") {
        if (estado != "ACTIVO") return false;
      } else if (_pestanaActiva == "TERMINADAS") {
        if (estado != "TERMINADO") return false;
      } else if (_pestanaActiva == "HISTORICO") {
        if (esMesActual && estado == "ACTIVO") return false;
      }

      // Filtro de Texto
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: nuevoEstado == 'TERMINADO'
              ? const Color(0xFF546E7A)
              : const Color(0xFF1E6B4C),
          content: Text(nuevoEstado == 'TERMINADO'
              ? 'Orden #$codOrden archivada en Terminadas.'
              : 'Orden #$codOrden reactivada.'),
        ),
      );
    }
  }

  void _confirmarBorrarOrden(int codOrden) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgroTheme.colorSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Eliminar Orden Técnica",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text("¿Deseas eliminar definitivamente la orden #$codOrden?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              elevation: 0,
            ),
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.delete(
                'recetas_aplicaciones',
                where: 'cod_orden = ? AND cod_productor = ?',
                whereArgs: [codOrden, widget.codProductor],
              );
              await db.delete(
                'parametros_aplic',
                where: 'cod_orden = ?',
                whereArgs: [codOrden],
              );

              try {
                await Supabase.instance.client
                    .from('recetas_aplicaciones')
                    .delete()
                    .eq('cod_orden', codOrden)
                    .eq('cod_productor', widget.codProductor);
              } catch (_) {}

              if (mounted) {
                Navigator.pop(ctx);
                _cargarOrdenes();
              }
            },
            child: const Text("Eliminar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _mostrarModalOpcionesPdf(Map<String, dynamic> orden) {
    final int codOrden = orden['cod_orden'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AgroTheme.colorSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Orden Técnica #$codOrden",
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16.5,
                          color: AgroTheme.colorText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "Documento PDF Oficial de Pulverización",
                        style: TextStyle(
                          fontSize: 12,
                          color: AgroTheme.colorTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: AgroTheme.colorBorder),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  Navigator.pop(ctx);
                  await ServicioExportarOrdenPdf.compartirOrdenPdf(
                    orden: orden,
                    nombreProductor: widget.nombreProductor,
                    cuit: widget.cuit,
                    renspa: widget.renspa,
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AgroTheme.colorBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.share_outlined,
                          color: Color(0xFF2E7D32),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Compartir por WhatsApp / Enviar",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: AgroTheme.colorText,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Envía el reporte técnico al productor o tractorista.",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: AgroTheme.colorTextSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  Navigator.pop(ctx);
                  await ServicioExportarOrdenPdf.guardarOImprimirPdf(
                    orden: orden,
                    nombreProductor: widget.nombreProductor,
                    cuit: widget.cuit,
                    renspa: widget.renspa,
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AgroTheme.colorBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.download_rounded,
                          color: Color(0xFF1565C0),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Descargar / Imprimir Documento",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: AgroTheme.colorText,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Abre el visor para guardar localmente o imprimir.",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AgroTheme.colorTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: AgroTheme.colorTextSecondary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double ancho = MediaQuery.of(context).size.width;
    final bool esDesktop = ancho >= 920;

    final int cantActivas = _todasLasOrdenes
        .where((o) => (o['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'ACTIVO')
        .length;
    final int cantTerminadas = _todasLasOrdenes
        .where((o) => (o['estado'] ?? 'ACTIVO').toString().toUpperCase() == 'TERMINADO')
        .length;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.nombreProductor,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16.5,
                color: AgroTheme.colorText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              "CUIT: ${widget.cuit} · RENSPA: ${widget.renspa}",
              style: const TextStyle(
                fontSize: 11,
                color: AgroTheme.colorTextSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E6B4C)),
            tooltip: "Recargar órdenes",
            onPressed: _cargarOrdenes,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              children: [
                // PESTAÑAS DEL ARCHIVERO
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    esDesktop ? 24 : 16,
                    12,
                    esDesktop ? 24 : 16,
                    4,
                  ),
                  child: Row(
                    children: [
                      _buildPestanaBoton(
                        label: "Activas",
                        icono: Icons.pending_actions_rounded,
                        count: cantActivas,
                        id: "ACTIVAS",
                        colorActivo: const Color(0xFF1E6B4C),
                        fondoActivo: const Color(0xFFE8F5E9),
                      ),
                      const SizedBox(width: 8),
                      _buildPestanaBoton(
                        label: "Terminadas",
                        icono: Icons.check_circle_outline_rounded,
                        count: cantTerminadas,
                        id: "TERMINADAS",
                        colorActivo: const Color(0xFF546E7A),
                        fondoActivo: const Color(0xFFECEFF1),
                      ),
                      const SizedBox(width: 8),
                      _buildPestanaBoton(
                        label: "Histórico / Meses",
                        icono: Icons.folder_open_rounded,
                        count: _todasLasOrdenes.length,
                        id: "HISTORICO",
                        colorActivo: const Color(0xFF8A6A1E),
                        fondoActivo: const Color(0xFFFFF8E1),
                      ),
                    ],
                  ),
                ),

                // BUSCADOR
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    esDesktop ? 24 : 16,
                    8,
                    esDesktop ? 24 : 16,
                    10,
                  ),
                  child: Container(
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
                      controller: _searchController,
                      onChanged: (val) => setState(() => _filtroTexto = val),
                      style: const TextStyle(color: AgroTheme.colorText, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: "Buscar por N° orden, chacra, motivo o fecha...",
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
                        contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: _cargando
                      ? const Center(
                          child: CircularProgressIndicator(color: Color(0xFF1E6B4C)))
                      : _ordenesFiltradas.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE8F5E9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.inventory_2_outlined,
                                        size: 42, color: Color(0xFF2E7D32)),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _pestanaActiva == "ACTIVAS"
                                        ? "No hay órdenes activas"
                                        : (_pestanaActiva == "TERMINADAS"
                                            ? "No hay órdenes terminadas"
                                            : "No hay registros históricos"),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AgroTheme.colorText,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    "Las órdenes generadas se listarán en este panel.",
                                    style: TextStyle(
                                      color: AgroTheme.colorTextSecondary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                esDesktop ? 24 : 16,
                                6,
                                esDesktop ? 24 : 16,
                                85,
                              ),
                              itemCount: _ordenesFiltradas.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
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
                                  onExportarPdf: () => _mostrarModalOpcionesPdf(orden),
                                  onTerminar: () => _cambiarEstadoTerminar(
                                    orden['cod_orden'] as int,
                                    orden['estado'] as String,
                                  ),
                                  onBorrar: () => _confirmarBorrarOrden(
                                    orden['cod_orden'] as int,
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _esIngenieroOAdmin
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF1E6B4C),
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              onPressed: _abrirNuevaReceta,
              icon: const Icon(Icons.add_task_rounded,
                  color: Colors.white, size: 20),
              label: const Text(
                "Nueva Orden Técnica",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildPestanaBoton({
    required String label,
    required IconData icono,
    required int count,
    required String id,
    required Color colorActivo,
    required Color fondoActivo,
  }) {
    final bool isSelected = _pestanaActiva == id;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _pestanaActiva = id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? fondoActivo : AgroTheme.colorSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colorActivo.withOpacity(0.5) : AgroTheme.colorBorder,
              width: isSelected ? 1.2 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icono,
                size: 15,
                color: isSelected ? colorActivo : AgroTheme.colorTextSecondary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? colorActivo : AgroTheme.colorText,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? colorActivo : AgroTheme.colorBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "$count",
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
}

class _OrdenCardItem extends StatefulWidget {
  final Map<String, dynamic> orden;
  final String nombreProductor;
  final String cuit;
  final String renspa;
  final bool esIngenieroOAdmin;
  final VoidCallback onTapCard;
  final VoidCallback onRegistrar;
  final VoidCallback onEditar;
  final VoidCallback onExportarPdf;
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
    required this.onExportarPdf,
    required this.onTerminar,
    required this.onBorrar,
  });

  @override
  State<_OrdenCardItem> createState() => _OrdenCardItemState();
}

class _OrdenCardItemState extends State<_OrdenCardItem> {
  bool _cuadrosExpandidos = false;

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
        (widget.orden['cuadros_detalle'] as List? ?? [])
            .cast<Map<String, dynamic>>();
    final double supTotal = widget.orden['sup_total_calculada'] ?? 0.0;

    final Map<String, dynamic> parametros =
        (widget.orden['parametros'] as Map? ?? {}).cast<String, dynamic>();

    return Container(
      decoration: BoxDecoration(
        color: AgroTheme.colorSurface,
        borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
        border: Border.all(
          color: estaTerminada ? const Color(0xFFCFD8DC) : AgroTheme.colorBorder,
          width: 1.1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04141E18),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.onTapCard,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AgroTheme.radiusLg),
              bottom: Radius.circular(_cuadrosExpandidos ? 0 : AgroTheme.radiusLg),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: estaTerminada
                                  ? const Color(0xFFECEFF1)
                                  : const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: estaTerminada
                                    ? const Color(0xFFCFD8DC)
                                    : const Color(0xFFA5D6A7),
                              ),
                            ),
                            child: Text(
                              "ORDEN #$codOrden",
                              style: TextStyle(
                                color: estaTerminada
                                    ? const Color(0xFF546E7A)
                                    : const Color(0xFF2E7D32),
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            fecha,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AgroTheme.colorTextSecondary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (!sincronizado)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2.5),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFFFFE082)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.cloud_upload_outlined,
                                      size: 11, color: Color(0xFF8A6A1E)),
                                  SizedBox(width: 3),
                                  Text(
                                    "Pendiente",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF8A6A1E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: estaTerminada
                                  ? const Color(0xFFECEFF1)
                                  : const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: estaTerminada
                                    ? const Color(0xFFCFD8DC)
                                    : const Color(0xFFA5D6A7),
                              ),
                            ),
                            child: Text(
                              estado,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: estaTerminada
                                    ? const Color(0xFF546E7A)
                                    : const Color(0xFF2E7D32),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    motivo,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AgroTheme.colorText,
                    ),
                  ),
                  if (momento.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      "Momento: $momento",
                      style: const TextStyle(
                        fontSize: 12,
                        color: AgroTheme.colorTextSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Mini Resumen
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AgroTheme.colorBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMiniDato("Chacra", chacra),
                        _buildMiniDato("Caudal", "$volHa L/Ha"),
                        _buildMiniDato("Superficie",
                            "${supTotal.toStringAsFixed(2)} Ha"),
                        _buildMiniDato("Productos", "$totalProductos insumos"),
                      ],
                    ),
                  ),

                  // PARÁMETROS TÉCNICOS (parametros_aplic)
                  if (parametros.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F8E9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDCEDC8)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildMiniParam(Icons.air_rounded, "Viento:",
                              parametros['vel_viento']?.toString() ?? '-'),
                          _buildMiniParam(Icons.thermostat_rounded, "Temp:",
                              parametros['Temperatura']?.toString() ?? '-'),
                          _buildMiniParam(Icons.grain_rounded, "Gota:",
                              parametros['Tamano_gota']?.toString() ?? '-'),
                          _buildMiniParam(Icons.speed_rounded, "Avance:",
                              parametros['Vel_Aplicacion']?.toString() ?? '-'),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: productos.take(4).map((prod) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: Text(
                          prod,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AgroTheme.colorText,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          // ACORDEÓN DE CUADROS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: () =>
                  setState(() => _cuadrosExpandidos = !_cuadrosExpandidos),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                          size: 15,
                          color: _cuadrosExpandidos
                              ? const Color(0xFF2E7D32)
                              : AgroTheme.colorTextSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Cuadros a tratar (${cuadrosDetalle.length})",
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _cuadrosExpandidos
                                ? const Color(0xFF2E7D32)
                                : AgroTheme.colorText,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      _cuadrosExpandidos
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AgroTheme.colorTextSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_cuadrosExpandidos) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AgroTheme.colorBg,
                  borderRadius: BorderRadius.circular(8),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AgroTheme.colorSurface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: AgroTheme.colorBorder),
                            ),
                            child: Text(
                              "Cd. ${c['cuadro']}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cultivo.isNotEmpty
                                  ? "$variedad ($cultivo)"
                                  : variedad,
                              style: const TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "${ha.toStringAsFixed(2)} Ha",
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AgroTheme.colorTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: AgroTheme.colorBorder),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (!estaTerminada)
                      SoftButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6.5),
                        borderRadius: 8,
                        onTap: widget.onRegistrar,
                        child: const Row(
                          children: [
                            Icon(Icons.add_task_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 5),
                            Text(
                              "Registrar",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECEFF1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 13, color: Color(0xFF546E7A)),
                            SizedBox(width: 4),
                            Text(
                              "Finalizada",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF546E7A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: widget.onExportarPdf,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined,
                                size: 15, color: Color(0xFF2E7D32)),
                            SizedBox(width: 4),
                            Text(
                              "PDF",
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2E7D32),
                              ),
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
                              : Icons.check_circle_outline_rounded,
                          color: estaTerminada
                              ? const Color(0xFF8A6A1E)
                              : const Color(0xFF2E7D32),
                          size: 19,
                        ),
                        tooltip: estaTerminada
                            ? "Reactivar Orden"
                            : "Archivar / Terminar",
                        onPressed: widget.onTerminar,
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: AgroTheme.colorText, size: 18),
                        tooltip: "Editar Orden",
                        onPressed: widget.onEditar,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFFC62828), size: 18),
                        tooltip: "Eliminar Orden",
                        onPressed: widget.onBorrar,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDato(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AgroTheme.colorTextSecondary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AgroTheme.colorText,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniParam(IconData icono, String label, String valor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 12, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 2),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1B5E20),
          ),
        ),
      ],
    );
  }
}