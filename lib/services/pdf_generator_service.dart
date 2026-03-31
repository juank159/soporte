import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/service_order.dart';
import '../models/tenant.dart';
import '../config/date_utils.dart';

/// Genera el PDF del Acta de Entrega de Servicio Tecnico.
/// Formato tipo carta basado en el modelo del cliente.
class PdfGeneratorService {
  Future<Uint8List> generateDeliveryAct({
    required ServiceOrder order,
    required Tenant tenant,
    required Uint8List clientSignaturePng,
    required String clientName,
    required Uint8List technicianSignaturePng,
    required String technicianName,
    DateTime? deliveryDate,
  }) async {
    final pdf = pw.Document(
      title: 'Acta de Entrega - ${order.orderNumber}',
      author: tenant.name,
    );

    final now = deliveryDate ?? DateTime.now();
    final dateStr = AppDateUtils.formatDate(now);

    final device = order.device;
    final customer = order.customer;
    final equipoDesc =
        '${device?.type ?? ''} ${device?.brand ?? ''} ${device?.model ?? ''}'.trim();
    final serialText = device?.serial ?? device?.imei ?? 'N/A';
    final totalStr = _formatMoney(order.total);
    final warrantyMonths = (order.warrantyDays / 30).round();
    final hasWarranty = order.warrantyDays > 0;

    // Logo
    pw.Widget? logoWidget;
    if (tenant.logoUrl != null &&
        tenant.logoUrl!.startsWith('data:') &&
        tenant.logoUrl!.contains(',')) {
      try {
        final logoBytes = base64Decode(tenant.logoUrl!.split(',').last);
        logoWidget = pw.Image(pw.MemoryImage(logoBytes), height: 60);
      } catch (_) {}
    }

    // Signatures - validate PNG header (0x89 0x50 0x4E 0x47)
    pw.Widget? clientSigWidget;
    pw.Widget? techSigWidget;
    if (clientSignaturePng.length > 50 &&
        clientSignaturePng[0] == 0x89 &&
        clientSignaturePng[1] == 0x50) {
      try {
        clientSigWidget =
            pw.Image(pw.MemoryImage(clientSignaturePng), height: 50);
      } catch (_) {}
    }
    if (technicianSignaturePng.length > 50 &&
        technicianSignaturePng[0] == 0x89 &&
        technicianSignaturePng[1] == 0x50) {
      try {
        techSigWidget =
            pw.Image(pw.MemoryImage(technicianSignaturePng), height: 50);
      } catch (_) {}
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 50, vertical: 40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ========== HEADER ==========
              pw.Center(
                child: pw.Column(
                  children: [
                    if (logoWidget != null) ...[
                      logoWidget,
                      pw.SizedBox(height: 6),
                    ],
                    pw.Text(
                      tenant.name.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (tenant.nit != null && tenant.nit!.isNotEmpty)
                      pw.Text(
                        'NIT ${tenant.nit}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // ========== CLIENT DATA ==========
              _labelLine('FECHA', dateStr),
              pw.SizedBox(height: 8),
              _labelLine('CEDULA', customer?.idNumber ?? '-'),
              pw.SizedBox(height: 8),
              _labelLine('NOMBRE', customer?.fullName ?? '-'),
              pw.SizedBox(height: 8),
              _labelLine('TELEFONO', customer?.phone ?? '-'),
              pw.SizedBox(height: 8),
              _labelLine('ORDEN No.', order.orderNumber),
              pw.SizedBox(height: 30),

              // ========== TITLE ==========
              pw.Text(
                'ACTA DE ENTREGA DE SERVICIO TECNICO',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),

              // ========== BODY TEXT ==========
              pw.RichText(
                textAlign: pw.TextAlign.justify,
                text: pw.TextSpan(
                  style: const pw.TextStyle(fontSize: 11, lineSpacing: 6),
                  children: [
                    const pw.TextSpan(text: 'Se le hace entrega de '),
                    pw.TextSpan(
                      text: equipoDesc,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    if (serialText != 'N/A') ...[
                      const pw.TextSpan(text: ' S/N: '),
                      pw.TextSpan(
                        text: serialText,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                    const pw.TextSpan(
                        text: ' que ingreso a nuestras instalaciones el dia '),
                    pw.TextSpan(
                      text: AppDateUtils.formatDate(order.createdAt),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    const pw.TextSpan(
                        text: ' presentando la siguiente falla y condicion: '),
                    pw.TextSpan(
                      text: order.problemReported,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),

              // Diagnosis / work done
              if (order.diagnosis != null && order.diagnosis!.isNotEmpty)
                pw.RichText(
                  textAlign: pw.TextAlign.justify,
                  text: pw.TextSpan(
                    style: const pw.TextStyle(fontSize: 11, lineSpacing: 6),
                    children: [
                      const pw.TextSpan(text: 'Cual se le realizo: '),
                      pw.TextSpan(
                        text: order.diagnosis!,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              pw.SizedBox(height: 12),

              // Amount
              pw.RichText(
                textAlign: pw.TextAlign.justify,
                text: pw.TextSpan(
                  style: const pw.TextStyle(fontSize: 11, lineSpacing: 6),
                  children: [
                    const pw.TextSpan(text: 'Por un monto de '),
                    pw.TextSpan(
                      text: '\$$totalStr',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const pw.TextSpan(
                        text:
                            ' se le entrega probado y a satisfaccion del mismo, se le explican los cuidados que debe tener con el equipo, se le aclara a nuestro cliente que la garantia de dicho arreglo es instantanea. '),
                    if (hasWarranty) ...[
                      const pw.TextSpan(text: 'Si '),
                      pw.TextSpan(
                        text: 'X',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      const pw.TextSpan(text: ', No___. De lo contrario cuenta con '),
                      pw.TextSpan(
                        text: '$warrantyMonths',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      const pw.TextSpan(
                          text:
                              ' meses de garantia. No nos hacemos cargo de lo que suceda despues de dicho tiempo, puesto que el cuidado y durabilidad depende de usted.'),
                    ] else ...[
                      const pw.TextSpan(text: 'Si___, No '),
                      pw.TextSpan(
                        text: 'X',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      const pw.TextSpan(text: '.'),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Items detail if any
              if (order.items.isNotEmpty) ...[
                pw.Text('Detalle:',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                ...order.items.map((item) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Text(
                        '  - ${item.qty}x ${item.description}: \$${_formatMoney(item.total)}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    )),
                if (order.laborCost > 0)
                  pw.Text(
                    '  - Mano de obra: \$${_formatMoney(order.laborCost)}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                pw.SizedBox(height: 16),
              ],

              // Terms acceptance
              pw.Text(
                'Despues de haber leido todo lo aqui mencionado acepto los terminos y condiciones y recibo conforme.',
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 6),
                textAlign: pw.TextAlign.justify,
              ),

              pw.Spacer(),

              // ========== SIGNATURES ==========
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // ENTREGA (technician)
                  pw.SizedBox(
                    width: 200,
                    child: pw.Column(
                      children: [
                        if (techSigWidget != null) techSigWidget,
                        pw.Container(
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(width: 1)),
                          ),
                          width: 200,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('ENTREGA',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text(technicianName,
                            style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),

                  // RECIBE CONFORME (client)
                  pw.SizedBox(
                    width: 200,
                    child: pw.Column(
                      children: [
                        if (clientSigWidget != null) clientSigWidget,
                        pw.Container(
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(width: 1)),
                          ),
                          width: 200,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('RECIBE CONFORME',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text(clientName,
                            style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 30),

              // ========== FOOTER ==========
              pw.Center(
                child: pw.Column(
                  children: [
                    if (tenant.address != null && tenant.address!.isNotEmpty)
                      pw.Text(
                        tenant.address!.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    if (tenant.phone != null && tenant.phone!.isNotEmpty)
                      pw.Text(
                        'CEL: ${tenant.phone}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _labelLine(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  String _formatMoney(double amount) {
    final str = amount.toStringAsFixed(0);
    final chars = str.split('').reversed.toList();
    final formatted = <String>[];
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) formatted.add('.');
      formatted.add(chars[i]);
    }
    return formatted.reversed.join('');
  }
}
