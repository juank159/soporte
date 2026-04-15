import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/service_order.dart';
import '../models/tenant.dart';
import '../config/date_utils.dart';

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
    final customer = order.customer;
    final totalStr = _formatMoney(order.total);
    final warrantyMonths = (order.warrantyDays / 30).round();
    final hasWarranty = order.warrantyDays > 0;
    final isMulti = order.equipments.isNotEmpty;

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

    // Signatures
    pw.Widget? clientSigWidget;
    pw.Widget? techSigWidget;
    if (clientSignaturePng.length > 50 &&
        clientSignaturePng[0] == 0x89 && clientSignaturePng[1] == 0x50) {
      try { clientSigWidget = pw.Image(pw.MemoryImage(clientSignaturePng), height: 50); } catch (_) {}
    }
    if (technicianSignaturePng.length > 50 &&
        technicianSignaturePng[0] == 0x89 && technicianSignaturePng[1] == 0x50) {
      try { techSigWidget = pw.Image(pw.MemoryImage(technicianSignaturePng), height: 50); } catch (_) {}
    }

    // Build equipment detail widgets
    final equipmentWidgets = <pw.Widget>[];

    if (isMulti) {
      // Multiple equipment
      for (int i = 0; i < order.equipments.length; i++) {
        final eq = order.equipments[i];
        if (eq.status != 'ready' && eq.status != 'delivered') continue; // Only include ready/delivered
        equipmentWidgets.addAll(_buildEquipmentBlock(i + 1, eq));
      }
    } else if (order.device != null) {
      // Single device (legacy)
      equipmentWidgets.addAll(_buildSingleDeviceBlock(order));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 30),
        build: (context) => [
          // ========== HEADER ==========
          pw.Center(
            child: pw.Column(children: [
              if (logoWidget != null) ...[logoWidget, pw.SizedBox(height: 6)],
              pw.Text(tenant.name.toUpperCase(),
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              if (tenant.nit != null && tenant.nit!.isNotEmpty)
                pw.Text('NIT ${tenant.nit}', style: const pw.TextStyle(fontSize: 10)),
              if (tenant.address != null && tenant.address!.isNotEmpty)
                pw.Text(tenant.address!, style: const pw.TextStyle(fontSize: 9)),
              if (tenant.phone != null && tenant.phone!.isNotEmpty)
                pw.Text('Tel: ${tenant.phone}', style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
          pw.SizedBox(height: 12),

          // ========== TITLE ==========
          pw.Center(
            child: pw.Text('ACTA DE ENTREGA DE SERVICIO TECNICO',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 12),

          // ========== CLIENT & ORDER DATA (table format) ==========
          pw.Table(
            columnWidths: {
              0: const pw.FixedColumnWidth(120),
              1: const pw.FlexColumnWidth(),
            },
            children: [
              _tableRow('FECHA', dateStr),
              _tableRow('ORDEN No.', order.orderNumber),
              _tableRow('CLIENTE', customer?.fullName ?? '-'),
              _tableRow('CEDULA / NIT', customer?.idNumber ?? '-'),
              _tableRow('TELEFONO', customer?.phone ?? '-'),
              if (customer?.email != null && customer!.email!.isNotEmpty)
                _tableRow('EMAIL', customer.email!),
            ],
          ),
          pw.SizedBox(height: 20),

          // ========== INTRO PARAGRAPH ==========
          pw.Text(
            isMulti
                ? 'Por medio de la presente acta se hace entrega de los siguientes equipos que ingresaron a nuestras instalaciones el dia ${AppDateUtils.formatDate(order.createdAt)} para servicio tecnico:'
                : 'Por medio de la presente acta se hace entrega del equipo que ingreso a nuestras instalaciones el dia ${AppDateUtils.formatDate(order.createdAt)} para servicio tecnico.',
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 5),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 10),

          // ========== EQUIPMENT DETAILS ==========
          ...equipmentWidgets,

          // ========== COST SUMMARY ==========
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(children: [
              if (order.items.isNotEmpty) ...[
                pw.Text('DETALLE DE COSTOS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                ...order.items.map((item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('${item.qty}x ${item.description}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('\$${_formatMoney(item.total)}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                )),
                if (order.laborCost > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Mano de obra', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('\$${_formatMoney(order.laborCost)}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                pw.Divider(),
              ],
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('VALOR TOTAL DEL SERVICIO',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('\$$totalStr',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ]),
          ),
          pw.SizedBox(height: 16),

          // ========== WARRANTY ==========
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.RichText(
              textAlign: pw.TextAlign.justify,
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 4),
                children: [
                  pw.TextSpan(text: 'GARANTIA: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  if (hasWarranty) ...[
                    const pw.TextSpan(text: 'Se otorga garantia de '),
                    pw.TextSpan(text: '$warrantyMonths mes(es)',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(
                        text: ' sobre el trabajo realizado. La garantia cubre exclusivamente la reparacion efectuada y no aplica por mal uso, golpes, humedad u otras causas ajenas al servicio prestado.'),
                  ] else ...[
                    const pw.TextSpan(text: 'Este servicio '),
                    pw.TextSpan(text: 'NO incluye garantia',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: '. El cliente ha sido informado y acepta esta condicion.'),
                  ],
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 8),

          // ========== TERMS ==========
          pw.Text(
            'El cliente declara recibir el(los) equipo(s) en funcionamiento, probado(s) y a satisfaccion. Se le han explicado los cuidados que debe tener. Despues de haber leido todo lo aqui mencionado acepta los terminos y condiciones y recibe conforme.',
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 5),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 20),

          // ========== SIGNATURES ==========
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBlock(techSigWidget, 'ENTREGA', technicianName),
              _signatureBlock(clientSigWidget, 'RECIBE CONFORME', clientName),
            ],
          ),
          pw.SizedBox(height: 20),

          // ========== FOOTER ==========
          pw.Center(
            child: pw.Text(
              '${tenant.name} - ${tenant.address ?? ''} - Tel: ${tenant.phone ?? ''}',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ===== Equipment block for multi-device =====
  List<pw.Widget> _buildEquipmentBlock(int number, OrderEquipment eq) {
    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        margin: const pw.EdgeInsets.only(bottom: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('EQUIPO $number',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              columnWidths: {
                0: const pw.FixedColumnWidth(100),
                1: const pw.FlexColumnWidth(),
              },
              children: [
                _tableRow('Tipo', eq.deviceType),
                _tableRow('Marca', eq.deviceBrand),
                _tableRow('Modelo', eq.deviceModel),
                if (eq.deviceSerial != null) _tableRow('Serial / IMEI', eq.deviceSerial!),
                if (eq.deviceColor != null) _tableRow('Color', eq.deviceColor!),
                if (eq.accessories != null && eq.accessories!.isNotEmpty)
                  _tableRow('Accesorios', eq.accessories!.join(', ')),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text('Falla reportada:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(eq.problemReported, style: const pw.TextStyle(fontSize: 10)),
            if (eq.diagnosis != null && eq.diagnosis!.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Diagnostico y trabajo realizado:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(eq.diagnosis!, style: const pw.TextStyle(fontSize: 10)),
            ],
            if (eq.notes != null && eq.notes!.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text('Observaciones: ${eq.notes!}', style: const pw.TextStyle(fontSize: 9)),
            ],
          ],
        ),
      ),
    ];
  }

  // ===== Single device block (legacy) =====
  List<pw.Widget> _buildSingleDeviceBlock(ServiceOrder order) {
    final device = order.device!;
    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        margin: const pw.EdgeInsets.only(bottom: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('EQUIPO', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              columnWidths: {
                0: const pw.FixedColumnWidth(100),
                1: const pw.FlexColumnWidth(),
              },
              children: [
                _tableRow('Tipo', device.type ?? '-'),
                _tableRow('Marca', device.brand ?? '-'),
                _tableRow('Modelo', device.model ?? '-'),
                if (device.serial != null) _tableRow('Serial / IMEI', device.serial!),
                if (device.color != null) _tableRow('Color', device.color!),
                if (device.accessories != null && device.accessories!.isNotEmpty)
                  _tableRow('Accesorios', device.accessories!.join(', ')),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text('Falla reportada:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(order.problemReported, style: const pw.TextStyle(fontSize: 10)),
            if (order.diagnosis != null && order.diagnosis!.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Diagnostico y trabajo realizado:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(order.diagnosis!, style: const pw.TextStyle(fontSize: 10)),
            ],
          ],
        ),
      ),
    ];
  }

  pw.Widget _signatureBlock(pw.Widget? sigWidget, String label, String name) {
    return pw.SizedBox(
      width: 200,
      child: pw.Column(children: [
        if (sigWidget != null) sigWidget,
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1)),
          ),
          width: 200,
        ),
        pw.SizedBox(height: 4),
        pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text(name, style: const pw.TextStyle(fontSize: 9)),
      ]),
    );
  }

  pw.TableRow _tableRow(String label, String value) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text('$label:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ),
    ]);
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
