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
    String? paymentMethod,
    List<Map<String, dynamic>>? history,
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
    final isMulti = order.equipments.length > 1;

    // Logo centered
    pw.Widget? logoWidget;
    if (tenant.logoUrl != null && tenant.logoUrl!.startsWith('data:') && tenant.logoUrl!.contains(',')) {
      try {
        final logoBytes = base64Decode(tenant.logoUrl!.split(',').last);
        logoWidget = pw.Image(pw.MemoryImage(logoBytes), height: 50);
      } catch (_) {}
    }

    // Signatures
    pw.Widget? clientSigWidget;
    pw.Widget? techSigWidget;
    if (clientSignaturePng.length > 50 && clientSignaturePng[0] == 0x89 && clientSignaturePng[1] == 0x50) {
      try { clientSigWidget = pw.Image(pw.MemoryImage(clientSignaturePng), height: 45); } catch (_) {}
    }
    if (technicianSignaturePng.length > 50 && technicianSignaturePng[0] == 0x89 && technicianSignaturePng[1] == 0x50) {
      try { techSigWidget = pw.Image(pw.MemoryImage(technicianSignaturePng), height: 45); } catch (_) {}
    }

    // Build equipment blocks
    final equipmentWidgets = <pw.Widget>[];
    if (order.equipments.isNotEmpty) {
      for (int i = 0; i < order.equipments.length; i++) {
        final eq = order.equipments[i];
        if (eq.status != 'ready' && eq.status != 'delivered') continue;
        equipmentWidgets.addAll(_buildEquipmentBlock(i + 1, eq, order.equipments.length == 1));
      }
    } else if (order.device != null) {
      equipmentWidgets.addAll(_buildSingleDeviceBlock(order));
    }

    // Build cost rows with payment method per equipment
    final costRows = <pw.Widget>[];
    if (order.equipments.isNotEmpty) {
      for (final eq in order.equipments) {
        if (eq.status != 'ready' && eq.status != 'delivered') continue;
        if (eq.laborCost <= 0) continue;
        final eqPayment = _extractPaymentFromHistory(history, eq);
        costRows.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('${eq.deviceBrand} ${eq.deviceModel}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('\$${_formatMoney(eq.laborCost)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ]),
            if (eqPayment.isNotEmpty)
              pw.Text('Pago: $eqPayment', style: const pw.TextStyle(fontSize: 8)),
          ]),
        ));
      }
    } else if (paymentMethod != null) {
      costRows.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Pago:', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(paymentMethod, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ]),
      ));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 25),
        build: (context) => [
          // ========== HEADER CENTERED ==========
          pw.Center(child: pw.Column(children: [
            if (logoWidget != null) ...[logoWidget!, pw.SizedBox(height: 4)],
            pw.Text(tenant.name.toUpperCase(),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            if (tenant.nit != null && tenant.nit!.isNotEmpty)
              pw.Text('NIT ${tenant.nit}', style: const pw.TextStyle(fontSize: 9)),
          ])),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('ACTA DE ENTREGA DE SERVICIO TECNICO',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 8),

          // ========== CLIENT DATA (compact: 2 columns) ==========
          pw.Row(children: [
            pw.Expanded(child: pw.Row(children: [
              pw.Text('FECHA: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(dateStr, style: const pw.TextStyle(fontSize: 9)),
            ])),
            pw.Expanded(child: pw.Row(children: [
              pw.Text('ORDEN: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(order.orderNumber, style: const pw.TextStyle(fontSize: 9)),
            ])),
          ]),
          pw.SizedBox(height: 3),
          pw.Row(children: [
            pw.Text('CLIENTE: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Expanded(child: pw.Text(customer?.fullName ?? '-', style: const pw.TextStyle(fontSize: 9))),
            pw.Text('CC/NIT: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Text(customer?.idNumber ?? '-', style: const pw.TextStyle(fontSize: 9)),
          ]),
          pw.SizedBox(height: 3),
          pw.Row(children: [
            pw.Text('TEL: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Expanded(child: pw.Text(customer?.phone ?? '-', style: const pw.TextStyle(fontSize: 9))),
            if (customer?.email != null && customer!.email!.isNotEmpty) ...[
              pw.Text('EMAIL: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text(customer.email!, style: const pw.TextStyle(fontSize: 9)),
            ],
          ]),
          pw.Divider(height: 10),

          // ========== INTRO ==========
          pw.Text(
            isMulti
                ? 'Se hace entrega de los siguientes equipos que ingresaron el ${AppDateUtils.formatDate(order.createdAt)}:'
                : 'Se hace entrega del equipo que ingreso el ${AppDateUtils.formatDate(order.createdAt)}:',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 6),

          // ========== EQUIPMENT DETAILS ==========
          ...equipmentWidgets,

          // ========== COST + PAYMENT ==========
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(children: [
              ...costRows,
              if (costRows.isNotEmpty) pw.Divider(height: 6),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('VALOR TOTAL', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text('\$$totalStr', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ]),
            ]),
          ),
          pw.SizedBox(height: 6),

          // ========== WARRANTY ==========
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('GARANTIA', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              if (isMulti)
                ...order.equipments.where((eq) => eq.status == 'ready' || eq.status == 'delivered').map((eq) {
                  final m = (eq.warrantyDays / 30).round();
                  return pw.Text(
                    '${eq.deviceBrand} ${eq.deviceModel}: ${eq.warrantyDays > 0 ? '$m mes(es)' : 'Instantanea'}',
                    style: const pw.TextStyle(fontSize: 8),
                  );
                })
              else
                pw.Text(
                  hasWarranty && warrantyMonths > 0
                      ? 'Se otorga garantia de $warrantyMonths mes(es). Cubre exclusivamente la reparacion efectuada.'
                      : 'Garantia instantanea. Se entrega probado y funcionando.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
            ]),
          ),
          pw.SizedBox(height: 6),

          // ========== TERMS ==========
          pw.Text('Declaro recibir el(los) equipo(s) probado(s) y a satisfaccion. Acepto los terminos y condiciones.',
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 14),

          // ========== SIGNATURES ==========
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            _signatureBlock(techSigWidget, 'ENTREGA', technicianName),
            _signatureBlock(clientSigWidget, 'RECIBE CONFORME', clientName),
          ]),
          pw.SizedBox(height: 8),

          // ========== FOOTER ==========
          pw.Center(child: pw.Text(
            '${tenant.name} | ${tenant.address ?? ''} | Tel: ${tenant.phone ?? ''}',
            style: const pw.TextStyle(fontSize: 7),
          )),
        ],
      ),
    );

    return pdf.save();
  }

  String _extractPaymentFromHistory(List<Map<String, dynamic>>? history, OrderEquipment eq) {
    if (history == null) return '';
    final eqLabel = '${eq.deviceType} ${eq.deviceBrand} ${eq.deviceModel}';
    for (final h in history.reversed) {
      final notes = h['notes'] as String? ?? '';
      final toStatus = h['toStatus'] as String? ?? '';
      if (toStatus != 'delivered' || !notes.contains('Entregado por')) continue;
      if (notes.contains(eqLabel) || !notes.contains('[')) {
        if (notes.contains('Efectivo')) return 'Efectivo';
        if (notes.contains('Transferencia')) return 'Transferencia';
        if (notes.contains('Tarjeta de Credito')) return 'T. Credito';
        if (notes.contains('Tarjeta de Debito')) return 'T. Debito';
      }
    }
    return '';
  }

  List<pw.Widget> _buildEquipmentBlock(int number, OrderEquipment eq, bool isSingle) {
    String? repairNotes;
    if (eq.notes != null && eq.notes!.isNotEmpty && !eq.notes!.startsWith('Entregado por')) {
      repairNotes = eq.notes;
    }
    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        margin: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(isSingle ? 'EQUIPO' : 'EQUIPO $number',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Table(
            columnWidths: {0: const pw.FixedColumnWidth(85), 1: const pw.FlexColumnWidth()},
            children: [
              _tableRow('Tipo', eq.deviceType),
              _tableRow('Marca', eq.deviceBrand),
              _tableRow('Modelo', eq.deviceModel),
              if (eq.deviceSerial != null) _tableRow('Serial', eq.deviceSerial!),
              if (eq.deviceColor != null) _tableRow('Color', eq.deviceColor!),
              if (eq.accessories != null && eq.accessories!.isNotEmpty) _tableRow('Accesorios', eq.accessories!.join(', ')),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('Falla: ${eq.problemReported}', style: const pw.TextStyle(fontSize: 9)),
          if (eq.diagnosis != null && eq.diagnosis!.isNotEmpty)
            pw.Text('Diagnostico: ${eq.diagnosis!}', style: const pw.TextStyle(fontSize: 9)),
          if (repairNotes != null)
            pw.Text('Reparacion: $repairNotes', style: const pw.TextStyle(fontSize: 9)),
        ]),
      ),
    ];
  }

  List<pw.Widget> _buildSingleDeviceBlock(ServiceOrder order) {
    final device = order.device!;
    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        margin: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('EQUIPO', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Table(
            columnWidths: {0: const pw.FixedColumnWidth(85), 1: const pw.FlexColumnWidth()},
            children: [
              _tableRow('Tipo', device.type ?? '-'),
              _tableRow('Marca', device.brand ?? '-'),
              _tableRow('Modelo', device.model ?? '-'),
              if (device.serial != null) _tableRow('Serial', device.serial!),
              if (device.color != null) _tableRow('Color', device.color!),
              if (device.accessories != null && device.accessories!.isNotEmpty) _tableRow('Accesorios', device.accessories!.join(', ')),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('Falla: ${order.problemReported}', style: const pw.TextStyle(fontSize: 9)),
          if (order.diagnosis != null && order.diagnosis!.isNotEmpty)
            pw.Text('Diagnostico: ${order.diagnosis!}', style: const pw.TextStyle(fontSize: 9)),
          if (order.notes != null && order.notes!.isNotEmpty && !order.notes!.startsWith('Entregado por'))
            pw.Text('Reparacion: ${order.notes!}', style: const pw.TextStyle(fontSize: 9)),
        ]),
      ),
    ];
  }

  pw.Widget _signatureBlock(pw.Widget? sigWidget, String label, String name) {
    return pw.SizedBox(width: 200, child: pw.Column(children: [
      if (sigWidget != null) sigWidget,
      pw.Container(decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1))), width: 200),
      pw.SizedBox(height: 3),
      pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.Text(name, style: const pw.TextStyle(fontSize: 8)),
    ]));
  }

  pw.TableRow _tableRow(String label, String value) {
    return pw.TableRow(children: [
      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Text('$label:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Text(value, style: const pw.TextStyle(fontSize: 9))),
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
