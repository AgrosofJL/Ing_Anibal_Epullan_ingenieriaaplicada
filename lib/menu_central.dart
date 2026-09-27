// ignore_for_file: deprecated_member_use

import 'package:aplicaciones_foliares/aplicaciones/aplica_productor.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base/base.dart';
import 'campo/menu_campo.dart';
import 'constantes/tema.dart';
import 'loguer.dart';
import 'productores/productores.dart';
import 'productos/catalogo.dart';
import 'reportes/menu_reportes.dart';
import 'servicios/sincronizar.dart';
import 'servicios/sync_esquema.dart';
import 'widgets/agro_ui.dart';

class MenuCentral extends StatefulWidget {
  const MenuCentral({super.key});

  @override
  State<MenuCentral> createState() => _MenuCentralState();
}

class _MenuCentralState extends State<MenuCentral>
    with SingleTickerProviderStateMixin {
  String _userName = "Usuario";
  String _userRole = "OPERARIO";
  int _userCodProductor = 0;

  List<Map<String, dynamic>> _listaProductores = [];
  int? _selectedCodProductor;
  Map<String, dynamic>? _productorActivo;

  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    ServicioSincronizacion.estaSincronizando.addListener(_handleSyncAnimation);
    // Triggers de sincronización (borrados / cambios) + contador de pendientes.
    SyncEsquema.asegurar()
        .then((_) => ServicioSincronizacion.actualizarPendientes())
        .catchError((_) {});
    _inicializarSesionYContexto();
  }

  void _handleSyncAnimation() {
    if (ServicioSincronizacion.estaSincronizando.value) {
      _rotationController.repeat();
    } else {
      _rotationController.stop();
      _rotationController.reset();
      _inicializarSesionYContexto();
    }
  }

  @override
  void dispose() {
    ServicioSincronizacion.estaSincronizando
        .removeListener(_handleSyncAnimation);
    _rotationController.dispose();
    super.dispose();
  }

  // ============================================================
  // LÓGICA (sin cambios)
  // ============================================================

  Future<void> _inicializarSesionYContexto() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName') ?? "Juan Sosa";
      _userRole =
          (prefs.getString('userRole') ?? "OPERARIO").toUpperCase().trim();
      _userCodProductor = prefs.getInt('userCodProductor') ?? 0;
    });

    await _cargarProductores();
  }

  Future<void> _cargarProductores() async {
    final db = await DatabaseHelper.instance.database;
    List<Map<String, dynamic>> prods = [];

    if (_esIngenieroOAdmin) {
      prods = await db.query(
        'productores',
        where: 'estado = ?',
        whereArgs: ['ACTIVO'],
        orderBy: 'productor ASC',
      );
    } else {
      prods = await db.query(
        'productores',
        where: 'cod_productor = ? AND estado = ?',
        whereArgs: [_userCodProductor, 'ACTIVO'],
        limit: 1,
      );
    }

    if (!mounted) return;

    setState(() {
      _listaProductores = prods;

      if (_esIngenieroOAdmin) {
        if (_listaProductores.isNotEmpty) {
          if (_selectedCodProductor == null ||
              !_listaProductores
                  .any((p) => p['cod_productor'] == _selectedCodProductor)) {
            _selectedCodProductor =
                _listaProductores.first['cod_productor'] as int;
          }
          _productorActivo = _listaProductores.firstWhere(
            (p) => p['cod_productor'] == _selectedCodProductor,
            orElse: () => _listaProductores.first,
          );
        } else {
          _productorActivo = null;
          _selectedCodProductor = null;
        }
      } else {
        _selectedCodProductor = _userCodProductor;
        if (_listaProductores.isNotEmpty) {
          _productorActivo = _listaProductores.first;
        } else {
          _productorActivo = {
            'cod_productor': _userCodProductor,
            'productor': 'Establecimiento Propio',
            'cuit': 'S/D',
            'renspa': 'S/D',
            'localidad': 'Campo',
          };
        }
      }
    });
  }

  void _cambiarProductor(int? nuevoCod) {
    if (nuevoCod == null || !_esIngenieroOAdmin) return;
    setState(() {
      _selectedCodProductor = nuevoCod;
      _productorActivo = _listaProductores.firstWhere(
        (p) => p['cod_productor'] == nuevoCod,
        orElse: () => _listaProductores.first,
      );
    });
  }

  Future<void> _logout() async {
    final ok = await confirmarAgro(
      context: context,
      titulo: 'Cerrar sesión',
      mensaje:
          '¿Querés salir de AgroSoft J&L? Los datos no sincronizados quedan guardados en este dispositivo.',
      confirmar: 'Salir',
      icono: Icons.logout_rounded,
    );
    if (!ok) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoguerScreen()),
      );
    }
  }

  Future<void> _sincronizar() async {
    mostrarAgroSnack(context, 'Sincronizando con el servidor de AgroSoft J&L…',
        duracion: const Duration(milliseconds: 1200));

    final bool exito = await ServicioSincronizacion.sincronizarEnSegundoPlano();

    if (!mounted) return;
    final int errores = ServicioSincronizacion.ultimoResultado?.errores ?? 0;
    mostrarAgroSnack(
      context,
      !exito
          ? 'No se pudo sincronizar. Verificá la conexión.'
          : (errores > 0
              ? 'Sincronizado, pero $errores ${errores == 1 ? 'registro quedó pendiente' : 'registros quedaron pendientes'} (se reintenta en la próxima).'
              : '¡Datos sincronizados correctamente!'),
      tipo: !exito
          ? AgroSnackTipo.error
          : (errores > 0 ? AgroSnackTipo.aviso : AgroSnackTipo.ok),
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final txt = DateFormat("EEEE d 'de' MMMM 'de' yyyy", 'es').format(now);
    return txt.isEmpty ? txt : txt[0].toUpperCase() + txt.substring(1);
  }

  String get _saludo {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buen día';
    if (h < 20) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String get _primerNombre {
    final partes = _userName.trim().split(' ');
    return partes.isEmpty ? _userName : partes.first;
  }

  bool get _esIngenieroOAdmin =>
      _userRole == 'INGENIERO' || _userRole == 'ADMIN' || _userRole == 'ADM';

  int get _codProductorActivo =>
      _selectedCodProductor ??
      (_productorActivo?['cod_productor'] as int? ?? _userCodProductor);

  String get _nombreProductorActivo =>
      _productorActivo?['productor'] ?? 'Establecimiento Propio';

  void _abrir(Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
  }

  // ============================================================
  // SELECTOR DE PRODUCTOR (panel con buscador)
  // ============================================================

  void _abrirSelectorProductor() {
    if (!_esIngenieroOAdmin || _listaProductores.isEmpty) return;
    String filtro = '';
    final ctrl = TextEditingController();

    mostrarAgroPanel<void>(
      context: context,
      titulo: 'Cambiar productor',
      subtitulo: '${_listaProductores.length} establecimientos activos',
      icono: Icons.swap_horiz_rounded,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModal) {
            final q = filtro.toLowerCase();
            final lista = _listaProductores.where((p) {
              if (q.isEmpty) return true;
              return (p['productor'] ?? '').toString().toLowerCase().contains(q) ||
                  (p['cuit'] ?? '').toString().toLowerCase().contains(q) ||
                  (p['localidad'] ?? '').toString().toLowerCase().contains(q);
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AgroSearchField(
                  controller: ctrl,
                  hint: 'Buscar por nombre, CUIT o localidad…',
                  onChanged: (v) => setModal(() => filtro = v),
                ),
                const SizedBox(height: 12),
                if (lista.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Sin coincidencias',
                        textAlign: TextAlign.center,
                        style: AgroText.secundario),
                  ),
                ...lista.map((p) {
                  final cod = p['cod_productor'] as int;
                  final sel = cod == _selectedCodProductor;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AgroCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      borderColor: sel ? AgroColors.primario : null,
                      color: sel ? AgroColors.primarioSoft : null,
                      onTap: () {
                        _cambiarProductor(cod);
                        Navigator.pop(ctx);
                      },
                      child: Row(
                        children: [
                          AgroIconBox(
                            icono: Icons.agriculture_rounded,
                            size: 38,
                            color: sel
                                ? AgroColors.primario
                                : AgroTheme.colorTextSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['productor']?.toString() ?? 'S/N',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AgroTheme.colorText,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'CUIT ${p['cuit'] ?? 'S/D'} · ${p['localidad'] ?? 'Sin localidad'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AgroText.secundario,
                                ),
                              ],
                            ),
                          ),
                          if (sel)
                            const Icon(Icons.check_circle_rounded,
                                color: AgroColors.primario, size: 22),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final esMovil = AgroBreakpoints.esMovil(context);

    final modulos = <_ModuloDef>[
      _ModuloDef(
        titulo: "Órdenes de Aplicación",
        subtitulo: "RECETAS & CALDOS",
        descripcion:
            "Recetas fitosanitarias, dosificación por máquina y hectárea, registro de labores.",
        icono: Icons.science_outlined,
        color: const Color(0xFF1E6B4C),
        tag: "Labor activa",
        onTap: () => _abrir(AplicaProductorScreen(
          codProductor: _codProductorActivo,
          nombreProductor: _nombreProductorActivo,
        )),
      ),
      _ModuloDef(
        titulo: "Gestión en Campo",
        subtitulo: "MONITOREO & FENOLOGÍA",
        descripcion:
            "Monitoreo fenológico, ubicación GPS de trampas y catastro de plantación.",
        icono: Icons.park_outlined,
        color: const Color(0xFF0F9D6B),
        tag: "Sanidad",
        onTap: () => _abrir(MenuCampoScreen(
          codProductor: _codProductorActivo,
          nombreProductor: _nombreProductorActivo,
        )),
      ),
      _ModuloDef(
        titulo: "Depósito & Pañol",
        subtitulo: "STOCK & CATÁLOGO",
        descripcion:
            "Existencias por galpón, ingresos con vencimiento, consumos y mermas.",
        icono: Icons.warehouse_outlined,
        color: const Color(0xFF2F6FDB),
        tag: "Insumos",
        onTap: () => _abrir(CatalogoInsumosScreen(
          codProductor: _codProductorActivo,
          nombreProductor: _nombreProductorActivo,
        )),
      ),
      _ModuloDef(
        titulo: "Reportería",
        subtitulo: "REGISTROS & AUDITORÍA",
        descripcion:
            "Cuaderno de campo BPA, capturas de trampeo, curvas fenológicas y Excel.",
        icono: Icons.insights_outlined,
        color: const Color(0xFFC77700),
        tag: "Oficial BPA",
        onTap: () => _abrir(MenuReportesScreen(
          codProductor: _codProductorActivo,
          nombreProductor: _nombreProductorActivo,
        )),
      ),
      if (_userRole == 'ADMIN' || _userRole == 'INGENIERO')
        _ModuloDef(
          titulo: "Gestión de Productores",
          subtitulo: "ADMINISTRACIÓN",
          descripcion:
              "Alta y edición de productores, RENSPA, CUIT y usuarios.",
          icono: Icons.badge_outlined,
          color: const Color(0xFF8A6A1E),
          tag: "Panel global",
          esAdmin: true,
          onTap: () => _abrir(const ProductoresScreen()),
        ),
    ];

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(esMovil),
            Expanded(
              child: RefreshIndicator(
                color: AgroColors.primario,
                onRefresh: _inicializarSesionYContexto,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 20, bottom: 32),
                  child: AgroContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Saludo
                        Text(_getFormattedDate(), style: AgroText.secundario),
                        const SizedBox(height: 4),
                        Text(
                          "$_saludo, $_primerNombre",
                          style: TextStyle(
                            fontSize: esMovil ? 22 : 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AgroTheme.colorText,
                          ),
                        ),
                        const SizedBox(height: 18),

                        _buildTarjetaProductor(),

                        const SizedBox(height: 28),
                        AgroSectionHeader(
                          titulo: "Módulos",
                          subtitulo: _esIngenieroOAdmin
                              ? "Trabajando sobre $_nombreProductorActivo"
                              : "Herramientas para tu establecimiento",
                        ),
                        const SizedBox(height: 14),

                        LayoutBuilder(
                          builder: (context, c) {
                            final cols = c.maxWidth >= 980
                                ? 3
                                : (c.maxWidth >= 620 ? 2 : 1);
                            const gap = 14.0;
                            final w =
                                ((c.maxWidth - gap * (cols - 1)) / cols)
                                    .floorToDouble();
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: modulos
                                  .map((m) => SizedBox(
                                        width: w,
                                        child: ModuloCardItem(
                                          titulo: m.titulo,
                                          subtitulo: m.subtitulo,
                                          descripcion: m.descripcion,
                                          icono: m.icono,
                                          accentColor: m.color,
                                          tag: m.tag,
                                          esAdmin: m.esAdmin,
                                          compacto: cols == 1,
                                          onTap: m.onTap,
                                        ),
                                      ))
                                  .toList(),
                            );
                          },
                        ),

                        const SizedBox(height: 36),
                        const Center(
                          child: Text(
                            "AgroSoft J&L · Soluciones Integrales",
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AgroTheme.colorTextSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool esMovil) {
    return Container(
      decoration: const BoxDecoration(
        color: AgroTheme.colorSurface,
        border: Border(bottom: BorderSide(color: AgroTheme.colorBorder)),
      ),
      child: AgroContent(
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AgroTheme.colorSurface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AgroTheme.colorBorder),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset(
                    'logo/logo_anibal.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Image.asset(
                      'logo/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.eco_rounded,
                        color: AgroColors.primario,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "AgroSoft J&L",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AgroTheme.colorText,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AgroTheme.colorTextSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AgroBadge(
                          texto: _userRole,
                          color: _esIngenieroOAdmin
                              ? AgroColors.warn
                              : AgroColors.primario,
                          fondo: _esIngenieroOAdmin
                              ? AgroColors.warnSoft
                              : AgroColors.primarioSoft,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<bool>(
                valueListenable: ServicioSincronizacion.estaSincronizando,
                builder: (context, isSyncing, _) {
                  final boton = Material(
                    color: isSyncing
                        ? AgroColors.primarioSoft
                        : AgroTheme.colorSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AgroTheme.colorBorder),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: isSyncing ? null : _sincronizar,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: esMovil ? 10 : 14, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RotationTransition(
                              turns: _rotationController,
                              child: Icon(
                                Icons.sync_rounded,
                                size: 20,
                                color: isSyncing
                                    ? AgroColors.primario
                                    : AgroTheme.colorTextSecondary,
                              ),
                            ),
                            if (!esMovil) ...[
                              const SizedBox(width: 8),
                              Text(
                                isSyncing ? 'Sincronizando…' : 'Sincronizar',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isSyncing
                                      ? AgroColors.primario
                                      : AgroTheme.colorText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                  return ValueListenableBuilder<int>(
                    valueListenable: ServicioSincronizacion.pendientes,
                    builder: (context, pend, _) {
                      return Tooltip(
                        message: pend > 0
                            ? '$pend ${pend == 1 ? 'cambio pendiente' : 'cambios pendientes'} de subir'
                            : 'Sincronizar datos',
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            boton,
                            if (pend > 0 && !isSyncing)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  constraints: const BoxConstraints(
                                      minWidth: 18, minHeight: 18),
                                  decoration: BoxDecoration(
                                    color: AgroColors.warn,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: AgroTheme.colorSurface,
                                        width: 1.5),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    pend > 99 ? '99+' : '$pend',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
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
              ),
              const SizedBox(width: 8),
              AgroIconButton(
                icono: Icons.logout_rounded,
                tooltip: 'Cerrar sesión',
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTarjetaProductor() {
    final String nombre = _productorActivo?['productor'] ?? 'Sin productor';
    final String cuit = _productorActivo?['cuit'] ?? 'S/D';
    final String renspa = _productorActivo?['renspa'] ?? 'S/D';
    final String localidad =
        _productorActivo?['localidad'] ?? 'Ubicación no especificada';
    final bool puedeCambiar =
        _esIngenieroOAdmin && _listaProductores.length > 1;

    return AgroCard(
      onTap: puedeCambiar ? _abrirSelectorProductor : null,
      padding: const EdgeInsets.all(18),
      accentColor: AgroColors.primario,
      child: LayoutBuilder(
        builder: (context, c) {
          final ancho = c.maxWidth >= 640;

          final info = Row(
            children: [
              const AgroIconBox(
                  icono: Icons.agriculture_rounded, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _esIngenieroOAdmin
                          ? "CLIENTE EN GESTIÓN"
                          : "MI ESTABLECIMIENTO",
                      style: AgroText.overline,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _productorActivo == null && _esIngenieroOAdmin
                          ? 'No hay productores activos'
                          : nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AgroTheme.colorText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final tags = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AgroTag(icono: Icons.fingerprint_rounded, texto: "CUIT $cuit"),
              AgroTag(icono: Icons.badge_outlined, texto: "RENSPA $renspa"),
              AgroTag(icono: Icons.location_on_outlined, texto: localidad),
            ],
          );

          final boton = puedeCambiar
              ? AgroButton(
                  label: 'Cambiar productor',
                  icono: Icons.swap_horiz_rounded,
                  tipo: AgroButtonTipo.secundario,
                  compacto: true,
                  expandido: !ancho,
                  onTap: _abrirSelectorProductor,
                )
              : null;

          if (ancho) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: info),
                    if (boton != null) ...[const SizedBox(width: 12), boton],
                  ],
                ),
                const SizedBox(height: 14),
                tags,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info,
              const SizedBox(height: 14),
              tags,
              if (boton != null) ...[const SizedBox(height: 14), boton],
            ],
          );
        },
      ),
    );
  }
}

class _ModuloDef {
  final String titulo;
  final String subtitulo;
  final String descripcion;
  final IconData icono;
  final Color color;
  final String tag;
  final bool esAdmin;
  final VoidCallback onTap;

  _ModuloDef({
    required this.titulo,
    required this.subtitulo,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.tag,
    this.esAdmin = false,
    required this.onTap,
  });
}

// ============================================================
// TARJETA DE MÓDULO
// ============================================================

class ModuloCardItem extends StatefulWidget {
  final String titulo;
  final String subtitulo;
  final String descripcion;
  final IconData icono;
  final Color accentColor;
  final String tag;
  final bool esAdmin;
  final bool compacto;
  final VoidCallback onTap;

  const ModuloCardItem({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.descripcion,
    required this.icono,
    required this.accentColor,
    required this.tag,
    this.esAdmin = false,
    this.compacto = false,
    required this.onTap,
  });

  @override
  State<ModuloCardItem> createState() => _ModuloCardItemState();
}

class _ModuloCardItemState extends State<ModuloCardItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.accentColor;

    // Versión compacta (celular): fila horizontal tipo lista.
    final Widget contenidoCompacto = Row(
      children: [
        AgroIconBox(icono: widget.icono, color: c, size: 50),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.subtitulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: c,
                    letterSpacing: 0.7,
                  )),
              const SizedBox(height: 2),
              Text(widget.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.tituloCard),
              const SizedBox(height: 3),
              Text(widget.descripcion,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.secundario.copyWith(fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right_rounded,
            color: _isHovered ? c : AgroTheme.colorTextSecondary),
      ],
    );

    // Versión amplia (tablet / web): tarjeta vertical.
    final Widget contenidoAmplio = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AgroIconBox(icono: widget.icono, color: c, size: 48),
            const Spacer(),
            AgroBadge(texto: widget.tag, color: c),
          ],
        ),
        const SizedBox(height: 16),
        Text(widget.subtitulo,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: c,
              letterSpacing: 0.7,
            )),
        const SizedBox(height: 3),
        Text(widget.titulo, style: AgroText.tituloCard.copyWith(fontSize: 16.5)),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: Text(widget.descripcion,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AgroText.secundario.copyWith(fontSize: 12.5)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('Abrir módulo',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: c,
                )),
            const SizedBox(width: 4),
            AnimatedSlide(
              duration: const Duration(milliseconds: 160),
              offset: Offset(_isHovered ? 0.3 : 0, 0),
              child: Icon(Icons.arrow_forward_rounded, size: 16, color: c),
            ),
          ],
        ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: _isPressed ? 0.985 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.all(widget.compacto ? 16 : 20),
            decoration: BoxDecoration(
              color: AgroTheme.colorSurface,
              borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
              border: Border.all(
                color: _isHovered || _isPressed
                    ? c.withOpacity(0.45)
                    : AgroTheme.colorBorder,
              ),
              boxShadow:
                  _isHovered ? AgroColors.sombraHover : AgroColors.sombraSuave,
            ),
            child: widget.compacto ? contenidoCompacto : contenidoAmplio,
          ),
        ),
      ),
    );
  }
}
