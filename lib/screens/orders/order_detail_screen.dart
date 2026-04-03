import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
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
  }

  final TicketPrinterService _printerService = TicketPrinterService();
  final PdfGeneratorService _pdfGenerator = PdfGeneratorService();
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _photos = [];

  void _onMenuAction(String action) {
    switch (action) {
      case 'print_ticket':
        _reprintTicket();
        break;
      case 'print_acta':
        _reprintActa();
        break;
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

  Future<void> _reprintActa() async {
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

      // Build full diagnosis with repair notes from history
      String fullDiagnosis = _order.diagnosis ?? '';
      try {
        final histRes = await _api.dio.get('/orders/${_order.id}/history');
        final hist = histRes.data as List;
        final excludes = ['control de calidad', 'enviado a control', 'listo para entrega', 'orden cerrada', 'orden creada', 'entregado por'];
        final repairNotes = hist
            .where((h) {
              final status = h['toStatus'] as String? ?? '';
              final notes = (h['notes'] as String? ?? '').toLowerCase();
              if (status != 'repairing' && status != 'diagnosing') return false;
              if (notes.isEmpty) return false;
              for (final p in excludes) { if (notes.contains(p)) return false; }
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

      // Create order copy with full diagnosis
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
        diagnosis: fullDiagnosis.isNotEmpty ? fullDiagnosis : null,
        notes: _order.notes,
        laborCost: _order.laborCost,
        subtotal: _order.subtotal,
        tax: _order.tax,
        total: _order.total,
        warrantyDays: _order.warrantyDays,
        createdAt: _order.createdAt,
        deliveredAt: _order.deliveredAt,
        items: _order.items,
      );

      final pdfBytes = await _pdfGenerator.generateDeliveryAct(
        order: orderForPdf,
        tenant: _tenant!,
        clientSignaturePng: clientSig,
        clientName: clientName,
        technicianSignaturePng: techSig,
        technicianName: techName,
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

  void _showFullPhotoUrl(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Image.network(url),
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
        return 'quality_check';
      case 'quality_check':
        return 'ready';
      case 'ready':
        return 'delivered';
      case 'delivered':
        return 'closed';
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
      case 'quality_check':
        return 'Enviar a Control Calidad';
      case 'ready':
        return 'Marcar como Listo';
      case 'delivered':
        return 'Registrar Entrega';
      case 'closed':
        return 'Cerrar Orden';
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
      case 'quality_check':
        return Icons.verified_rounded;
      case 'ready':
        return Icons.check_circle_rounded;
      case 'delivered':
        return Icons.local_shipping_rounded;
      case 'closed':
        return Icons.lock_rounded;
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
              if (_order.status != 'closed') {
                items.add(const PopupMenuItem(
                  value: 'print_ticket',
                  child: Row(children: [
                    Icon(Icons.receipt_long_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Reimprimir ticket'),
                  ]),
                ));
              }
              // Reimprimir acta (solo si está entregada o cerrada)
              if (_order.status == 'delivered' || _order.status == 'closed') {
                items.add(const PopupMenuItem(
                  value: 'print_acta',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Reimprimir acta de entrega'),
                  ]),
                ));
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
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isWide ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status + action bar
              _statusHeader(color, isWide),
              const SizedBox(height: 16),

              // Timeline
              _timeline(),
              const SizedBox(height: 16),

              // Content - responsive grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;

                  if (w > 900) {
                    // Desktop: 3 columns
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _colInfo()),
                        const SizedBox(width: 12),
                        Expanded(child: _colService()),
                        const SizedBox(width: 12),
                        Expanded(child: _colHistory()),
                      ],
                    );
                  }

                  if (w > 600) {
                    // Tablet: 2 columns
                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _colInfo()),
                            const SizedBox(width: 12),
                            Expanded(child: _colService()),
                          ],
                        ),
                        _colHistory(),
                      ],
                    );
                  }

                  // Mobile: 1 column
                  return Column(
                    children: [
                      _colInfo(),
                      _colService(),
                      _colHistory(),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
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

          // Assign technician warning
          if (_order.technicianId == null &&
              _order.status != 'delivered' &&
              _order.status != 'closed') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showAssignTechnicianDialog,
                icon: const Icon(Icons.engineering_rounded, size: 18),
                label: const Text('Asignar tecnico'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentOrange,
                  side: const BorderSide(color: AppTheme.accentOrange),
                ),
              ),
            ),
          ],

          // Action button
          if (_nextStatus != null && _order.status != 'closed') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _order.status == 'ready'
                  ? ElevatedButton.icon(
                      onPressed: _loading || _tenant == null
                          ? null
                          : () async {
                              final delivered = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DeliveryScreen(
                                    order: _order,
                                    tenant: _tenant!,
                                  ),
                                ),
                              );
                              await _refreshOrder();
                              if (delivered == true && mounted) {
                                context.read<OrdersBloc>().add(OrdersLoadRequested());
                              }
                            },
                      icon: const Icon(Icons.draw_rounded),
                      label: const Text('Firmar y Entregar'),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () {
                              // Require technician for diagnosis/repair
                              final next = _nextStatus;
                              if (next == 'diagnosing' &&
                                  _order.technicianId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Asigne un tecnico antes de continuar'),
                                    backgroundColor: AppTheme.accentOrange,
                                  ),
                                );
                                return;
                              }
                              _showChangeStatusDialog();
                            },
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_nextStatusIcon(_nextStatus!)),
                      label: Text(_nextStatusLabel(_nextStatus!)),
                    ),
            ),
          ],
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
      case 'quality_check':
        labelText = 'Observaciones (opcional)';
        hintText = 'Ej: Se verifico funcionamiento correcto...';
        defaultNote = 'Reparacion completada, enviado a control de calidad';
        break;
      case 'ready':
        labelText = 'Observaciones (opcional)';
        hintText = '';
        final equipo = '${_order.device?.brand ?? ''} ${_order.device?.model ?? ''}'.trim();
        defaultNote = 'El equipo $equipo esta listo para entrega';
        break;
      case 'closed':
        labelText = 'Observaciones (opcional)';
        hintText = '';
        defaultNote = 'Orden cerrada';
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
      case 'quality_check': return 'Control de Calidad';
      case 'ready': return 'Listo para Entrega';
      case 'delivered': return 'Entregado';
      case 'closed': return 'Cerrado';
      default: return status;
    }
  }

  Widget _timeline() {
    final stages = [
      ('received', 'Recibido', Icons.inbox_rounded),
      ('diagnosing', 'Diagnostico', Icons.search_rounded),
      ('repairing', 'Reparacion', Icons.build_rounded),
      ('quality_check', 'Calidad', Icons.verified_rounded),
      ('ready', 'Listo', Icons.check_circle_rounded),
      ('delivered', 'Entregado', Icons.local_shipping_rounded),
      ('closed', 'Cerrado', Icons.lock_rounded),
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

  // Column 1: Client + Device
  Widget _colInfo() {
    return Column(
      children: [
        _sectionCard('Cliente', Icons.person_rounded, AppTheme.accentBlue, [
          _infoRow('Nombre', _order.customer?.fullName ?? '-'),
          _infoRow('Cedula', _order.customer?.idNumber ?? '-'),
          _infoRow('Telefono', _order.customer?.phone ?? '-'),
          if (_order.customer?.email != null)
            _infoRow('Email', _order.customer!.email!),
        ]),
        _sectionCard('Equipo', Icons.devices_rounded, AppTheme.accentPurple, [
          _infoRow('Tipo', _order.device?.type ?? '-'),
          _infoRow('Marca', _order.device?.brand ?? '-'),
          _infoRow('Modelo', _order.device?.model ?? '-'),
          if (_order.device?.serial != null)
            _infoRow('Serial', _order.device!.serial!),
          if (_order.device?.color != null)
            _infoRow('Color', _order.device!.color!),
          if (_order.device?.accessories != null &&
              _order.device!.accessories!.isNotEmpty)
            _infoRow('Accesorios', _order.device!.accessories!.join(', ')),
        ]),
        _sectionCard('Fechas', Icons.schedule_rounded, AppTheme.textSecondary, [
          _infoRow('Creada', AppDateUtils.format(_order.createdAt)),
          if (_order.deliveredAt != null)
            _infoRow('Entregada', AppDateUtils.format(_order.deliveredAt!)),
          if (_order.closedAt != null)
            _infoRow('Cerrada', AppDateUtils.format(_order.closedAt!)),
          if (_order.warrantyDays > 0)
            _infoRow('Garantia', '${_order.warrantyDays} dias'),
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

  // Column 2: Problem + Diagnosis + Costs
  Widget _colService() {
    return Column(
      children: [
        _sectionCard(
            'Problema', Icons.report_rounded, AppTheme.accentOrange, [
          Text(_order.problemReported,
              style:
                  TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
        ]),
        if (_order.diagnosis != null)
          _sectionCard('Diagnostico', Icons.medical_services_rounded,
              AppTheme.accentCyan, [
            Text(_order.diagnosis!,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13)),
          ]),
        if (_order.items.isNotEmpty || _order.total > 0)
          _sectionCard(
              'Costos', Icons.receipt_long_rounded, AppTheme.accentGreen, [
            ..._order.items.map((item) => Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text('${item.qty}x ${item.description}',
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 12))),
                      Text('\$${formatMoney(item.total)}',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                )),
            if (_order.laborCost > 0)
              _infoRow('Mano de obra',
                  '\$${formatMoney(_order.laborCost)}'),
            Divider(color: AppTheme.dividerColor),
            _infoRow('Subtotal', '\$${formatMoney(_order.subtotal)}'),
            _infoRow('IVA 19%', '\$${formatMoney(_order.tax)}'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentGreen,
                        fontSize: 16)),
                Text('\$${formatMoney(_order.total)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentGreen,
                        fontSize: 16)),
              ],
            ),
          ]),
      ],
    );
  }

  // Column 3: History timeline
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
            // PDF Preview
            Expanded(
              child: printing_lib.PdfPreview(
                build: (_) async => pdfBytes,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                allowPrinting: false, // We handle printing ourselves
                allowSharing: false,
                pdfFileName: 'Acta_$orderNumber.pdf',
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
