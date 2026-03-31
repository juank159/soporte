import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/orders/orders_bloc.dart';
import '../../config/theme.dart';
import '../../config/format_utils.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/date_range_picker.dart';
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
    ('delivered', 'Entregados', Icons.local_shipping_rounded),
    ('closed', 'Cerrados', Icons.lock_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStr = _fmt(now);
    final weekAgo = _fmt(now.subtract(const Duration(days: 7)));
    final monthStart = _fmt(DateTime(now.year, now.month, 1));

    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Buscar orden, cliente, equipo...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _loadOrders();
                      },
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (v) {
              setState(() {});
              _onSearchChanged(v);
            },
          ),
        ),

        // Date filters
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              _dateChip('Todas', null, null),
              _dateChip('Hoy', todayStr, todayStr),
              _dateChip('Esta semana', weekAgo, todayStr),
              _dateChip('Este mes', monthStart, todayStr),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.date_range_rounded,
                      size: 14, color: AppTheme.accentPurple),
                  label: Text(
                    _dateFrom != null &&
                            !['Todas', 'Hoy', 'Esta semana', 'Este mes']
                                .contains(_dateLabel)
                        ? _dateLabel
                        : 'Rango',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _showDatePicker,
                ),
              ),
            ],
          ),
        ),

        // Status filters
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _statusOptions.length,
            itemBuilder: (context, i) {
              final (value, label, icon) = _statusOptions[i];
              final selected = _statusFilter == value;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  avatar: Icon(icon,
                      size: 14,
                      color: selected
                          ? AppTheme.accentCyan
                          : AppTheme.textSecondary),
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  onSelected: (_) => _onFilterChanged(value),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ),

        // List
        Expanded(
          child: BlocBuilder<OrdersBloc, OrdersState>(
            builder: (context, state) {
              if (state is OrdersLoading) {
                return const Center(
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
                        const SizedBox(height: 12),
                        Text(
                          _searchCtrl.text.isNotEmpty
                              ? 'Sin resultados'
                              : _dateFrom != null
                                  ? 'Sin ordenes en este periodo'
                                  : 'Sin ordenes',
                          style:
                              const TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
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
                          ).then((_) => _loadOrders());
                        },
                        child: GlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 48,
                                decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(2)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(order.orderNumber,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textPrimary,
                                            fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text(
                                        '${order.device?.brand ?? ''} ${order.device?.model ?? ''}',
                                        style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 13),
                                        overflow: TextOverflow.ellipsis),
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
                                            (order.status == 'delivered' ||
                                                order.status == 'closed'))
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
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  Widget _dateChip(String label, String? from, String? to) {
    final selected = _dateLabel == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        avatar: Icon(
          label == 'Todas'
              ? Icons.all_inclusive_rounded
              : label == 'Hoy'
                  ? Icons.today_rounded
                  : Icons.calendar_today_rounded,
          size: 14,
          color: selected ? AppTheme.accentCyan : AppTheme.textSecondary,
        ),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => _setDateFilter(label, from, to),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
