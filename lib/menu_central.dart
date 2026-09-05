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
import 'widgets/soft_button.dart';

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
    _inicializarSesionYContexto();
  }

  void _handleSyncAnimation() {
    if (ServicioSincronizacion.estaSincronizando.value) {
      _rotationController.repeat();
    } else {
      _rotationController.stop();
      _rotationController.reset();
      _cargarProductores();
    }
  }

  @override
  void dispose() {
    ServicioSincronizacion.estaSincronizando
        .removeListener(_handleSyncAnimation);
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _inicializarSesionYContexto() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? "Juan Sosa";
      _userRole = (prefs.getString('userRole') ?? "OPERARIO").toUpperCase();
      _userCodProductor = prefs.getInt('userCodProductor') ?? 0;
    });

    await _cargarProductores();
  }

  Future<void> _cargarProductores() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> prods = await db.query(
      'productores',
      where: 'estado = ?',
      whereArgs: ['ACTIVO'],
      orderBy: 'productor ASC',
    );

    if (!mounted) return;

    setState(() {
      _listaProductores = prods;

      if (_esIngenieroOAdmin) {
        if (_listaProductores.isNotEmpty) {
          _selectedCodProductor ??=
              _listaProductores.first['cod_productor'] as int;
          _productorActivo = _listaProductores.firstWhere(
            (p) => p['cod_productor'] == _selectedCodProductor,
            orElse: () => _listaProductores.first,
          );
        }
      } else {
        _selectedCodProductor = _userCodProductor;
        _productorActivo = _listaProductores.firstWhere(
          (p) => p['cod_productor'] == _userCodProductor,
          orElse: () => {
            'productor': 'Establecimiento Propio',
            'cuit': 'S/D',
            'localidad': 'Campo',
          },
        );
      }
    });
  }

  void _cambiarProductor(int? nuevoCod) {
    if (nuevoCod == null) return;
    setState(() {
      _selectedCodProductor = nuevoCod;
      _productorActivo = _listaProductores.firstWhere(
        (p) => p['cod_productor'] == nuevoCod,
      );
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoguerScreen()),
      );
    }
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    return DateFormat("EEEE d 'DE' MMMM 'DE' yyyy", 'es')
        .format(now)
        .toUpperCase();
  }

  bool get _esIngenieroOAdmin =>
      _userRole == 'INGENIERO' || _userRole == 'ADMIN';

  int get _codProductorActivo =>
      _selectedCodProductor ??
      (_productorActivo?['cod_productor'] as int? ?? 1);

  String get _nombreProductorActivo =>
      _productorActivo?['productor'] ?? 'Establecimiento Propio';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      body: SafeArea(
        child: Column(
          children: [
            // =========================================================
            // BARRA SUPERIOR APPLE SOFT
            // =========================================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AgroTheme.colorSurface.withOpacity(0.92),
                border: const Border(
                  bottom: BorderSide(color: AgroTheme.colorBorder, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AgroTheme.colorSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AgroTheme.colorBorder),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'logo/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.eco_rounded,
                                    color: AgroTheme.colorAccent, size: 24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "AgroSoft J&L",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16.5,
                              color: AgroTheme.colorText,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Row(
                            children: [
                              Text(
                                _userName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  color: AgroTheme.colorTextSecondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _esIngenieroOAdmin
                                      ? AgroTheme.colorGoldSoft
                                      : AgroTheme.colorAccentSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _userRole,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: _esIngenieroOAdmin
                                        ? const Color(0xFF8A6A1E)
                                        : AgroTheme.colorAccentDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable:
                            ServicioSincronizacion.estaSincronizando,
                        builder: (context, isSyncing, _) {
                          return SoftButton(
                            isSecondary: true,
                            padding: const EdgeInsets.all(10),
                            borderRadius: 12,
                            onTap: isSyncing
                                ? null
                                : () => ServicioSincronizacion
                                    .sincronizarEnSegundoPlano(),
                            child: RotationTransition(
                              turns: _rotationController,
                              child: Icon(
                                Icons.sync_rounded,
                                size: 20,
                                color: isSyncing
                                    ? AgroTheme.colorAccentDark
                                    : AgroTheme.colorTextSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded,
                            size: 20, color: AgroTheme.colorTextSecondary),
                        onPressed: _logout,
                        tooltip: 'Cerrar sesión',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ==========================================
            // CONTENIDO PRINCIPAL
            // ==========================================
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getFormattedDate(),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AgroTheme.colorTextSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildTarjetaProductorProfesional(),

                    const SizedBox(height: 24),

                    const Text(
                      "Módulos Operativos",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AgroTheme.colorText,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _esIngenieroOAdmin
                          ? "Gestión técnica sobre el establecimiento de $_nombreProductorActivo."
                          : "Acciones agronómicas para tu campo.",
                      style: const TextStyle(
                        fontSize: 13,
                        color: AgroTheme.colorTextSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Grid Limpio con 4 módulos principales + Gestión si aplica
                    GridView.count(
                      crossAxisCount:
                          MediaQuery.of(context).size.width > 600 ? 2 : 1,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio:
                          MediaQuery.of(context).size.width > 600 ? 1.6 : 2.2,
                      children: [
                        ModuloCardItem(
                          titulo: "Nueva Receta",
                          descripcion:
                              "Carga de aplicaciones foliares, dosificación de máquina y hectárea.",
                          icono: Icons.note_alt_outlined,
                          esAdmin: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AplicaProductorScreen()),
                            );
                          },
                        ),
                        ModuloCardItem(
                          titulo: "Gestión en Campo",
                          descripcion:
                              "Monitoreo fenológico, ubicación de trampas, capturas y cuarteles.",
                          icono: Icons.park_outlined,
                          esAdmin: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MenuCampoScreen(
                                  codProductor: _codProductorActivo,
                                  nombreProductor: _nombreProductorActivo,
                                ),
                              ),
                            );
                          },
                        ),
                        ModuloCardItem(
                          titulo: "Catálogo de Insumos",
                          descripcion:
                              "Stock disponible, principios activos y tiempos de carencia.",
                          icono: Icons.science_outlined,
                          esAdmin: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const CatalogoInsumosScreen()),
                            );
                          },
                        ),
                        // 💡 ACA ES LO NUEVO: Centro Unificado de Reportería
                        ModuloCardItem(
                          titulo: "Reportería",
                          descripcion:
                              "Cuaderno de campo, informes de capturas, fenología y Excel oficial.",
                          icono: Icons.assessment_outlined,
                          esAdmin: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MenuReportesScreen(
                                  codProductor: _codProductorActivo,
                                  nombreProductor: _nombreProductorActivo,
                                ),
                              ),
                            );
                          },
                        ),
                        if (_userRole == 'ADMIN' || _userRole == 'INGENIERO')
                          ModuloCardItem(
                            titulo: "Gestión de Productores",
                            descripcion:
                                "Administración de RENSPA, CUITs y usuarios independientes.",
                            icono: Icons.badge_outlined,
                            esAdmin: true,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ProductoresScreen()),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    const Center(
                      child: Text(
                        "AgroSoft J&L · Soluciones Integrales",
                        style: TextStyle(
                          fontSize: 12,
                          color: AgroTheme.colorTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaProductorProfesional() {
    final String nombre = _productorActivo?['productor'] ?? 'Sin Productor';
    final String cuit = _productorActivo?['cuit'] ?? 'S/D';
    final String renspa = _productorActivo?['renspa'] ?? 'S/D';
    final String localidad =
        _productorActivo?['localidad'] ?? 'Ubicación no especificada';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AgroTheme.colorSurface,
        borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
        border: Border.all(color: AgroTheme.colorBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0x06141E18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _esIngenieroOAdmin
                          ? AgroTheme.colorGoldSoft
                          : AgroTheme.colorAccentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.agriculture_rounded,
                      color: _esIngenieroOAdmin
                          ? const Color(0xFF8A6A1E)
                          : AgroTheme.colorAccentDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _esIngenieroOAdmin
                            ? "CLIENTE EN GESTIÓN"
                            : "ESTABLECIMIENTO PRODUCTIVO",
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AgroTheme.colorTextSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AgroTheme.colorText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_esIngenieroOAdmin && _listaProductores.length > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AgroTheme.colorBorder),
                  ),
                  child: const Text(
                    "Cambiar",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AgroTheme.colorAccentDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_esIngenieroOAdmin && _listaProductores.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: AgroTheme.colorBg,
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                border: Border.all(color: AgroTheme.colorBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedCodProductor,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AgroTheme.colorText),
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    color: AgroTheme.colorText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                  items: _listaProductores.map((prod) {
                    final pNombre = prod['productor'] ?? 'S/N';
                    final pCuit = prod['cuit'] ?? 'S/D';
                    return DropdownMenuItem<int>(
                      value: prod['cod_productor'] as int,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              pNombre,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "CUIT: $pCuit",
                            style: const TextStyle(
                              fontSize: 11,
                              color: AgroTheme.colorTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: _cambiarProductor,
                ),
              ),
            ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildMetaTag(Icons.fingerprint_rounded, "CUIT: $cuit"),
              _buildMetaTag(Icons.badge_outlined, "RENSPA: $renspa"),
              _buildMetaTag(Icons.location_on_outlined, localidad),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaTag(IconData icono, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgroTheme.colorBorder.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: AgroTheme.colorTextSecondary),
          const SizedBox(width: 4),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AgroTheme.colorTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class ModuloCardItem extends StatefulWidget {
  final String titulo;
  final String descripcion;
  final IconData icono;
  final bool esAdmin;
  final VoidCallback onTap;

  const ModuloCardItem({
    super.key,
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.esAdmin,
    required this.onTap,
  });

  @override
  State<ModuloCardItem> createState() => _ModuloCardItemState();
}

class _ModuloCardItemState extends State<ModuloCardItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.identity()..scale(_isPressed ? 0.98 : 1.0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isPressed ? AgroTheme.colorActiveBg : AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
          border: Border.all(
            color:
                _isPressed ? AgroTheme.colorActiveBorder : AgroTheme.colorBorder,
            width: 1.2,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: const Color(0xFFFBC02D).withOpacity(0.35),
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0x08141E18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.esAdmin
                    ? AgroTheme.colorGoldSoft
                    : AgroTheme.colorAccentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.icono,
                color: widget.esAdmin
                    ? const Color(0xFF8A6A1E)
                    : AgroTheme.colorAccentDark,
                size: 22,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                    color: AgroTheme.colorText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.descripcion,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgroTheme.colorTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}