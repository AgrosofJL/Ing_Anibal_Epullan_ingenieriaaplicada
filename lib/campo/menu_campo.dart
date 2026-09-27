// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../constantes/tema.dart';
import '../widgets/agro_reportes_ui.dart';
import '../widgets/agro_ui.dart';
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

  void _abrir(BuildContext context, Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    final modulos = <_ModuloCampo>[
      _ModuloCampo(
        titulo: "Estados fenológicos",
        descripcion:
            "Lectura de yemas, floración, cuaje y curvas de evolución por variedad.",
        tag: "Fenología",
        icono: Icons.eco_outlined,
        color: const Color(0xFF2E7D32),
        onTap: () => _abrir(
          context,
          FenologiaScreen(
            codProductor: codProductor,
            nombreProductor: nombreProductor,
          ),
        ),
      ),
      _ModuloCampo(
        titulo: "Ubicación de trampas",
        descripcion:
            "Mapeo satelital, georreferenciación GPS y códigos QR de trampas.",
        tag: "GPS / QR",
        icono: Icons.my_location_rounded,
        color: const Color(0xFF8A6A1E),
        onTap: () => _abrir(
          context,
          TrampasUbicacionScreen(
            codProductor: codProductor,
            nombreProductor: nombreProductor,
          ),
        ),
      ),
      _ModuloCampo(
        titulo: "Lecturas de trampas",
        descripcion:
            "Recuento semanal de capturas (Carpocapsa, Grafolita) y control de umbrales.",
        tag: "Sanidad",
        icono: Icons.pest_control_outlined,
        color: const Color(0xFFC62828),
        onTap: () => _abrir(
          context,
          LecturasTrampasScreen(
            codProductor: codProductor,
            nombreProductor: nombreProductor,
          ),
        ),
      ),
      _ModuloCampo(
        titulo: "Inventario de plantación",
        descripcion:
            "Catastro de cuarteles: superficies, variedades, marco, riego y UP.",
        tag: "Catastro",
        icono: Icons.park_outlined,
        color: const Color(0xFF1E6B4C),
        onTap: () => _abrir(
          context,
          InventarioPlantacionScreen(
            codProductor: codProductor,
            nombreProductor: nombreProductor,
          ),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      appBar: AgroAppBar(
        titulo: "Gestión en campo",
        subtitulo: nombreProductor,
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
                  titulo: "Operaciones y control de lote",
                  subtitulo:
                      "Seguimiento fenológico, trampeo fitosanitario e inventario de plantación.",
                  icono: Icons.agriculture_rounded,
                  chips: [
                    AgroHeaderChip(
                      texto: nombreProductor.trim().isEmpty
                          ? 'Establecimiento'
                          : nombreProductor,
                      icono: Icons.storefront_outlined,
                    ),
                    AgroHeaderChip(
                      texto: '${modulos.length} módulos',
                      icono: Icons.apps_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const AgroSectionHeader(
                  titulo: "Módulos de campo",
                  subtitulo: "Elegí la operación que querés registrar o consultar",
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
                      children: modulos
                          .map((m) => SizedBox(
                                width: w,
                                child: _ModuloCampoCard(modulo: m),
                              ))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 28),
                const Center(
                  child: Text(
                    "Los registros se guardan en el dispositivo y se sincronizan al conectarse.",
                    textAlign: TextAlign.center,
                    style: AgroText.secundario,
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

class _ModuloCampo {
  final String titulo;
  final String descripcion;
  final String tag;
  final IconData icono;
  final Color color;
  final VoidCallback onTap;

  const _ModuloCampo({
    required this.titulo,
    required this.descripcion,
    required this.tag,
    required this.icono,
    required this.color,
    required this.onTap,
  });
}

class _ModuloCampoCard extends StatelessWidget {
  final _ModuloCampo modulo;

  const _ModuloCampoCard({required this.modulo});

  @override
  Widget build(BuildContext context) {
    final c = modulo.color;
    return AgroCard(
      onTap: modulo.onTap,
      accentColor: c,
      padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
      child: Row(
        children: [
          AgroIconBox(icono: modulo.icono, color: c, size: 50),
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
                        modulo.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgroText.tituloCard,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AgroBadge(texto: modulo.tag, color: c),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  modulo.descripcion,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AgroText.secundario.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded,
              color: AgroTheme.colorTextSecondary),
        ],
      ),
    );
  }
}
