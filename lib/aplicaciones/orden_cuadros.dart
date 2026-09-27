// AgroSoft J&L · Cuadros de una orden (una o varias chacras)
// -----------------------------------------------------------------------------
// Ubicación: lib/aplicaciones/orden_cuadros.dart
//
// Formato guardado en recetas_aplicaciones (compatible con órdenes viejas):
//
//   • Una sola chacra (igual que siempre):
//       chacra  = "5"
//       cuadros = "1, 2, 3"
//
//   • Varias chacras:
//       chacra  = "5, 7"
//       cuadros = "5:1, 5:2, 7:3"      (chacra:cuadro)
//
// Toda la app debe leer/escribir los cuadros de una orden con estas funciones.

/// Referencia a un cuadro dentro de una chacra.
class CuadroRef {
  final String chacra;
  final String cuadro;

  const CuadroRef(this.chacra, this.cuadro);

  /// Clave única para sets/maps.
  String get clave => claveCuadro(chacra, cuadro);

  @override
  bool operator ==(Object other) =>
      other is CuadroRef && other.chacra == chacra && other.cuadro == cuadro;

  @override
  int get hashCode => Object.hash(chacra, cuadro);

  @override
  String toString() => '$chacra:$cuadro';
}

/// Clave única "chacra::cuadro" (normalizada).
String claveCuadro(dynamic chacra, dynamic cuadro) =>
    '${(chacra ?? '').toString().trim()}::${normalizarCuadro(cuadro)}';

/// Limpia textos tipo "Cuadro 5" / "C.5" → "5" (misma regla que se usaba antes).
String normalizarCuadro(dynamic v) => (v ?? '')
    .toString()
    .trim()
    .replaceAll(RegExp(r'cuadro', caseSensitive: false), '')
    .replaceAll('C.', '')
    .trim();

/// Lee los cuadros de una orden a partir de sus campos `chacra` y `cuadros`.
List<CuadroRef> parsearCuadrosOrden(dynamic chacraCampo, dynamic cuadrosCampo) {
  final String chacraBase = (chacraCampo ?? '').toString().trim();
  final String texto = (cuadrosCampo ?? '').toString();
  final List<CuadroRef> res = [];
  final Set<String> vistos = {};

  for (final token in texto.split(',')) {
    final t = token.trim();
    if (t.isEmpty) continue;

    String ch;
    String cd;
    final int idx = t.lastIndexOf(':');
    if (idx > 0) {
      ch = t.substring(0, idx).trim();
      cd = normalizarCuadro(t.substring(idx + 1));
    } else {
      ch = chacraBase;
      cd = normalizarCuadro(t);
    }
    if (cd.isEmpty) continue;

    final ref = CuadroRef(ch, cd);
    if (vistos.add(ref.clave)) res.add(ref);
  }
  return res;
}

/// Chacras distintas de una orden, en orden de aparición.
List<String> chacrasDeOrden(dynamic chacraCampo, dynamic cuadrosCampo) {
  final refs = parsearCuadrosOrden(chacraCampo, cuadrosCampo);
  final List<String> res = [];
  for (final r in refs) {
    if (!res.contains(r.chacra)) res.add(r.chacra);
  }
  if (res.isEmpty) {
    final base = (chacraCampo ?? '').toString().trim();
    if (base.isNotEmpty) res.add(base);
  }
  return res;
}

/// Campos listos para guardar en recetas_aplicaciones.
class CamposCuadros {
  final String chacra;
  final String cuadros;
  const CamposCuadros(this.chacra, this.cuadros);
}

/// Arma los campos `chacra` y `cuadros` para guardar.
CamposCuadros serializarCuadrosOrden(List<CuadroRef> refs) {
  final ordenadas = [...refs]..sort((a, b) {
      final c = compararNatural(a.chacra, b.chacra);
      return c != 0 ? c : compararNatural(a.cuadro, b.cuadro);
    });

  final List<String> chacras = [];
  for (final r in ordenadas) {
    if (!chacras.contains(r.chacra)) chacras.add(r.chacra);
  }

  if (chacras.length <= 1) {
    return CamposCuadros(
      chacras.isEmpty ? '' : chacras.first,
      ordenadas.map((r) => r.cuadro).join(', '),
    );
  }
  return CamposCuadros(
    chacras.join(', '),
    ordenadas.map((r) => '${r.chacra}:${r.cuadro}').join(', '),
  );
}

/// Texto legible: "Ch 5: 1, 2 · Ch 7: 3" (o "1, 2, 3" si es una sola chacra).
String cuadrosLegibles(List<CuadroRef> refs) {
  final Map<String, List<String>> m = {};
  for (final r in refs) {
    m.putIfAbsent(r.chacra, () => []).add(r.cuadro);
  }
  if (m.length <= 1) {
    return refs.map((r) => r.cuadro).join(', ');
  }
  final claves = m.keys.toList()..sort(compararNatural);
  return claves
      .map((k) => 'Ch $k: ${(m[k]!..sort(compararNatural)).join(', ')}')
      .join(' · ');
}

/// Orden "natural": 2 < 10, y si no hay números, alfabético.
int compararNatural(String a, String b) {
  final na = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
  final nb = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  return a.toLowerCase().compareTo(b.toLowerCase());
}

// -----------------------------------------------------------------------------
// Cultivos / variedades a tratar de una orden
// -----------------------------------------------------------------------------
// Se guardan en recetas_aplicaciones y ordenes_aplicaciones, columnas
// `cultivos` y `variedades`, como texto separado por ";" (vacío = todos).
// Ej: cultivos = "Cerezo;Ciruelo"  variedades = ""  → todas las variedades
//     de esos cultivos.

/// Texto guardado → conjunto. Vacío/null = sin restricción.
Set<String> parsearFiltroOrden(dynamic v) => (v ?? '')
    .toString()
    .split(';')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toSet();

/// Conjunto → texto para guardar (ordenado para que sea estable).
String serializarFiltroOrden(Set<String> valores) =>
    (valores.toList()..sort()).join(';');

/// true si una fila de inventario entra en la orden según cultivos/variedades.
/// La comparación ignora mayúsculas y espacios.
bool coincideFiltroOrden(
  dynamic cultivo,
  dynamic variedad,
  Set<String> cultivos,
  Set<String> variedades,
) {
  String n(dynamic x) => (x ?? '').toString().trim().toLowerCase();
  final cul = n(cultivo);
  final vr = n(variedad);
  final okCul = cultivos.isEmpty || cultivos.any((c) => n(c) == cul);
  final okVr = variedades.isEmpty || variedades.any((v) => n(v) == vr);
  return okCul && okVr;
}
