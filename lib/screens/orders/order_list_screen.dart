import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/orders/orders_bloc.dart';
import '../../models/service_order.dart';
import '../../config/theme.dart';
import '../../config/format_utils.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/date_range_picker.dart';
import '../../services/orders_pdf_service.dart';
import '../../services/actas_batch_service.dart';
import '../../services/api_service.dart';
import '../../models/tenant.dart';
import 'package:printing/printing.dart' as printing_lib;
import '../dashboard/dashboard_screen.dart';
import 'order_detail_screen.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  String? _statusFilter;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Date filter
  String _dateLabel = 'Todas';
  String? _dateFrom;
  String? _dateTo;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _loadOrders() {
    context.read<OrdersBloc>().add(OrdersLoadRequested(
          statusFilter: _statusFilter,
          search: _searchCtrl.text.trim(),
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        ));
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadOrders);
  }

  void _onFilterChanged(String? status) {
    setState(() => _statusFilter = status);
    _loadOrders();
  }

  void _setDateFilter(String label, String? from, String? to) {
    setState(() {
      _dateLabel = label;
      _dateFrom = from;
      _dateTo = to;
    });
    _loadOrders();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _statusEmoji(String status) {
    switch (status) {
      case 'received': return '📥';
      case 'diagnosing': return '🔍';
      case 'repairing': return '🔧';
      case 'ready': return '✅';
      case 'delivered': return '🚀';
      case 'returned': return '↩️';
      default: return '⏳';
    }
  }

  Future<void> _printOrders(List<ServiceOrder> orders) async {
    if (orders.isEmpty) return;

    try {
      // Load tenant info
      final api = ApiService();
      final res = await api.dio.get('/tenants/me');
      final tenant = Tenant.fromJson(res.data);

      final pdfService = OrdersPdfService();
      final pdfBytes = await pdfService.generateOrdersReport(
        orders: orders,
        tenant: tenant,
        periodLabel: _dateLabel,
      );

      await printing_lib.Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Ordenes_$_dateLabel.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al generar reporte: $e'),
          backgroundColor: AppTheme.accentRed,
        ));
      }
    }
  }

  Future<void> _printActasBatch(List<ServiceOrder> orders) async {
    final delivered = orders
        .where((o) => o.status == 'delivered')
        .toList();

    if (delivered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay ordenes entregadas en este periodo'),
          backgroundColor: AppTheme.accentOrange,
        ));
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Generando ${delivered.length} actas de entrega...'),
        duration: const Duration(seconds: 2),
      ));
    }

    try {
      final api = ApiService();
      final res = await api.dio.get('/tenants/me');
      final tenant = Tenant.fromJson(res.data);

      final service = ActasBatchService();
      final pdfBytes = await service.generateBatchActas(
        deliveredOrders: delivered,
        tenant: tenant,
        periodLabel: _dateLabel,
      );

      await printing_lib.Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Actas_Entrega_$_dateLabel.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.accentRed,
        ));
      }
    }
  }

  Future<void> _showDatePicker() async {
    final result = await showDateRangePickerDialog(
      context,
      initialFrom: _dateFrom,
      initialTo: _dateTo,
    );
    if (result != null) {
      _setDateFilter(result['label'] ?? 'Rango', result['from'], result['to']);
    }
  }

  final _statusOptions = [
    (null, 'Todos', Icons.apps_rounded),
    ('received', 'Recibidos', Icons.inbox_rounded),
    ('diagnosing', 'Diagnostico', Icons.search_rounded),
    ('repairing', 'Reparacion', Icons.build_rounded),
    ('ready', 'Listos', Icons.check_circle_rounded),
    ('returned', 'Devueltos', Icons.undo_rounded),
    ('delivered', 'Entregados', Icons.local_shipping_rounded),
  ];

  void _showFilterDialog() {
    final now = DateTime.now();
    final todayStr = _fmt(now);
    final weekAgo = _fmt(now.subtract(Duration(days: 7)));
    final monthStart = _fmt(DateTime(now.year, now.month, 1));

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text('Filtros',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 16),

              // Date section
              const Text('Periodo',
                  style: TextStyle(color: AppTheme.accentCyan, fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _filterOption('Todas', _dateLabel == 'Todas', () {
                  _setDateFilter('Todas', null, null);
                  Navigator.pop(ctx);
                }),
                _filterOption('Hoy', _dateLabel == 'Hoy', () {
                  _setDateFilter('Hoy', todayStr, todayStr);
                  Navigator.pop(ctx);
                }),
                _filterOption('Semana', _dateLabel == 'Esta semana', () {
                  _setDateFilter('Esta semana', weekAgo, todayStr);
                  Navigator.pop(ctx);
                }),
                _filterOption('Mes', _dateLabel == 'Este mes', () {
                  _setDateFilter('Este mes', monthStart, todayStr);
                  Navigator.pop(ctx);
                }),
                _filterOption('Rango', _dateLabel != 'Todas' &&
                    _dateLabel != 'Hoy' && _dateLabel != 'Esta semana' &&
                    _dateLabel != 'Este mes', () {
                  Navigator.pop(ctx);
                  _showDatePicker();
                }),
              ]),
              const SizedBox(height: 16),

              // Status section
              const Text('Estado',
                  style: TextStyle(color: AppTheme.accentPurple, fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ..._statusOptions.map((s) {
                  final (value, label, icon) = s;
                  return _filterOption(label, _statusFilter == value, () {
                    _onFilterChanged(value);
                    Navigator.pop(ctx);
                  });
                }),
              ]),
              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterOption(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accentCyan.withValues(alpha: 0.15)
              : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.accentCyan
                : AppTheme.dividerColor,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppTheme.accentCyan : AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            )),
      ),
    );
  }

  String get _activeFiltersLabel {
    final parts = <String>[];
    if (_dateLabel != 'Todas') parts.add(_dateLabel);
    if (_statusFilter != null) {
      final match = _statusOptions.where((s) => s.$1 == _statusFilter).firstOrNull;
      if (match != null) parts.add(match.$2);
    }
    return parts.isEmpty ? 'Sin filtros' : parts.join(' | ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search + Filter button
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Buscar orden, cliente, equipo...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 18),
                            onPressed: () { _searchCtrl.clear(); _loadOrders(); },
                          )
                        : null,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (v) { setState(() {}); _onSearchChanged(v); },
                ),
              ),
              SizedBox(width: 8),
              // Filter button
              GestureDetector(
                onTap: _showFilterDialog,
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_statusFilter != null || _dateLabel != 'Todas')
                        ? AppTheme.accentCyan.withValues(alpha: 0.15)
                        : AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_statusFilter != null || _dateLabel != 'Todas')
                          ? AppTheme.accentCyan
                          : AppTheme.dividerColor,
                    ),
                  ),
                  child: Icon(Icons.tune_rounded,
                      color: (_statusFilter != null || _dateLabel != 'Todas')
                          ? AppTheme.accentCyan
                          : AppTheme.textSecondary,
                      size: 22),
                ),
              ),
            ],
          ),
        ),

        // Active filters banner
        if (_statusFilter != null || _dateLabel != 'Todas')
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.filter_list_rounded, size: 16, color: AppTheme.accentCyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Filtro: $_activeFiltersLabel',
                      style: TextStyle(color: AppTheme.accentCyan, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                InkWell(
                  onTap: () {
                    _setDateFilter('Todas', null, null);
                    _onFilterChanged(null);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.close_rounded, size: 14, color: AppTheme.accentRed),
                      const SizedBox(width: 4),
                      Text('Limpiar', style: TextStyle(color: AppTheme.accentRed, fontSize: 11, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        // List
        Expanded(
          child: BlocBuilder<OrdersBloc, OrdersState>(
            builder: (context, state) {
              if (state is OrdersLoading) {
                return Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.accentCyan));
              }
              if (state is OrdersLoaded) {
                if (state.orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48,
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.4)),
                        SizedBox(height: 12),
                        Text(
                          _searchCtrl.text.isNotEmpty
                              ? 'Sin resultados'
                              : _dateFrom != null
                                  ? 'Sin ordenes en este periodo'
                                  : 'Sin ordenes',
                          style:
                              TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    // Results header with print button
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            '${state.orders.length} ordenes',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          const Spacer(),
                          // Print orders report
                          TextButton.icon(
                            onPressed: () => _printOrders(state.orders),
                            icon: const Icon(Icons.list_alt_rounded, size: 16),
                            label: const Text('Reporte', style: TextStyle(fontSize: 11)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Print actas batch
                          TextButton.icon(
                            onPressed: () => _printActasBatch(state.orders),
                            icon: const Icon(Icons.description_rounded, size: 16),
                            label: const Text('Actas', style: TextStyle(fontSize: 11)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                  color: AppTheme.accentCyan,
                  onRefresh: () async => _loadOrders(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.orders.length,
                    itemBuilder: (context, i) {
                      final order = state.orders[i];
                      final color = statusColor(order.status);
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BlocProvider.value(
                                value: context.read<OrdersBloc>(),
                                child: OrderDetailScreen(order: order),
                              ),
                            ),
                          ).then((_) { if (mounted) _loadOrders(); });
                        },
                        child: GlassCard(
                          padding: EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 48,
                                decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(2)),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(order.orderNumber,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textPrimary,
                                            fontSize: 14)),
                                    SizedBox(height: 2),
                                    // Device info
                                    if (order.equipments.isEmpty)
                                      Text(
                                          '${order.device?.brand ?? ''} ${order.device?.model ?? ''}',
                                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                          overflow: TextOverflow.ellipsis)
                                    else
                                      // Multi-equipment: show each with status icon
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 2,
                                        children: order.equipments.map((eq) {
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(_statusEmoji(eq.status), style: TextStyle(fontSize: 10)),
                                              const SizedBox(width: 3),
                                              Text('${eq.deviceBrand} ${eq.deviceModel}',
                                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                              const SizedBox(width: 6),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(order.customer?.fullName ?? '',
                                              style: TextStyle(
                                                  color: AppTheme.textSecondary
                                                      .withValues(alpha: 0.7),
                                                  fontSize: 12),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                        if (order.total > 0 &&
                                            order.status == 'delivered')
                                          Text(
                                            '\$${formatMoney(order.total)}',
                                            style: const TextStyle(
                                                color: AppTheme.accentGreen,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              StatusBadge(
                                  label: order.statusLabel, color: color),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

}
