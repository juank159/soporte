import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:image_picker/image_picker.dart';
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
  final _totalCtrl = TextEditingController(); // used only for single-device
  final _warrantyMonthsCtrl = TextEditingController();

  // Single-device: one global payment method
  String? _paymentMethod;

  // Multi-device: per-equipment payment method and value
  final Map<String, String?> _equipmentPaymentMethod = {};
  final Map<String, TextEditingController> _equipmentValueCtrl = {};

  bool? _hasWarranty; // null = not selected yet

  // Whether this order requires client signature
  bool get _requiresClientSignature => widget.order.requiresClientSignature;

  double get _multiDeviceTotal {
    double total = 0;
    for (final eq in _readyEquipments) {
      try {
        total += parseFormattedMoney(_equipmentValueCtrl[eq.id]?.text ?? '0');
      } catch (_) {}
    }
    return total;
  }

  // Ready equipments for delivery
  List<OrderEquipment> get _readyEquipments =>
      widget.order.equipments.where((e) => e.status == 'ready').toList();

  bool get _isMultiDevice => widget.order.equipments.isNotEmpty;

  // Technician assigned to the order
  List<User> _technicians = [];
  User? _assignedTechnician;
  bool _loadingTechnicians = true;

  bool _generating = false;
  File? _deliveryPhoto;
  Uint8List? _generatedPdf;
  bool _statusUpdated = false;

  @override
  void initState() {
    super.initState();
    _clientNameCtrl.text = widget.order.customer?.fullName ?? '';
    _totalCtrl.text = '';
    _loadTechnicians();
    // Initialize per-equipment controllers for multi-device
    for (final eq in _readyEquipments) {
      _equipmentValueCtrl[eq.id] = TextEditingController();
      _equipmentValueCtrl[eq.id]!.addListener(() => setState(() {}));
      _equipmentPaymentMethod[eq.id] = null;
    }
    // Rebuild when text fields change so _canGenerate updates
    _totalCtrl.addListener(() => setState(() {}));
    _warrantyMonthsCtrl.addListener(() => setState(() {}));
    _clientNameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    _totalCtrl.dispose();
    _warrantyMonthsCtrl.dispose();
    for (final ctrl in _equipmentValueCtrl.values) {
      ctrl.dispose();
    }
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
          // Auto-load technician signature if available
          if (_assignedTechnician != null && _assignedTechnician!.hasSignature) {
            _loadTechnicianSignature(_assignedTechnician!.signatureUrl!);
          }
        }
        _loadingTechnicians = false;
      });
    } catch (_) {
      setState(() => _loadingTechnicians = false);
    }
  }

  Future<void> _loadTechnicianSignature(String sigUrl) async {
    try {
      Uint8List? bytes;
      if (sigUrl.contains('base64,')) {
        bytes = base64Decode(sigUrl.split('base64,').last);
      } else if (sigUrl.startsWith('http')) {
        final res = await _api.dio.get(sigUrl, options: dio.Options(responseType: dio.ResponseType.bytes));
        bytes = Uint8List.fromList(res.data as List<int>);
      }
      if (bytes != null && bytes.isNotEmpty && mounted) {
        setState(() => _technicianSignature = bytes);
      }
    } catch (_) {}
  }

  bool get _canGenerate {
    if (_clientNameCtrl.text.isEmpty) return false;
    if (_assignedTechnician == null) return false;
    if (_technicianSignature == null) return false;
    if (_requiresClientSignature && _clientSignature == null) return false;
    if (_hasWarranty == null) return false;
    if (_hasWarranty == true && _warrantyMonthsCtrl.text.isEmpty) return false;

    if (_isMultiDevice) {
      for (final eq in _readyEquipments) {
        if (_equipmentValueCtrl[eq.id]?.text.isEmpty ?? true) return false;
        if (_equipmentPaymentMethod[eq.id] == null) return false;
      }
    } else {
      if (_totalCtrl.text.isEmpty) return false;
      if (_paymentMethod == null) return false;
    }

    return true;
  }

  Future<void> _generateAndDeliver() async {
    if (!_canGenerate) return;

    setState(() => _generating = true);

    try {
      final warrantyMonths = int.tryParse(_warrantyMonthsCtrl.text.trim()) ?? 1;
      final warrantyDays = _hasWarranty == true ? warrantyMonths * 30 : 0;
      final warrantyLabel = _hasWarranty == true ? '$warrantyMonths meses' : 'Sin garantia';

      double totalValue;
      List<OrderEquipment> readyEquipments;

      if (_isMultiDevice) {
        readyEquipments = _readyEquipments;
        // Total = sum of per-equipment values
        totalValue = 0;
        for (final eq in readyEquipments) {
          totalValue += parseFormattedMoney(_equipmentValueCtrl[eq.id]!.text.trim());
        }
      } else {
        readyEquipments = [];
        totalValue = parseFormattedMoney(_totalCtrl.text.trim());
      }

      // Sum new value to existing total
      final newTotal = widget.order.total + totalValue;

      try {
        await _api.dio.patch('/orders/${widget.order.id}/delivery-info', data: {
          'total': newTotal,
          'warrantyDays': _isMultiDevice ? widget.order.warrantyDays : warrantyDays,
        });
      } catch (_) {}

      if (_isMultiDevice) {
        for (final eq in readyEquipments) {
          final eqValue = parseFormattedMoney(_equipmentValueCtrl[eq.id]!.text.trim());
          final eqPayment = _equipmentPaymentMethod[eq.id]!;
          final paymentLabel = _paymentMethodLabel(eqPayment);
          final deliveryNote =
              'Entregado por \$${_equipmentValueCtrl[eq.id]!.text.trim()} - $paymentLabel - Garantia: $warrantyLabel';
          try {
            await _api.dio.patch('/orders/${widget.order.id}/equipments/${eq.id}/status', data: {
              'status': 'delivered',
              'notes': deliveryNote,
              'warrantyDays': warrantyDays,
              'laborCost': eqValue,
              'paymentMethod': eqPayment,
            });
          } catch (_) {}
        }
      } else {
        // Single device order - change order status directly
        final paymentLabel = _paymentMethodLabel(_paymentMethod!);
        final deliveryNote =
            'Entregado por \$${_totalCtrl.text.trim()} - $paymentLabel - Garantia: $warrantyLabel';
        try {
          await _api.dio.patch('/orders/${widget.order.id}/status', data: {
            'status': 'delivered',
            'notes': deliveryNote,
          });
        } catch (_) {}
      }
      _statusUpdated = true;

      // Track IDs of equipment we just delivered
      final deliveredIds = readyEquipments.map((eq) => eq.id).toSet();

      // Reload order to get updated equipment data (with warranty/cost saved)
      ServiceOrder? updatedOrder;
      try {
        final orderRes = await _api.dio.get('/orders/${widget.order.id}');
        updatedOrder = ServiceOrder.fromJson(orderRes.data);
      } catch (_) {}

      // Only include the equipment we JUST delivered in this session
      final sourceOrder = updatedOrder ?? widget.order;
      final deliveringEquipments = sourceOrder.equipments
          .where((eq) => deliveredIds.contains(eq.id))
          .toList();

      final warrantyDaysForPdf = _hasWarranty == true ? warrantyMonths * 30 : 0;
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
        diagnosis: sourceOrder.diagnosis,
        notes: widget.order.notes,
        laborCost: widget.order.laborCost,
        subtotal: widget.order.subtotal,
        tax: widget.order.tax,
        total: totalValue, // This delivery's value, not accumulated
        warrantyDays: warrantyDaysForPdf,
        requiresClientSignature: _requiresClientSignature,
        createdAt: widget.order.createdAt,
        items: widget.order.items,
        equipments: deliveringEquipments,
      );

      final clientName = _clientNameCtrl.text.trim();
      final techName = _assignedTechnician!.fullName;

      // Upload delivery photo if taken
      if (_deliveryPhoto != null) {
        try {
          final bytes = await _deliveryPhoto!.readAsBytes();
          final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          await _api.dio.post('/orders/${widget.order.id}/photos', data: {
            'photoUrl': b64,
            'description': 'Foto de entrega',
            'stage': 'delivery',
          });
        } catch (_) {}
      }

      // Save signatures to backend for future reprints
      try {
        final techB64 = base64Encode(_technicianSignature!);
        if (_requiresClientSignature && _clientSignature != null) {
          final clientB64 = base64Encode(_clientSignature!);
          await _api.dio.post(
            '/orders/${widget.order.id}/signatures',
            data: {
              'signerType': 'customer',
              'signerName': clientName,
              'pngData': 'data:image/png;base64,$clientB64',
            },
          );
        }
        await _api.dio.post(
          '/orders/${widget.order.id}/signatures',
          data: {
            'signerType': 'technician',
            'signerName': techName,
            'pngData': 'data:image/png;base64,$techB64',
          },
        );
      } catch (_) {}

      // Load history for payment method extraction in PDF
      List<Map<String, dynamic>> historyData = [];
      try {
        final histRes = await _api.dio.get('/orders/${widget.order.id}/history');
        historyData = (histRes.data as List).cast<Map<String, dynamic>>();
      } catch (_) {}

      // Build payment method label for PDF
      String pdfPaymentLabel;
      if (_isMultiDevice) {
        final labels = _readyEquipments
            .map((eq) => _paymentMethodLabel(_equipmentPaymentMethod[eq.id] ?? ''))
            .toSet()
            .join(' / ');
        pdfPaymentLabel = labels;
      } else {
        pdfPaymentLabel = _paymentMethodLabel(_paymentMethod!);
      }

      final pdfBytes = await _pdfService.generateDeliveryAct(
        order: orderForPdf,
        tenant: widget.tenant,
        clientSignaturePng: _requiresClientSignature && _clientSignature != null
            ? _clientSignature!
            : Uint8List(0),
        clientName: clientName,
        technicianSignaturePng: _technicianSignature!,
        technicianName: techName,
        paymentMethod: pdfPaymentLabel,
        history: historyData,
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

  String _paymentMethodLabel(String method) {
    switch (method) {
      case 'efectivo': return 'Efectivo';
      case 'transferencia': return 'Transferencia';
      case 'tarjeta_credito': return 'Tarjeta de Credito';
      case 'tarjeta_debito': return 'Tarjeta de Debito';
      case 'adi': return 'ADI';
      default: return method;
    }
  }

  Widget _paymentMethodSelector({
    required String? selected,
    required ValueChanged<String> onSelected,
  }) {
    final methods = [
      ('efectivo', 'Efectivo', Icons.money_rounded, AppTheme.accentGreen),
      ('transferencia', 'Transferencia', Icons.swap_horiz_rounded, AppTheme.accentBlue),
      ('tarjeta_credito', 'T. Credito', Icons.credit_card_rounded, AppTheme.accentPurple),
      ('tarjeta_debito', 'T. Debito', Icons.credit_card_rounded, AppTheme.accentCyan),
      ('adi', 'ADI', Icons.account_balance_rounded, AppTheme.accentOrange),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: methods.map((m) {
        final (key, label, icon, color) = m;
        return ChoiceChip(
          avatar: Icon(icon, size: 14, color: selected == key ? color : AppTheme.textSecondary),
          label: Text(label),
          selected: selected == key,
          onSelected: (_) => onSelected(key),
        );
      }).toList(),
    );
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
          icon: Icon(Icons.arrow_back_rounded),
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
                Row(children: [
                  Icon(Icons.attach_money_rounded, color: AppTheme.accentGreen, size: 20),
                  SizedBox(width: 8),
                  Text('Valor y garantia',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.accentGreen, fontSize: 15)),
                ]),
                SizedBox(height: 16),

                // Single-device: one global value + payment
                if (!_isMultiDevice) ...[
                  TextField(
                    controller: _totalCtrl,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Valor del servicio *',
                      prefixText: '\$ ',
                      prefixIcon: Icon(Icons.payments_rounded),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text('Metodo de pago: *',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  SizedBox(height: 8),
                  _paymentMethodSelector(
                    selected: _paymentMethod,
                    onSelected: (v) => setState(() => _paymentMethod = v),
                  ),
                ],

                // Multi-device: per-equipment value + payment
                if (_isMultiDevice) ...[
                  if (_readyEquipments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No hay equipos listos para entregar',
                          style: TextStyle(color: AppTheme.accentOrange, fontSize: 13)),
                    )
                  else ...[
                    Text('Valor y pago por equipo:',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    SizedBox(height: 12),
                    ..._readyEquipments.map((eq) => Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.devices_rounded, size: 14, color: AppTheme.accentCyan),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(eq.summary,
                                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ]),
                        SizedBox(height: 10),
                        TextField(
                          controller: _equipmentValueCtrl[eq.id],
                          style: TextStyle(color: AppTheme.textPrimary),
                          keyboardType: TextInputType.number,
                          inputFormatters: [ThousandSeparatorFormatter()],
                          decoration: InputDecoration(
                            labelText: 'Valor de este servicio *',
                            prefixText: '\$ ',
                            prefixIcon: Icon(Icons.payments_rounded, size: 18),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                        SizedBox(height: 10),
                        Text('Pago: *', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        SizedBox(height: 6),
                        _paymentMethodSelector(
                          selected: _equipmentPaymentMethod[eq.id],
                          onSelected: (v) => setState(() => _equipmentPaymentMethod[eq.id] = v),
                        ),
                      ]),
                    )),
                    // Total computed
                    Divider(color: AppTheme.dividerColor),
                    Row(children: [
                      Text('Total calculado:',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                      Spacer(),
                      Text(
                        '\$ ${formatMoney(_multiDeviceTotal)}',
                        style: TextStyle(color: AppTheme.accentGreen, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ]),
                  ],
                ],

                SizedBox(height: 16),
                Text('Garantia: *', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Row(children: [
                  ChoiceChip(label: Text('Si'), selected: _hasWarranty == true,
                      onSelected: (_) => setState(() => _hasWarranty = true)),
                  SizedBox(width: 8),
                  ChoiceChip(label: Text('No'), selected: _hasWarranty == false,
                      onSelected: (_) => setState(() => _hasWarranty = false)),
                  if (_hasWarranty == true) ...[
                    SizedBox(width: 16),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _warrantyMonthsCtrl,
                        style: TextStyle(color: AppTheme.textPrimary),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Meses',
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),

          // ===== QUIEN RECIBE (CLIENT) =====
          GlassCard(
            borderColor: AppTheme.accentBlue.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.person_rounded,
                      color: AppTheme.accentBlue, size: 18),
                  SizedBox(width: 8),
                  Text('Recibe conforme',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentBlue,
                          fontSize: 14)),
                ]),
                SizedBox(height: 12),
                TextField(
                  controller: _clientNameCtrl,
                  style: TextStyle(color: AppTheme.textPrimary),
                  readOnly: widget.order.customer?.fullName != null &&
                      widget.order.customer!.fullName.isNotEmpty &&
                      widget.order.customer!.idNumber != 'EXPRESS',
                  decoration: InputDecoration(
                    labelText: 'Nombre de quien recibe',
                    prefixIcon: Icon(Icons.badge_rounded),
                    suffixIcon: widget.order.customer?.fullName != null &&
                        widget.order.customer!.idNumber != 'EXPRESS'
                        ? Icon(Icons.lock_rounded,
                            size: 16, color: AppTheme.textSecondary)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                if (_requiresClientSignature)
                  SignaturePadWidget(
                    label: 'Firma de quien recibe',
                    fullScreen: true,
                    onSigned: (data) => setState(() => _clientSignature = data),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded, color: AppTheme.accentOrange, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Sin firma de cliente (configurado al crear la orden)',
                            style: TextStyle(color: AppTheme.accentOrange, fontSize: 12)),
                      ),
                    ]),
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
                SizedBox(height: 12),
                if (_loadingTechnicians)
                  Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accentCyan))
                else if (_assignedTechnician != null)
                  // Show assigned technician (can't change here)
                  GlassCard(
                    margin: EdgeInsets.zero,
                    borderColor:
                        AppTheme.accentGreen.withValues(alpha: 0.3),
                    padding: EdgeInsets.all(10),
                    child: Row(children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppTheme.accentGreen, size: 18),
                      SizedBox(width: 10),
                      Text(_assignedTechnician!.fullName,
                          style: TextStyle(
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
                          if (tech.hasSignature) {
                            _loadTechnicianSignature(tech.signatureUrl!);
                          }
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
                  // If technician already has saved signature, show it
                  if (_technicianSignature != null && _assignedTechnician!.hasSignature)
                    Column(children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                        ),
                        child: Column(children: [
                          Image.memory(_technicianSignature!, height: 60),
                          const SizedBox(height: 6),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 16),
                            const SizedBox(width: 6),
                            Text('Firma guardada', style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(() => _technicianSignature = null),
                        child: Text('Firmar manualmente', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ),
                    ])
                  else
                    SignaturePadWidget(
                      key: ValueKey('tech_sig_${_assignedTechnician!.id}'),
                      label: 'Firme aqui',
                      onSigned: (data) => setState(() => _technicianSignature = data),
                    ),
                ],
              ),
            ),

          // ===== DELIVERY PHOTO (optional) =====
          GlassCard(
            borderColor: AppTheme.accentOrange.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.camera_alt_rounded,
                      color: AppTheme.accentOrange, size: 18),
                  SizedBox(width: 8),
                  Text('Foto de entrega (opcional)',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentOrange,
                          fontSize: 14)),
                ]),
                const SizedBox(height: 10),
                if (_deliveryPhoto != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(_deliveryPhoto!,
                            height: 120, width: double.infinity,
                            fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _deliveryPhoto = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                                color: AppTheme.accentRed,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final isDesktop = !kIsWeb &&
                            (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
                        final picker = ImagePicker();
                        try {
                          final img = await picker.pickImage(
                            source: isDesktop
                                ? ImageSource.gallery
                                : ImageSource.camera,
                            imageQuality: 80,
                            maxWidth: 1280,
                          );
                          if (img != null) {
                            setState(() => _deliveryPhoto = File(img.path));
                          }
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                      label: const Text('Tomar foto del equipo'),
                    ),
                  ),
              ],
            ),
          ),

          SizedBox(height: 8),

          // ===== GENERATE BUTTON =====
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed:
                  _canGenerate && !_generating ? _generateAndDeliver : null,
              icon: _generating
                  ? SizedBox(
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
                _hasWarranty == null
                    ? 'Seleccione si tiene garantia (Si/No)'
                    : (!_isMultiDevice && _totalCtrl.text.isEmpty)
                        ? 'Ingrese el valor del servicio'
                        : (!_isMultiDevice && _paymentMethod == null)
                            ? 'Seleccione el metodo de pago'
                            : (_isMultiDevice && _readyEquipments.any((e) =>
                                  _equipmentValueCtrl[e.id]?.text.isEmpty ?? true))
                                ? 'Ingrese el valor para cada equipo'
                                : (_isMultiDevice && _readyEquipments.any((e) =>
                                      _equipmentPaymentMethod[e.id] == null))
                                    ? 'Seleccione metodo de pago para cada equipo'
                                    : _assignedTechnician == null
                                        ? 'Seleccione el tecnico'
                                        : (_requiresClientSignature && _clientSignature == null)
                                            ? 'Se requiere firma del cliente'
                                            : _technicianSignature == null
                                                ? 'Se requiere firma del tecnico'
                                                : 'Complete el nombre de quien recibe',
                style: const TextStyle(fontSize: 12, color: AppTheme.accentOrange),
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
          margin: EdgeInsets.all(16),
          borderColor: AppTheme.accentGreen.withValues(alpha: 0.4),
          child: Column(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: AppTheme.accentGreen, size: 48),
              SizedBox(height: 12),
              Text('Equipo entregado',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentGreen)),
              SizedBox(height: 4),
              Text(
                'Orden ${widget.order.orderNumber}${_isMultiDevice ? ' - \$${formatMoney(_multiDeviceTotal)}' : ' - \$${_totalCtrl.text}'}',
                style: TextStyle(
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
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
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
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
