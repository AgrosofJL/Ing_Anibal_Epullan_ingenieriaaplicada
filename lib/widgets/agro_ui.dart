// ignore_for_file: deprecated_member_use
//
// AgroSoft J&L · Kit de UI compartido
// ------------------------------------------------------------
// Componentes visuales reutilizables y responsive (celular, tablet, web).
// Ubicación sugerida: lib/widgets/agro_ui.dart
//
// Solo depende de AgroTheme (constantes/tema.dart) para mantener
// la identidad de colores ya existente en la app.

import 'package:flutter/material.dart';

import '../constantes/tema.dart';

// ============================================================
// BREAKPOINTS / RESPONSIVE
// ============================================================

class AgroBreakpoints {
  static const double movil = 600;
  static const double tablet = 1024;
  static const double maxContenido = 1240;

  static double ancho(BuildContext context) => MediaQuery.of(context).size.width;

  static bool esMovil(BuildContext context) => ancho(context) < movil;
  static bool esTablet(BuildContext context) {
    final w = ancho(context);
    return w >= movil && w < tablet;
  }

  static bool esDesktop(BuildContext context) => ancho(context) >= tablet;

  /// Padding horizontal según el tamaño de pantalla.
  static double gutter(BuildContext context) {
    final w = ancho(context);
    if (w < movil) return 16;
    if (w < tablet) return 24;
    return 32;
  }

  /// Cantidad de columnas sugeridas para una grilla de tarjetas.
  static int columnas(BuildContext context,
      {double anchoMinimoTarjeta = 340, int maximo = 3}) {
    final double disponible =
        ancho(context).clamp(0.0, maxContenido).toDouble() - gutter(context) * 2;
    final int cols = (disponible / anchoMinimoTarjeta).floor();
    return cols.clamp(1, maximo).toInt();
  }
}

// ============================================================
// PALETA SEMÁNTICA (estados)
// ============================================================

class AgroColors {
  static const Color primario = Color(0xFF1E6B4C);
  static const Color primarioSoft = Color(0xFFE6F2EC);

  static const Color ok = Color(0xFF2E7D32);
  static const Color okSoft = Color(0xFFE8F5E9);

  static const Color warn = Color(0xFF8A6A1E);
  static const Color warnSoft = Color(0xFFFFF6DD);

  static const Color danger = Color(0xFFC62828);
  static const Color dangerSoft = Color(0xFFFDECEC);

  static const Color info = Color(0xFF1565C0);
  static const Color infoSoft = Color(0xFFE7F0FB);

  static const Color neutral = Color(0xFF546E7A);
  static const Color neutralSoft = Color(0xFFECEFF1);

  static const List<BoxShadow> sombraSuave = [
    BoxShadow(color: Color(0x0A141E18), blurRadius: 12, offset: Offset(0, 3)),
  ];

  static const List<BoxShadow> sombraHover = [
    BoxShadow(color: Color(0x14141E18), blurRadius: 22, offset: Offset(0, 8)),
  ];
}

// ============================================================
// TIPOGRAFÍA
// ============================================================

class AgroText {
  static const TextStyle overline = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    color: AgroTheme.colorTextSecondary,
  );

  static const TextStyle titulo = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: AgroTheme.colorText,
  );

  static const TextStyle tituloCard = TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: AgroTheme.colorText,
  );

  static const TextStyle cuerpo = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AgroTheme.colorText,
  );

  static const TextStyle secundario = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AgroTheme.colorTextSecondary,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: AgroTheme.colorTextSecondary,
  );

  static const TextStyle valor = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w800,
    color: AgroTheme.colorText,
  );
}

// ============================================================
// APP BAR
// ============================================================

class AgroAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget> acciones;
  final bool mostrarAtras;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  const AgroAppBar({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.acciones = const [],
    this.mostrarAtras = true,
    this.leading,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(64 + (bottom?.preferredSize.height ?? 1));

  @override
  Widget build(BuildContext context) {
    final puedeVolver = mostrarAtras && Navigator.of(context).canPop();
    return AppBar(
      toolbarHeight: 64,
      backgroundColor: AgroTheme.colorSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: const Color(0x22141E18),
      automaticallyImplyLeading: false,
      titleSpacing: puedeVolver || leading != null ? 0 : 16,
      leading: leading ??
          (puedeVolver
              ? IconButton(
                  tooltip: 'Volver',
                  icon: const Icon(Icons.arrow_back_rounded,
                      size: 22, color: AgroTheme.colorText),
                  onPressed: () => Navigator.maybePop(context),
                )
              : null),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              letterSpacing: -0.2,
              color: AgroTheme.colorText,
            ),
          ),
          if (subtitulo != null && subtitulo!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitulo!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AgroTheme.colorTextSecondary,
              ),
            ),
          ],
        ],
      ),
      actions: [
        ...acciones.map((a) => Center(child: a)),
        const SizedBox(width: 8),
      ],
      bottom: bottom ??
          const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: AgroTheme.colorBorder),
          ),
    );
  }
}

/// Botón de ícono cuadrado usado en barras y tarjetas.
class AgroIconButton extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final bool conBorde;
  final double size;

  const AgroIconButton({
    super.key,
    required this.icono,
    required this.tooltip,
    this.onTap,
    this.color,
    this.conBorde = true,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AgroTheme.colorTextSecondary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: conBorde ? Border.all(color: AgroTheme.colorBorder) : null,
              color: conBorde ? AgroTheme.colorSurface : null,
            ),
            child: Icon(icono,
                size: 20, color: onTap == null ? c.withOpacity(0.35) : c),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CONTENEDOR DE PÁGINA
// ============================================================

/// Centra el contenido con ancho máximo y padding responsive.
class AgroContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;

  const AgroContent({
    super.key,
    required this.child,
    this.maxWidth = AgroBreakpoints.maxContenido,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final g = AgroBreakpoints.gutter(context);
    return Align(
      alignment: Alignment.topCenter,
      // heightFactor 1: ocupa solo el alto del contenido (seguro en
      // bottomNavigationBar y dentro de listas).
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: g),
          child: child,
        ),
      ),
    );
  }
}

// ============================================================
// TARJETA
// ============================================================

class AgroCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final Color? accentColor; // barra lateral de color (estado)
  final double? radius;

  const AgroCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.accentColor,
    this.radius,
  });

  @override
  State<AgroCard> createState() => _AgroCardState();
}

class _AgroCardState extends State<AgroCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.radius ?? AgroTheme.radiusLg;
    final clickable = widget.onTap != null;

    Widget contenido = Padding(padding: widget.padding, child: widget.child);

    if (widget.accentColor != null) {
      // Stack (no IntrinsicHeight) para que funcione con LayoutBuilder adentro.
      contenido = Stack(
        children: [
          Padding(padding: const EdgeInsets.only(left: 4), child: contenido),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: widget.accentColor),
          ),
        ],
      );
    }

    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (clickable) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: widget.color ?? AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(r),
          border: Border.all(
            color: _hover
                ? (widget.accentColor ?? AgroColors.primario).withOpacity(0.45)
                : (widget.borderColor ?? AgroTheme.colorBorder),
          ),
          boxShadow: _hover ? AgroColors.sombraHover : AgroColors.sombraSuave,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              child: contenido,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BADGE / CHIP
// ============================================================

class AgroBadge extends StatelessWidget {
  final String texto;
  final Color color;
  final Color? fondo;
  final IconData? icono;
  final bool grande;

  const AgroBadge({
    super.key,
    required this.texto,
    this.color = AgroColors.primario,
    this.fondo,
    this.icono,
    this.grande = false,
  });

  factory AgroBadge.estado(String estado) {
    final e = estado.toUpperCase();
    if (e == 'TERMINADO' || e == 'FINALIZADO' || e == 'INACTIVO') {
      return AgroBadge(
          texto: estado,
          color: AgroColors.neutral,
          fondo: AgroColors.neutralSoft,
          icono: Icons.check_circle_rounded);
    }
    if (e == 'PENDIENTE') {
      return AgroBadge(
          texto: estado,
          color: AgroColors.warn,
          fondo: AgroColors.warnSoft,
          icono: Icons.schedule_rounded);
    }
    return AgroBadge(
        texto: estado,
        color: AgroColors.ok,
        fondo: AgroColors.okSoft,
        icono: Icons.circle);
  }

  @override
  Widget build(BuildContext context) {
    final esPunto = icono == Icons.circle;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: grande ? 10 : 8, vertical: grande ? 5 : 3.5),
      decoration: BoxDecoration(
        color: fondo ?? color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: esPunto ? 7 : (grande ? 14 : 12), color: color),
            SizedBox(width: esPunto ? 5 : 4),
          ],
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: grande ? 12 : 10.5,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta informativa neutra (CUIT, RENSPA, producto, etc).
class AgroTag extends StatelessWidget {
  final String texto;
  final IconData? icono;

  const AgroTag({super.key, required this.texto, this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgroTheme.colorBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 13, color: AgroTheme.colorTextSecondary),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AgroTheme.colorText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ÍCONO CON FONDO
// ============================================================

class AgroIconBox extends StatelessWidget {
  final IconData icono;
  final Color color;
  final double size;

  const AgroIconBox({
    super.key,
    required this.icono,
    this.color = AgroColors.primario,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icono, color: color, size: size * 0.5),
    );
  }
}

// ============================================================
// ENCABEZADO DE SECCIÓN
// ============================================================

class AgroSectionHeader extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final IconData? icono;
  final Widget? trailing;

  const AgroSectionHeader({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.icono,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icono != null) ...[
          AgroIconBox(icono: icono!, size: 34),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AgroTheme.colorText,
                    letterSpacing: -0.2,
                  )),
              if (subtitulo != null) ...[
                const SizedBox(height: 2),
                Text(subtitulo!, style: AgroText.secundario),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ============================================================
// BUSCADOR
// ============================================================

class AgroSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const AgroSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: AgroTheme.colorText, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AgroTheme.colorSurface,
            hintText: hint,
            hintStyle: const TextStyle(
                color: AgroTheme.colorTextSecondary, fontSize: 13.5),
            prefixIcon: const Icon(Icons.search_rounded,
                color: AgroTheme.colorTextSecondary, size: 20),
            suffixIcon: value.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: AgroTheme.colorTextSecondary),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                      onClear?.call();
                    },
                  )
                : null,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
              borderSide: const BorderSide(color: AgroTheme.colorBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
              borderSide: const BorderSide(color: AgroTheme.colorBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
              borderSide:
                  const BorderSide(color: AgroColors.primario, width: 1.5),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// INPUT DECORATION ESTÁNDAR PARA FORMULARIOS
// ============================================================

InputDecoration agroInputDecoration({
  required String label,
  String? hint,
  IconData? icono,
  String? sufijo,
  String? helper,
}) {
  OutlineInputBorder borde(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        borderSide: BorderSide(color: c, width: w),
      );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    suffixText: sufijo,
    isDense: true,
    filled: true,
    fillColor: AgroTheme.colorSurface,
    prefixIcon: icono != null
        ? Icon(icono, size: 19, color: AgroTheme.colorTextSecondary)
        : null,
    labelStyle: const TextStyle(
        fontSize: 13.5,
        color: AgroTheme.colorTextSecondary,
        fontWeight: FontWeight.w600),
    floatingLabelStyle: const TextStyle(
        color: AgroColors.primario, fontWeight: FontWeight.w700),
    hintStyle:
        const TextStyle(fontSize: 13, color: AgroTheme.colorTextSecondary),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: borde(AgroTheme.colorBorder),
    enabledBorder: borde(AgroTheme.colorBorder),
    focusedBorder: borde(AgroColors.primario, 1.5),
    errorBorder: borde(AgroColors.danger),
    focusedErrorBorder: borde(AgroColors.danger, 1.5),
  );
}

// ============================================================
// PESTAÑAS SEGMENTADAS (con contador)
// ============================================================

class AgroTabItem {
  final String id;
  final String label;
  final IconData icono;
  final int? count;
  final Color color;

  const AgroTabItem({
    required this.id,
    required this.label,
    required this.icono,
    this.count,
    this.color = AgroColors.primario,
  });
}

class AgroSegmentedTabs extends StatelessWidget {
  final List<AgroTabItem> items;
  final String seleccionado;
  final ValueChanged<String> onChanged;

  const AgroSegmentedTabs({
    super.key,
    required this.items,
    required this.seleccionado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AgroTheme.colorSurface,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd + 2),
        border: Border.all(color: AgroTheme.colorBorder),
      ),
      child: Row(
        children: items.map((it) {
          final sel = it.id == seleccionado;
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                onTap: () => onChanged(it.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: sel ? it.color : Colors.transparent,
                    borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(it.icono,
                          size: 16,
                          color: sel ? Colors.white : AgroTheme.colorTextSecondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          it.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            color: sel ? Colors.white : AgroTheme.colorText,
                          ),
                        ),
                      ),
                      if (it.count != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: sel
                                ? Colors.white.withOpacity(0.22)
                                : AgroTheme.colorBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${it.count}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: sel
                                  ? Colors.white
                                  : AgroTheme.colorTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================
// DATO / MÉTRICA
// ============================================================

class AgroStat extends StatelessWidget {
  final String label;
  final String valor;
  final IconData? icono;
  final Color color;

  const AgroStat({
    super.key,
    required this.label,
    required this.valor,
    this.icono,
    this.color = AgroTheme.colorTextSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.overline.copyWith(fontSize: 9.5)),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AgroText.valor.copyWith(fontSize: 13.5)),
      ],
    );
  }
}

/// Grilla de métricas que se adapta: 2 columnas en celular, N en pantallas anchas.
class AgroStatGrid extends StatelessWidget {
  final List<Widget> stats;
  final Color? fondo;

  const AgroStatGrid({super.key, required this.stats, this.fondo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fondo ?? AgroTheme.colorBg,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          if (stats.isEmpty) return const SizedBox.shrink();
          final int cols = (c.maxWidth < 360
                  ? 2
                  : (c.maxWidth < 560
                      ? (stats.length > 3 ? 2 : stats.length)
                      : stats.length))
              .clamp(1, stats.length)
              .toInt();
          final anchoItem =
              ((c.maxWidth - (cols - 1) * 12) / cols).floorToDouble();
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: stats
                .map((s) => SizedBox(width: anchoItem, child: s))
                .toList(),
          );
        },
      ),
    );
  }
}

// ============================================================
// BOTONES
// ============================================================

enum AgroButtonTipo { primario, secundario, peligro, texto }

class AgroButton extends StatelessWidget {
  final String label;
  final IconData? icono;
  final VoidCallback? onTap;
  final AgroButtonTipo tipo;
  final bool cargando;
  final bool expandido;
  final bool compacto;

  const AgroButton({
    super.key,
    required this.label,
    this.icono,
    this.onTap,
    this.tipo = AgroButtonTipo.primario,
    this.cargando = false,
    this.expandido = false,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BorderSide borde = BorderSide.none;

    switch (tipo) {
      case AgroButtonTipo.primario:
        bg = AgroColors.primario;
        fg = Colors.white;
        break;
      case AgroButtonTipo.secundario:
        bg = AgroTheme.colorSurface;
        fg = AgroTheme.colorText;
        borde = const BorderSide(color: AgroTheme.colorBorder);
        break;
      case AgroButtonTipo.peligro:
        bg = AgroColors.dangerSoft;
        fg = AgroColors.danger;
        break;
      case AgroButtonTipo.texto:
        bg = Colors.transparent;
        fg = AgroColors.primario;
        break;
    }

    final deshabilitado = onTap == null || cargando;

    final child = Row(
      mainAxisSize: expandido ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (cargando)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icono != null)
          Icon(icono, size: compacto ? 16 : 18, color: fg),
        if (cargando || icono != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compacto ? 12.5 : 13.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: deshabilitado && !cargando ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
          side: borde,
        ),
        child: InkWell(
          onTap: deshabilitado ? null : onTap,
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compacto ? 38 : 46),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: compacto ? 12 : 18, vertical: 8),
              child: Center(widthFactor: expandido ? null : 1, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ESTADOS VACÍO / CARGANDO
// ============================================================

class AgroEmptyState extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? mensaje;
  final Widget? accion;

  const AgroEmptyState({
    super.key,
    required this.icono,
    required this.titulo,
    this.mensaje,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  color: AgroColors.primarioSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, size: 36, color: AgroColors.primario),
              ),
              const SizedBox(height: 18),
              Text(titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: AgroTheme.colorText,
                  )),
              if (mensaje != null) ...[
                const SizedBox(height: 6),
                Text(mensaje!,
                    textAlign: TextAlign.center, style: AgroText.secundario),
              ],
              if (accion != null) ...[
                const SizedBox(height: 18),
                accion!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AgroLoading extends StatelessWidget {
  final String? mensaje;
  const AgroLoading({super.key, this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: AgroColors.primario),
          ),
          if (mensaje != null) ...[
            const SizedBox(height: 14),
            Text(mensaje!, style: AgroText.secundario),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// HOJA DE ACCIONES (bottom sheet en celular / diálogo en web)
// ============================================================

/// Muestra un panel adaptable: bottom sheet en celular, diálogo centrado en
/// tablet/web. [builder] recibe el contexto del panel (para hacer pop).
Future<T?> mostrarAgroPanel<T>({
  required BuildContext context,
  required String titulo,
  String? subtitulo,
  IconData? icono,
  required Widget Function(BuildContext ctx) builder,
  double maxWidth = 520,
}) {
  Widget encabezado(BuildContext ctx) => Row(
        children: [
          if (icono != null) ...[
            AgroIconBox(icono: icono, size: 40),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: AgroTheme.colorText,
                    )),
                if (subtitulo != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitulo, style: AgroText.secundario),
                ],
              ],
            ),
          ),
          AgroIconButton(
            icono: Icons.close_rounded,
            tooltip: 'Cerrar',
            conBorde: false,
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      );

  if (AgroBreakpoints.esMovil(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.92),
          decoration: const BoxDecoration(
            color: AgroTheme.colorSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AgroTheme.colorBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: encabezado(ctx),
                ),
                const Divider(height: 1, color: AgroTheme.colorBorder),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: builder(ctx),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  return showDialog<T>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: AgroTheme.colorSurface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AgroTheme.radiusLg + 4)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
                child: encabezado(ctx),
              ),
              const Divider(height: 1, color: AgroTheme.colorBorder),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: builder(ctx),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Opción de lista para usar dentro de un panel de acciones.
class AgroOptionTile extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? descripcion;
  final Color color;
  final VoidCallback onTap;

  const AgroOptionTile({
    super.key,
    required this.icono,
    required this.titulo,
    this.descripcion,
    this.color = AgroColors.primario,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AgroCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            AgroIconBox(icono: icono, color: color, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AgroTheme.colorText,
                      )),
                  if (descripcion != null) ...[
                    const SizedBox(height: 2),
                    Text(descripcion!, style: AgroText.secundario),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AgroTheme.colorTextSecondary),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CONFIRMACIÓN Y MENSAJES
// ============================================================

Future<bool> confirmarAgro({
  required BuildContext context,
  required String titulo,
  required String mensaje,
  String confirmar = 'Confirmar',
  String cancelar = 'Cancelar',
  bool peligroso = false,
  IconData? icono,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AgroTheme.colorSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgroTheme.radiusLg + 4)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AgroIconBox(
                icono: icono ??
                    (peligroso
                        ? Icons.warning_amber_rounded
                        : Icons.help_outline_rounded),
                color: peligroso ? AgroColors.danger : AgroColors.primario,
                size: 46,
              ),
              const SizedBox(height: 16),
              Text(titulo,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AgroTheme.colorText,
                  )),
              const SizedBox(height: 8),
              Text(mensaje, style: AgroText.cuerpo),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: AgroButton(
                      label: cancelar,
                      tipo: AgroButtonTipo.secundario,
                      expandido: true,
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Material(
                      color: peligroso ? AgroColors.danger : AgroColors.primario,
                      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                        onTap: () => Navigator.pop(ctx, true),
                        child: Container(
                          height: 46,
                          alignment: Alignment.center,
                          child: Text(confirmar,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              )),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return res ?? false;
}

enum AgroSnackTipo { ok, error, info, aviso }

void mostrarAgroSnack(BuildContext context, String mensaje,
    {AgroSnackTipo tipo = AgroSnackTipo.info,
    Duration duracion = const Duration(seconds: 3)}) {
  Color color;
  IconData icono;
  switch (tipo) {
    case AgroSnackTipo.ok:
      color = AgroColors.primario;
      icono = Icons.check_circle_rounded;
      break;
    case AgroSnackTipo.error:
      color = AgroColors.danger;
      icono = Icons.error_rounded;
      break;
    case AgroSnackTipo.aviso:
      color = const Color(0xFF9A6B00);
      icono = Icons.warning_amber_rounded;
      break;
    case AgroSnackTipo.info:
      color = const Color(0xFF263238);
      icono = Icons.info_rounded;
      break;
  }

  final ancho = MediaQuery.of(context).size.width;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: color,
      duration: duracion,
      width: ancho > AgroBreakpoints.movil ? 440 : null,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgroTheme.radiusMd)),
      content: Row(
        children: [
          Icon(icono, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mensaje,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}

// ============================================================
// FILA CLAVE / VALOR
// ============================================================

class AgroKeyValue extends StatelessWidget {
  final String clave;
  final String valor;
  final IconData? icono;

  const AgroKeyValue(
      {super.key, required this.clave, required this.valor, this.icono});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 16, color: AgroTheme.colorTextSecondary),
            const SizedBox(width: 8),
          ],
          Expanded(flex: 4, child: Text(clave, style: AgroText.label)),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(valor,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AgroTheme.colorText,
                )),
          ),
        ],
      ),
    );
  }
}
