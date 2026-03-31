import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../config/format_utils.dart';
import '../../models/service_order.dart';
import '../../models/tenant.dart';
import '../../models/user.dart';
import '../../services/pdf_generator_service.dart';
import '../../services/order_service.dart';
import '../../services/api_service.dart';
import '../../widgets/signature_pad_widget.dart';
import '../../widgets/glass_card.dart';
import '../../config/theme.dart';

class DeliveryScreen extends StatefulWidget {
  final ServiceOrder order;
  final Tenant tenant;

  const DeliveryScreen({
    super.key,
    required this.order,
    required this.tenant,
  });

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final PdfGeneratorService _pdfService = PdfGeneratorService();
  final OrderService _orderService = OrderService();
  final ApiService _api = ApiService();

  Uint8List? _clientSignature;
  Uint8List? _technicianSignature;
  final _clientNameCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _warrantyMonthsCtrl = TextEditingController();

  bool? _hasWarranty; // null = not selected yet

  // Technician assigned to the order
  List<User> _technicians = [];
  User? _assignedTechnician;
  bool _loadingTechnicians = true;

  bool _generating = false;
  Uint8List? _generatedPdf;
  bool _statusUpdated = false;

  @override
  void initState() {
    super.initState();
    _clientNameCtrl.text = widget.order.customer?.fullName ?? '';
    _totalCtrl.text = widget.order.total > 0
        ? formatMoney(widget.order.total)
        : '';
    _loadTechnicians();
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    _totalCtrl.dispose();
    _warrantyMonthsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTechnicians() async {
    try {
      final res = await _api.dio.get('/users');
      final allUsers = (res.data as List)
          .map((e) => User.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _technicians = allUsers
            .where((u) =>
                u.role == 'technician' ||
                u.role == 'supervisor' ||
                u.role == 'admin')
            .toList();
        // Auto-select the assigned technician
        if (widget.order.technicianId != null) {
          _assignedTechnician = _technicians
              .where((t) => t.id == widget.order.technicianId)
              .firstOrNull;
        }
        _loadingTechnicians = false;
      });
    } catch (_) {
      setState(() => _loadingTechnicians = false);
    }
  }

  bool get _canGenerate =>
      _clientSignature != null &&
      _technicianSignature != null &&
      _clientNameCtrl.text.isNotEmpty &&
      _assignedTechnician != null &&
      _totalCtrl.text.isNotEmpty &&
      _hasWarranty != null &&
      (_hasWarranty == false || _warrantyMonthsCtrl.text.isNotEmpty);

  Future<void> _generateAndDeliver() async {
    if (!_canGenerate) return;

    setState(() => _generating = true);

    try {
      final totalValue = parseFormattedMoney(_totalCtrl.text.trim());
      final warrantyMonths =
          int.tryParse(_warrantyMonthsCtrl.text.trim()) ?? 1;

      // Save total and warranty on the order
      try {
        await _api.dio.patch('/orders/${widget.order.id}/delivery-info', data: {
          'total': totalValue,
          'warrantyDays': _hasWarranty == true ? warrantyMonths * 30 : 0,
        });
      } catch (_) {}

      // Change status to delivered
      try {
        await _api.dio.patch('/orders/${widget.order.id}/status', data: {
          'status': 'delivered',
          'notes':
              'Entregado por \$${_totalCtrl.text.trim()} - Garantia: ${_hasWarranty == true ? '$warrantyMonths meses' : 'Sin garantia'}',
        });
        _statusUpdated = true;
      } catch (_) {}

      // Load repair notes from history for the acta
      String fullDiagnosis = widget.order.diagnosis ?? '';
      try {
        final histRes = await _api.dio.get('/orders/${widget.order.id}/history');
        final history = histRes.data as List;
        // Only include actual repair work notes, exclude automatic/system notes
        final excludePatterns = [
          'control de calidad', 'enviado a control', 'listo para entrega',
          'orden cerrada', 'orden creada',
        ];
        final repairNotes = history
            .where((h) {
              final status = h['toStatus'] as String? ?? '';
              final notes = (h['notes'] as String? ?? '').toLowerCase();
              if (status != 'repairing') return false;
              if (notes.isEmpty) return false;
              for (final p in excludePatterns) {
                if (notes.contains(p)) return false;
              }
              return true;
            })
            .map((h) => h['notes'] as String)
            .toList();
        if (repairNotes.isNotEmpty) {
          if (fullDiagnosis.isNotEmpty && !fullDiagnosis.endsWith('.')) {
            fullDiagnosis += '.';
          }
          fullDiagnosis = '$fullDiagnosis ${repairNotes.join('. ')}.'.trim();
        }
      } catch (_) {}

      // Build order copy with the entered values
      final orderForPdf = ServiceOrder(
        id: widget.order.id,
        orderNumber: widget.order.orderNumber,
        customerId: widget.order.customerId,
        customer: widget.order.customer,
        deviceId: widget.order.deviceId,
        device: widget.order.device,
        technicianId: widget.order.technicianId,
        status: 'delivered',
        problemReported: widget.order.problemReported,
        diagnosis: fullDiagnosis.isNotEmpty ? fullDiagnosis : null,
        notes: widget.order.notes,
        laborCost: widget.order.laborCost,
        subtotal: widget.order.subtotal,
        tax: widget.order.tax,
        total: totalValue,
        warrantyDays: _hasWarranty == true ? warrantyMonths * 30 : 0,
        createdAt: widget.order.createdAt,
        items: widget.order.items,
      );

      final clientName = _clientNameCtrl.text.trim();
      final techName = _assignedTechnician!.fullName;

      // Save signatures to backend for future reprints
      try {
        final clientB64 = base64Encode(_clientSignature!);
        final techB64 = base64Encode(_technicianSignature!);
        await _api.dio.post(
          '/orders/${widget.order.id}/signatures',
          data: {
            'signerType': 'customer',
            'signerName': clientName,
            'pngData': 'data:image/png;base64,$clientB64',
          },
        );
        await _api.dio.post(
          '/orders/${widget.order.id}/signatures',
          data: {
            'signerType': 'technician',
            'signerName': techName,
            'pngData': 'data:image/png;base64,$techB64',
          },
        );
      } catch (_) {}

      final pdfBytes = await _pdfService.generateDeliveryAct(
        order: orderForPdf,
        tenant: widget.tenant,
        clientSignaturePng: _clientSignature!,
        clientName: clientName,
        technicianSignaturePng: _technicianSignature!,
        technicianName: techName,
      );

      setState(() {
        _generatedPdf = pdfBytes;
        _generating = false;
      });
    } catch (e) {
      setState(() => _generating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.accentRed,
        ));
      }
    }
  }

  void _finish() {
    Navigator.pop(context, _statusUpdated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Entrega ${widget.order.orderNumber}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _finish,
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.gradientPrimary,
          ),
        ),
        child:
            _generatedPdf != null ? _buildSuccessView() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== ORDER SUMMARY =====
          GlassCard(
            borderColor: AppTheme.accentCyan.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.assignment_rounded,
                      color: AppTheme.accentCyan, size: 20),
                  SizedBox(width: 8),
                  Text('Resumen',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentCyan,
                          fontSize: 15)),
                ]),
                const SizedBox(height: 12),
                _infoRow('Orden', widget.order.orderNumber),
                _infoRow('Cliente',
                    widget.order.customer?.fullName ?? 'Express'),
                _infoRow('Equipo',
                    '${widget.order.device?.brand ?? ''} ${widget.order.device?.model ?? ''}'),
                _infoRow('Problema', widget.order.problemReported),
                if (widget.order.diagnosis != null)
                  _infoRow('Trabajo', widget.order.diagnosis!),
              ],
            ),
          ),

          // ===== VALOR Y GARANTIA =====
          GlassCard(
            borderColor: AppTheme.accentGreen.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.attach_money_rounded,
                      color: AppTheme.accentGreen, size: 20),
                  SizedBox(width: 8),
                  Text('Valor y garantia',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentGreen,
                          fontSize: 15)),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _totalCtrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 18),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandSeparatorFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Valor total del servicio *',
                    prefixText: '\$ ',
                    prefixIcon: Icon(Icons.payments_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Garantia: *',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Si'),
                      selected: _hasWarranty == true,
                      onSelected: (_) =>
                          setState(() => _hasWarranty = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('No'),
                      selected: _hasWarranty == false,
                      onSelected: (_) =>
                          setState(() => _hasWarranty = false),
                    ),
                    if (_hasWarranty == true) ...[
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _warrantyMonthsCtrl,
                          style: const TextStyle(
                              color: AppTheme.textPrimary),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            labelText: 'Meses',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // ===== QUIEN RECIBE (CLIENT) =====
          GlassCard(
            borderColor: AppTheme.accentBlue.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.person_rounded,
                      color: AppTheme.accentBlue, size: 18),
                  SizedBox(width: 8),
                  Text('Recibe conforme',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentBlue,
                          fontSize: 14)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientNameCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  readOnly: widget.order.customer?.fullName != null &&
                      widget.order.customer!.fullName.isNotEmpty &&
                      widget.order.customer!.idNumber != 'EXPRESS',
                  decoration: InputDecoration(
                    labelText: 'Nombre de quien recibe',
                    prefixIcon: const Icon(Icons.badge_rounded),
                    suffixIcon: widget.order.customer?.fullName != null &&
                        widget.order.customer!.idNumber != 'EXPRESS'
                        ? const Icon(Icons.lock_rounded,
                            size: 16, color: AppTheme.textSecondary)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                SignaturePadWidget(
                  label: 'Firma de quien recibe',
                  onSigned: (data) =>
                      setState(() => _clientSignature = data),
                ),
              ],
            ),
          ),

          // ===== TECNICO QUE ENTREGA =====
          GlassCard(
            borderColor: AppTheme.accentPurple.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.engineering_rounded,
                      color: AppTheme.accentPurple, size: 18),
                  SizedBox(width: 8),
                  Text('Entrega',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentPurple,
                          fontSize: 14)),
                ]),
                const SizedBox(height: 12),
                if (_loadingTechnicians)
                  const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accentCyan))
                else if (_assignedTechnician != null)
                  // Show assigned technician (can't change here)
                  GlassCard(
                    margin: EdgeInsets.zero,
                    borderColor:
                        AppTheme.accentGreen.withValues(alpha: 0.3),
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded,
                          color: AppTheme.accentGreen, size: 18),
                      const SizedBox(width: 10),
                      Text(_assignedTechnician!.fullName,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600)),
                    ]),
                  )
                else
                  // Select technician if none assigned
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _technicians.map((tech) {
                      final selected =
                          _assignedTechnician?.id == tech.id;
                      return ChoiceChip(
                        label: Text(tech.fullName),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            _assignedTechnician = tech;
                            _technicianSignature = null;
                          });
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),

          // Technician signature
          if (_assignedTechnician != null)
            GlassCard(
              borderColor:
                  AppTheme.accentPurple.withValues(alpha: 0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.draw_rounded,
                        color: AppTheme.accentPurple, size: 18),
                    const SizedBox(width: 8),
                    Text('Firma de ${_assignedTechnician!.fullName}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentPurple,
                            fontSize: 14)),
                  ]),
                  const SizedBox(height: 12),
                  SignaturePadWidget(
                    key: ValueKey(
                        'tech_sig_${_assignedTechnician!.id}'),
                    label: 'Firme aqui',
                    onSigned: (data) =>
                        setState(() => _technicianSignature = data),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // ===== GENERATE BUTTON =====
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed:
                  _canGenerate && !_generating ? _generateAndDeliver : null,
              icon: _generating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primaryColor))
                  : const Icon(Icons.check_circle_rounded),
              label: Text(
                _generating
                    ? 'Generando acta...'
                    : 'Firmar y entregar equipo',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),

          if (!_canGenerate)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _totalCtrl.text.isEmpty
                    ? 'Ingrese el valor total del servicio'
                    : _hasWarranty == null
                        ? 'Seleccione si tiene garantia (Si/No)'
                        : _assignedTechnician == null
                            ? 'Seleccione el tecnico'
                            : _clientSignature == null ||
                                    _technicianSignature == null
                                ? 'Complete ambas firmas'
                                : 'Complete el nombre de quien recibe',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.accentOrange),
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      children: [
        GlassCard(
          margin: const EdgeInsets.all(16),
          borderColor: AppTheme.accentGreen.withValues(alpha: 0.4),
          child: Column(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppTheme.accentGreen, size: 48),
              const SizedBox(height: 12),
              const Text('Equipo entregado',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentGreen)),
              const SizedBox(height: 4),
              Text(
                'Orden ${widget.order.orderNumber} - \$${_totalCtrl.text}',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Builder(builder: (ctx) {
                final isDesktop =
                    Theme.of(ctx).platform == TargetPlatform.macOS ||
                    Theme.of(ctx).platform == TargetPlatform.windows ||
                    Theme.of(ctx).platform == TargetPlatform.linux;
                return Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Printing.sharePdf(
                          bytes: _generatedPdf!,
                          filename: 'Acta_${widget.order.orderNumber}.pdf',
                        );
                      },
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: Text(isDesktop ? 'Imprimir' : 'Compartir',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: ElevatedButton.icon(
                      onPressed: _finish,
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Listo'),
                    ),
                  ),
                ],
              );
              }),
            ],
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: (_) async => _generatedPdf!,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
            pdfFileName: 'Acta_${widget.order.orderNumber}.pdf',
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
