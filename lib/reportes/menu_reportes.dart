import 'package:aplicaciones_foliares/reportes/cuaderno_campo.dart';
import 'package:aplicaciones_foliares/reportes/fenologia_reporte.dart';
import 'package:aplicaciones_foliares/reportes/trampas_reportes.dart';
import 'package:flutter/material.dart';
import '../constantes/tema.dart';
import '../servicios/exportar_excel.dart';
import '../servicios/exportar_pdf.dart';

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
                  fontSize: 17,
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Documentación Oficial y Planillas",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AgroTheme.colorText,
                    letterSpacing: -0.4),
              ),
              const SizedBox(height: 4),
              const Text(
                "Informes consolidados, auditorías de campo y registros de labor.",
                style: TextStyle(
                    fontSize: 13,
                    color: AgroTheme.colorTextSecondary,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),

              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 2 : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio:
                    MediaQuery.of(context).size.width > 600 ? 1.6 : 2.3,
                children: [
                  _buildReporteCard(
                    titulo: "Cuaderno de Campo",
                    descripcion:
                        "Historial agronómico consolidado exigido para certificaciones y BPA.",
                    icono: Icons.menu_book_rounded,
                    color: const Color(0xFF1E6B4C),
                    onTap: () {
                      CuadernoCampoScreen();
                    },
                  ),
                  _buildReporteCard(
                    titulo: "Reporte de Lecturas Trampas",
                    descripcion:
                        "Curva poblacional y capturas semanales de Carpocapsa y Grafolita.",
                    icono: Icons.pest_control_outlined,
                    color: AgroTheme.colorDanger,
                    onTap: () {
                      ReportesTrampasScreen();
                    
                    },
                  ),
                  _buildReporteCard(
                    titulo: "Reporte Fenológico",
                    descripcion:
                        "Evolución de estados vegetativos y temperaturas críticas registradas.",
                    icono: Icons.eco_outlined,
                    color: const Color(0xFFB8862A),
                    onTap: () { Navigator.push(context,MaterialPageRoute(builder: (_) => const ReportesFenologiaScreen()),
  
                      );
                    },
                  ),
                  _buildReporteCard(
                    titulo: "Aplicaciones Foliares",
                    descripcion:
                        "Planilla de recetas, caldo consumido por cuadro y carencias (.XLSX).",
                    icono: Icons.table_chart_outlined,
                    color: const Color(0xFF2563EB),
                    onTap: () {
                      ServicioExportacionExcel.exportarRecetas();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReporteCard({
    required String titulo,
    required String descripcion,
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AgroTheme.colorSurface,
          borderRadius: BorderRadius.circular(AgroTheme.radiusLg),
          border: Border.all(color: AgroTheme.colorBorder),
          boxShadow: [
            BoxShadow(
                color: const Color(0x04141E18),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icono, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: AgroTheme.colorText),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descripcion,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AgroTheme.colorTextSecondary,
                        height: 1.3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AgroTheme.colorTextSecondary),
          ],
        ),
      ),
    );
  }
}