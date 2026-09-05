import 'package:flutter/material.dart';
import '../constantes/tema.dart';
import 'fenologia.dart';
import 'inventario_plantacion.dart';
import 'lecturas_trampas.dart';
import 'trampas_ubicacion.dart';

class MenuCampoScreen extends StatelessWidget {
  final int codProductor;
  final String nombreProductor;

  const MenuCampoScreen({
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AgroTheme.colorText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Monitoreo de Campo",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AgroTheme.colorText),
            ),
            Text(
              nombreProductor,
              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
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
                "Operaciones de Lote",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AgroTheme.colorText, letterSpacing: -0.4),
              ),
              const SizedBox(height: 4),
              const Text(
                "Seguimiento fenológico, trampeo de plagas e inventario botánico.",
                style: TextStyle(fontSize: 13, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),

              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 2 : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: MediaQuery.of(context).size.width > 600 ? 1.6 : 2.3,
                children: [
                  _buildCard(
                    context: context,
                    titulo: "Estados Fenológicos",
                    descripcion: "Lectura de estados de yemas, flores, cuaje y temperaturas críticas.",
                    icono: Icons.eco_outlined,
                    colorIcono: AgroTheme.colorAccentDark,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FenologiaScreen(
                            codProductor: codProductor,
                            nombreProductor: nombreProductor,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildCard(
                    context: context,
                    titulo: "Ubicación de Trampas",
                    descripcion: "Mapeo, colocación y georreferenciación de trampas de plagas en campo.",
                    icono: Icons.my_location_rounded,
                    colorIcono: const Color(0xFFB8862A),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TrampasUbicacionScreen(
                            codProductor: codProductor,
                            nombreProductor: nombreProductor,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildCard(
                    context: context,
                    titulo: "Lecturas de Trampas",
                    descripcion: "Recuento semanal de capturas (Carpocapsa, Grafolita, machos/hembras).",
                    icono: Icons.pest_control_outlined,
                    colorIcono: AgroTheme.colorDanger,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LecturasTrampasScreen(
                            codProductor: codProductor,
                            nombreProductor: nombreProductor,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildCard(
                    context: context,
                    titulo: "Inventario de Plantación",
                    descripcion: "Consulta de cuadros, hectáreas, variedad, portainjerto y riego.",
                    icono: Icons.park_outlined,
                    colorIcono: const Color(0xFF1E6B4C),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const InventarioPlantacionScreen(),
                        ),
                      );
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

  Widget _buildCard({
    required BuildContext context,
    required String titulo,
    required String descripcion,
    required IconData icono,
    required Color colorIcono,
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
            BoxShadow(color: const Color(0x04141E18), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: colorIcono.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icono, color: colorIcono, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AgroTheme.colorText)),
                  const SizedBox(height: 4),
                  Text(descripcion, style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AgroTheme.colorTextSecondary),
          ],
        ),
      ),
    );
  }
}