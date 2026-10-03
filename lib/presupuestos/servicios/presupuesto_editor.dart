// AgroSoft J&L · Editor de Presupuesto
// -----------------------------------------------------------------------------
// Ubicación: lib/presupuestos/presupuesto_editor.dart


import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../constantes/tema.dart';
import '../servicios/presupuesto_pdf.dart';
import '../../widgets/agro_reportes_ui.dart';
import '../../widgets/agro_ui.dart';
import 'presupuesto_modelo.dart';

/// Devuelve `true` por Navigator.pop si hubo cambios guardados.
class PresupuestoEditorPage extends StatefulWidget {
  final Presupuesto presupuesto;
  final bool esNuevo;

  const PresupuestoEditorPage({
    super.key,
    required this.presupuesto,
    this.esNuevo = false,
  });

  @override
  State<PresupuestoEditorPage> createState() => _PresupuestoEditorPageState();
}

class _PresupuestoEditorPageState extends State<PresupuestoEditorPage> {
  late Presupuesto _p;

  final _tituloCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _emisorCtrl = TextEditingController();
  final _firmanteCtrl = TextEditingController();
  final _condCtrl = TextEditingController();
  final _cierreCtrl = TextEditingController();

  bool _cambios = false;
  bool _guardadoAlgunaVez = false;
  bool _guardando = false;
  bool _compartiendo = false;

  List<String> _destinatariosPrevios = [];
  List<String> _emisoresPrevios = [];
  List<String> _serviciosPrevios = [];

  @override
  void initState() {
    super.initState();
    _p = widget.presupuesto.copia();
    _tituloCtrl.text = _p.titulo;
    _destCtrl.text = _p.destinatario;
    _emisorCtrl.text = _p.emisor;
    _firmanteCtrl.text = _p.firmante;
    _condCtrl.text = _p.condiciones;
    _cierreCtrl.text = _p.textoCierre;
    _cambios = widget.esNuevo;
    _cargarSugerencias();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _destCtrl.dispose();
    _emisorCtrl.dispose();
    _firmanteCtrl.dispose();
    _condCtrl.dispose();
    _cierreCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarSugerencias() async {
    try {
      final dest = await RepositorioPresupuestos.valoresUsados('destinatario');
      final emi = await RepositorioPresupuestos.valoresUsados('emisor');
      final prods = await RepositorioPresupuestos.nombresProductores();
      final serv = await RepositorioPresupuestos.serviciosUsados();
      if (!mounted) return;
      setState(() {
        _destinatariosPrevios = dest;
        _emisoresPrevios = {...emi, ...prods}.toList();
        _serviciosPrevios = {...kServiciosSugeridos, ...serv}.toList();
      });
    } catch (_) {}
  }

  void _marcar(VoidCallback f) {
    setState(() {
      f();
      _cambios = true;
    });
  }

  void _volcarControladores() {
    _p.titulo = _tituloCtrl.text;
    _p.destinatario = _destCtrl.text;
    _p.emisor = _emisorCtrl.text;
    _p.firmante = _firmanteCtrl.text;
    _p.condiciones = _condCtrl.text;
    _p.textoCierre = _cierreCtrl.text;
  }

  // ============================================================
  // GUARDAR / PDF
  // ============================================================

  String? _validar() {
    _volcarControladores();
    if (_p.destinatario.trim().isEmpty) return 'Completá el destinatario.';
    if (_p.emisor.trim().isEmpty) return 'Completá quién emite el presupuesto.';
    if (_p.items.isEmpty) return 'Agregá al menos un servicio.';
    if (_p.items.any((i) => i.servicio.trim().isEmpty)) {
      return 'Hay un renglón sin descripción del servicio.';
    }
    return null;
  }

  Future<bool> _guardar({bool silencioso = false}) async {
    if (_guardando) return false;
    final error = _validar();
    if (error != null) {
      mostrarAgroSnack(context, error, tipo: AgroSnackTipo.aviso);
      return false;
    }
    if (_p.total <= 0 && !silencioso) {
      final ok = await confirmarAgro(
        context: context,
        titulo: 'Presupuesto sin valor',
        mensaje: 'El total es \$ 0. ¿Querés guardarlo igual?',
        confirmar: 'Guardar',
        icono: Icons.warning_amber_rounded,
      );
      if (!ok || !mounted) return false;
    }
    setState(() => _guardando = true);
    try {
      await RepositorioPresupuestos.guardar(_p);
      if (!mounted) return true;
      setState(() {
        _cambios = false;
        _guardadoAlgunaVez = true;
      });
      if (!silencioso) {
        mostrarAgroSnack(context, 'Presupuesto N° ${_p.numeroTexto} guardado',
            tipo: AgroSnackTipo.ok);
      }
      return true;
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'No se pudo guardar: $e',
            tipo: AgroSnackTipo.error);
      }
      return false;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _vistaPrevia() async {
    final error = _validar();
    if (error != null) {
      mostrarAgroSnack(context, error, tipo: AgroSnackTipo.aviso);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VistaPreviaPresupuestoPage(presupuesto: _p.copia())),
    );
  }

  Future<void> _compartir() async {
    if (_compartiendo) return;
    final ok = await _guardar(silencioso: true);
    if (!ok || !mounted) return;
    setState(() => _compartiendo = true);
    try {
      final bytes = await PresupuestoPdf.generar(_p);
      if (!mounted) return;
      await exportarArchivoAgro(
        bytes: bytes,
        nombre: PresupuestoPdf.nombreArchivo(_p),
        mime: AgroMime.pdf,
        texto: '${_p.titulo} N° ${_p.numeroTexto} - ${_p.destinatario}',
        context: context,
      );
      if (_p.estado == EstadoPresupuesto.borrador) {
        await RepositorioPresupuestos.cambiarEstado(_p.cod, EstadoPresupuesto.enviado);
        if (!mounted) return;
        setState(() => _p.estado = EstadoPresupuesto.enviado);
        mostrarAgroSnack(context, 'Presupuesto marcado como enviado',
            tipo: AgroSnackTipo.ok);
      }
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(context, 'No se pudo generar el PDF: $e',
            tipo: AgroSnackTipo.error);
      }
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  Future<bool> _alSalir() async {
    if (!_cambios) {
      Navigator.pop(context, _guardadoAlgunaVez);
      return false;
    }
    final salir = await confirmarAgro(
      context: context,
      titulo: 'Cambios sin guardar',
      mensaje: '¿Querés salir sin guardar el presupuesto?',
      confirmar: 'Salir sin guardar',
      cancelar: 'Seguir editando',
      peligroso: true,
      icono: Icons.exit_to_app_rounded,
    );
    if (salir && mounted) Navigator.pop(context, _guardadoAlgunaVez);
    return false;
  }

  // ============================================================
  // RENGLONES
  // ============================================================

  Future<void> _editarItem([int? indice]) async {
    final bool esNuevo = indice == null;
    final ItemPresupuesto it =
        esNuevo ? ItemPresupuesto() : _p.items[indice!].copia();

    final servCtrl = TextEditingController(text: it.servicio);
    final detCtrl = TextEditingController(text: it.detalle);
    final cantCtrl =
        TextEditingController(text: FormatoPresupuesto.numeroEditable(it.cantidad));
    final unidadCtrl = TextEditingController(text: it.unidad);
    final puCtrl = TextEditingController(
        text: FormatoPresupuesto.numeroEditable(it.precioUnitario));
    final impCtrl =
        TextEditingController(text: FormatoPresupuesto.numeroEditable(it.importe));

    final resultado = await mostrarAgroPanel<String>(
      context: context,
      titulo: esNuevo ? 'Agregar servicio' : 'Editar servicio',
      subtitulo: 'Renglón de la cotización',
      icono: Icons.design_services_outlined,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPanel) {
          final double cant = FormatoPresupuesto.parseNumero(cantCtrl.text);
          final double pu = FormatoPresupuesto.parseNumero(puCtrl.text);
          final bool calcula = pu > 0;
          final double importeCalc = calcula ? cant * pu : 0;
          final filtro = servCtrl.text.trim().toLowerCase();
          final sugerencias = _serviciosPrevios
              .where((s) =>
                  s.toLowerCase() != filtro &&
                  (filtro.isEmpty || s.toLowerCase().contains(filtro)))
              .take(6)
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: servCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: agroInputDecoration(
                    label: 'Servicio', icono: Icons.flight_takeoff_rounded),
                onChanged: (_) => setPanel(() {}),
              ),
              if (sugerencias.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ChipsSugeridos(
                  opciones: sugerencias,
                  onTap: (s) => setPanel(() {
                    servCtrl.text = s;
                    servCtrl.selection =
                        TextSelection.collapsed(offset: s.length);
                  }),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: detCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: agroInputDecoration(
                  label: 'Detalle (opcional)',
                  hint: 'Ej: incluye producto, 2 pasadas, traslado…',
                  icono: Icons.notes_rounded,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: cantCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: agroInputDecoration(
                          label: 'Cantidad', icono: Icons.straighten_rounded),
                      onChanged: (_) => setPanel(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: unidadCtrl,
                      decoration: agroInputDecoration(
                          label: 'Unidad', icono: Icons.square_foot_rounded),
                      onChanged: (_) => setPanel(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ChipsSugeridos(
                opciones: kUnidadesSugeridas,
                seleccionado: unidadCtrl.text.trim(),
                onTap: (u) => setPanel(() => unidadCtrl.text = u),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: puCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: agroInputDecoration(
                  label: 'Precio unitario (opcional)',
                  hint: 'Si lo cargás, el valor se calcula solo',
                  icono: Icons.sell_outlined,
                  sufijo: unidadCtrl.text.trim().isEmpty
                      ? null
                      : '/ ${unidadCtrl.text.trim()}',
                ),
                onChanged: (_) => setPanel(() {}),
              ),
              const SizedBox(height: 12),
              if (calcula)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AgroColors.primarioSoft,
                    borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calculate_outlined,
                          color: AgroColors.primario, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${FormatoPresupuesto.numero(cant)} × ${FormatoPresupuesto.importe(pu, _p.moneda)}',
                          style: AgroText.secundario,
                        ),
                      ),
                      Text(
                        FormatoPresupuesto.importe(importeCalc, _p.moneda),
                        style: AgroText.valor
                            .copyWith(color: AgroColors.primario, fontSize: 16),
                      ),
                    ],
                  ),
                )
              else
                TextField(
                  controller: impCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: agroInputDecoration(
                    label: 'Valor del renglón',
                    hint: 'Ej: 150.000',
                    icono: Icons.attach_money_rounded,
                    sufijo: _p.ivaModo == IvaModo.masIva ? '+ IVA' : null,
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (!esNuevo) ...[
                    Expanded(
                      child: AgroButton(
                        label: 'Quitar',
                        icono: Icons.delete_outline_rounded,
                        tipo: AgroButtonTipo.peligro,
                        expandido: true,
                        onTap: () => Navigator.pop(ctx, 'quitar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: AgroButton(
                      label: esNuevo ? 'Agregar' : 'Aplicar cambios',
                      icono: Icons.check_rounded,
                      expandido: true,
                      onTap: () {
                        if (servCtrl.text.trim().isEmpty) {
                          mostrarAgroSnack(ctx, 'Escribí el servicio',
                              tipo: AgroSnackTipo.aviso);
                          return;
                        }
                        Navigator.pop(ctx, 'ok');
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    if (resultado == 'ok') {
      final double cant = FormatoPresupuesto.parseNumero(cantCtrl.text);
      final double pu = FormatoPresupuesto.parseNumero(puCtrl.text);
      it.servicio = servCtrl.text.trim();
      it.detalle = detCtrl.text.trim();
      it.cantidad = cant;
      it.unidad = unidadCtrl.text.trim();
      it.precioUnitario = pu;
      it.importe = pu > 0 ? cant * pu : FormatoPresupuesto.parseNumero(impCtrl.text);
      _marcar(() {
        if (esNuevo) {
          _p.items.add(it);
        } else {
          _p.items[indice!] = it;
        }
      });
    } else if (resultado == 'quitar' && !esNuevo) {
      _marcar(() => _p.items.removeAt(indice!));
    }

    // Se liberan después de la animación de cierre del panel.
    Future.delayed(const Duration(milliseconds: 600), () {
      for (final c in [servCtrl, detCtrl, cantCtrl, unidadCtrl, puCtrl, impCtrl]) {
        c.dispose();
      }
    });
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _p.fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Fecha del presupuesto',
    );
    if (f != null) _marcar(() => _p.fecha = f);
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _alSalir,
      child: Scaffold(
        backgroundColor: AgroTheme.colorBg,
        appBar: AgroAppBar(
          titulo: widget.esNuevo && !_guardadoAlgunaVez
              ? 'Nuevo presupuesto'
              : 'Presupuesto N° ${_p.numeroTexto}',
          subtitulo: _cambios ? 'Cambios sin guardar' : 'Guardado',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: AgroTheme.colorText),
            onPressed: _alSalir,
          ),
          acciones: [
            AgroIconButton(
              icono: Icons.visibility_outlined,
              tooltip: 'Vista previa del PDF',
              onTap: _vistaPrevia,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, c) {
            final bool ancho = c.maxWidth >= 900;
            final formulario = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _seccionDatos(),
                const SizedBox(height: 14),
                _seccionServicios(),
                const SizedBox(height: 14),
                _seccionImpuestos(),
                const SizedBox(height: 14),
                _seccionCondiciones(),
              ],
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              child: AgroContent(
                child: ancho
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: formulario),
                          const SizedBox(width: 18),
                          SizedBox(width: 340, child: _resumen()),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          formulario,
                          const SizedBox(height: 14),
                          _resumen(),
                        ],
                      ),
              ),
            );
          },
        ),
        bottomNavigationBar: _barraAcciones(),
      ),
    );
  }

  Widget _tarjeta({
    required String titulo,
    required IconData icono,
    String? subtitulo,
    Widget? trailing,
    required Widget child,
  }) {
    return AgroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgroSectionHeader(
            titulo: titulo,
            subtitulo: subtitulo,
            icono: icono,
            trailing: trailing,
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _seccionDatos() {
    return _tarjeta(
      titulo: 'Datos generales',
      icono: Icons.description_outlined,
      subtitulo: 'Encabezado del documento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _tituloCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: agroInputDecoration(
                label: 'Título del documento', icono: Icons.title_rounded),
            onChanged: (_) => _marcar(() {}),
          ),
          const SizedBox(height: 8),
          _ChipsSugeridos(
            opciones: const [
              'PEDIDO DE COTIZACIÓN',
              'PRESUPUESTO',
              'COTIZACIÓN DE SERVICIOS',
            ],
            seleccionado: _tituloCtrl.text.trim(),
            onTap: (t) => _marcar(() => _tituloCtrl.text = t),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _elegirFecha,
                  borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  child: InputDecorator(
                    decoration: agroInputDecoration(
                        label: 'Fecha', icono: Icons.event_rounded),
                    child: Text(FormatoPresupuesto.fechaLarga(_p.fecha),
                        style: AgroText.cuerpo),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: InputDecorator(
                  decoration: agroInputDecoration(label: 'N°'),
                  child: Text(_p.numeroTexto, style: AgroText.valor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _destCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: agroInputDecoration(
              label: 'Destinatario',
              hint: 'Empresa o persona a quien va dirigido',
              icono: Icons.apartment_rounded,
            ),
            onChanged: (_) => _marcar(() {}),
          ),
          _sugerenciasDe(_destCtrl, _destinatariosPrevios),
          const SizedBox(height: 12),
          TextField(
            controller: _emisorCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: agroInputDecoration(
              label: 'Emite (aparece en negrita)',
              hint: 'Ej: Agropecuaria Natalini S.R.L.',
              icono: Icons.business_center_outlined,
            ),
            onChanged: (_) => _marcar(() {}),
          ),
          _sugerenciasDe(_emisorCtrl, _emisoresPrevios),
          const SizedBox(height: 12),
          TextField(
            controller: _firmanteCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: agroInputDecoration(
              label: 'Firma (opcional)',
              hint: 'Ej: Ing. Agr. Aníbal …',
              icono: Icons.draw_outlined,
            ),
            onChanged: (_) => _marcar(() {}),
          ),
        ],
      ),
    );
  }

  Widget _sugerenciasDe(TextEditingController ctrl, List<String> opciones) {
    final q = ctrl.text.trim().toLowerCase();
    final lista = opciones
        .where((o) =>
            o.toLowerCase() != q && (q.isEmpty || o.toLowerCase().contains(q)))
        .take(6)
        .toList();
    if (lista.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _ChipsSugeridos(
        opciones: lista,
        icono: Icons.history_rounded,
        onTap: (v) => _marcar(() {
          ctrl.text = v;
          ctrl.selection = TextSelection.collapsed(offset: v.length);
        }),
      ),
    );
  }

  Widget _seccionServicios() {
    return _tarjeta(
      titulo: 'Servicios',
      icono: Icons.design_services_outlined,
      subtitulo: _p.items.isEmpty
          ? 'Agregá lo que vas a cotizar'
          : '${_p.items.length} ${_p.items.length == 1 ? 'renglón' : 'renglones'}',
      trailing: AgroButton(
        label: 'Agregar',
        icono: Icons.add_rounded,
        compacto: true,
        onTap: () => _editarItem(),
      ),
      child: _p.items.isEmpty
          ? const AgroEmptyState(
              icono: Icons.playlist_add_rounded,
              titulo: 'Sin servicios',
              mensaje: 'Tocá "Agregar" para cargar el primer renglón.',
            )
          : Column(
              children: [
                for (int i = 0; i < _p.items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _ItemTile(
                    item: _p.items[i],
                    moneda: _p.moneda,
                    ivaModo: _p.ivaModo,
                    onTap: () => _editarItem(i),
                    onSubir: i == 0
                        ? null
                        : () => _marcar(() {
                              final x = _p.items.removeAt(i);
                              _p.items.insert(i - 1, x);
                            }),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _seccionImpuestos() {
    return _tarjeta(
      titulo: 'Moneda e IVA',
      icono: Icons.percent_rounded,
      subtitulo: 'Cómo se muestran los valores',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgroSegmentedTabs(
            seleccionado: _p.moneda,
            onChanged: (m) => _marcar(() => _p.moneda = m),
            items: const [
              AgroTabItem(
                  id: Moneda.ars, label: 'Pesos \$', icono: Icons.payments_outlined),
              AgroTabItem(
                  id: Moneda.usd,
                  label: 'Dólares U\$S',
                  icono: Icons.attach_money_rounded,
                  color: AgroColors.info),
            ],
          ),
          const SizedBox(height: 12),
          AgroSegmentedTabs(
            seleccionado: _p.ivaModo,
            onChanged: (m) => _marcar(() => _p.ivaModo = m),
            items: const [
              AgroTabItem(
                  id: IvaModo.masIva, label: '+ IVA', icono: Icons.add_rounded),
              AgroTabItem(
                  id: IvaModo.incluido,
                  label: 'Incluido',
                  icono: Icons.check_rounded),
              AgroTabItem(
                  id: IvaModo.discriminado,
                  label: 'Discriminar',
                  icono: Icons.receipt_long_rounded),
            ],
          ),
          const SizedBox(height: 10),
          Text(_ayudaIva(), style: AgroText.secundario),
          if (_p.ivaModo != IvaModo.masIva) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Alícuota', style: AgroText.label),
                const SizedBox(width: 10),
                for (final a in const [21.0, 10.5]) ...[
                  ChoiceChip(
                    label: Text('${FormatoPresupuesto.numero(a)}%'),
                    selected: _p.ivaPorc == a,
                    selectedColor: AgroColors.primarioSoft,
                    onSelected: (_) => _marcar(() => _p.ivaPorc = a),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _ayudaIva() {
    switch (_p.ivaModo) {
      case IvaModo.incluido:
        return 'Los valores cargados ya incluyen IVA. El PDF muestra "(IVA incluido)".';
      case IvaModo.discriminado:
        return 'Se suma el IVA a los valores: el PDF muestra subtotal, IVA y total.';
      default:
        return 'Los valores se muestran como "\$ 150.000 + IVA", igual que tu modelo.';
    }
  }

  Widget _seccionCondiciones() {
    return _tarjeta(
      titulo: 'Condiciones y cierre',
      icono: Icons.handshake_outlined,
      subtitulo: 'Opcional',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Validez de la oferta', style: AgroText.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in const [7, 15, 30, 0])
                ChoiceChip(
                  label: Text(d == 0 ? 'No mostrar' : '$d días'),
                  selected: _p.validezDias == d,
                  selectedColor: AgroColors.primarioSoft,
                  onSelected: (_) => _marcar(() => _p.validezDias = d),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _condCtrl,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: agroInputDecoration(
              label: 'Condiciones / observaciones',
              hint: 'Una por línea. Ej: Forma de pago: transferencia a 15 días',
              icono: Icons.rule_rounded,
            ),
            onChanged: (_) => _marcar(() {}),
          ),
          const SizedBox(height: 8),
          _ChipsSugeridos(
            opciones: const [
              'Forma de pago: transferencia bancaria.',
              'Pago contra entrega del servicio.',
              'No incluye el costo de los productos fitosanitarios.',
              'Sujeto a condiciones climáticas aptas para la aplicación.',
            ],
            icono: Icons.add_rounded,
            onTap: (t) => _marcar(() {
              final actual = _condCtrl.text.trim();
              _condCtrl.text = actual.isEmpty ? t : '$actual\n$t';
            }),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _cierreCtrl,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: agroInputDecoration(
                label: 'Texto de cierre', icono: Icons.short_text_rounded),
            onChanged: (_) => _marcar(() {}),
          ),
        ],
      ),
    );
  }

  Widget _resumen() {
    Color colorEstado(String e) {
      switch (e) {
        case EstadoPresupuesto.enviado:
          return AgroColors.info;
        case EstadoPresupuesto.aceptado:
          return AgroColors.ok;
        case EstadoPresupuesto.rechazado:
          return AgroColors.danger;
        default:
          return AgroColors.neutral;
      }
    }

    return AgroCard(
      accentColor: AgroColors.primario,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('RESUMEN', style: AgroText.overline),
          const SizedBox(height: 10),
          if (_p.ivaModo == IvaModo.discriminado ||
              _p.ivaModo == IvaModo.incluido) ...[
            _filaResumen('Subtotal (neto)',
                FormatoPresupuesto.importe(_p.subtotal, _p.moneda)),
            _filaResumen('IVA ${FormatoPresupuesto.numero(_p.ivaPorc)}%',
                FormatoPresupuesto.importe(_p.iva, _p.moneda)),
            const Divider(height: 18, color: AgroTheme.colorBorder),
          ],
          const Text('Valor total del servicio', style: AgroText.label),
          const SizedBox(height: 4),
          Text(
            _p.totalTexto,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AgroColors.primario,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Estado', style: AgroText.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: EstadoPresupuesto.todos.map((e) {
              final sel = _p.estado == e;
              final col = colorEstado(e);
              return ChoiceChip(
                label: Text(EstadoPresupuesto.etiqueta(e)),
                selected: sel,
                selectedColor: col.withOpacity(0.15),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: sel ? col : AgroTheme.colorTextSecondary,
                ),
                onSelected: (_) => _marcar(() => _p.estado = e),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          AgroButton(
            label: 'Ver PDF',
            icono: Icons.picture_as_pdf_outlined,
            tipo: AgroButtonTipo.secundario,
            expandido: true,
            onTap: _vistaPrevia,
          ),
        ],
      ),
    );
  }

  Widget _filaResumen(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(child: Text(k, style: AgroText.secundario)),
            Text(v, style: AgroText.valor.copyWith(fontSize: 13)),
          ],
        ),
      );

  Widget _barraAcciones() {
    return AgroBottomExport(
      child: Row(
        children: [
          Expanded(
            child: AgroButton(
              label: 'Guardar',
              icono: Icons.save_outlined,
              tipo: AgroButtonTipo.secundario,
              cargando: _guardando,
              expandido: true,
              onTap: _guardando ? null : () => _guardar(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: AgroButton(
              label: 'Compartir PDF',
              icono: Icons.ios_share_rounded,
              cargando: _compartiendo,
              expandido: true,
              onTap: _compartiendo ? null : _compartir,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WIDGETS AUXILIARES
// ============================================================

class _ItemTile extends StatelessWidget {
  final ItemPresupuesto item;
  final String moneda;
  final String ivaModo;
  final VoidCallback onTap;
  final VoidCallback? onSubir;

  const _ItemTile({
    required this.item,
    required this.moneda,
    required this.ivaModo,
    required this.onTap,
    this.onSubir,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AgroTheme.colorBg,
      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Row(
            children: [
              const AgroIconBox(icono: Icons.agriculture_outlined, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.servicio.isEmpty ? 'Sin descripción' : item.servicio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.valor.copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        item.cantidadTexto,
                        if (item.usaPrecioUnitario)
                          '${FormatoPresupuesto.importe(item.precioUnitario, moneda)} c/u',
                        if (item.detalle.isNotEmpty) item.detalle,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.secundario.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                FormatoPresupuesto.importeConIva(item.importe, moneda, ivaModo),
                style: AgroText.valor
                    .copyWith(fontSize: 13.5, color: AgroColors.primario),
              ),
              if (onSubir != null)
                IconButton(
                  tooltip: 'Subir',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward_rounded,
                      size: 18, color: AgroTheme.colorTextSecondary),
                  onPressed: onSubir,
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipsSugeridos extends StatelessWidget {
  final List<String> opciones;
  final ValueChanged<String> onTap;
  final String? seleccionado;
  final IconData? icono;

  const _ChipsSugeridos({
    required this.opciones,
    required this.onTap,
    this.seleccionado,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opciones.map((o) {
          final sel = seleccionado != null &&
              seleccionado!.toLowerCase() == o.toLowerCase();
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: icono == null
                  ? null
                  : Icon(icono, size: 14, color: AgroTheme.colorTextSecondary),
              label: Text(o),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sel ? AgroColors.primario : AgroTheme.colorText,
              ),
              backgroundColor:
                  sel ? AgroColors.primarioSoft : AgroTheme.colorSurface,
              side: BorderSide(
                  color: sel ? AgroColors.primario : AgroTheme.colorBorder),
              onPressed: () => onTap(o),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================
// VISTA PREVIA DEL PDF (imprimir / compartir desde el visor)
// ============================================================

class VistaPreviaPresupuestoPage extends StatelessWidget {
  final Presupuesto presupuesto;

  const VistaPreviaPresupuestoPage({super.key, required this.presupuesto});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: 'Vista previa',
        subtitulo:
            'N° ${presupuesto.numeroTexto} · ${presupuesto.destinatario}',
      ),
      body: PdfPreview(
        build: (_) => PresupuestoPdf.generar(presupuesto),
        pdfFileName: PresupuestoPdf.nombreArchivo(presupuesto),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        loadingWidget: const AgroLoading(mensaje: 'Generando PDF…'),
      ),
    );
  }
}
