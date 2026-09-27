// ignore_for_file: deprecated_member_use

import 'package:aplicaciones_foliares/reportes/cuaderno_campo.dart';
import 'package:aplicaciones_foliares/reportes/fenologia_reporte.dart';
import 'package:aplicaciones_foliares/reportes/trampas_reportes.dart';
import 'package:flutter/material.dart';

import '../constantes/tema.dart';
import '../servicios/exportar_excel.dart';
import '../widgets/agro_reportes_ui.dart';
import '../widgets/agro_ui.dart';

class MenuReportesScreen extends StatefulWidget {
  final int codProductor;
  final String nombreProductor;

  const MenuReportesScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  State<MenuReportesScreen> createState() => _MenuReportesScreenState();
}

class _MenuReportesScreenState extends State<MenuReportesScreen> {
  bool _exportandoRecetas = false;

  void _abrir(Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
  }

  /// Genera la planilla de recetas / caldo. Evita dobles toques mientras
  /// se está generando y muestra el resultado con un aviso.
  Future<void> _exportarRecetas() async {
    if (_exportandoRecetas) return;
    setState(() => _exportandoRecetas = true);
    mostrarAgroSnack(
      context,
      'Generando planilla de aplicaciones y caldo…',
      duracion: const Duration(seconds: 4),
    );
    try {
      // El cast a dynamic permite esperar el resultado tanto si el servicio
      // devuelve un Future como si es sincrónico.
      final dynamic resultado =
          ServicioExportacionExcel.exportarRecetas() as dynamic;
      if (resultado is Future) await resultado;
    } catch (e) {
      if (mounted) {
        mostrarAgroSnack(
          context,
          'No se pudo generar la planilla: $e',
          tipo: AgroSnackTipo.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exportandoRecetas = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String nombre = widget.nombreProductor;

    final reportes = <_ReporteDef>[
      _ReporteDef(
        titulo: "Cuaderno de campo",
        descripcion:
            "Historial agronómico consolidado exigido para certificaciones y BPA.",
        tag: "Oficial BPA",
        icono: Icons.menu_book_rounded,
        color: const Color(0xFF1E6B4C),
        onTap: () => _abrir(CuadernoCampoScreen(
          codProductor: widget.codProductor,
          nombreProductor: widget.nombreProductor,
        )),
      ),
      _ReporteDef(
        titulo: "Reporte de trampeo",
        descripcion:
            "Curva poblacional y capturas semanales de Carpocapsa y Grafolita.",
        tag: "Plagas",
        icono: Icons.pest_control_outlined,
        color: const Color(0xFFC62828),
        onTap: () => _abrir(ReportesTrampasScreen(
          codProductor: widget.codProductor,
          nombreProductor: widget.nombreProductor,
        )),
      ),
      _ReporteDef(
        titulo: "Reporte fenológico",
        descripcion:
            "Evolución de estados vegetativos, floración y cuaje por variedad.",
        tag: "Curva anual",
        icono: Icons.eco_outlined,
        color: const Color(0xFF8A6A1E),
        onTap: () => _abrir(ReportesFenologiaScreen(
          codProductor: widget.codProductor,
          nombreProductor: widget.nombreProductor,
        )),
      ),
      _ReporteDef(
        titulo: "Aplicaciones y caldo",
        descripcion: _exportandoRecetas
            ? "Generando la planilla… esto puede demorar unos segundos."
            : "Planilla de recetas, caldo consumido por cuadro y carencias (.xlsx).",
        tag: "Excel",
        icono: Icons.table_chart_outlined,
        color: const Color(0xFF1565C0),
        esDescarga: true,
        cargando: _exportandoRecetas,
        onTap: _exportandoRecetas ? null : _exportarRecetas,
      ),
    ];

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: "Centro de reportes",
        subtitulo: nombre,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 20, bottom: 32),
          child: AgroContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AgroReporteHeader(
                  titulo: "Documentación oficial y planillas",
                  subtitulo:
                      "Informes consolidados, auditorías de campo y registros fitosanitarios.",
                  icono: Icons.insights_outlined,
                  color: const Color(0xFF1E6B4C),
                  chips: [
                    AgroHeaderChip(
                      texto: nombre.trim().isEmpty ? 'Establecimiento' : nombre,
                      icono: Icons.storefront_outlined,
                    ),
                    const AgroHeaderChip(
                      texto: 'PDF y Excel',
                      icono: Icons.file_download_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const AgroSectionHeader(
                  titulo: "Reportes disponibles",
                  subtitulo:
                      "Consultá en pantalla o exportá para auditorías y clientes",
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, c) {
                    final int cols = c.maxWidth >= 700 ? 2 : 1;
                    const double gap = 14;
                    final double w =
                        ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: reportes
                          .map((r) => SizedBox(
                                width: w,
                                child: _ReporteCard(reporte: r),
                              ))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),
                AgroCard(
                  color: AgroColors.infoSoft,
                  borderColor: AgroColors.infoSoft,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(Icons.info_outline_rounded,
                          size: 20, color: AgroColors.info),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Los reportes se generan con los datos guardados en este dispositivo. Sincronizá antes de exportar para incluir los últimos registros.",
                          style: AgroText.secundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReporteDef {
  final String titulo;
  final String descripcion;
  final String tag;
  final IconData icono;
  final Color color;
  final bool esDescarga;
  final bool cargando;
  final VoidCallback? onTap;

  const _ReporteDef({
    required this.titulo,
    required this.descripcion,
    required this.tag,
    required this.icono,
    required this.color,
    required this.onTap,
    this.esDescarga = false,
    this.cargando = false,
  });
}

class _ReporteCard extends StatelessWidget {
  final _ReporteDef reporte;

  const _ReporteCard({required this.reporte});

  @override
  Widget build(BuildContext context) {
    final c = reporte.color;

    Widget trailing;
    if (reporte.cargando) {
      trailing = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: c),
      );
    } else if (reporte.esDescarga) {
      trailing = Icon(Icons.file_download_outlined, color: c, size: 22);
    } else {
      trailing = const Icon(Icons.chevron_right_rounded,
          color: AgroTheme.colorTextSecondary);
    }

    return AgroCard(
      onTap: reporte.onTap,
      accentColor: c,
      padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
      child: Row(
        children: [
          AgroIconBox(icono: reporte.icono, color: c, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        reporte.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.tituloCard,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AgroBadge(texto: reporte.tag, color: c),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  reporte.descripcion,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.secundario.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Center(child: trailing),
          ),
        ],
      ),
    );
  }
}
