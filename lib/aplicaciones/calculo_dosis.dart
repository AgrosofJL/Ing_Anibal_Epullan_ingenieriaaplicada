// AgroSoft J&L · Cálculo de dosis y cantidades de producto
// -----------------------------------------------------------------------------
// Ubicación: lib/aplicaciones/calculo_dosis.dart
//
// Reglas (definidas por el ingeniero):
//
//  • Dosis cada 100 L (máquina de 2000 L):
//      dosisMaq  = dosis100 × (2000 / 100)
//      cantMaq   = (Sup. total × caldo L/Ha) / 2000      ← cantidad de máquinas
//      cantProd  = cantMaq × dosisMaq
//
//  • Dosis por Ha:
//      cantProd  = dosis/Ha × Sup. total
//      (dosisMaq = dosis/Ha × Ha que cubre una máquina, solo informativo)
//
// Sirve tanto para los ítems de la receta en armado (nueva_receta: usan
// 'metodo_dosis' y 'dosis_valor') como para las filas guardadas en
// recetas_aplicaciones (usan 'dosis_x' y la dosis/Ha en 'vol_aplic_ha').

class CalculoDosis {
  /// Capacidad de la máquina pulverizadora (litros).
  static const double volumenMaquina = 2000.0;

  static double _n(dynamic v) =>
      double.tryParse('${v ?? ''}'.replaceAll(',', '.').trim()) ?? 0.0;

  /// true si el producto se dosifica por hectárea.
  static bool esPorHa(Map<String, dynamic> it) {
    final x = (it['dosis_x'] ?? '').toString().trim().toLowerCase();
    if (x == 'dosis_ha') return true;
    if (x == 'vol_100') return false;
    return (it['metodo_dosis'] ?? '').toString().trim().toUpperCase() ==
        'DOSIS_HA';
  }

  /// Dosis por Ha (L o Kg de producto por hectárea).
  static double dosisPorHa(Map<String, dynamic> it) {
    final dv = _n(it['dosis_valor']);
    return dv > 0 ? dv : _n(it['vol_aplic_ha']);
  }

  /// Dosis cada 100 L de caldo.
  static double dosis100(Map<String, dynamic> it) => _n(it['dosis_100']);

  /// Cantidad de máquinas (tanques de 2000 L) para cubrir la superficie.
  static double cantidadMaquinas(double supTotal, double caldoHa) =>
      volumenMaquina > 0 ? (supTotal * caldoHa) / volumenMaquina : 0.0;

  /// Producto por máquina de 2000 L.
  static double dosisMaquina(Map<String, dynamic> it, double caldoHa) {
    if (esPorHa(it)) {
      return caldoHa > 0 ? dosisPorHa(it) * (volumenMaquina / caldoHa) : 0.0;
    }
    final dm = _n(it['dosis_maq']);
    return dm > 0 ? dm : dosis100(it) * (volumenMaquina / 100.0);
  }

  /// Cantidad total de producto para la superficie indicada.
  static double cantidadProducto(
    Map<String, dynamic> it,
    double supTotal,
    double caldoHa,
  ) {
    if (esPorHa(it)) return dosisPorHa(it) * supTotal;
    return cantidadMaquinas(supTotal, caldoHa) * dosisMaquina(it, caldoHa);
  }

  /// Texto de la dosis prescripta: "1.5 /100 L" o "2 /Ha".
  static String textoDosis(Map<String, dynamic> it) {
    final v = esPorHa(it) ? dosisPorHa(it) : dosis100(it);
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return esPorHa(it) ? '$s /Ha' : '$s /100 L';
  }

  // ---------------------------------------------------------------------------
  // REGISTRO DE UNA TANDA (el operario carga los LITROS TOTALES aplicados)
  // ---------------------------------------------------------------------------
  //  volHa        = litros totales ÷ Sup. total de la tanda
  //  litros combo = volHa × Ha de la combinación (cuadro + variedad)
  //  Producto total de la tanda:
  //     por 100 L → (litros totales ÷ 2000) × dosisMaq
  //     por Ha    → dosis/Ha × Sup. total
  //  Ese total se REPARTE entre las combinaciones según su Ha
  //  (la suma de lo repartido da exactamente el total).

  /// Cantidad total de producto para una tanda con [litrosTotales] en [supTotal].
  static double totalProductoTanda(
    Map<String, dynamic> it,
    double supTotal,
    double litrosTotales,
  ) {
    if (esPorHa(it)) return dosisPorHa(it) * supTotal;
    final double volHa = supTotal > 0 ? litrosTotales / supTotal : 0.0;
    return (litrosTotales / volumenMaquina) * dosisMaquina(it, volHa);
  }

  /// Reparte [total] según las hectáreas de cada combinación.
  /// La última absorbe el redondeo para que la suma sea exacta.
  static List<double> repartirPorHa(double total, List<double> has) {
    final double sup = has.fold(0.0, (s, h) => s + h);
    if (has.isEmpty) return const [];
    if (sup <= 0) return List<double>.filled(has.length, 0.0);
    final List<double> res = [];
    double acumulado = 0.0;
    for (int i = 0; i < has.length; i++) {
      if (i == has.length - 1) {
        res.add(total - acumulado);
      } else {
        final double parte =
            double.parse((total * has[i] / sup).toStringAsFixed(6));
        res.add(parte);
        acumulado += parte;
      }
    }
    return res;
  }
}
