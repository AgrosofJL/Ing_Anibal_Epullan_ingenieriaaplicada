// AgroSoft J&L · PDF de Presupuesto / Pedido de cotización
// -----------------------------------------------------------------------------
// Ubicación: lib/servicios/presupuesto_pdf.dart
// Formato: logo arriba a la izquierda (logo/logo_anibal.png), título centrado,
// Fecha / Destinatario, texto de presentación con el emisor en negrita,
// tabla Servicio | Cantidad | Valor, total, condiciones, cierre y firma.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../presupuestos/servicios/presupuesto_modelo.dart';

class PresupuestoPdf {
  static const PdfColor _verde = PdfColor.fromInt(0xFF1E6B4C);
  static const PdfColor _verdeOscuro = PdfColor.fromInt(0xFF134E32);
  static const PdfColor _cabeceraTabla = PdfColor.fromInt(0xFFE2EFD9);
  static const PdfColor _bordeTabla = PdfColor.fromInt(0xFFB7CBA8);
  static const PdfColor _texto = PdfColor.fromInt(0xFF1F2933);
  static const PdfColor _gris = PdfColor.fromInt(0xFF6B7280);

  static pw.MemoryImage? _logoCache;

  static Future<pw.MemoryImage?> _logo() async {
    if (_logoCache != null) return _logoCache;
    for (final ruta in ['logo/logo_anibal.png', 'logo/logo.png']) {
      try {
        final ByteData b = await rootBundle.load(ruta);
        _logoCache = pw.MemoryImage(b.buffer.asUint8List());
        return _logoCache;
      } catch (_) {}
    }
    return null;
  }

  static String nombreArchivo(Presupuesto p) {
    final dest = p.destinatario.trim().isEmpty
        ? 'SinDestinatario'
        : p.destinatario
            .trim()
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
            .replaceAll(RegExp(r'\s+'), '_');
    return 'Presupuesto_${p.numeroTexto}_$dest.pdf';
  }

  /// La fuente por defecto (Helvetica) solo admite Latin-1: un "…", comillas
  /// tipográficas, "–" o "€" (habituales al tipear en el celular) hacen fallar
  /// la generación. Se reemplazan por equivalentes y se descarta el resto.
  static String _latin1(String s) {
    const reemplazos = {
      '\u2026': '...',
      '\u201C': '"',
      '\u201D': '"',
      '\u201E': '"',
      '\u2018': "'",
      '\u2019': "'",
      '\u201A': "'",
      '\u2013': '-',
      '\u2014': '-',
      '\u2212': '-',
      '\u2022': '-',
      '\u20AC': 'EUR',
    };
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (r <= 0xFF) {
        b.write(ch);
      } else {
        b.write(reemplazos[ch] ?? '');
      }
    }
    return b.toString();
  }

  static Presupuesto _saneado(Presupuesto o) {
    final c = o.copia();
    c.titulo = _latin1(c.titulo);
    c.destinatario = _latin1(c.destinatario);
    c.emisor = _latin1(c.emisor);
    c.firmante = _latin1(c.firmante);
    c.condiciones = _latin1(c.condiciones);
    c.textoCierre = _latin1(c.textoCierre);
    for (final i in c.items) {
      i.servicio = _latin1(i.servicio);
      i.detalle = _latin1(i.detalle);
      i.unidad = _latin1(i.unidad);
    }
    return c;
  }

  static Future<Uint8List> generar(Presupuesto original) async {
    final p = _saneado(original);
    final logo = await _logo();
    final doc = pw.Document(
      title: '${p.titulo} N° ${p.numeroTexto}',
      author: p.firmante.isNotEmpty ? p.firmante : 'AgroSoft J&L',
    );

    const estiloLabel = pw.TextStyle(fontSize: 10.5, color: _texto);

    pw.Widget filaDato(String label, String valor) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 9),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 100,
                child: pw.Text(label,
                    style: estiloLabel.copyWith(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Expanded(
                child: pw.Text(valor.isEmpty ? '-' : valor, style: estiloLabel),
              ),
            ],
          ),
        );

    pw.Widget celda(String txt,
            {bool bold = false,
            pw.TextAlign align = pw.TextAlign.left,
            String? sub}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: pw.Column(
            crossAxisAlignment: align == pw.TextAlign.right
                ? pw.CrossAxisAlignment.end
                : pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                txt,
                textAlign: align,
                style: pw.TextStyle(
                  fontSize: 10.5,
                  color: _texto,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
              if (sub != null && sub.trim().isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(sub,
                    textAlign: align,
                    style: const pw.TextStyle(fontSize: 8.5, color: _gris)),
              ],
            ],
          ),
        );

    final bool hayPrecioUnitario = p.items.any((i) => i.usaPrecioUnitario);

    final tabla = pw.Table(
      border: pw.TableBorder.all(color: _bordeTabla, width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _cabeceraTabla),
          children: [
            celda('Servicio', bold: true),
            celda('Cantidad', bold: true),
            celda('Valor', bold: true),
          ],
        ),
        ...p.items.map((it) => pw.TableRow(
              verticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                celda(it.servicio.isEmpty ? '-' : it.servicio, sub: it.detalle),
                celda(it.cantidadTexto),
                celda(
                  FormatoPresupuesto.importeConIva(it.importe, p.moneda, p.ivaModo),
                  align: pw.TextAlign.right,
                  sub: hayPrecioUnitario && it.usaPrecioUnitario
                      ? '${FormatoPresupuesto.importe(it.precioUnitario, p.moneda)} / ${_unidadSingular(it.unidad)}'
                      : null,
                ),
              ],
            )),
      ],
    );

    pw.Widget filaTotal(String label, String valor, {bool fuerte = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: fuerte ? 11 : 10,
                      color: fuerte ? _texto : _gris,
                      fontWeight:
                          fuerte ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.SizedBox(width: 12),
              pw.SizedBox(
                width: 120,
                child: pw.Text(valor,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: fuerte ? 11 : 10,
                        color: _texto,
                        fontWeight:
                            fuerte ? pw.FontWeight.bold : pw.FontWeight.normal)),
              ),
            ],
          ),
        );

    final List<String> condiciones = [
      if (p.validezDias > 0)
        'Validez de la oferta: ${p.validezDias} días desde la fecha de emisión.',
      ...p.condiciones
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 36, 48, 36),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text(
                  '${p.titulo} N° ${p.numeroTexto} · ${p.destinatario}',
                  style: const pw.TextStyle(fontSize: 8, color: _gris),
                ),
              ),
        footer: (ctx) => pw.Column(
          children: [
            pw.Divider(color: _bordeTabla, thickness: 0.6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  p.emisor.isEmpty ? 'AgroSoft J&L' : p.emisor,
                  style: const pw.TextStyle(fontSize: 7.5, color: _gris),
                ),
                pw.Text(
                  'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7.5, color: _gris),
                ),
              ],
            ),
          ],
        ),
        build: (ctx) => [
          // Logo arriba a la izquierda + número de presupuesto a la derecha
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.Container(
                  width: 90,
                  height: 60,
                  alignment: pw.Alignment.topLeft,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                )
              else
                pw.SizedBox(width: 90, height: 60),
              pw.Spacer(),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _bordeTabla, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('N° ${p.numeroTexto}',
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: _verdeOscuro)),
                    pw.Text(FormatoPresupuesto.fechaCorta(p.fecha),
                        style: const pw.TextStyle(fontSize: 8, color: _gris)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.Text(
              p.titulo.toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 19,
                fontWeight: pw.FontWeight.bold,
                color: _texto,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Container(width: 60, height: 2, color: _verde),
          ),
          pw.SizedBox(height: 22),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                filaDato('Fecha:', FormatoPresupuesto.fechaLarga(p.fecha)),
                filaDato('Destinatario:', p.destinatario),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 10.5, color: _texto, lineSpacing: 2),
              children: [
                pw.TextSpan(text: 'Por medio de la presente, '),
                pw.TextSpan(
                  text: p.emisor.isEmpty ? 'nuestra empresa' : p.emisor,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: ' presenta la siguiente cotización:'),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          tabla,
          pw.SizedBox(height: 16),
          if (p.ivaModo == IvaModo.discriminado) ...[
            filaTotal('Subtotal', FormatoPresupuesto.importe(p.subtotal, p.moneda)),
            filaTotal('IVA ${FormatoPresupuesto.numero(p.ivaPorc)}%',
                FormatoPresupuesto.importe(p.iva, p.moneda)),
            pw.SizedBox(height: 6),
          ],
          pw.Text(
            'Valor total del servicio: ${p.totalTexto}',
            style: pw.TextStyle(
              fontSize: 13.5,
              fontWeight: pw.FontWeight.bold,
              color: _texto,
            ),
          ),
          if (p.moneda == Moneda.usd)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text('Valores expresados en dólares estadounidenses.',
                  style: const pw.TextStyle(fontSize: 8.5, color: _gris)),
            ),
          if (condiciones.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF6FAF3),
                border: pw.Border(
                    left: const pw.BorderSide(color: _verde, width: 2.5)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Condiciones',
                      style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _verdeOscuro)),
                  pw.SizedBox(height: 4),
                  ...condiciones.map((c) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text('-  $c',
                            style: const pw.TextStyle(fontSize: 9, color: _texto)),
                      )),
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 22),
          pw.Text(
            p.textoCierre.trim().isEmpty ? kCierrePresupuestoDefault : p.textoCierre,
            style: const pw.TextStyle(fontSize: 10.5, color: _texto),
          ),
          if (p.firmante.trim().isNotEmpty) ...[
            pw.SizedBox(height: 46),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                children: [
                  pw.Container(width: 170, height: 0.8, color: _gris),
                  pw.SizedBox(height: 4),
                  pw.Text(p.firmante,
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  if (p.emisor.trim().isNotEmpty)
                    pw.Text(p.emisor,
                        style: const pw.TextStyle(fontSize: 8.5, color: _gris)),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static String _unidadSingular(String u) {
    final t = u.trim().toLowerCase();
    const mapa = {
      'hectáreas': 'ha',
      'hectareas': 'ha',
      'horas': 'hora',
      'jornadas': 'jornada',
      'visitas': 'visita',
      'litros': 'litro',
      'unidades': 'unidad',
    };
    return mapa[t] ?? (t.isEmpty ? 'unidad' : t);
  }
}
