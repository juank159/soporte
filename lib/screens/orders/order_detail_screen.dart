import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/orders/orders_bloc.dart';
import '../../config/theme.dart';
import '../../config/format_utils.dart';
import '../../config/date_utils.dart';
import '../../models/service_order.dart';
import '../../models/tenant.dart';
import '../../models/user.dart';
import '../../services/order_service.dart';
import '../../services/api_service.dart';
import '../../services/ticket_printer_service.dart';
import '../../services/pdf_generator_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/ticket_preview_widget.dart';
import '../dashboard/dashboard_screen.dart';
import 'delivery_screen.dart';
import 'package:printing/printing.dart' as printing_lib;
import 'package:pdf/pdf.dart';

class OrderDetailScreen extends StatefulWidget {
  final ServiceOrder order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late ServiceOrder _order;
  final OrderService _orderService = OrderService();
  final ApiService _api = ApiService();
  bool _loading = false;
  Tenant? _tenant;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _refreshOrder();
    _loadTenant();
    _loadHistory();
    _loadPhotos();
    _loadTechNames();
  }

  final TicketPrinterService _printerService = TicketPrinterService();
  final PdfGeneratorService _pdfGenerator = PdfGeneratorService();
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _photos = [];
  Map<String, String> _techNames = {}; // techId -> name

  void _onMenuAction(String action) {
    if (action == 'print_ticket') {
      _reprintTicket();
    } else if (action == 'print_acta_all') {
      _reprintActa(null); // All delivered
    } else if (action.startsWith('print_acta_eq_')) {
      final eqId = action.replaceFirst('print_acta_eq_', '');
      _reprintActa(eqId);
    }
  }

  Future<void> _reprintTicket() async {
    if (_tenant == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cargando datos del tenant...'),
      ));
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _TicketPreviewScreen(
            order: _order,
            tenant: _tenant!,
            printerService: _printerService,
          ),
        ),
      );
    }
  }

  Future<void> _reprintActa(String? equipmentId) async {
    if (_tenant == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Generando acta de entrega...'),
        duration: Duration(seconds: 1),
      ));
    }

    try {
      // Load saved signatures from backend
      final sigRes = await _api.dio.get('/orders/${_order.id}/signatures');
      final signatures = sigRes.data as List;

      Uint8List clientSig = Uint8List(0);
      Uint8List techSig = Uint8List(0);
      String clientName = _order.customer?.fullName ?? 'Cliente';
      String techName = 'Tecnico';

      for (final sig in signatures) {
        final pngData = sig['pngUrl'] as String? ?? '';
        final name = sig['signerName'] as String? ?? '';
        Uint8List? decoded;

        // Load from Cloudinary URL
        if (pngData.startsWith('http')) {
          try {
            final resp = await _api.dio.get(pngData,
                options: dio.Options(responseType: dio.ResponseType.bytes));
            decoded = Uint8List.fromList(resp.data);
          } catch (_) {}
        }
        // Load from base64
        else if (pngData.contains('base64,')) {
          try {
            decoded = base64Decode(pngData.split('base64,').last);
          } catch (_) {}
        }

        if (decoded != null && decoded.length > 50) {
          if (sig['signerType'] == 'customer') {
            clientSig = decoded;
            clientName = name;
          } else if (sig['signerType'] == 'technician') {
            techSig = decoded;
            techName = name;
          }
        }
      }

      // Use diagnosis and notes directly from the order (not from history)
      // They already have the final edited text

      // Filter equipments for the acta
      List<OrderEquipment> actaEquipments;
      if (equipmentId != null) {
        actaEquipments = _order.equipments.where((eq) => eq.id == equipmentId).toList();
      } else {
        actaEquipments = _order.equipments.where((eq) => eq.status == 'delivered').toList();
      }

      final orderForPdf = ServiceOrder(
        id: _order.id,
        orderNumber: _order.orderNumber,
        customerId: _order.customerId,
        customer: _order.customer,
        deviceId: _order.deviceId,
        device: _order.device,
        technicianId: _order.technicianId,
        status: _order.status,
        problemReported: _order.problemReported,
        diagnosis: _order.diagnosis,
        notes: _order.notes,
        laborCost: _order.laborCost,
        subtotal: _order.subtotal,
        tax: _order.tax,
        total: _order.total,
        warrantyDays: _order.warrantyDays,
        createdAt: _order.createdAt,
        deliveredAt: _order.deliveredAt,
        items: _order.items,
        equipments: actaEquipments,
      );

      // Extract payment method from history for the acta
      String? reprintPayment;
      for (final h in _history.reversed) {
        final notes = h['notes'] as String? ?? '';
        if (notes.contains('Entregado por')) {
          if (notes.contains('Efectivo')) { reprintPayment = 'Efectivo'; break; }
          if (notes.contains('Transferencia')) { reprintPayment = 'Transferencia'; break; }
          if (notes.contains('Tarjeta de Credito')) { reprintPayment = 'Tarjeta de Credito'; break; }
          if (notes.contains('Tarjeta de Debito')) { reprintPayment = 'Tarjeta de Debito'; break; }
        }
      }

      final pdfBytes = await _pdfGenerator.generateDeliveryAct(
        order: orderForPdf,
        tenant: _tenant!,
        clientSignaturePng: clientSig,
        clientName: clientName,
        technicianSignaturePng: techSig,
        technicianName: techName,
        deliveryDate: _order.deliveredAt,
        paymentMethod: reprintPayment,
        history: _history,
      );

      // Navigate to a preview screen instead of printing directly
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ActaPreviewScreen(
              pdfBytes: pdfBytes,
              orderNumber: _order.orderNumber,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al generar acta: $e'),
          backgroundColor: AppTheme.accentRed,
        ));
      }
    }
  }

  Widget _brokenImage() => Container(
    width: 80, height: 80,
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(Icons.broken_image_rounded, color: AppTheme.textSecondary),
  );

  Widget _equipRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11))),
        Expanded(child: Text(value, style: TextStyle(color: color ?? AppTheme.textPrimary, fontSize: 11))),
      ]),
    );
  }

  /// Get displayable equipment list (converts single-device to equipment format)
  List<OrderEquipment> get _displayEquipments {
    if (_order.equipments.isNotEmpty) return _order.equipments;
    if (_order.device == null) return [];
    // Convert single device to OrderEquipment for unified display
    return [
      OrderEquipment(
        id: _order.deviceId ?? _order.id,
        orderId: _order.id,
        deviceType: _order.device!.type ?? '-',
        deviceBrand: _order.device!.brand ?? '-',
        deviceModel: _order.device!.model ?? '-',
        deviceSerial: _order.device!.serial,
        deviceColor: _order.device!.color,
        accessories: _order.device!.accessories,
        problemReported: _order.problemReported,
        status: _order.status,
        diagnosis: _order.diagnosis,
        notes: _order.notes,
        technicianId: _order.technicianId,
        laborCost: _order.total,
        warrantyDays: _order.warrantyDays,
        deliveredAt: _order.deliveredAt,
        createdAt: _order.createdAt,
      ),
    ];
  }

  bool get _isSingleDevice => _order.equipments.isEmpty;

  /// Equipment that are ready to be delivered
  List<OrderEquipment> get _readyEquipments =>
      _displayEquipments.where((eq) => eq.status == 'ready').toList();

  /// True when ALL active (non-returned) equipments are ready
  bool get _allActiveReady {
    final active = _displayEquipments.where((eq) => eq.status != 'returned' && eq.status != 'delivered').toList();
    return active.isNotEmpty && active.every((eq) => eq.status == 'ready');
  }

  String? _nextEquipmentStatus(String current) {
    const flow = ['received', 'diagnosing', 'repairing', 'ready', 'delivered'];
    final idx = flow.indexOf(current);
    if (idx >= 0 && idx < flow.length - 1) return flow[idx + 1];
    return null;
  }

  Future<void> _loadTechNames() async {
    try {
      final res = await _api.dio.get('/users');
      final users = res.data as List;
      setState(() {
        _techNames = {for (final u in users) u['id'] as String: u['fullName'] as String};
      });
    } catch (_) {}
  }

  String _getTechName(String? techId) {
    if (techId == null) return '';
    return _techNames[techId] ?? '';
  }

  Future<void> _assignTechnicianToEquipment(String equipmentId) async {
    List<User> techs = [];
    try {
      final res = await _api.dio.get('/users');
      techs = (res.data as List)
          .map((e) => User.fromJson(e as Map<String, dynamic>))
          .where((u) => u.role == 'technician' || u.role == 'supervisor')
          .toList();
    } catch (_) {}

    if (techs.isEmpty) {
      if (mounted) _showError('No hay tecnicos registrados');
      return;
    }

    final selected = await showDialog<User>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Asignar tecnico', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: techs.map((t) => ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.accentPurple.withValues(alpha: 0.2),
              child: Text(t.fullName[0], style: TextStyle(color: AppTheme.accentPurple)),
            ),
            title: Text(t.fullName, style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(t.role == 'supervisor' ? 'Supervisor' : 'Tecnico',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, t),
          )).toList(),
        ),
      ),
    );

    if (selected == null) return;
    try {
      if (_isSingleDevice) {
        await _api.dio.post('/orders/${_order.id}/assign', data: {
          'technicianId': selected.id,
        });
      } else {
        await _api.dio.post('/orders/${_order.id}/equipments/$equipmentId/assign', data: {
          'technicianId': selected.id,
        });
      }
      _refreshOrder();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${selected.fullName} asignado al equipo'),
          backgroundColor: AppTheme.accentGreen,
        ));
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _editField(OrderEquipment eq, String field) async {
    final isDiag = field == 'diagnosis';
    final currentValue = isDiag
        ? (eq.diagnosis ?? '')
        : (eq.notes != null && !eq.notes!.startsWith('Entregado por') ? eq.notes! : '');
    final ctrl = TextEditingController(text: currentValue);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(isDiag ? 'Editar diagnostico' : 'Editar reparacion',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${eq.deviceBrand} ${eq.deviceModel}',
                style: TextStyle(color: AppTheme.accentCyan, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: isDiag ? 'Diagnostico (que se encontro)' : 'Reparacion (que se hizo)',
                hintText: isDiag
                    ? 'Ej: Se encontro bateria dañada...'
                    : 'Ej: Se cambio bateria, se limpio...',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (saved != true) return;
    try {
      if (_isSingleDevice) {
        if (isDiag) {
          await _orderService.addDiagnosis(_order.id, diagnosis: ctrl.text.trim());
        } else {
          await _orderService.updateStatus(_order.id, _order.status, notes: ctrl.text.trim());
        }
      } else {
        if (isDiag) {
          await _api.dio.patch('/orders/${_order.id}/equipments/${eq.id}/diagnosis', data: {
            'diagnosis': ctrl.text.trim(),
          });
        } else {
          // Update notes directly without changing status
          await _orderService.updateEquipmentStatus(
            _order.id, eq.id, eq.status, notes: ctrl.text.trim(),
          );
        }
      }
      _refreshOrder();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isDiag ? 'Diagnostico actualizado' : 'Reparacion actualizada'),
          backgroundColor: AppTheme.accentGreen,
        ));
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  Future<void> _editOrderDiagnosis() async {
    final ctrl = TextEditingController(text: _order.diagnosis ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Row(children: [
          Icon(Icons.edit_rounded, color: AppTheme.accentCyan, size: 20),
          const SizedBox(width: 8),
          Text('Editar diagnostico', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        ]),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Diagnostico y reparacion',
              hintText: 'Describa el diagnostico y lo que se realizo...',
              alignLabelWithHint: true,
            ),
            maxLines: 6,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (saved != true) return;
    try {
      await _orderService.addDiagnosis(_order.id, diagnosis: ctrl.text.trim());
      _refreshOrder();
    } catch (e) {
      if (mounted) _showError('Error: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.accentOrange));
  }

  Future<void> _changeEquipmentStatus(String equipmentId, String newStatus) async {
    // Check technician assignment before diagnosing
    if (newStatus == 'diagnosing') {
      final eq = _displayEquipments.where((e) => e.id == equipmentId).firstOrNull;
      final hasTech = eq?.technicianId != null || _order.technicianId != null;
      if (!hasTech) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Asigne un tecnico al equipo antes de iniciar diagnostico'),
            backgroundColor: AppTheme.accentOrange,
          ));
        }
        return;
      }
    }

    final notesCtrl = TextEditingController();
    final notesRequired = newStatus == 'diagnosing' || newStatus == 'repairing';

    String labelText;
    String hintText;
    switch (newStatus) {
      case 'diagnosing':
        labelText = 'Diagnostico del equipo *';
        hintText = 'Ej: Se reviso el equipo, se encontro falla en...';
        break;
      case 'repairing':
        labelText = 'Trabajo a realizar *';
        hintText = 'Ej: Se procedera con cambio de pantalla...';
        break;
      case 'ready':
        labelText = 'Observaciones (opcional)';
        hintText = 'Ej: Reparacion completada...';
        break;
      default:
        labelText = 'Notas (opcional)';
        hintText = '';
    }

    void confirmAction(BuildContext ctx) {
      if (notesRequired && notesCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Este campo es obligatorio'),
          backgroundColor: AppTheme.accentOrange,
        ));
        return;
      }
      Navigator.pop(ctx, true);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(_nextStatusLabel(newStatus), style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: notesCtrl,
            autofocus: true,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
              alignLabelWithHint: true,
            ),
            maxLines: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => confirmAction(ctx),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => confirmAction(ctx),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (_isSingleDevice) {
        await _orderService.updateStatus(_order.id, newStatus, notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null);
      } else {
        await _orderService.updateEquipmentStatus(
          _order.id, equipmentId, newStatus, notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
        );
      }
      _refreshOrder();
      _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accentRed));
      }
    }
  }

  Future<void> _returnEquipment(OrderEquipment eq) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Row(children: [
          Icon(Icons.undo_rounded, color: AppTheme.accentRed),
          const SizedBox(width: 8),
          Expanded(child: Text('Devolver ${eq.summary}',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 15))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Este equipo sera devuelto sin reparar.',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: notesCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Motivo de devolucion *',
              hintText: 'Ej: Cliente no aprobo el costo...',
            ),
            maxLines: 3,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            onPressed: () {
              if (notesCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Ingrese el motivo'), backgroundColor: AppTheme.accentOrange));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Confirmar devolucion'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (_isSingleDevice) {
        await _orderService.updateStatus(_order.id, 'returned', notes: notesCtrl.text.trim());
      } else {
        await _orderService.updateEquipmentStatus(
          _order.id, eq.id, 'returned', notes: notesCtrl.text.trim(),
        );
      }
      _refreshOrder();
      _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accentRed));
      }
    }
  }

  void _showFullPhotoUrl(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Image.network(url,
              errorBuilder: (_, __, ___) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.broken_image_rounded, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 8),
                  Text('Imagen no disponible', style: TextStyle(color: AppTheme.textSecondary)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFullPhoto(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Image.memory(bytes),
          ),
        ),
      ),
    );
  }

  Future<void> _loadPhotos() async {
    try {
      final res = await _api.dio.get('/orders/${_order.id}/photos');
      setState(() => _photos = (res.data as List).cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final res = await _api.dio.get('/orders/${_order.id}/history');
      setState(() {
        _history = (res.data as List).cast<Map<String, dynamic>>();
      });
    } catch (_) {}
  }


  void _showReturnDialog() {
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.undo_rounded, color: AppTheme.accentRed),
          const SizedBox(width: 10),
          Text('Devolver equipo',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        ]),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'El equipo sera devuelto al cliente sin reparar.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notesCtrl,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Motivo de la devolucion *',
                hintText: 'Ej: Cliente no aprobo el costo de reparacion...',
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Ingrese el motivo' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
            ),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx);
              _changeStatus('returned', notes: notesCtrl.text.trim());
            },
            child: const Text('Confirmar devolucion'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssignTechnicianDialog() async {
    List<User> techs = [];
    try {
      final res = await _api.dio.get('/users');
      techs = (res.data as List)
          .map((e) => User.fromJson(e as Map<String, dynamic>))
          .where((u) => u.role == 'technician' || u.role == 'supervisor')
          .toList();
    } catch (_) {}

    if (!mounted) return;
    final selected = await showDialog<User>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Asignar tecnico',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: techs
              .map((t) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          AppTheme.accentPurple.withValues(alpha: 0.15),
                      child: Text(t.fullName[0],
                          style: TextStyle(
                              color: AppTheme.accentPurple)),
                    ),
                    title: Text(t.fullName,
                        style: TextStyle(
                            color: AppTheme.textPrimary)),
                    subtitle: Text(t.role,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                    onTap: () => Navigator.pop(ctx, t),
                  ))
              .toList(),
        ),
      ),
    );

    if (selected != null) {
      try {
        await _orderService.updateStatus(_order.id, _order.status);
        await _api.dio.post('/orders/${_order.id}/assign',
            data: {'technicianId': selected.id});
        _refreshOrder();
      } catch (_) {}
    }
  }

  Future<void> _loadTenant() async {
    try {
      final res = await _api.dio.get('/tenants/me');
      setState(() => _tenant = Tenant.fromJson(res.data));
    } catch (_) {}
  }

  Future<void> _refreshOrder() async {
    try {
      final updated = await _orderService.getOrder(_order.id);
      setState(() => _order = updated);
      _loadHistory();
    } catch (_) {}
  }

  Future<void> _changeStatus(String newStatus, {String? notes}) async {
    setState(() => _loading = true);
    try {
      final updated =
          await _orderService.updateStatus(_order.id, newStatus, notes: notes);
      setState(() {
        _order = updated;
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Estado actualizado: ${_order.statusLabel}'),
          backgroundColor: AppTheme.accentGreen,
        ));
        context.read<OrdersBloc>().add(OrdersLoadRequested());
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al cambiar estado'),
          backgroundColor: AppTheme.accentRed,
        ));
      }
    }
  }

  String? get _nextStatus {
    switch (_order.status) {
      case 'received':
        return 'diagnosing';
      case 'diagnosing':
        return 'repairing';
      case 'repairing':
        return 'ready';
      case 'ready':
        return 'delivered';
      default:
        return null;
    }
  }

  String _nextStatusLabel(String status) {
    switch (status) {
      case 'diagnosing':
        return 'Iniciar Diagnostico';
      case 'repairing':
        return 'Iniciar Reparacion';
      case 'ready':
        return 'Marcar como Listo';
      case 'delivered':
        return 'Registrar Entrega';
      default:
        return 'Siguiente';
    }
  }

  IconData _nextStatusIcon(String status) {
    switch (status) {
      case 'diagnosing':
        return Icons.search_rounded;
      case 'repairing':
        return Icons.build_rounded;
      case 'ready':
        return Icons.check_circle_rounded;
      case 'delivered':
        return Icons.local_shipping_rounded;
      default:
        return Icons.arrow_forward_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor(_order.status);
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        title: Text(_order.orderNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshOrder,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _onMenuAction,
            itemBuilder: (_) {
              final items = <PopupMenuEntry<String>>[];
              // Reimprimir ticket (solo si no está cerrada)
              if (_order.status != 'delivered') {
                items.add(PopupMenuItem(
                  value: 'print_ticket',
                  child: Row(children: [
                    Icon(Icons.receipt_long_rounded, size: 18, color: AppTheme.accentCyan),
                    const SizedBox(width: 10),
                    Text('Reimprimir ticket', style: TextStyle(color: AppTheme.textPrimary)),
                  ]),
                ));
              }
              // Reimprimir actas
              final deliveredEqs = _order.equipments.where((eq) => eq.status == 'delivered').toList();
              if (_order.status == 'delivered' && _order.equipments.isEmpty) {
                // Single device - one acta
                items.add(PopupMenuItem(
                  value: 'print_acta_all',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf_rounded, size: 18, color: AppTheme.accentRed),
                    const SizedBox(width: 10),
                    Text('Reimprimir acta', style: TextStyle(color: AppTheme.textPrimary)),
                  ]),
                ));
              } else if (deliveredEqs.isNotEmpty) {
                // Multi-equipment: option per delivered equipment + general if all delivered
                if (deliveredEqs.length > 1) {
                  items.add(PopupMenuItem(
                    value: 'print_acta_all',
                    child: Row(children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 18, color: AppTheme.accentRed),
                      const SizedBox(width: 10),
                      Text('Reimprimir acta general', style: TextStyle(color: AppTheme.textPrimary)),
                    ]),
                  ));
                }
                for (int i = 0; i < _order.equipments.length; i++) {
                  final eq = _order.equipments[i];
                  if (eq.status == 'delivered') {
                    items.add(PopupMenuItem(
                      value: 'print_acta_eq_${eq.id}',
                      child: Row(children: [
                        Icon(Icons.description_rounded, size: 18, color: AppTheme.accentPurple),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Acta equipo ${i + 1}: ${eq.deviceBrand} ${eq.deviceModel}',
                            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                            overflow: TextOverflow.ellipsis)),
                      ]),
                    ));
                  }
                }
              }
              return items;
            },
          ),
        ],
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
        child: LayoutBuilder(
          builder: (context, screenConstraints) {
            final screenW = screenConstraints.maxWidth;
            final pad = isWide ? 24.0 : 16.0;

            return SingleChildScrollView(
              padding: EdgeInsets.all(pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status header
                  _statusHeader(color, isWide),
                  const SizedBox(height: 16),

                  // ====== RESPONSIVE LAYOUT ======
                  if (screenW > 900) ...[
                    // DESKTOP: equipment cards left, info+history right
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: equipment cards (takes 60%)
                        Expanded(
                          flex: 3,
                          child: Column(children: [
                            _equipmentsSection(),
                            const SizedBox(height: 12),
                            _colService(),
                          ]),
                        ),
                        const SizedBox(width: 16),
                        // Right: client + dates + photos + history (takes 40%)
                        Expanded(
                          flex: 2,
                          child: Column(children: [
                            _colInfo(),
                            _historyCard(),
                          ]),
                        ),
                      ],
                    ),
                  ] else if (screenW > 600) ...[
                    // TABLET: equipment full width, then 2 columns below
                    _equipmentsSection(),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(children: [_colInfo(), _colService()])),
                        const SizedBox(width: 12),
                        Expanded(child: _historyCard()),
                      ],
                    ),
                  ] else ...[
                    // MOBILE: everything stacked
                    _equipmentsSection(),
                    const SizedBox(height: 12),
                    _colInfo(),
                    _colService(),
                    _historyCard(),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Equipment section with delivery button
  Widget _equipmentsSection() {
    return Column(children: [
      _equipmentsGrid(),
      if (_allActiveReady && _tenant != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push<bool>(context, MaterialPageRoute(
                builder: (_) => DeliveryScreen(order: _order, tenant: _tenant!),
              )).then((delivered) {
                _refreshOrder();
                _loadHistory();
                if (delivered == true && mounted) {
                  context.read<OrdersBloc>().add(OrdersLoadRequested());
                }
              });
            },
            icon: const Icon(Icons.draw_rounded),
            label: Text(_readyEquipments.length > 1
                ? 'Firmar y Entregar todos (${_readyEquipments.length} equipos)'
                : 'Firmar y Entregar'),
          ),
        ),
      ],
    ]);
  }

  Widget _statusHeader(Color color, bool isWide) {
    return GlassCard(
      borderColor: color.withValues(alpha: 0.4),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.assignment_rounded, color: color, size: 28),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _order.orderNumber,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    StatusBadge(label: _order.statusLabel, color: color),
                  ],
                ),
              ),
              if (_order.total > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Total',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                    Text(
                      '\$${formatMoney(_order.total)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentGreen,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // All action buttons are now in the equipment grid above
        ],
      ),
    );
  }

  void _showChangeStatusDialog() {
    final next = _nextStatus!;
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Notas obligatorias en diagnostico y reparacion
    final notesRequired = next == 'diagnosing' || next == 'repairing';

    // Config por estado
    String labelText;
    String hintText;
    String defaultNote;
    switch (next) {
      case 'diagnosing':
        labelText = 'Diagnostico del equipo *';
        hintText = 'Ej: Se reviso el equipo, se encontro falla en...';
        defaultNote = '';
        break;
      case 'repairing':
        labelText = 'Trabajo a realizar *';
        hintText = 'Ej: Se procedera con cambio de pantalla, limpieza de placa...';
        defaultNote = '';
        break;
      case 'ready':
        labelText = 'Observaciones (opcional)';
        hintText = 'Ej: Reparacion completada, equipo funcionando...';
        final equipo = '${_order.device?.brand ?? ''} ${_order.device?.model ?? ''}'.trim();
        defaultNote = 'El equipo $equipo esta listo para entrega';
        break;
      default:
        labelText = 'Notas (opcional)';
        hintText = '';
        defaultNote = '';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_nextStatusIcon(next), color: AppTheme.accentCyan),
            SizedBox(width: 10),
            Expanded(
              child: Text(_nextStatusLabel(next),
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontSize: 16)),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cambiar estado a "${_statusLabelFor(next)}"',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: notesCtrl,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: labelText,
                  hintText: hintText,
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: notesRequired
                    ? (v) => v == null || v.trim().isEmpty
                        ? 'Este campo es obligatorio'
                        : null
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx);
              final notes = notesCtrl.text.trim().isNotEmpty
                  ? notesCtrl.text.trim()
                  : defaultNote;
              _changeStatus(next, notes: notes);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  String _statusLabelFor(String status) {
    switch (status) {
      case 'received': return 'Recibido';
      case 'diagnosing': return 'En Diagnostico';
      case 'repairing': return 'En Reparacion';
      case 'ready': return 'Listo';
      case 'returned': return 'Devuelto';
      case 'delivered': return 'Entregado';
      default: return status;
    }
  }

  Widget _timeline() {
    final stages = [
      ('received', 'Recibido', Icons.inbox_rounded),
      ('diagnosing', 'Diagnostico', Icons.search_rounded),
      ('repairing', 'Reparacion', Icons.build_rounded),
      ('ready', 'Listo', Icons.check_circle_rounded),
      ('delivered', 'Entregado', Icons.local_shipping_rounded),
    ];

    final currentIndex =
        stages.indexWhere((s) => s.$1 == _order.status);

    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: stages.length,
        itemBuilder: (context, i) {
          final (_, label, icon) = stages[i];
          final isActive = i <= currentIndex;
          final isCurrent = i == currentIndex;
          final color = isActive
              ? AppTheme.accentCyan
              : AppTheme.textSecondary.withValues(alpha: 0.3);

          return Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? color.withValues(alpha: 0.15)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Icon(icon, color: color, size: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (i < stages.length - 1)
                Container(
                  width: 20,
                  height: 1,
                  color: i < currentIndex
                      ? AppTheme.accentCyan
                      : AppTheme.textSecondary.withValues(alpha: 0.2),
                  margin: const EdgeInsets.only(bottom: 16),
                ),
            ],
          );
        },
      ),
    );
  }

  // Column 1: Client + Dates + Photos
  Widget _colInfo() {
    return Column(
      children: [
        _sectionCard('Cliente', Icons.person_rounded, AppTheme.accentBlue, [
          _infoRow('Nombre', _order.customer?.fullName ?? '-'),
          _infoRow('Cedula', _order.customer?.idNumber ?? '-'),
          _copyableRow('Telefono', _order.customer?.phone ?? '-'),
          if (_order.customer?.email != null)
            _infoRow('Email', _order.customer!.email!),
        ]),
        _sectionCard('Fechas', Icons.schedule_rounded, AppTheme.textSecondary, [
          _infoRow('Creada', AppDateUtils.format(_order.createdAt)),
          if (_order.deliveredAt != null)
            _infoRow('Entregada', AppDateUtils.format(_order.deliveredAt!)),
        ]),

        // Photos
        if (_photos.isNotEmpty)
          _sectionCard('Fotos del equipo', Icons.photo_library_rounded,
              AppTheme.accentOrange, [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _photos.map((p) {
                final url = p['photoUrl'] as String? ?? '';

                // Cloudinary URL or any http URL
                if (url.startsWith('http')) {
                  return GestureDetector(
                    onTap: () => _showFullPhotoUrl(url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(url,
                          width: 80, height: 80, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _brokenImage()),
                    ),
                  );
                }

                // Base64 fallback
                if (url.contains('base64,')) {
                  try {
                    final bytes = base64Decode(url.split('base64,').last);
                    return GestureDetector(
                      onTap: () => _showFullPhoto(bytes),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(bytes,
                            width: 80, height: 80, fit: BoxFit.cover),
                      ),
                    );
                  } catch (_) {}
                }
                return Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.broken_image_rounded,
                      color: AppTheme.textSecondary),
                );
              }).toList(),
            ),
          ]),

      ],
    );
  }

  Widget _editableRow(String label, String value, bool canEdit, VoidCallback onEdit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: canEdit ? onEdit : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
          Expanded(child: Text(value, style: TextStyle(color: AppTheme.textPrimary, fontSize: 12))),
          if (canEdit)
            Icon(Icons.edit_rounded, color: AppTheme.accentCyan.withValues(alpha: 0.5), size: 13),
        ]),
      ),
    );
  }

  Widget _addLink(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(children: [
          Icon(Icons.add_circle_outline_rounded, color: AppTheme.accentCyan, size: 13),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: AppTheme.accentCyan, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _warrantyProgress(int warrantyDays, DateTime deliveredAt) {
    final now = DateTime.now();
    final endDate = deliveredAt.add(Duration(days: warrantyDays));
    final totalDays = warrantyDays;
    final elapsed = now.difference(deliveredAt).inDays;
    final remaining = totalDays - elapsed;
    final progress = (elapsed / totalDays).clamp(0.0, 1.0);
    final expired = remaining <= 0;
    final color = expired ? AppTheme.accentRed : remaining <= 7 ? AppTheme.accentOrange : AppTheme.accentGreen;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(expired ? Icons.gpp_bad_rounded : Icons.verified_user_rounded, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            expired
                ? 'Garantia vencida'
                : 'Garantia: $remaining dia(s) restante(s)',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Vence: ${AppDateUtils.formatDate(endDate)}',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 9),
        ),
      ]),
    );
  }

  // Mini timeline for individual equipment
  Widget _equipmentTimeline(String status) {
    final stages = [
      ('received', '📥'),
      ('diagnosing', '🔍'),
      ('repairing', '🔧'),
      ('ready', '✅'),
      ('delivered', '🚀'),
    ];
    final currentIdx = stages.indexWhere((s) => s.$1 == status);

    return Row(
      children: stages.asMap().entries.expand((e) {
        final i = e.key;
        final (_, icon) = e.value;
        final isActive = i <= currentIdx;
        final isCurrent = i == currentIdx;
        return [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppTheme.accentCyan.withValues(alpha: 0.15) : Colors.transparent,
              border: Border.all(
                color: isActive ? AppTheme.accentCyan : AppTheme.textSecondary.withValues(alpha: 0.2),
                width: isCurrent ? 2 : 1,
              ),
            ),
            child: Center(child: Text(icon, style: TextStyle(fontSize: 12,
                color: isActive ? null : AppTheme.textSecondary.withValues(alpha: 0.3)))),
          ),
          if (i < stages.length - 1)
            Expanded(
              child: Container(
                height: 2,
                color: i < currentIdx
                    ? AppTheme.accentCyan.withValues(alpha: 0.5)
                    : AppTheme.textSecondary.withValues(alpha: 0.1),
              ),
            ),
        ];
      }).toList(),
    );
  }

  // Equipment grid (full width, uniform cards)
  Widget _equipmentsGrid() {
    return Column(
      children: _displayEquipments.asMap().entries.map((entry) {
            final i = entry.key;
            final eq = entry.value;
            final eqColor = statusColor(eq.status);
            final nextEqStatus = _nextEquipmentStatus(eq.status);
            // Don't show "delivered" button per-equipment - that's handled by the global delivery button
            final showNextButton = nextEqStatus != null && nextEqStatus != 'delivered';

            return _sectionCard(
                'Equipo ${i + 1}',
                Icons.devices_rounded,
                eqColor,
                [
                  // Status badge
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: eqColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: eqColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(eq.statusLabel,
                          style: TextStyle(color: eqColor, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Mini timeline per equipment
                  _equipmentTimeline(eq.status),
                  const SizedBox(height: 10),
                  // Equipment details
                  _infoRow('Tipo', eq.deviceType),
                  _infoRow('Marca', eq.deviceBrand),
                  _infoRow('Modelo', eq.deviceModel),
                  if (eq.deviceSerial != null) _infoRow('Serial', eq.deviceSerial!),
                  if (eq.deviceColor != null) _infoRow('Color', eq.deviceColor!),
                  if (eq.accessories != null && eq.accessories!.isNotEmpty)
                    _infoRow('Accesorios', eq.accessories!.join(', ')),
                  if (eq.technicianId != null && _getTechName(eq.technicianId).isNotEmpty)
                    _infoRow('Tecnico', _getTechName(eq.technicianId)),
                  _infoRow('Problema', eq.problemReported),
                  // Diagnosis with individual edit
                  if (eq.diagnosis != null && eq.diagnosis!.isNotEmpty)
                    _editableRow('Diagnostico', eq.diagnosis!, eq.status != 'delivered', () => _editField(eq, 'diagnosis'))
                  else if (eq.status != 'received' && eq.status != 'delivered')
                    _addLink('Agregar diagnostico', () => _editField(eq, 'diagnosis')),
                  // Repair with individual edit
                  if (eq.notes != null && eq.notes!.isNotEmpty && !eq.notes!.startsWith('Entregado por'))
                    _editableRow('Reparacion', eq.notes!, eq.status != 'delivered', () => _editField(eq, 'repair'))
                  else if (eq.status != 'received' && eq.status != 'diagnosing' && eq.status != 'delivered')
                    _addLink('Agregar reparacion', () => _editField(eq, 'repair')),
                  if (eq.laborCost > 0) _infoRow('Valor', '\$${formatMoney(eq.laborCost)}'),
                  // Warranty with progress bar
                  if (eq.status == 'delivered' && eq.warrantyDays > 0 && eq.deliveredAt != null)
                    _warrantyProgress(eq.warrantyDays, eq.deliveredAt!)
                  else if (eq.status == 'delivered' && eq.warrantyDays == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Garantia instantanea',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
                    ),
                  // Technician assignment for this equipment
                  if (eq.status == 'received' && eq.technicianId == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: InkWell(
                        onTap: () => _assignTechnicianToEquipment(eq.id),
                        child: Row(children: [
                          Icon(Icons.warning_rounded, color: AppTheme.accentOrange, size: 14),
                          const SizedBox(width: 4),
                          Text('Sin tecnico - toque para asignar',
                              style: TextStyle(color: AppTheme.accentOrange, fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  // Action buttons
                  if (eq.status != 'delivered' && eq.status != 'returned' && eq.status != 'ready') ...[
                    if (showNextButton) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: ElevatedButton.icon(
                              onPressed: () => _changeEquipmentStatus(eq.id, nextEqStatus),
                              icon: Icon(Icons.arrow_forward_rounded, size: 16),
                              label: Text(_nextStatusLabel(nextEqStatus),
                                  style: TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: eqColor,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 34,
                          child: OutlinedButton.icon(
                            onPressed: () => _returnEquipment(eq),
                            icon: Icon(Icons.undo_rounded, size: 14),
                            label: Text('Devolver', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.accentRed,
                              side: BorderSide(color: AppTheme.accentRed.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          ),
                        ),
                      ]),
                    ] else ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: OutlinedButton.icon(
                          onPressed: () => _returnEquipment(eq),
                          icon: Icon(Icons.undo_rounded, size: 14),
                          label: Text('Devolver equipo', style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accentRed,
                            side: BorderSide(color: AppTheme.accentRed.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ],
                  ],
                  // Ready state: individual delivery button
                  if (eq.status == 'ready' && _tenant != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push<bool>(context, MaterialPageRoute(
                                builder: (_) => DeliveryScreen(order: _order, tenant: _tenant!),
                              )).then((delivered) {
                                _refreshOrder();
                                _loadHistory();
                                if (delivered == true && mounted) {
                                  context.read<OrdersBloc>().add(OrdersLoadRequested());
                                }
                              });
                            },
                            icon: Icon(Icons.draw_rounded, size: 16),
                            label: Text('Firmar y Entregar', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentGreen,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 34,
                        child: OutlinedButton.icon(
                          onPressed: () => _returnEquipment(eq),
                          icon: Icon(Icons.undo_rounded, size: 14),
                          label: Text('Devolver', style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accentRed,
                            side: BorderSide(color: AppTheme.accentRed.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      ),
                    ]),
                  ],
                  // Delivered state
                  if (eq.status == 'delivered')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(Icons.local_shipping_rounded, color: AppTheme.accentCyan, size: 16),
                        const SizedBox(width: 6),
                        Text('Entregado',
                            style: TextStyle(color: AppTheme.accentCyan, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  // Returned state
                  if (eq.status == 'returned')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(Icons.undo_rounded, color: AppTheme.accentRed, size: 16),
                        const SizedBox(width: 6),
                        Text('Equipo devuelto',
                            style: TextStyle(color: AppTheme.accentRed, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ],
              );
          }).toList(),
    );
  }

  // Column 2: Problem + Diagnosis + Costs
  String _extractPaymentMethod(String? notes) {
    if (notes == null) return '';
    if (notes.contains('Efectivo')) return 'Efectivo';
    if (notes.contains('Transferencia')) return 'Transferencia';
    if (notes.contains('Tarjeta de Credito')) return 'T. Credito';
    if (notes.contains('Tarjeta de Debito')) return 'T. Debito';
    return '';
  }

  /// Get payment method for a specific equipment from history
  String _getEquipmentPaymentMethod(OrderEquipment eq) {
    final eqLabel = '${eq.deviceType} ${eq.deviceBrand} ${eq.deviceModel}';
    // Search history for delivery note matching this equipment
    for (final h in _history.reversed) {
      final notes = h['notes'] as String? ?? '';
      final toStatus = h['toStatus'] as String? ?? '';
      if (toStatus != 'delivered') continue;
      if (!notes.contains('Entregado por')) continue;
      // Multi-device: notes have [EquipmentLabel] prefix
      if (notes.contains(eqLabel) || _isSingleDevice) {
        return _extractPaymentMethod(notes);
      }
    }
    return '';
  }

  Widget _colService() {
    final deliveredEqs = _displayEquipments.where((eq) => eq.status == 'delivered' && eq.laborCost > 0).toList();

    return Column(
      children: [
        if (_order.total > 0)
          _sectionCard('Costos', Icons.receipt_long_rounded, AppTheme.accentGreen, [
            // Per-equipment: value + payment method
            ...deliveredEqs.map((eq) {
              final method = _getEquipmentPaymentMethod(eq);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${eq.deviceBrand} ${eq.deviceModel}',
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
                    Text('\$${formatMoney(eq.laborCost)}',
                        style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  if (method.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(children: [
                        Icon(Icons.payment_rounded, color: AppTheme.textSecondary, size: 12),
                        const SizedBox(width: 4),
                        Text(method, style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                      ]),
                    ),
                ]),
              );
            }),
            if (deliveredEqs.isNotEmpty)
              Divider(color: AppTheme.dividerColor),
            // Items detail
            ..._order.items.map((item) => Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Expanded(child: Text('${item.qty}x ${item.description}',
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 12))),
                    Text('\$${formatMoney(item.total)}',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ]),
                )),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.accentGreen, fontSize: 16)),
                Text('\$${formatMoney(_order.total)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.accentGreen, fontSize: 16)),
              ],
            ),
          ]),
      ],
    );
  }

  // Column 3: History timeline
  Widget _historyCard() {
    if (_history.isEmpty) return const SizedBox.shrink();
    return _sectionCard('Historial', Icons.history_rounded, AppTheme.accentCyan, [
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 350),
        child: SingleChildScrollView(
          child: Column(
            children: _history.map((h) {
              final toLabel = _statusLabelFor(h['toStatus'] ?? '');
              final notes = h['notes'] as String?;
              final userName = h['userName'] as String?;
              final createdAt = h['createdAt'] != null ? DateTime.tryParse(h['createdAt']) : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: AppTheme.accentCyan, shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3), width: 2),
                      ),
                    ),
                    Container(width: 2, height: 30, color: AppTheme.accentCyan.withValues(alpha: 0.15)),
                  ]),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(toLabel, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
                    if (notes != null && notes.isNotEmpty)
                      Text(notes, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (createdAt != null)
                      Text('${AppDateUtils.format(createdAt)}${userName != null ? ' · $userName' : ''}',
                          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 10)),
                  ])),
                ]),
              );
            }).toList(),
          ),
        ),
      ),
    ]);
  }

  Widget _colHistory() {
    if (_history.isEmpty) return const SizedBox.shrink();

    return _sectionCard(
        'Historial', Icons.history_rounded, AppTheme.accentCyan, [
      ..._history.map((h) {
        final toLabel = _statusLabelFor(h['toStatus'] ?? '');
        final notes = h['notes'] as String?;
        final userName = h['userName'] as String?;
        final createdAt = h['createdAt'] != null
            ? DateTime.tryParse(h['createdAt'])
            : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppTheme.accentCyan.withValues(alpha: 0.3),
                          width: 2),
                    ),
                  ),
                  if (_history.last != h)
                    Container(
                      width: 2,
                      height: 30,
                      color: AppTheme.dividerColor,
                    ),
                ],
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(toLabel,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    if (userName != null)
                      Text(userName,
                          style: TextStyle(
                              color: AppTheme.accentCyan, fontSize: 11)),
                    if (notes != null && notes.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(notes,
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontStyle: FontStyle.italic)),
                      ),
                    if (createdAt != null)
                      Text(AppDateUtils.format(createdAt),
                          style: TextStyle(
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.5),
                              fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    ]);
  }

  Widget _sectionCard(
      String title, IconData icon, Color color, List<Widget> children) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontSize: 14)),
            ],
          ),
          SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _copyableRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$label copiado: $value'),
            backgroundColor: AppTheme.accentGreen,
            duration: const Duration(seconds: 2),
          ));
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            SizedBox(width: 12),
            Flexible(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(value, style: TextStyle(color: AppTheme.textPrimary, fontSize: 12), textAlign: TextAlign.end),
                const SizedBox(width: 4),
                Icon(Icons.copy_rounded, size: 12, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          SizedBox(width: 12),
          Flexible(
            child: Text(value,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontSize: 12),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

}

/// Pantalla de previsualización del acta de entrega con opciones de imprimir/compartir.
class _ActaPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String orderNumber;

  const _ActaPreviewScreen({
    required this.pdfBytes,
    required this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;

    return Scaffold(
      appBar: AppBar(
        title: Text('Acta $orderNumber'),
        actions: [
          if (!isDesktop)
            IconButton(
              icon: Icon(Icons.share_rounded),
              tooltip: 'Compartir',
              onPressed: () {
                printing_lib.Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: 'Acta_$orderNumber.pdf',
                );
              },
            ),
        ],
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        printing_lib.Printing.sharePdf(
                          bytes: pdfBytes,
                          filename: 'Acta_$orderNumber.pdf',
                        );
                      },
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: Text(isDesktop ? 'Imprimir' : 'Imprimir / Compartir'),
                    ),
                  ),
                ],
              ),
            ),
            // PDF Preview with zoom
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: printing_lib.PdfPreview(
                  build: (_) async => pdfBytes,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  allowPrinting: false,
                allowSharing: false,
                pdfFileName: 'Acta_$orderNumber.pdf',
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla de previsualización del ticket con opción de imprimir.
class _TicketPreviewScreen extends StatelessWidget {
  final ServiceOrder order;
  final Tenant tenant;
  final TicketPrinterService printerService;

  _TicketPreviewScreen({
    required this.order,
    required this.tenant,
    required this.printerService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ticket ${order.orderNumber}'),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Print button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final ok = await printerService.printReceptionTicket(
                      order: order,
                      tenant: tenant,
                    );
                    if (context.mounted) {
                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ticket impreso'),
                            backgroundColor: AppTheme.accentGreen,
                          ),
                        );
                      } else {
                        // Fallback: open system print dialog
                        final pdfBytes = await printerService
                            .generateTicketPdf(order, tenant);
                        await printing_lib.Printing.sharePdf(
                          bytes: pdfBytes,
                          filename: 'Ticket_${order.orderNumber}.pdf',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Imprimir ticket'),
                ),
              ),
              const SizedBox(height: 20),

              // Preview
              Center(
                child: TicketPreviewWidget(
                  order: order,
                  tenant: tenant,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
