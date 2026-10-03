// AgroSoft J&L · Presupuestos (listado)
// -----------------------------------------------------------------------------
// Ubicación: lib/presupuestos/presupuestos.dart

import 'package:flutter/material.dart';

import '../../constantes/tema.dart';
import '../servicios/presupuesto_pdf.dart';
import '../../servicios/sincronizar.dart';
import '../../widgets/agro_reportes_ui.dart';
import '../../widgets/agro_ui.dart';
import 'presupuesto_editor.dart';
import 'presupuesto_modelo.dart';

class PresupuestosScreen extends StatefulWidget {
  final int? codProductor;
  final String? nombreProductor;

  const PresupuestosScreen({super.key, this.codProductor, this.nombreProductor});

  @override
  State<PresupuestosScreen> createState() => _PresupuestosScreenState();
}

class _PresupuestosScreenState extends State<PresupuestosScreen> {
  bool _cargando = true;
  List<Presupuesto> _todos = [];
  String? _filtroEstado;
  String _busqueda = '';
  final _buscarCtrl = TextEditingController();
  final Set<String> _compartiendo = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final lista = await RepositorioPresupuestos.listar();
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      mostrarAgroSnack(context, 'No se pudieron cargar los presupuestos: $e',
          tipo: AgroSnackTipo.error);
    }
  }

  List<Presupuesto> get _filtrados {
    final q = _busqueda.trim().toLowerCase();
    return _todos.where((p) {
      if (_filtroEstado != null &&
          EstadoPresupuesto.etiqueta(p.estado) != _filtroEstado) {
        return false;
      }
      if (q.isEmpty) return true;
      return p.destinatario.toLowerCase().contains(q) ||
          p.emisor.toLowerCase().contains(q) ||
          p.numeroTexto.contains(q) ||
          p.items.any((i) => i.servicio.toLowerCase().contains(q));
    }).toList();
  }

  // ============================================================
  // ACCIONES
  // ============================================================

  Future<void> _nuevo() async {
    final p = await RepositorioPresupuestos.nuevo(codProductor: widget.codProductor);
    if (!mounted) return;
    await _abrirEditor(p, esNuevo: true);
  }

  Future<void> _abrirEditor(Presupuesto p, {bool esNuevo = false}) async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PresupuestoEditorPage(presupuesto: p, esNuevo: esNuevo),
      ),
    );
    if (guardado == true || !esNuevo) {
      await _cargar();
      ServicioSincronizacion.actualizarPendientes();
    }
  }

  Future<void> _compartir(Presupuesto p) async {
    if (_compartiendo.contains(p.cod)) return;
    setState(() => _compartiendo.add(p.cod));
    try {
      final bytes = await PresupuestoPdf.generar(p);
      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: PresupuestoPdf.nombreArchivo(p),
        mime: AgroMime.pdf,
        texto: '${p.titulo} N° ${p.numeroTexto} - ${p.destinatario}',
        context: context,
      );
      if (p.estado == EstadoPresupuesto.borrador) {
        await RepositorioPresupuestos.cambiarEstado(p.cod, EstadoPresupuesto.enviado);
        await _cargar();
      }
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'No se pudo generar el PDF: $e',
            tipo: AgroSnackTipo.error);
      }
    } finally {
      if (mounted) setState(() => _compartiendo.remove(p.cod));
    }
  }

  Future<void> _duplicar(Presupuesto p) async {
    final copia = await RepositorioPresupuestos.duplicar(p);
    if (!mounted) return;
    mostrarAgroSnack(context, 'Copia creada: N° ${copia.numeroTexto}',
        tipo: AgroSnackTipo.ok);
    await _abrirEditor(copia);
  }

  Future<void> _cambiarEstado(Presupuesto p) async {
    final nuevo = await mostrarAgroPanel<String>(
      context: context,
      titulo: 'Cambiar estado',
      subtitulo: 'Presupuesto N° ${p.numeroTexto} · ${p.destinatario}',
      icono: Icons.flag_outlined,
      builder: (ctx) => Column(
        children: EstadoPresupuesto.todos.map((e) {
          final est = _estiloEstado(e);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AgroOptionTile(
              icono: est.icono,
              titulo: EstadoPresupuesto.etiqueta(e),
              descripcion: p.estado == e ? 'Estado actual' : null,
              color: est.color,
              onTap: () => Navigator.pop(ctx, e),
            ),
          );
        }).toList(),
      ),
    );
    if (nuevo == null || nuevo == p.estado) return;
    await RepositorioPresupuestos.cambiarEstado(p.cod, nuevo);
    await _cargar();
    if (mounted) {
      mostrarAgroSnack(context, 'Estado: ${EstadoPresupuesto.etiqueta(nuevo)}',
          tipo: AgroSnackTipo.ok);
    }
  }

  Future<void> _eliminar(Presupuesto p) async {
    final ok = await confirmarAgro(
      context: context,
      titulo: 'Eliminar presupuesto',
      mensaje:
          'Se eliminará el presupuesto N° ${p.numeroTexto} para ${p.destinatario}. '
          'También se borra del servidor al sincronizar.',
      confirmar: 'Eliminar',
      peligroso: true,
      icono: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    await RepositorioPresupuestos.eliminar(p.cod);
    await _cargar();
    ServicioSincronizacion.actualizarPendientes();
    if (mounted) {
      mostrarAgroSnack(context, 'Presupuesto eliminado', tipo: AgroSnackTipo.info);
    }
  }

  void _verPdf(Presupuesto p) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => VistaPreviaPresupuestoPage(presupuesto: p)),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: 'Presupuestos',
        subtitulo: 'Cotizaciones de servicios en PDF',
        acciones: [
          AgroIconButton(
            icono: Icons.refresh_rounded,
            tooltip: 'Recargar',
            onTap: _cargar,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AgroColors.primario,
        onPressed: _nuevo,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Nuevo presupuesto',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: _cargando
          ? const AgroLoading(mensaje: 'Cargando presupuestos…')
          : RefreshIndicator(
              color: AgroColors.primario,
              onRefresh: _cargar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 16, bottom: 96),
                children: [
                  AgroContent(child: _kpis()),
                  const SizedBox(height: 14),
                  AgroContent(child: _filtros()),
                  const SizedBox(height: 14),
                  AgroContent(child: _listado(lista)),
                ],
              ),
            ),
    );
  }

  Widget _kpis() {
    int cuenta(String e) => _todos.where((p) => p.estado == e).length;
    double montoArs(String e) => _todos
        .where((p) => p.estado == e && p.moneda == Moneda.ars)
        .fold(0.0, (a, p) => a + p.total);

    return AgroKpiGrid(
      kpis: [
        AgroKpiTile(
          label: 'Presupuestos',
          valor: '${_todos.length}',
          icono: Icons.request_quote_outlined,
          detalle: '${cuenta(EstadoPresupuesto.borrador)} en borrador',
        ),
        AgroKpiTile(
          label: 'Enviados',
          valor: '${cuenta(EstadoPresupuesto.enviado)}',
          icono: Icons.send_outlined,
          color: AgroColors.info,
          detalle: 'Esperando respuesta',
        ),
        AgroKpiTile(
          label: 'Aceptados',
          valor: '${cuenta(EstadoPresupuesto.aceptado)}',
          icono: Icons.verified_outlined,
          color: AgroColors.ok,
          detalle: FormatoPresupuesto.importe(
              montoArs(EstadoPresupuesto.aceptado), Moneda.ars),
        ),
        AgroKpiTile(
          label: 'En curso',
          valor: FormatoPresupuesto.importe(
              montoArs(EstadoPresupuesto.enviado), Moneda.ars),
          icono: Icons.hourglass_top_rounded,
          color: AgroColors.warn,
          detalle: 'Monto enviado (\$)',
        ),
      ],
    );
  }

  Widget _filtros() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgroSearchField(
          controller: _buscarCtrl,
          hint: 'Buscar por destinatario, emisor, N° o servicio…',
          onChanged: (v) => setState(() => _busqueda = v),
          onClear: () {
            _buscarCtrl.clear();
            setState(() => _busqueda = '');
          },
        ),
        const SizedBox(height: 10),
        AgroChipSelector(
          opciones: EstadoPresupuesto.todos.map(EstadoPresupuesto.etiqueta).toList(),
          valor: _filtroEstado,
          textoTodos: 'Todos',
          onChanged: (v) => setState(() => _filtroEstado = v),
        ),
      ],
    );
  }

  Widget _listado(List<Presupuesto> lista) {
    if (_todos.isEmpty) {
      return AgroEmptyState(
        icono: Icons.request_quote_outlined,
        titulo: 'Todavía no hay presupuestos',
        mensaje:
            'Armá tu primera cotización y compartila en PDF con tu logo en segundos.',
        accion: AgroButton(
          label: 'Crear presupuesto',
          icono: Icons.add_rounded,
          onTap: _nuevo,
        ),
      );
    }
    if (lista.isEmpty) {
      return const AgroEmptyState(
        icono: Icons.search_off_rounded,
        titulo: 'Sin resultados',
        mensaje: 'Probá con otra búsqueda o cambiá el filtro de estado.',
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final int cols = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 700 ? 2 : 1);
      const double esp = 12;
      final double anchoCard =
          ((c.maxWidth - (cols - 1) * esp) / cols).floorToDouble();
      return Wrap(
        spacing: esp,
        runSpacing: esp,
        children: lista
            .map((p) => SizedBox(width: anchoCard, child: _card(p)))
            .toList(),
      );
    });
  }

  Widget _card(Presupuesto p) {
    final est = _estiloEstado(p.estado);
    final compartiendo = _compartiendo.contains(p.cod);
    final servicios = p.items.map((i) => i.servicio).where((s) => s.isNotEmpty);

    return AgroCard(
      accentColor: est.color,
      onTap: () => _abrirEditor(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AgroColors.primarioSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'N° ${p.numeroTexto}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AgroColors.primario,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AgroBadge(
                texto: EstadoPresupuesto.etiqueta(p.estado),
                color: est.color,
                icono: est.icono,
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                icon: const Icon(Icons.more_vert_rounded,
                    color: AgroTheme.colorTextSecondary),
                onSelected: (op) {
                  switch (op) {
                    case 'ver':
                      _verPdf(p);
                      break;
                    case 'estado':
                      _cambiarEstado(p);
                      break;
                    case 'duplicar':
                      _duplicar(p);
                      break;
                    case 'eliminar':
                      _eliminar(p);
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'ver',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('Ver / imprimir PDF'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'estado',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.flag_outlined),
                      title: Text('Cambiar estado'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'duplicar',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.copy_all_outlined),
                      title: Text('Duplicar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'eliminar',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete_outline_rounded,
                          color: AgroColors.danger),
                      title: Text('Eliminar',
                          style: TextStyle(color: AgroColors.danger)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            p.destinatario.isEmpty ? 'Sin destinatario' : p.destinatario,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AgroText.tituloCard,
          ),
          const SizedBox(height: 2),
          Text(
            '${FormatoPresupuesto.fechaLarga(p.fecha)}${p.emisor.isEmpty ? '' : ' · ${p.emisor}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AgroText.secundario,
          ),
          if (servicios.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              servicios.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AgroText.cuerpo.copyWith(fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOTAL', style: AgroText.overline),
                    Text(
                      p.totalTexto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AgroTheme.colorText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AgroButton(
                label: 'Compartir',
                icono: Icons.ios_share_rounded,
                compacto: true,
                cargando: compartiendo,
                onTap: compartiendo ? null : () => _compartir(p),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EstiloEstado {
  final Color color;
  final IconData icono;
  const _EstiloEstado(this.color, this.icono);
}

_EstiloEstado _estiloEstado(String e) {
  switch (e) {
    case EstadoPresupuesto.enviado:
      return const _EstiloEstado(AgroColors.info, Icons.send_rounded);
    case EstadoPresupuesto.aceptado:
      return const _EstiloEstado(AgroColors.ok, Icons.verified_rounded);
    case EstadoPresupuesto.rechazado:
      return const _EstiloEstado(AgroColors.danger, Icons.cancel_rounded);
    default:
      return const _EstiloEstado(AgroColors.neutral, Icons.edit_note_rounded);
  }
}
