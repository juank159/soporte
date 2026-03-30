import 'package:flutter/material.dart';
import '../../config/theme.dart';
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
      ]);
      setState(() {
        _dashboard = r[0].data;
        _technicians = r[1].data;
        _repairTime = r[2].data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accentCyan));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;

        return RefreshIndicator(
          color: AppTheme.accentCyan,
          onRefresh: _load,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isWide ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reportes',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 16),

                // Top cards - responsive
                if (isWide)
                  Row(
                    children: [
                      Expanded(child: _revenueCard()),
                      const SizedBox(width: 12),
                      Expanded(child: _repairTimeCard()),
                    ],
                  )
                else ...[
                  _revenueCard(),
                  _repairTimeCard(),
                ],

                const SizedBox(height: 4),
                _technicianCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _revenueCard() {
    if (_dashboard == null) return const SizedBox.shrink();
    final revenue = (_dashboard!['totalRevenue'] ?? 0).toDouble();

    return GlassCard(
      borderColor: AppTheme.accentGreen.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.trending_up_rounded,
                    color: AppTheme.accentGreen, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ingresos',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                    GradientText(
                      '\$${revenue.toStringAsFixed(0)} COP',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800),
                      colors: [AppTheme.accentGreen, AppTheme.accentCyan],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat('Total', '${_dashboard!['totalOrders'] ?? 0}',
                  AppTheme.accentBlue),
              const SizedBox(width: 16),
              _miniStat('Entregadas',
                  '${_dashboard!['completedCount'] ?? _dashboard!['deliveredCount'] ?? 0}', AppTheme.accentGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _repairTimeCard() {
    if (_repairTime == null) return const SizedBox.shrink();

    return GlassCard(
      borderColor: AppTheme.accentBlue.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.timer_rounded,
                    color: AppTheme.accentBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Tiempos de reparacion',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat('Promedio', '${_repairTime!['averageHours'] ?? 0}h',
                  AppTheme.accentBlue),
              const SizedBox(width: 12),
              _miniStat('Rapido', '${_repairTime!['fastestHours'] ?? 0}h',
                  AppTheme.accentGreen),
              const SizedBox(width: 12),
              _miniStat('Lento', '${_repairTime!['slowestHours'] ?? 0}h',
                  AppTheme.accentOrange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _technicianCard() {
    if (_technicians == null || _technicians!.isEmpty) {
      return const SizedBox.shrink();
    }

    return GlassCard(
      borderColor: AppTheme.accentPurple.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.engineering_rounded,
                    color: AppTheme.accentPurple, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Rendimiento por tecnico',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          ...(_technicians!.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          AppTheme.accentPurple.withValues(alpha: 0.15),
                      child: Text(
                        (t['name'] as String? ?? 'T')[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.accentPurple, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['name'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                  fontSize: 13)),
                          Text(
                            '${t['completedOrders']} completadas | ${t['activeOrders']} activas',
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '\$${(t['totalRevenue'] ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentGreen,
                          fontSize: 13),
                    ),
                  ],
                ),
              ))),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }
}
