import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:dio/dio.dart' as dio;
import '../models/service_order.dart';
import '../models/tenant.dart';
import '../config/date_utils.dart';
import '../config/format_utils.dart';
import 'api_service.dart';

/// Genera un PDF con multiples actas de entrega en un solo documento.
class ActasBatchService {
  final ApiService _api = ApiService();

  Future<Uint8List> generateBatchActas({
    required List<ServiceOrder> deliveredOrders,
    required Tenant tenant,
    required String periodLabel,
  }) async {
    final pdf = pw.Document(
      title: 'Actas de Entrega - $periodLabel',
      author: tenant.name,
    );

    // Logo
    pw.Widget? logoWidget;
    if (tenant.logoUrl != null && tenant.logoUrl!.contains('base64,')) {
      try {
        final bytes = base64Decode(tenant.logoUrl!.split(',').last);
        logoWidget = pw.Image(pw.MemoryImage(bytes), height: 50);
      } catch (_) {}
    }

    for (final order in deliveredOrders) {
      // Load signatures for this order
      Uint8List clientSig = Uint8List(0);
      Uint8List techSig = Uint8List(0);
      String clientName = order.customer?.fullName ?? 'Cliente';
      String techName = 'Tecnico';

      try {
        final sigRes = await _api.dio.get('/orders/${order.id}/signatures');
        for (final sig in sigRes.data as List) {
          final pngData = sig['pngUrl'] as String? ?? '';
          final name = sig['signerName'] as String? ?? '';
          Uint8List? decoded;

          if (pngData.startsWith('http')) {
            try {
              final resp = await _api.dio.get(pngData,
                  options: dio.Options(responseType: dio.ResponseType.bytes));
              decoded = Uint8List.fromList(resp.data);
            } catch (_) {}
          } else if (pngData.contains('base64,')) {
            try { decoded = base64Decode(pngData.split('base64,').last); } catch (_) {}
          }

          if (decoded != null && decoded.length > 50) {
            if (sig['signerType'] == 'customer') { clientSig = decoded; clientName = name; }
            else if (sig['signerType'] == 'technician') { techSig = decoded; techName = name; }
          }
        }
      } catch (_) {}

      // Load repair notes
      String fullDiagnosis = order.diagnosis ?? '';
      try {
        final histRes = await _api.dio.get('/orders/${order.id}/history');
        final excludes = ['control de calidad', 'enviado a control', 'listo para entrega', 'orden cerrada', 'orden creada', 'entregado por'];
        final notes = (histRes.data as List)
            .where((h) {
              final s = h['toStatus'] as String? ?? '';
              final n = (h['notes'] as String? ?? '').toLowerCase();
              if (s != 'repairing' && s != 'diagnosing') return false;
              if (n.isEmpty) return false;
              for (final p in excludes) { if (n.contains(p)) return false; }
              return true;
            })
            .map((h) => h['notes'] as String)
            .toList();
        if (notes.isNotEmpty) {
          if (fullDiagnosis.isNotEmpty && !fullDiagnosis.endsWith('.')) fullDiagnosis += '.';
          fullDiagnosis = '$fullDiagnosis ${notes.join('. ')}.'.trim();
        }
      } catch (_) {}

      // Build signatures widgets
      pw.Widget? clientSigW;
      pw.Widget? techSigW;
      if (clientSig.length > 50 && clientSig[0] == 0x89 && clientSig[1] == 0x50) {
        try { clientSigW = pw.Image(pw.MemoryImage(clientSig), height: 45); } catch (_) {}
      }
      if (techSig.length > 50 && techSig[0] == 0x89 && techSig[1] == 0x50) {
        try { techSigW = pw.Image(pw.MemoryImage(techSig), height: 45); } catch (_) {}
      }

      final device = order.device;
      final equipoDesc = '${device?.type ?? ''} ${device?.brand ?? ''} ${device?.model ?? ''}'.trim();
      final serialText = device?.serial ?? device?.imei ?? 'N/A';
      final totalStr = formatMoney(order.total);
      final warrantyMonths = (order.warrantyDays / 30).round();
      final hasWarranty = order.warrantyDays > 0;
      final deliveryDate = order.deliveredAt ?? order.createdAt;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.symmetric(horizontal: 50, vertical: 35),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(child: pw.Column(children: [
                if (logoWidget != null) ...[logoWidget, pw.SizedBox(height: 4)],
                pw.Text(tenant.name.toUpperCase(),
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                if (tenant.nit != null)
                  pw.Text('NIT ${tenant.nit}', style: const pw.TextStyle(fontSize: 9)),
              ])),
              pw.SizedBox(height: 20),

              // Client data
              _line('FECHA', AppDateUtils.formatDate(deliveryDate)),
              pw.SizedBox(height: 6),
              _line('CEDULA', order.customer?.idNumber ?? '-'),
              pw.SizedBox(height: 6),
              _line('NOMBRE', order.customer?.fullName ?? '-'),
              pw.SizedBox(height: 6),
              _line('TELEFONO', order.customer?.phone ?? '-'),
              pw.SizedBox(height: 6),
              _line('ORDEN No.', order.orderNumber),
              pw.SizedBox(height: 20),

              pw.Text('ACTA DE ENTREGA DE SERVICIO TECNICO',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 14),

              // Body
              pw.RichText(textAlign: pw.TextAlign.justify, text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 5),
                children: [
                  const pw.TextSpan(text: 'Se le hace entrega de '),
                  pw.TextSpan(text: equipoDesc, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  if (serialText != 'N/A') ...[
                    const pw.TextSpan(text: ' S/N: '),
                    pw.TextSpan(text: serialText, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                  const pw.TextSpan(text: ' que ingreso a nuestras instalaciones el dia '),
                  pw.TextSpan(text: AppDateUtils.formatDate(order.createdAt),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  const pw.TextSpan(text: ' presentando la siguiente falla y condicion: '),
                  pw.TextSpan(text: order.problemReported,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              )),
              pw.SizedBox(height: 8),

              if (fullDiagnosis.isNotEmpty)
                pw.RichText(textAlign: pw.TextAlign.justify, text: pw.TextSpan(
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 5),
                  children: [
                    const pw.TextSpan(text: 'Cual se le realizo: '),
                    pw.TextSpan(text: fullDiagnosis, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                )),
              pw.SizedBox(height: 8),

              pw.RichText(textAlign: pw.TextAlign.justify, text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 5),
                children: [
                  const pw.TextSpan(text: 'Por un monto de '),
                  pw.TextSpan(text: '\$$totalStr',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  const pw.TextSpan(text: ' se le entrega probado y a satisfaccion del mismo. '),
                  if (hasWarranty) ...[
                    const pw.TextSpan(text: 'Garantia: Si. '),
                    pw.TextSpan(text: '$warrantyMonths meses.',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ] else
                    const pw.TextSpan(text: 'Garantia: No.'),
                ],
              )),
              pw.SizedBox(height: 8),

              pw.Text('Despues de haber leido todo lo aqui mencionado acepto los terminos y condiciones y recibo conforme.',
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 5), textAlign: pw.TextAlign.justify),

              pw.Spacer(),

              // Signatures
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.SizedBox(width: 190, child: pw.Column(children: [
                  if (techSigW != null) techSigW,
                  pw.Container(width: 190, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1)))),
                  pw.SizedBox(height: 3),
                  pw.Text('ENTREGA', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(techName, style: const pw.TextStyle(fontSize: 8)),
                ])),
                pw.SizedBox(width: 190, child: pw.Column(children: [
                  if (clientSigW != null) clientSigW,
                  pw.Container(width: 190, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1)))),
                  pw.SizedBox(height: 3),
                  pw.Text('RECIBE CONFORME', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(clientName, style: const pw.TextStyle(fontSize: 8)),
                ])),
              ]),
              pw.SizedBox(height: 20),

              // Footer
              pw.Center(child: pw.Column(children: [
                if (tenant.address != null) pw.Text(tenant.address!.toUpperCase(),
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                if (tenant.phone != null) pw.Text('CEL: ${tenant.phone}',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ])),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  pw.Widget _line(String label, String value) => pw.Row(children: [
    pw.Text('$label: ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    pw.Expanded(child: pw.Container(
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
    )),
  ]);
}
