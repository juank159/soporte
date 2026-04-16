import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/format_utils.dart';
import '../../services/api_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/date_range_picker.dart';

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
  Map<String, dynamic>? _revenue;
  bool _loading = true;
  String _revenueFilter = 'today';
  String _revenueLabel = 'Hoy';
  String? _revFrom;
  String? _revTo;

  @override
  void initState() { super.initState(); _setFilter('today'); _load(); }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  void _setFilter(String f) {
    final n = DateTime.now();
    switch (f) {
      case 'today': _revFrom=_fmt(n); _revTo=_fmt(n); _revenueLabel='Hoy';
      case 'week': _revFrom=_fmt(n.subtract(const Duration(days:7))); _revTo=_fmt(n); _revenueLabel='Esta semana';
      case 'month': _revFrom=_fmt(DateTime(n.year,n.month,1)); _revTo=_fmt(n); _revenueLabel='Este mes';
      case 'all': _revFrom=_fmt(DateTime(2020)); _revTo=_fmt(n); _revenueLabel='Todo';
    }
    _revenueFilter = f;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _api.dio.get('/reports/dashboard'),
        _api.dio.get('/reports/technicians'),
        _api.dio.get('/reports/repair-time'),
        _api.dio.get('/reports/stale-orders'),
        _api.dio.get('/reports/revenue', queryParameters: {'startDate': _revFrom, 'endDate': _revTo}),
      ]);
      setState(() { _dashboard=r[0].data; _technicians=r[1].data; _repairTime=r[2].data; _staleOrders=r[3].data; _revenue=r[4].data; _loading=false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePickerDialog(context, initialFrom: _revFrom, initialTo: _revTo);
    if (r != null) { setState(() { _revFrom=r['from']; _revTo=r['to']; _revenueLabel=r['label']??'Rango'; _revenueFilter='custom'; }); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: AppTheme.accentCyan));
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth > 700;
      return RefreshIndicator(color: AppTheme.accentCyan, onRefresh: _load, child: SingleChildScrollView(
        padding: EdgeInsets.all(w ? 24 : 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reportes', style: TextStyle(fontSize:22, fontWeight:FontWeight.w800, color:AppTheme.textPrimary)),
          const SizedBox(height: 16),
          _revenueCard(),
          if (w) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _repairTimeCard()), const SizedBox(width:12), Expanded(child: _statusCard())])
          else ...[ _repairTimeCard(), _statusCard() ],
          if (_staleOrders != null && (_staleOrders!['total'] as int? ?? 0) > 0) _staleCard(),
          if (_technicians != null && _technicians!.isNotEmpty) _techCard(),
        ]),
      ));
    });
  }

  Widget _revenueCard() {
    final rev = (_revenue?['totalRevenue'] ?? _dashboard?['totalRevenue'] ?? 0).toDouble();
    final cnt = _revenue?['ordersCount'] ?? 0;
    final total = _dashboard?['totalOrders'] ?? 0;
    final done = _dashboard?['completedCount'] ?? _dashboard?['deliveredCount'] ?? 0;
    return GlassCard(borderColor: AppTheme.accentGreen.withValues(alpha:0.3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.accentGreen.withValues(alpha:0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.trending_up_rounded, color: AppTheme.accentGreen, size:22)),
        SizedBox(width:12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ingresos - $_revenueLabel', style: TextStyle(color: AppTheme.textSecondary, fontSize:12)),
          Text('\$${formatMoney(rev)}', style: TextStyle(fontSize:24, fontWeight:FontWeight.w800, color: AppTheme.accentGreen)),
        ])),
        if (cnt > 0) Text('$cnt ordenes', style: TextStyle(color: AppTheme.textSecondary, fontSize:11)),
      ]),
      const SizedBox(height:14),
      SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [
        _chip('Hoy','today'), _chip('Semana','week'), _chip('Mes','month'), _chip('Todo','all'),
        const SizedBox(width:4),
        ActionChip(avatar: const Icon(Icons.date_range_rounded, size:14, color: AppTheme.accentPurple),
          label: Text(_revenueFilter=='custom' ? _revenueLabel : 'Rango', style: const TextStyle(fontSize:11)),
          onPressed: _pickRange, visualDensity: VisualDensity.compact),
      ])),
      SizedBox(height:12),
      Row(children: [
        _stat('Total', '$total', AppTheme.accentBlue), SizedBox(width:12),
        _stat('Completadas', '$done', AppTheme.accentGreen), SizedBox(width:12),
        _stat('Pendientes', '${total-done}', AppTheme.accentOrange),
      ]),
      // Payment method breakdown
      if (_revenue != null && _revenue!['paymentBreakdown'] != null) ...[
        const SizedBox(height: 14),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 8),
        Text('Ingresos por metodo de pago', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...(_revenue!['paymentBreakdown'] as Map<String, dynamic>).entries
            .where((e) => (e.value as num) > 0)
            .map((e) {
          final icon = _paymentIcon(e.key);
          final color = _paymentColor(e.key);
          final amount = (e.value as num).toDouble();
          final pct = rev > 0 ? (amount / rev * 100) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_paymentLabel(e.key), style: TextStyle(color: AppTheme.textPrimary, fontSize: 12))),
                  Text('\$${formatMoney(amount)}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 4,
                    backgroundColor: color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ])),
              const SizedBox(width: 8),
              Text('${pct.toStringAsFixed(0)}%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
            ]),
          );
        }),
      ],
    ]));
  }

  IconData _paymentIcon(String method) {
    switch (method) {
      case 'Efectivo': return Icons.money_rounded;
      case 'Transferencia': return Icons.swap_horiz_rounded;
      case 'Tarjeta de Credito': return Icons.credit_card_rounded;
      case 'Tarjeta de Debito': return Icons.credit_card_rounded;
      case 'Sin especificar': return Icons.receipt_long_rounded;
      default: return Icons.receipt_long_rounded;
    }
  }

  Color _paymentColor(String method) {
    switch (method) {
      case 'Efectivo': return AppTheme.accentGreen;
      case 'Transferencia': return AppTheme.accentBlue;
      case 'Tarjeta de Credito': return AppTheme.accentPurple;
      case 'Tarjeta de Debito': return AppTheme.accentCyan;
      case 'Sin especificar': return AppTheme.accentOrange;
      default: return AppTheme.accentOrange;
    }
  }

  String _paymentLabel(String method) {
    if (method == 'Sin especificar') return 'Otros (sin metodo)';
    return method;
  }

  Widget _chip(String l, String v) => Padding(padding: EdgeInsets.only(right:6), child: FilterChip(
    label: Text(l, style: TextStyle(fontSize:11)), selected: _revenueFilter==v,
    onSelected: (_) { _setFilter(v); _load(); }, visualDensity: VisualDensity.compact));

  Widget _repairTimeCard() {
    if (_repairTime == null) return SizedBox.shrink();
    return GlassCard(borderColor: AppTheme.accentBlue.withValues(alpha:0.3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.accentBlue.withValues(alpha:0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.timer_rounded, color: AppTheme.accentBlue, size:22)), const SizedBox(width:12),
        Text('Tiempos de reparacion', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))]),
      SizedBox(height:14),
      Row(children: [_stat('Promedio','${_repairTime!['averageHours']??0}h',AppTheme.accentBlue), SizedBox(width:12),
        _stat('Rapido','${_repairTime!['fastestHours']??0}h',AppTheme.accentGreen), SizedBox(width:12),
        _stat('Lento','${_repairTime!['slowestHours']??0}h',AppTheme.accentOrange)]),
      SizedBox(height:6), Text('${_repairTime!['count']??0} completadas', style: TextStyle(color: AppTheme.textSecondary, fontSize:11)),
    ]));
  }

  Widget _statusCard() {
    if (_dashboard == null) return SizedBox.shrink();
    final c = (_dashboard!['statusCounts'] as Map<String, dynamic>?) ?? {};
    final s = [('received','Recibidos',AppTheme.accentBlue,Icons.inbox_rounded),('diagnosing','Diagnostico',AppTheme.accentOrange,Icons.search_rounded),
      ('repairing','Reparacion',AppTheme.accentPurple,Icons.build_rounded),
      ('ready','Listos',AppTheme.accentGreen,Icons.check_circle_rounded),('returned','Devueltos',AppTheme.accentRed,Icons.undo_rounded),
      ('delivered','Entregados',AppTheme.accentCyan,Icons.local_shipping_rounded)];
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.pie_chart_rounded, color: AppTheme.accentCyan, size:20), SizedBox(width:8),
        Text('Por estado', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize:15))]),
      SizedBox(height:12),
      ...s.map((x) { final n=c[x.$1]??0; if(n==0) return SizedBox.shrink();
        return Padding(padding: EdgeInsets.only(bottom:6), child: Row(children: [
          Icon(x.$4, color:x.$3, size:16), SizedBox(width:8),
          Text(x.$2, style: TextStyle(color: AppTheme.textPrimary, fontSize:13)), Spacer(),
          Container(padding: EdgeInsets.symmetric(horizontal:10,vertical:3),
            decoration: BoxDecoration(color: x.$3.withValues(alpha:0.15), borderRadius: BorderRadius.circular(10)),
            child: Text('$n', style: TextStyle(color:x.$3, fontWeight:FontWeight.w700, fontSize:12)))])); }),
    ]));
  }

  Widget _staleCard() {
    final d=_staleOrders!; final cr=d['critical'] as int?? 0; final w=d['warning'] as int?? 0; final o=(d['orders'] as List?) ?? [];
    final cl = cr>0 ? AppTheme.accentRed : AppTheme.accentOrange;
    final lb = {'received':'Recibido','diagnosing':'Diagnostico','repairing':'Reparacion','ready':'Listo'};
    return GlassCard(borderColor: cl.withValues(alpha:0.4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: cl.withValues(alpha:0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.warning_rounded, color:cl, size:22)), SizedBox(width:12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ordenes pendientes', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize:15)),
          Text('$cr criticas (+30d) | $w atencion (+15d)', style: TextStyle(color:cl, fontSize:11))]))]),
      SizedBox(height:12),
      ...o.take(10).map((x) { final dy=x['daysInSystem'] as int?? 0; final p=x['priority'] as String?? 'normal';
        final pc = p=='critical'?AppTheme.accentRed:p=='warning'?AppTheme.accentOrange:AppTheme.textSecondary;
        return Padding(padding: EdgeInsets.only(bottom:8), child: Row(children: [
          Container(width:4, height:36, decoration: BoxDecoration(color:pc, borderRadius: BorderRadius.circular(2))),
          SizedBox(width:10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['orderNumber']} - ${x['device']??''}', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize:12), overflow: TextOverflow.ellipsis),
            Text('${x['customerName']??'Express'} | ${lb[x['status']]??x['status']}', style: TextStyle(color: AppTheme.textSecondary, fontSize:11))])),
          Container(padding: EdgeInsets.symmetric(horizontal:8,vertical:3), decoration: BoxDecoration(color: pc.withValues(alpha:0.15), borderRadius: BorderRadius.circular(10)),
            child: Text('$dy d', style: TextStyle(color:pc, fontSize:11, fontWeight: FontWeight.w700)))])); }),
    ]));
  }

  Widget _techCard() => GlassCard(borderColor: AppTheme.accentPurple.withValues(alpha:0.3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Icon(Icons.engineering_rounded, color: AppTheme.accentPurple, size:20), SizedBox(width:8),
      Text('Rendimiento por tecnico', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize:15))]),
    SizedBox(height:12),
    ...(_technicians!.map((t) => Padding(padding: EdgeInsets.only(bottom:10), child: Row(children: [
      CircleAvatar(radius:16, backgroundColor: AppTheme.accentPurple.withValues(alpha:0.15),
        child: Text((t['name'] as String? ?? 'T')[0].toUpperCase(), style: TextStyle(color: AppTheme.accentPurple, fontSize:13))),
      SizedBox(width:12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t['name']??'', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize:13)),
        Text('${t['completedOrders']} completadas | ${t['activeOrders']} activas', style: TextStyle(color: AppTheme.textSecondary, fontSize:11))])),
      Text('\$${formatMoney(t['totalRevenue']??0)}', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.accentGreen, fontSize:13))]))))
  ]));

  Widget _stat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize:18, fontWeight:FontWeight.w800, color:c)),
    Text(l, style: TextStyle(color: AppTheme.textSecondary, fontSize:10))]));
}
