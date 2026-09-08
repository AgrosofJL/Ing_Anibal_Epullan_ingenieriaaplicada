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
    final double ancho = MediaQuery.of(context).size.width;
    final bool esDesktop = ancho >= 800;

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
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AgroTheme.colorText),
            ),
            Text(
              nombreProductor,
              style: const TextStyle(fontSize: 11.5, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: esDesktop ? 28 : 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Operaciones y Control de Lote",
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AgroTheme.colorText,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Seguimiento fenológico, trampeo fitosanitario e inventario botánico.",
                    style: TextStyle(fontSize: 13, color: AgroTheme.colorTextSecondary, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 20),

                  GridView.count(
                    crossAxisCount: esDesktop ? 2 : 1,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: esDesktop ? 2.2 : 2.5,
                    children: [
                      _buildCard(
                        context: context,
                        titulo: "Estados Fenológicos",
                        descripcion: "Lectura de yemas, floración, cuaje y curvas de evolución.",
                        icono: Icons.eco_outlined,
                        colorIcono: const Color(0xFF2E7D32),
                        fondoIcono: const Color(0xFFE8F5E9),
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
                        descripcion: "Mapeo satelital, georreferenciación GPS y QR de trampas.",
                        icono: Icons.my_location_rounded,
                        colorIcono: const Color(0xFF8A6A1E),
                        fondoIcono: const Color(0xFFFFF8E1),
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
                        descripcion: "Recuento semanal de capturas (Carpocapsa, Grafolita, umbrales).",
                        icono: Icons.pest_control_outlined,
                        colorIcono: const Color(0xFFC62828),
                        fondoIcono: const Color(0xFFFFEBEE),
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
                        descripcion: "Catastro de cuarteles, superficies, variedades, riego y UP.",
                        icono: Icons.park_outlined,
                        colorIcono: const Color(0xFF1E6B4C),
                        fondoIcono: const Color(0xFFE8F5E9),
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
            BoxShadow(color: Color(0x04141E18), blurRadius: 10, offset: Offset(0, 3)),
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
                  Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AgroTheme.colorText),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    descripcion,
                    style: const TextStyle(fontSize: 12, color: AgroTheme.colorTextSecondary, height: 1.25),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AgroTheme.colorTextSecondary),
          ],
        ),
      ),
    );
  }
}