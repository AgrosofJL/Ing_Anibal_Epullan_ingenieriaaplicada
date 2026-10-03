// AgroSoft J&L · Presupuestos — modelo, formato y acceso a datos
// -----------------------------------------------------------------------------
// Ubicación: lib/presupuestos/presupuesto_modelo.dart
//
// Tablas locales (se sincronizan con Supabase vía SyncConfig):
//   presupuestos        → cabecera (pk cod_presupuesto)
//   presupuestos_items  → renglones (pk cod_item = "<cod_presupuesto>-<orden>")

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../base/base.dart';

// ============================================================
// CONSTANTES
// ============================================================

class EstadoPresupuesto {
  static const String borrador = 'BORRADOR';
  static const String enviado = 'ENVIADO';
  static const String aceptado = 'ACEPTADO';
  static const String rechazado = 'RECHAZADO';

  static const List<String> todos = [borrador, enviado, aceptado, rechazado];

  static String etiqueta(String e) {
    switch (e) {
      case enviado:
        return 'Enviado';
      case aceptado:
        return 'Aceptado';
      case rechazado:
        return 'Rechazado';
      default:
        return 'Borrador';
    }
  }
}

class IvaModo {
  /// "$ 150.000 + IVA"
  static const String masIva = 'MAS_IVA';

  /// "$ 150.000 (IVA incluido)"
  static const String incluido = 'INCLUIDO';

  /// Subtotal + IVA discriminado + Total
  static const String discriminado = 'DISCRIMINADO';
}

class Moneda {
  static const String ars = 'ARS';
  static const String usd = 'USD';

  static String simbolo(String m) => m == usd ? 'U\$S' : '\$';
}

const String kTituloPresupuestoDefault = 'PEDIDO DE COTIZACIÓN';
const String kCierrePresupuestoDefault =
    'Sin otro particular, quedamos a disposición para cualquier consulta o requerimiento adicional.';

const List<String> kServiciosSugeridos = [
  'Servicio de aplicación con dron',
  'Pulverización terrestre',
  'Asesoramiento técnico agronómico',
  'Monitoreo de plagas y trampeo',
  'Relevamiento fenológico',
  'Mapeo / vuelo de relevamiento con dron',
];

const List<String> kUnidadesSugeridas = [
  'hectáreas',
  'horas',
  'jornadas',
  'visitas',
  'servicio',
  'litros',
  'km',
];

// ============================================================
// FORMATO (sin depender de inicializar locales de intl)
// ============================================================

class FormatoPresupuesto {
  static const List<String> _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// "2 de octubre de 2026"
  static String fechaLarga(DateTime f) =>
      '${f.day} de ${_meses[f.month - 1]} de ${f.year}';

  /// "02/10/2026"
  static String fechaCorta(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  static String fechaIso(DateTime f) =>
      '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

  static DateTime parseFecha(String? s) =>
      DateTime.tryParse((s ?? '').split('T').first) ?? DateTime.now();

  /// Número con punto de miles y coma decimal: 150000 → "150.000", 2.5 → "2,5".
  static String numero(double v, {int maxDecimales = 2}) {
    final bool negativo = v < 0;
    double a = v.abs();
    String txt = a.toStringAsFixed(maxDecimales);
    String entero = txt.split('.').first;
    String dec = txt.contains('.') ? txt.split('.').last : '';
    dec = dec.replaceAll(RegExp(r'0+$'), '');

    final buf = StringBuffer();
    for (int i = 0; i < entero.length; i++) {
      final desdeFin = entero.length - i;
      buf.write(entero[i]);
      if (desdeFin > 1 && desdeFin % 3 == 1) buf.write('.');
    }
    final r = dec.isEmpty ? buf.toString() : '${buf.toString()},$dec';
    return negativo ? '-$r' : r;
  }

  /// "$ 150.000" / "U$S 1.250,50"
  static String importe(double v, String moneda) {
    final redondo = (v * 100).roundToDouble() / 100;
    final bool tieneCentavos = (redondo - redondo.truncate()).abs() > 0.0001;
    String txt = numero(redondo);
    if (tieneCentavos && !txt.contains(RegExp(r',\d\d$'))) txt = '${txt}0';
    return '${Moneda.simbolo(moneda)} $txt';
  }

  /// Importe con la leyenda de IVA según el modo.
  static String importeConIva(double v, String moneda, String ivaModo) {
    final base = importe(v, moneda);
    if (ivaModo == IvaModo.masIva) return '$base + IVA';
    return base;
  }

  /// Interpreta "150.000", "150000", "2,5", "1.250,50".
  static double parseNumero(String s) {
    var t = s.trim().replaceAll(' ', '').replaceAll('\$', '');
    if (t.isEmpty) return 0;
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
      // "150.000" → miles
      t = t.replaceAll('.', '');
    }
    return double.tryParse(t) ?? 0;
  }

  /// Número para poner en un TextField al editar (2.5 → "2,5").
  static String numeroEditable(double v) => v == 0 ? '' : numero(v, maxDecimales: 4);

  static String numeroPresupuesto(int n) => n.toString().padLeft(4, '0');
}

// ============================================================
// MODELO
// ============================================================

class ItemPresupuesto {
  String servicio;
  String detalle;
  double cantidad;
  String unidad;

  /// Opcional: si se carga, el importe = cantidad × precio unitario.
  double precioUnitario;
  double importe;

  ItemPresupuesto({
    this.servicio = '',
    this.detalle = '',
    this.cantidad = 0,
    this.unidad = 'hectáreas',
    this.precioUnitario = 0,
    this.importe = 0,
  });

  ItemPresupuesto copia() => ItemPresupuesto(
        servicio: servicio,
        detalle: detalle,
        cantidad: cantidad,
        unidad: unidad,
        precioUnitario: precioUnitario,
        importe: importe,
      );

  bool get usaPrecioUnitario => precioUnitario > 0;

  /// "2,5 hectáreas"
  String get cantidadTexto {
    if (cantidad <= 0) return unidad.isEmpty ? '-' : unidad;
    return '${FormatoPresupuesto.numero(cantidad)} $unidad'.trim();
  }

  factory ItemPresupuesto.desdeFila(Map<String, dynamic> f) => ItemPresupuesto(
        servicio: (f['servicio'] ?? '').toString(),
        detalle: (f['detalle'] ?? '').toString(),
        cantidad: _d(f['cantidad']),
        unidad: (f['unidad'] ?? '').toString(),
        precioUnitario: _d(f['precio_unitario']),
        importe: _d(f['importe']),
      );

  Map<String, dynamic> aFila(String codPresupuesto, int orden) => {
        'cod_item': '$codPresupuesto-$orden',
        'cod_presupuesto': codPresupuesto,
        'orden': orden,
        'servicio': servicio.trim(),
        'detalle': detalle.trim(),
        'cantidad': cantidad,
        'unidad': unidad.trim(),
        'precio_unitario': precioUnitario,
        'importe': importe,
        'sincronizado': 0,
      };
}

class Presupuesto {
  String cod;
  int numero;
  String titulo;
  DateTime fecha;
  String destinatario;
  String emisor;
  int? codProductor;
  String moneda;
  String ivaModo;
  double ivaPorc;
  int validezDias;
  String condiciones;
  String textoCierre;
  String firmante;
  String estado;
  String usuario;
  String createdAt;
  List<ItemPresupuesto> items;

  Presupuesto({
    required this.cod,
    this.numero = 0,
    this.titulo = kTituloPresupuestoDefault,
    DateTime? fecha,
    this.destinatario = '',
    this.emisor = '',
    this.codProductor,
    this.moneda = Moneda.ars,
    this.ivaModo = IvaModo.masIva,
    this.ivaPorc = 21,
    this.validezDias = 15,
    this.condiciones = '',
    this.textoCierre = kCierrePresupuestoDefault,
    this.firmante = '',
    this.estado = EstadoPresupuesto.borrador,
    this.usuario = '',
    this.createdAt = '',
    List<ItemPresupuesto>? items,
  })  : fecha = fecha ?? DateTime.now(),
        items = items ?? [];

  // ---- Totales ----

  double get sumaItems => items.fold(0.0, (a, i) => a + i.importe);

  /// Neto sin IVA.
  double get subtotal {
    if (ivaModo == IvaModo.incluido && ivaPorc > 0) {
      return sumaItems / (1 + ivaPorc / 100);
    }
    return sumaItems;
  }

  double get iva {
    if (ivaModo == IvaModo.discriminado) return sumaItems * ivaPorc / 100;
    if (ivaModo == IvaModo.incluido) return sumaItems - subtotal;
    return 0;
  }

  /// Total a mostrar como "Valor total del servicio".
  double get total {
    if (ivaModo == IvaModo.discriminado) return sumaItems + iva;
    return sumaItems;
  }

  String get totalTexto {
    final base = FormatoPresupuesto.importe(total, moneda);
    switch (ivaModo) {
      case IvaModo.masIva:
        return '$base + IVA';
      case IvaModo.incluido:
        return '$base (IVA incluido)';
      default:
        return base;
    }
  }

  String get numeroTexto => FormatoPresupuesto.numeroPresupuesto(numero);

  Presupuesto copia() => Presupuesto(
        cod: cod,
        numero: numero,
        titulo: titulo,
        fecha: fecha,
        destinatario: destinatario,
        emisor: emisor,
        codProductor: codProductor,
        moneda: moneda,
        ivaModo: ivaModo,
        ivaPorc: ivaPorc,
        validezDias: validezDias,
        condiciones: condiciones,
        textoCierre: textoCierre,
        firmante: firmante,
        estado: estado,
        usuario: usuario,
        createdAt: createdAt,
        items: items.map((e) => e.copia()).toList(),
      );

  factory Presupuesto.desdeFila(
      Map<String, dynamic> f, List<Map<String, dynamic>> filasItems) {
    return Presupuesto(
      cod: (f['cod_presupuesto'] ?? '').toString(),
      numero: int.tryParse(f['numero']?.toString() ?? '') ?? 0,
      titulo: _txt(f['titulo'], kTituloPresupuestoDefault),
      fecha: FormatoPresupuesto.parseFecha(f['fecha']?.toString()),
      destinatario: (f['destinatario'] ?? '').toString(),
      emisor: (f['emisor'] ?? '').toString(),
      codProductor: int.tryParse(f['cod_productor']?.toString() ?? ''),
      moneda: _txt(f['moneda'], Moneda.ars),
      ivaModo: _txt(f['iva_modo'], IvaModo.masIva),
      ivaPorc: f['iva_porc'] == null ? 21 : _d(f['iva_porc']),
      validezDias: int.tryParse(f['validez_dias']?.toString() ?? '') ?? 0,
      condiciones: (f['condiciones'] ?? '').toString(),
      textoCierre: (f['texto_cierre'] ?? kCierrePresupuestoDefault).toString(),
      firmante: (f['firmante'] ?? '').toString(),
      estado: _txt(f['estado'], EstadoPresupuesto.borrador).toUpperCase(),
      usuario: (f['usuario'] ?? '').toString(),
      createdAt: (f['created_at'] ?? '').toString(),
      items: filasItems.map(ItemPresupuesto.desdeFila).toList(),
    );
  }

  Map<String, dynamic> aFila() => {
        'cod_presupuesto': cod,
        'numero': numero,
        'titulo': titulo.trim().isEmpty ? kTituloPresupuestoDefault : titulo.trim(),
        'fecha': FormatoPresupuesto.fechaIso(fecha),
        'destinatario': destinatario.trim(),
        'emisor': emisor.trim(),
        'cod_productor': codProductor,
        'moneda': moneda,
        'iva_modo': ivaModo,
        'iva_porc': ivaPorc,
        'subtotal': _r2(subtotal),
        'iva': _r2(iva),
        'total': _r2(total),
        'validez_dias': validezDias,
        'condiciones': condiciones.trim(),
        'texto_cierre': textoCierre.trim(),
        'firmante': firmante.trim(),
        'estado': estado,
        'usuario': usuario,
        'created_at': createdAt.isEmpty ? DateTime.now().toIso8601String() : createdAt,
        'actualizado_el': DateTime.now().toIso8601String(),
        'sincronizado': 0,
      };
}

double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
double _r2(double v) => (v * 100).roundToDouble() / 100;
String _txt(dynamic v, String def) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? def : s;
}

// ============================================================
// REPOSITORIO
// ============================================================

class RepositorioPresupuestos {
  static const String tabla = 'presupuestos';
  static const String tablaItems = 'presupuestos_items';

  static const String _prefEmisor = 'presupuesto_ultimo_emisor';
  static const String _prefFirmante = 'presupuesto_ultimo_firmante';

  static Future<Database> get _db => DatabaseHelper.instance.database;

  /// Código único entre dispositivos: PRE-<milisegundos>.
  static String nuevoCodigo() => 'PRE-${DateTime.now().millisecondsSinceEpoch}';

  static Future<int> siguienteNumero() async {
    final db = await _db;
    final r = await db.rawQuery(
        'SELECT MAX(CAST(numero AS INTEGER)) AS m FROM $tabla');
    final int m = int.tryParse(r.first['m']?.toString() ?? '') ?? 0;
    return m + 1;
  }

  /// Arma un presupuesto nuevo con los últimos datos usados.
  static Future<Presupuesto> nuevo({int? codProductor}) async {
    final prefs = await SharedPreferences.getInstance();
    return Presupuesto(
      cod: nuevoCodigo(),
      numero: await siguienteNumero(),
      emisor: prefs.getString(_prefEmisor) ?? '',
      firmante: prefs.getString(_prefFirmante) ?? (prefs.getString('userName') ?? ''),
      usuario: prefs.getString('userName') ?? '',
      codProductor: codProductor,
      items: [ItemPresupuesto(servicio: kServiciosSugeridos.first)],
    );
  }

  static Future<List<Presupuesto>> listar() async {
    final db = await _db;
    final cabs = await db.query(tabla, orderBy: 'fecha DESC, numero DESC');
    final its = await db.query(tablaItems, orderBy: 'cod_presupuesto, orden ASC');
    final Map<String, List<Map<String, dynamic>>> porCod = {};
    for (final i in its) {
      porCod.putIfAbsent((i['cod_presupuesto'] ?? '').toString(), () => []).add(i);
    }
    return cabs
        .map((c) => Presupuesto.desdeFila(
            c, porCod[(c['cod_presupuesto'] ?? '').toString()] ?? const []))
        .toList();
  }

  /// Guarda cabecera + renglones en una transacción.
  /// Los renglones que sobran se borran (los triggers encolan el borrado arriba).
  static Future<void> guardar(Presupuesto p) async {
    final db = await _db;
    await db.transaction((txn) async {
      final fila = p.aFila();
      final existe = await txn.query(tabla,
          columns: ['cod_presupuesto'],
          where: 'cod_presupuesto = ?',
          whereArgs: [p.cod],
          limit: 1);
      if (existe.isEmpty) {
        await txn.insert(tabla, fila);
      } else {
        await txn.update(tabla, fila,
            where: 'cod_presupuesto = ?', whereArgs: [p.cod]);
      }

      for (int i = 0; i < p.items.length; i++) {
        final f = p.items[i].aFila(p.cod, i + 1);
        final n = await txn.update(tablaItems, f,
            where: 'cod_item = ?', whereArgs: [f['cod_item']]);
        if (n == 0) await txn.insert(tablaItems, f);
      }
      await txn.delete(tablaItems,
          where: 'cod_presupuesto = ? AND orden > ?',
          whereArgs: [p.cod, p.items.length]);
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      if (p.emisor.trim().isNotEmpty) {
        await prefs.setString(_prefEmisor, p.emisor.trim());
      }
      if (p.firmante.trim().isNotEmpty) {
        await prefs.setString(_prefFirmante, p.firmante.trim());
      }
    } catch (e) {
      debugPrint('Aviso guardando preferencias de presupuesto: $e');
    }
  }

  static Future<void> cambiarEstado(String cod, String estado) async {
    final db = await _db;
    await db.update(
      tabla,
      {
        'estado': estado,
        'actualizado_el': DateTime.now().toIso8601String(),
        'sincronizado': 0,
      },
      where: 'cod_presupuesto = ?',
      whereArgs: [cod],
    );
  }

  static Future<void> eliminar(String cod) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(tablaItems, where: 'cod_presupuesto = ?', whereArgs: [cod]);
      await txn.delete(tabla, where: 'cod_presupuesto = ?', whereArgs: [cod]);
    });
  }

  /// Copia como borrador nuevo, con fecha de hoy y nuevo número.
  static Future<Presupuesto> duplicar(Presupuesto origen) async {
    final c = origen.copia();
    c.cod = nuevoCodigo();
    c.numero = await siguienteNumero();
    c.fecha = DateTime.now();
    c.estado = EstadoPresupuesto.borrador;
    c.createdAt = '';
    await guardar(c);
    return c;
  }

  /// Valores usados antes (para sugerir al escribir).
  static Future<List<String>> valoresUsados(String columna) async {
    final db = await _db;
    final r = await db.rawQuery(
        'SELECT DISTINCT TRIM($columna) AS v FROM $tabla '
        "WHERE $columna IS NOT NULL AND TRIM($columna) <> '' ORDER BY v");
    return r.map((e) => (e['v'] ?? '').toString()).toList();
  }

  static Future<List<String>> serviciosUsados() async {
    final db = await _db;
    final r = await db.rawQuery(
        'SELECT DISTINCT TRIM(servicio) AS v FROM $tablaItems '
        "WHERE servicio IS NOT NULL AND TRIM(servicio) <> '' ORDER BY v");
    return r.map((e) => (e['v'] ?? '').toString()).toList();
  }

  static Future<List<String>> nombresProductores() async {
    final db = await _db;
    try {
      final r = await db.query('productores',
          columns: ['productor'], orderBy: 'productor ASC');
      return r
          .map((e) => (e['productor'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
