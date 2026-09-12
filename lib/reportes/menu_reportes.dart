import 'package:aplicaciones_foliares/reportes/cuaderno_campo.dart';
import 'package:aplicaciones_foliares/reportes/fenologia_reporte.dart';
import 'package:aplicaciones_foliares/reportes/trampas_reportes.dart';
import 'package:flutter/material.dart';
import '../constantes/tema.dart';
import '../servicios/exportar_excel.dart';

class MenuReportesScreen extends StatelessWidget {
  final int codProductor;
  final String nombreProductor;

  const MenuReportesScreen({
    super.key,
    required this.codProductor,
    required this.nombreProductor,
  });

  @override
  Widget build(BuildContext context) {
    final double anchoPantalla = MediaQuery.of(context).size.width;
    final bool esDesktop = anchoPantalla >= 900;

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
            const Text(
              "Centro de Reportería",
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16.5,
                  color: AgroTheme.colorText),
            ),
            Text(
              nombreProductor,
              style: const TextStyle(
                  fontSize: 11.5,
                  color: AgroTheme.colorTextSecondary,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1150),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: esDesktop ? 28 : 20,
                vertical: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Documentación Oficial y Planillas",
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AgroTheme.colorText,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Informes consolidados, auditorías de campo y registros fitosanitarios.",
                    style: TextStyle(
                      fontSize: 13,
                      color: AgroTheme.colorTextSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      int columnas = 1;
                      double aspect = 2.4;

                      if (constraints.maxWidth >= 950) {
                        columnas = 2;
                        aspect = 2.3;
                      } else if (constraints.maxWidth >= 650) {
                        columnas = 2;
                        aspect = 2.0;
                      }

                      return GridView.count(
                        crossAxisCount: columnas,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: aspect,
                        children: [
                          _buildReporteCard(
                            titulo: "Cuaderno de Campo",
                            descripcion:
                                "Historial agronómico consolidado exigido para certificaciones y BPA.",
                            etiqueta: "Oficial BPA",
                            icono: Icons.menu_book_rounded,
                            colorIcono: const Color(0xFF1E6B4C),
                            fondoIcono: const Color(0xFFE8F5E9),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CuadernoCampoScreen(
                                    codProductor: codProductor,
                                    nombreProductor: nombreProductor,
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildReporteCard(
                            titulo: "Reporte de Trampeo",
                            descripcion:
                                "Curva poblacional y capturas semanales de Carpocapsa y Grafolita.",
                            etiqueta: "Plagas",
                            icono: Icons.pest_control_outlined,
                            colorIcono: const Color(0xFFC62828),
                            fondoIcono: const Color(0xFFFFEBEE),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReportesTrampasScreen(
                                    codProductor: codProductor,
                                    nombreProductor: nombreProductor,
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildReporteCard(
                            titulo: "Reporte Fenológico",
                            descripcion:
                                "Evolución de estados vegetativos, floración y cuaje por variedad.",
                            etiqueta: "Curva Anual",
                            icono: Icons.eco_outlined,
                            colorIcono: const Color(0xFF8A6A1E),
                            fondoIcono: const Color(0xFFFFF8E1),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReportesFenologiaScreen(
                                    codProductor: codProductor,
                                    nombreProductor: nombreProductor,
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildReporteCard(
                            titulo: "Aplicaciones y Caldo",
                            descripcion:
                                "Planilla de recetas, caldo consumido por cuadro y carencias (.XLSX).",
                            etiqueta: "Excel / Libro",
                            icono: Icons.table_chart_outlined,
                            colorIcono: const Color(0xFF1565C0),
                            fondoIcono: const Color(0xFFE3F2FD),
                            onTap: () {
                              ServicioExportacionExcel.exportarRecetas();
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReporteCard({
    required String titulo,
    required String descripcion,
    required String etiqueta,
    required IconData icono,
    required Color colorIcono,
    required Color fondoIcono,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
          border: Border.all(color: AgroTheme.colorBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x03141E18),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: fondoIcono,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: colorIcono, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: AgroTheme.colorText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: fondoIcono,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          etiqueta,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: colorIcono,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    descripcion,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AgroTheme.colorTextSecondary,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AgroTheme.colorTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}