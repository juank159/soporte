import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/format_utils.dart';
import '../../config/date_utils.dart';
import '../../services/api_service.dart';
import '../../widgets/glass_card.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _dashboard;
  List<dynamic>? _technicians;
  Map<String, dynamic>? _repairTime;
  Map<String, dynamic>? _staleOrders;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _api.dio.get('/reports/dashboard'),
        _api.dio.get('/reports/technicians'),
        _api.dio.get('/reports/repair-time'),
        _api.dio.get('/reports/stale-orders'),
      ]);
      setState(() {
        _dashboard = r[0].data;
        _technicians = r[1].data;
        _repairTime = r[2].data;
        _staleOrders = r[3].data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 700;

      return RefreshIndicator(
        color: AppTheme.accentCyan,
        onRefresh: _load,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isWide ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reportes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 16),

              // Top row
              if (isWide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _revenueCard()),
                  const SizedBox(width: 12),
                  Expanded(child: _repairTimeCard()),
                ])
              else ...[
                _revenueCard(),
                _repairTimeCard(),
              ],

              // Stale orders alert
              if (_staleOrders != null && (_staleOrders!['total'] as int? ?? 0) > 0)
                _staleOrdersCard(),

              // Status summary
              if (_dashboard != null) _statusSummaryCard(),

              // Technicians
              if (_technicians != null && _technicians!.isNotEmpty)
                _technicianCard(),
            ],
          ),
        ),
      );
    });
  }

  Widget _revenueCard() {
    if (_dashboard == null) return const SizedBox.shrink();
    final revenue = (_dashboard!['totalRevenue'] ?? 0).toDouble();
    final total = _dashboard!['totalOrders'] ?? 0;
    final completed = _dashboard!['completedCount'] ?? _dashboard!['deliveredCount'] ?? 0;

    return GlassCard(
      borderColor: AppTheme.accentGreen.withValues(alpha: 0.3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.accentGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.trending_up_rounded, color: AppTheme.accentGreen, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ingresos totales', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            Text('\$${formatMoney(revenue)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.accentGreen)),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _miniStat('Ordenes', '$total', AppTheme.accentBlue),
          const SizedBox(width: 12),
          _miniStat('Completadas', '$completed', AppTheme.accentGreen),
          const SizedBox(width: 12),
          _miniStat('Pendientes', '${total - completed}', AppTheme.accentOrange),
        ]),
      ]),
    );
  }

  Widget _repairTimeCard() {
    if (_repairTime == null) return const SizedBox.shrink();
    return GlassCard(
      borderColor: AppTheme.accentBlue.withValues(alpha: 0.3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.accentBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.timer_rounded, color: AppTheme.accentBlue, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Tiempos de reparacion', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _miniStat('Promedio', '${_repairTime!['averageHours'] ?? 0}h', AppTheme.accentBlue),
          const SizedBox(width: 12),
          _miniStat('Rapido', '${_repairTime!['fastestHours'] ?? 0}h', AppTheme.accentGreen),
          const SizedBox(width: 12),
          _miniStat('Lento', '${_repairTime!['slowestHours'] ?? 0}h', AppTheme.accentOrange),
        ]),
        const SizedBox(height: 6),
        Text('${_repairTime!['count'] ?? 0} ordenes completadas',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ]),
    );
  }

  Widget _staleOrdersCard() {
    final data = _staleOrders!;
    final critical = data['critical'] as int? ?? 0;
    final warning = data['warning'] as int? ?? 0;
    final orders = (data['orders'] as List?) ?? [];
    final color = critical > 0 ? AppTheme.accentRed : AppTheme.accentOrange;

    return GlassCard(
      borderColor: color.withValues(alpha: 0.4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.warning_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ordenes pendientes', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            Text('$critical criticas (+30 dias) | $warning atencion (+15 dias)',
                style: TextStyle(color: color, fontSize: 11)),
          ])),
        ]),
        const SizedBox(height: 12),
        ...orders.take(10).map((o) {
          final days = o['daysInSystem'] as int? ?? 0;
          final priority = o['priority'] as String? ?? 'normal';
          final pColor = priority == 'critical' ? AppTheme.accentRed : priority == 'warning' ? AppTheme.accentOrange : AppTheme.textSecondary;
          final statusLabels = {
            'received': 'Recibido', 'diagnosing': 'Diagnostico',
            'repairing': 'Reparacion', 'quality_check': 'Calidad', 'ready': 'Listo',
          };

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 4, height: 36,
                decoration: BoxDecoration(color: pColor, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o['orderNumber']} - ${o['device'] ?? ''}',
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                Text('${o['customerName'] ?? 'Express'} | ${statusLabels[o['status']] ?? o['status']}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: pColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Text('$days dias', style: TextStyle(color: pColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _statusSummaryCard() {
    final counts = (_dashboard!['statusCounts'] as Map<String, dynamic>?) ?? {};
    final statuses = [
      ('received', 'Recibidos', AppTheme.accentBlue, Icons.inbox_rounded),
      ('diagnosing', 'Diagnostico', AppTheme.accentOrange, Icons.search_rounded),
      ('repairing', 'Reparacion', AppTheme.accentPurple, Icons.build_rounded),
      ('quality_check', 'Calidad', const Color(0xFFEAB308), Icons.verified_rounded),
      ('ready', 'Listos', AppTheme.accentGreen, Icons.check_circle_rounded),
      ('delivered', 'Entregados', AppTheme.accentCyan, Icons.local_shipping_rounded),
      ('closed', 'Cerrados', AppTheme.textSecondary, Icons.lock_rounded),
    ];

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.pie_chart_rounded, color: AppTheme.accentCyan, size: 20),
          SizedBox(width: 8),
          Text('Resumen por estado', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 15)),
        ]),
        const SizedBox(height: 12),
        ...statuses.map((s) {
          final count = counts[s.$1] ?? 0;
          if (count == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(s.$4, color: s.$3, size: 16),
              const SizedBox(width: 8),
              Text(s.$2, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: s.$3.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: TextStyle(color: s.$3, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _technicianCard() {
    return GlassCard(
      borderColor: AppTheme.accentPurple.withValues(alpha: 0.3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.engineering_rounded, color: AppTheme.accentPurple, size: 20),
          SizedBox(width: 8),
          Text('Rendimiento por tecnico', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 15)),
        ]),
        const SizedBox(height: 12),
        ...(_technicians!.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.accentPurple.withValues(alpha: 0.15),
                  child: Text((t['name'] as String? ?? 'T')[0].toUpperCase(),
                      style: const TextStyle(color: AppTheme.accentPurple, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 13)),
                  Text('${t['completedOrders']} completadas | ${t['activeOrders']} activas',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ])),
                Text('\$${formatMoney(t['totalRevenue'] ?? 0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.accentGreen, fontSize: 13)),
              ]),
            ))),
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
      ]),
    );
  }
}
