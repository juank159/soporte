import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/service_order.dart';
import '../models/tenant.dart';
import '../config/date_utils.dart';
import '../config/format_utils.dart';

class OrdersPdfService {
  Future<Uint8List> generateOrdersReport({
    required List<ServiceOrder> orders,
    required Tenant tenant,
    required String periodLabel,
  }) async {
    final pdf = pw.Document(
      title: 'Reporte de Ordenes - $periodLabel',
      author: tenant.name,
    );

    final now = DateTime.now();
    final dateStr = AppDateUtils.format(now);

    // Split orders in pages of 20
    final pageSize = 20;
    final totalPages = (orders.length / pageSize).ceil().clamp(1, 100);

    for (int page = 0; page < totalPages; page++) {
      final start = page * pageSize;
      final end = (start + pageSize).clamp(0, orders.length);
      final pageOrders = orders.sublist(start, end);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter.landscape,
          margin: const pw.EdgeInsets.all(30),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(tenant.name,
                            style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold)),
                        if (tenant.nit != null)
                          pw.Text('NIT: ${tenant.nit}',
                              style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('REPORTE DE ORDENES',
                            style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text(periodLabel,
                            style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('Generado: $dateStr',
                            style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 1.5),
                pw.SizedBox(height: 6),

                // Summary
                pw.Row(children: [
                  _summaryBox('Total', '${orders.length}'),
                  pw.SizedBox(width: 12),
                  _summaryBox('Pendientes',
                      '${orders.where((o) => o.status != 'delivered' && o.status != 'closed').length}'),
                  pw.SizedBox(width: 12),
                  _summaryBox('Entregadas',
                      '${orders.where((o) => o.status == 'delivered' || o.status == 'closed').length}'),
                  pw.SizedBox(width: 12),
                  _summaryBox('Ingresos',
                      '\$${formatMoney(orders.where((o) => o.status == 'delivered' || o.status == 'closed').fold(0.0, (sum, o) => sum + o.total))}'),
                ]),
                pw.SizedBox(height: 10),

                // Table
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 7),
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.grey200),
                  cellPadding: const pw.EdgeInsets.all(4),
                  headers: [
                    'Orden',
                    'Fecha',
                    'Cliente',
                    'Equipo',
                    'Serial',
                    'Problema',
                    'Tecnico',
                    'Estado',
                    'Valor',
                  ],
                  data: pageOrders.map((o) {
                    return [
                      o.orderNumber,
                      AppDateUtils.formatDate(o.createdAt),
                      o.customer?.fullName ?? 'Express',
                      '${o.device?.brand ?? ''} ${o.device?.model ?? ''}',
                      o.device?.serial ?? '-',
                      o.problemReported.length > 40
                          ? '${o.problemReported.substring(0, 40)}...'
                          : o.problemReported,
                      '', // Technician name not available in order model
                      _statusLabel(o.status),
                      o.total > 0 ? '\$${formatMoney(o.total)}' : '-',
                    ];
                  }).toList(),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.2),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1.2),
                    5: const pw.FlexColumnWidth(2.5),
                    6: const pw.FlexColumnWidth(1.2),
                    7: const pw.FlexColumnWidth(1),
                    8: const pw.FlexColumnWidth(1),
                  },
                ),

                pw.Spacer(),

                // Footer
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        '${tenant.address ?? ''} | ${tenant.phone ?? ''}',
                        style: const pw.TextStyle(fontSize: 7)),
                    pw.Text('Pagina ${page + 1} de $totalPages',
                        style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  pw.Widget _summaryBox(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(children: [
        pw.Text(value,
            style:
                pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
      ]),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'received': return 'Recibido';
      case 'diagnosing': return 'Diagnostico';
      case 'repairing': return 'Reparacion';
      case 'quality_check': return 'Calidad';
      case 'ready': return 'Listo';
      case 'delivered': return 'Entregado';
      case 'closed': return 'Cerrado';
      default: return status;
    }
  }
}
