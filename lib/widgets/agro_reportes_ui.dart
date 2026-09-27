// ============================================================
// KIT DE REPORTES — AgroSoft J&L
// Componentes comunes para pantallas de campo y reportes:
// exportación multiplataforma, filtros de fecha, KPIs, gráfico
// de barras, selector de modo, barra de exportación y chips.
// ============================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../constantes/tema.dart';
import 'agro_ui.dart';

// ============================================================
// EXPORTACIÓN MULTIPLATAFORMA
// ============================================================

class AgroMime {
  static const String pdf = 'application/pdf';
  static const String xlsx =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
}

/// Limpia un texto para usarlo dentro de un nombre de archivo.
String agroNombreArchivo(String texto) {
  return texto
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
}

/// Guarda / comparte un archivo generado en memoria.
/// - Web: descarga (Printing.sharePdf funciona con cualquier binario).
/// - Windows / macOS / Linux: lo guarda en Descargas y lo abre.
/// - Android / iOS: abre la hoja de compartir del sistema.
/// Nunca usa archivos temporales de dart:io en web.
Future<void> exportarArchivoAgro({
  required Uint8List bytes,
  required String nombre,
  required String mime,
  String? texto,
  BuildContext? context,
}) async {
  try {
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: nombre);
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final ruta = '${dir.path}${Platform.pathSeparator}$nombre';
      await File(ruta).writeAsBytes(bytes, flush: true);
      await OpenFilex.open(ruta);
      if (context != null && context.mounted) {
        mostrarAgroSnack(context, 'Guardado en Descargas: $nombre');
      }
    } else {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: nombre, mimeType: mime)],
        text: texto ?? nombre,
      );
    }
  } catch (e) {
    if (context != null && context.mounted) {
      mostrarAgroSnack(context, 'No se pudo exportar: $e',
          tipo: AgroSnackTipo.error);
    }
  }
}

// ============================================================
// ENCABEZADO DE REPORTE (hero)
// ============================================================

class AgroReporteHeader extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final IconData icono;
  final Color color;
  final List<Widget> chips;
  final Widget? trailing;

  const AgroReporteHeader({
    super.key,
    required this.titulo,
    required this.icono,
    this.subtitulo,
    this.color = AgroColors.primario,
    this.chips = const [],
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final movil = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(movil ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.25)!],
        ),
        boxShadow: AgroColors.sombraSuave,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: movil ? 42 : 48,
                height: movil ? 42 : 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: Colors.white, size: movil ? 22 : 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: movil ? 17 : 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitulo != null && subtitulo!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitulo!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
        ],
      ),
    );
  }
}

/// Chip claro para usar dentro de [AgroReporteHeader].
class AgroHeaderChip extends StatelessWidget {
  final String texto;
  final IconData? icono;

  const AgroHeaderChip({super.key, required this.texto, this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 13, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// KPI DE COLORES
// ============================================================

class AgroKpiTile extends StatelessWidget {
  final String label;
  final String valor;
  final IconData icono;
  final Color color;
  final Color? fondo;
  final String? detalle;
  final VoidCallback? onTap;

  const AgroKpiTile({
    super.key,
    required this.label,
    required this.valor,
    required this.icono,
    this.color = AgroColors.primario,
    this.fondo,
    this.detalle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AgroTheme.colorSurface,
      borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
            border: Border.all(color: AgroTheme.colorBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: fondo ?? color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AgroText.label,
                    ),
                    if (detalle != null)
                      Text(
                        detalle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.secundario.copyWith(fontSize: 11),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grilla responsiva de KPIs: 2 columnas en celular, hasta [maxColumnas] en web.
class AgroKpiGrid extends StatelessWidget {
  final List<Widget> kpis;
  final int maxColumnas;
  final double anchoMinimo;

  const AgroKpiGrid({
    super.key,
    required this.kpis,
    this.maxColumnas = 4,
    this.anchoMinimo = 160,
  });

  @override
  Widget build(BuildContext context) {
    if (kpis.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        const espacio = 10.0;
        int cols = (c.maxWidth / anchoMinimo).floor();
        cols = cols.clamp(2, maxColumnas).toInt();
        if (cols > kpis.length) cols = kpis.length;
        if (cols < 1) cols = 1;
        final ancho = ((c.maxWidth - (cols - 1) * espacio) / cols).floorToDouble();
        return Wrap(
          spacing: espacio,
          runSpacing: espacio,
          children: kpis.map((k) => SizedBox(width: ancho, child: k)).toList(),
        );
      },
    );
  }
}

// ============================================================
// GRÁFICO DE BARRAS (sin paquetes externos)
// ============================================================

class AgroBarItem {
  final String label;
  final double valor;
  final Color? color;
  final String? detalle;

  const AgroBarItem({
    required this.label,
    required this.valor,
    this.color,
    this.detalle,
  });
}

/// Barras horizontales: se leen bien en celular y en web.
/// Si se pasa [umbral], las barras que lo superan se pintan en rojo
/// y se dibuja una línea de referencia.
class AgroBarChart extends StatelessWidget {
  final List<AgroBarItem> items;
  final String unidad;
  final double? umbral;
  final Color color;
  final int decimales;
  final double anchoLabel;

  const AgroBarChart({
    super.key,
    required this.items,
    this.unidad = '',
    this.umbral,
    this.color = AgroColors.primario,
    this.decimales = 0,
    this.anchoLabel = 96,
  });

  String _fmt(double v) => v.toStringAsFixed(decimales);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text('Sin datos para graficar', style: AgroText.secundario),
        ),
      );
    }
    double maximo = items.map((e) => e.valor).fold<double>(0, (a, b) => b > a ? b : a);
    if (umbral != null && umbral! > maximo) maximo = umbral!;
    if (maximo <= 0) maximo = 1;

    return LayoutBuilder(builder: (context, c) {
      final labelW = c.maxWidth < 380 ? anchoLabel * 0.8 : anchoLabel;
      return Column(
        children: items.map((it) {
          final supera = umbral != null && it.valor >= umbral!;
          final col = it.color ?? (supera ? AgroColors.danger : color);
          final frac = (it.valor / maximo).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: labelW,
                  child: Text(
                    it.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AgroText.label.copyWith(color: AgroTheme.colorText),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(builder: (context, b) {
                    final w = b.maxWidth;
                    return SizedBox(
                      height: 22,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AgroTheme.colorBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            width: (w * frac).floorToDouble(),
                            decoration: BoxDecoration(
                              color: col,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          if (umbral != null)
                            Positioned(
                              left: w < 2
                                  ? 0.0
                                  : ((w * (umbral! / maximo)).clamp(0.0, w - 2))
                                      .floorToDouble(),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: AgroColors.danger.withOpacity(0.55),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 44),
                  child: Text(
                    '${_fmt(it.valor)}${unidad.isEmpty ? '' : ' $unidad'}',
                    textAlign: TextAlign.right,
                    style: AgroText.valor.copyWith(fontSize: 12.5, color: col),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    });
  }
}

/// Mini gráfico de columnas verticales (ej: capturas por semana).
class AgroColumnChart extends StatelessWidget {
  final List<AgroBarItem> items;
  final double altura;
  final double? umbral;
  final Color color;

  const AgroColumnChart({
    super.key,
    required this.items,
    this.altura = 140,
    this.umbral,
    this.color = AgroColors.primario,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SizedBox(
        height: altura,
        child: const Center(
          child: Text('Sin datos para graficar', style: AgroText.secundario),
        ),
      );
    }
    double maximo = items.map((e) => e.valor).fold<double>(0, (a, b) => b > a ? b : a);
    if (umbral != null && umbral! > maximo) maximo = umbral!;
    if (maximo <= 0) maximo = 1;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width < 600 ? 0 : 300,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: items.map((it) {
            final supera = umbral != null && it.valor >= umbral!;
            final col = it.color ?? (supera ? AgroColors.danger : color);
            final h = ((altura - 34) * (it.valor / maximo)).clamp(2.0, altura - 34);
            return Tooltip(
              message: it.detalle ?? '${it.label}: ${it.valor.toStringAsFixed(0)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: SizedBox(
                  width: 30,
                  height: altura,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        it.valor.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: col,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: h.toDouble(),
                        decoration: BoxDecoration(
                          color: col,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        it.label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: AgroText.label.copyWith(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ============================================================
// SELECTOR DE MODO (AUDITORÍA / INTERNO)
// ============================================================

class AgroModoSelector extends StatelessWidget {
  /// 'AUDITORIA' o 'INTERNO'
  final String valor;
  final ValueChanged<String> onChanged;

  const AgroModoSelector({
    super.key,
    required this.valor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget opcion(String clave, String texto, IconData icono, String ayuda) {
      final activo = valor == clave;
      return Expanded(
        child: Tooltip(
          message: ayuda,
          child: InkWell(
            onTap: () => onChanged(clave),
            borderRadius: BorderRadius.circular(AgroTheme.radiusMd - 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
              decoration: BoxDecoration(
                color: activo ? AgroTheme.colorSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(AgroTheme.radiusMd - 2),
                boxShadow: activo ? AgroColors.sombraSuave : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icono,
                      size: 16,
                      color: activo
                          ? AgroColors.primario
                          : AgroTheme.colorTextSecondary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: activo
                            ? AgroColors.primario
                            : AgroTheme.colorTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AgroColors.neutralSoft,
        borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
      ),
      child: Row(
        children: [
          opcion('AUDITORIA', 'Auditoría', Icons.verified_outlined,
              'Formato oficial para certificadoras'),
          opcion('INTERNO', 'Interno', Icons.insights_outlined,
              'Formato de trabajo con más detalle'),
        ],
      ),
    );
  }
}

// ============================================================
// FILTRO DE FECHAS CON ATAJOS
// ============================================================

enum AgroPresetFecha { dias7, dias30, mesActual, temporada, anio, todo }

class AgroFiltroFechas extends StatelessWidget {
  final DateTime? desde;
  final DateTime? hasta;
  final void Function(DateTime? desde, DateTime? hasta) onChanged;

  /// Mes (1-12) en que empieza la temporada. Por defecto julio.
  final int mesInicioTemporada;
  final List<AgroPresetFecha> presets;

  const AgroFiltroFechas({
    super.key,
    required this.desde,
    required this.hasta,
    required this.onChanged,
    this.mesInicioTemporada = 7,
    this.presets = const [
      AgroPresetFecha.dias7,
      AgroPresetFecha.dias30,
      AgroPresetFecha.temporada,
      AgroPresetFecha.anio,
      AgroPresetFecha.todo,
    ],
  });

  static DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime?> _rango(AgroPresetFecha p) {
    final hoy = _dia(DateTime.now());
    switch (p) {
      case AgroPresetFecha.dias7:
        return <DateTime?>[hoy.subtract(const Duration(days: 6)), hoy];
      case AgroPresetFecha.dias30:
        return <DateTime?>[hoy.subtract(const Duration(days: 29)), hoy];
      case AgroPresetFecha.mesActual:
        return <DateTime?>[DateTime(hoy.year, hoy.month, 1), hoy];
      case AgroPresetFecha.temporada:
        final anioIni =
            hoy.month >= mesInicioTemporada ? hoy.year : hoy.year - 1;
        return <DateTime?>[DateTime(anioIni, mesInicioTemporada, 1), hoy];
      case AgroPresetFecha.anio:
        return <DateTime?>[DateTime(hoy.year, 1, 1), hoy];
      case AgroPresetFecha.todo:
        return <DateTime?>[null, null];
    }
  }

  String _nombre(AgroPresetFecha p) {
    switch (p) {
      case AgroPresetFecha.dias7:
        return '7 días';
      case AgroPresetFecha.dias30:
        return '30 días';
      case AgroPresetFecha.mesActual:
        return 'Este mes';
      case AgroPresetFecha.temporada:
        return 'Temporada';
      case AgroPresetFecha.anio:
        return 'Año';
      case AgroPresetFecha.todo:
        return 'Todo';
    }
  }

  bool _esActivo(AgroPresetFecha p) {
    final r = _rango(p);
    final a = desde == null ? null : _dia(desde!);
    final b = hasta == null ? null : _dia(hasta!);
    return r[0] == a && r[1] == b;
  }

  Future<void> _elegir(BuildContext context) async {
    final hoy = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(hoy.year + 1, 12, 31),
      initialDateRange: (desde != null && hasta != null)
          ? DateTimeRange(start: desde!, end: hasta!)
          : null,
      helpText: 'Rango de fechas',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: AgroColors.primario),
        ),
        child: child!,
      ),
    );
    if (r != null) onChanged(_dia(r.start), _dia(r.end));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy');
    final personalizado = desde != null && !presets.any(_esActivo);
    final textoRango = (desde == null && hasta == null)
        ? 'Todas las fechas'
        : '${desde != null ? fmt.format(desde!) : '…'} → ${hasta != null ? fmt.format(hasta!) : '…'}';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...presets.map((p) {
            final activo = _esActivo(p);
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ChipFiltro(
                texto: _nombre(p),
                activo: activo,
                onTap: () {
                  final r = _rango(p);
                  onChanged(r[0], r[1]);
                },
              ),
            );
          }),
          _ChipFiltro(
            texto: personalizado ? textoRango : 'Elegir fechas',
            icono: Icons.date_range_rounded,
            activo: personalizado,
            onTap: () => _elegir(context),
          ),
        ],
      ),
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final bool activo;
  final VoidCallback onTap;

  const _ChipFiltro({
    required this.texto,
    required this.activo,
    required this.onTap,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo ? AgroColors.primario : AgroTheme.colorSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: activo ? AgroColors.primario : AgroTheme.colorBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null) ...[
                Icon(icono,
                    size: 15,
                    color: activo ? Colors.white : AgroTheme.colorTextSecondary),
                const SizedBox(width: 5),
              ],
              Text(
                texto,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: activo ? Colors.white : AgroTheme.colorText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SELECTOR DE CHIPS (una opción) — para chacra, variedad, plaga, etc.
// ============================================================

class AgroChipSelector extends StatelessWidget {
  final String? label;
  final List<String> opciones;

  /// null = "Todos"
  final String? valor;
  final ValueChanged<String?> onChanged;
  final bool incluirTodos;
  final String textoTodos;

  const AgroChipSelector({
    super.key,
    required this.opciones,
    required this.valor,
    required this.onChanged,
    this.label,
    this.incluirTodos = true,
    this.textoTodos = 'Todos',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!.toUpperCase(), style: AgroText.overline),
          const SizedBox(height: 6),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (incluirTodos)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _ChipFiltro(
                    texto: textoTodos,
                    activo: valor == null,
                    onTap: () => onChanged(null),
                  ),
                ),
              ...opciones.map((o) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ChipFiltro(
                      texto: o,
                      activo: valor == o,
                      onTap: () => onChanged(o),
                    ),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BARRA DE EXPORTACIÓN
// ============================================================

class AgroExportBar extends StatelessWidget {
  final VoidCallback? onPdf;
  final VoidCallback? onExcel;
  final bool cargandoPdf;
  final bool cargandoExcel;
  final String? info;

  const AgroExportBar({
    super.key,
    this.onPdf,
    this.onExcel,
    this.cargandoPdf = false,
    this.cargandoExcel = false,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    final botones = <Widget>[
      if (onPdf != null || cargandoPdf)
        AgroButton(
          label: 'PDF',
          icono: Icons.picture_as_pdf_rounded,
          onTap: onPdf,
          cargando: cargandoPdf,
          tipo: AgroButtonTipo.peligro,
          compacto: true,
          expandido: true,
        ),
      if (onExcel != null || cargandoExcel)
        AgroButton(
          label: 'Excel',
          icono: Icons.grid_on_rounded,
          onTap: onExcel,
          cargando: cargandoExcel,
          tipo: AgroButtonTipo.primario,
          compacto: true,
          expandido: true,
        ),
    ];
    if (botones.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, c) {
      final angosto = c.maxWidth < 420;
      final fila = Row(
        children: [
          for (int i = 0; i < botones.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: botones[i]),
          ],
        ],
      );
      if (info == null) return fila;
      if (angosto) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info!, style: AgroText.secundario),
            const SizedBox(height: 8),
            fila,
          ],
        );
      }
      return Row(
        children: [
          Expanded(
            child: Text(info!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AgroText.secundario),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 120.0 * botones.length, child: fila),
        ],
      );
    });
  }
}

/// Barra inferior fija con los botones de exportación (ideal en celular).
class AgroBottomExport extends StatelessWidget {
  final Widget child;

  const AgroBottomExport({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AgroTheme.colorSurface,
        border: Border(top: BorderSide(color: AgroTheme.colorBorder)),
      ),
      child: SafeArea(
        top: false,
        child: AgroContent(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LEYENDA DE COLORES
// ============================================================

class AgroLeyendaItem {
  final String texto;
  final Color color;
  const AgroLeyendaItem(this.texto, this.color);
}

class AgroLeyenda extends StatelessWidget {
  final List<AgroLeyendaItem> items;
  const AgroLeyenda({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: items
          .map((i) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(i.texto, style: AgroText.secundario.copyWith(fontSize: 11.5)),
                ],
              ))
          .toList(),
    );
  }
}
