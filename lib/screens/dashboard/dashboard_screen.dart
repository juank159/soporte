import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/orders/orders_bloc.dart';
import '../../config/theme.dart';
import '../../models/service_order.dart';
import '../../models/user.dart';
import '../../widgets/glass_card.dart';
import '../orders/order_list_screen.dart';
import '../orders/create_order_screen.dart';
import '../orders/scan_qr_screen.dart';
import '../customers/customers_screen.dart';
import '../settings/printer_setup_screen.dart';
import '../settings/device_catalog_screen.dart';
import '../settings/users_management_screen.dart';
import '../settings/tenant_settings_screen.dart';
import '../settings/subscription_screen.dart';
import '../../widgets/sync_status_widget.dart';
import '../../blocs/theme/theme_cubit.dart';
import '../reports/reports_screen.dart';
import '../orders/order_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final User user;

  const DashboardScreen({super.key, required this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late final AnimationController _fabController;

  @override
  void initState() {
    super.initState();
    context.read<OrdersBloc>().add(OrdersLoadRequested());
    _fabController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  void _showQuickSearch() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.search_rounded, color: AppTheme.accentCyan),
          SizedBox(width: 10),
          Text('Buscar orden', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        ]),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Numero de orden, cliente o serial...',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              Navigator.pop(ctx);
              // Switch to orders tab with search
              setState(() => _currentIndex = 1);
              context.read<OrdersBloc>().add(
                  OrdersLoadRequested(search: v.trim()));
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                setState(() => _currentIndex = 1);
                context.read<OrdersBloc>().add(
                    OrdersLoadRequested(search: ctrl.text.trim()));
              }
            },
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
  }

  void _navigateToCreateOrder() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => BlocProvider.value(
          value: context.read<OrdersBloc>(),
          child: const CreateOrderScreen(),
        ),
        transitionsBuilder: (_, a, __, child) =>
            SlideTransition(
              position: Tween(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child,
            ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  bool get _isAdmin => widget.user.isAdmin;
  bool get _isAdminOrSupervisor => widget.user.isAdmin || widget.user.isSupervisor;

  List<Widget> get _pages {
    final pages = <Widget>[
      _DashboardHome(user: widget.user),
      const OrderListScreen(),
    ];
    if (_isAdminOrSupervisor) {
      pages.add(const CustomersScreen());
    }
    if (_isAdmin) {
      pages.add(const ReportsScreen());
    }
    return pages;
  }

  List<NavigationDestination> get _navBarDests {
    final dests = <NavigationDestination>[
      const NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: 'Dashboard'),
      const NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          selectedIcon: Icon(Icons.assignment_rounded),
          label: 'Ordenes'),
    ];
    if (_isAdminOrSupervisor) {
      dests.add(const NavigationDestination(
          icon: Icon(Icons.people_outlined),
          selectedIcon: Icon(Icons.people_rounded),
          label: 'Clientes'));
    }
    if (_isAdmin) {
      dests.add(const NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart_rounded),
          label: 'Reportes'));
    }
    return dests;
  }

  List<NavigationRailDestination> get _navRailDests {
    final dests = <NavigationRailDestination>[
      const NavigationRailDestination(
          icon: Icon(Icons.dashboard_rounded), label: Text('Dashboard')),
      const NavigationRailDestination(
          icon: Icon(Icons.assignment_rounded), label: Text('Ordenes')),
    ];
    if (_isAdminOrSupervisor) {
      dests.add(const NavigationRailDestination(
          icon: Icon(Icons.people_rounded), label: Text('Clientes')));
    }
    if (_isAdmin) {
      dests.add(const NavigationRailDestination(
          icon: Icon(Icons.bar_chart_rounded), label: Text('Reportes')));
    }
    return dests;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 800;
    final pages = _pages;

    // Clamp index if role changed
    if (_currentIndex >= pages.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: AppTheme.gradientAccent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.construction_rounded,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text('Soporte', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          const SyncStatusWidget(),
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 22),
            tooltip: 'Buscar orden',
            onPressed: _showQuickSearch,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () =>
                context.read<OrdersBloc>().add(OrdersLoadRequested()),
          ),
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.accentCyan.withValues(alpha: 0.15),
              child: Text(
                widget.user.fullName[0].toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.accentCyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            onSelected: (value) {
              if (value == 'theme') {
                context.read<ThemeCubit>().toggleTheme();
              } else if (value == 'logout') {
                context.read<AuthBloc>().add(AuthLogoutRequested());
              } else if (value == 'printer') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PrinterSetupScreen()));
              } else if (value == 'catalog') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DeviceCatalogScreen()));
              } else if (value == 'users') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => UsersManagementScreen()));
              } else if (value == 'subscription') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => SubscriptionScreen()));
              } else if (value == 'tenant') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => TenantSettingsScreen()));
              }
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.user.fullName,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary)),
                      Text(widget.user.role.toUpperCase(),
                          style: const TextStyle(
                              color: AppTheme.accentCyan, fontSize: 11)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
              ];

              // Solo admin ve configuraciones
              if (_isAdmin) {
                items.addAll([
                  PopupMenuItem(
                    value: 'subscription',
                    child: Row(children: [
                      Icon(Icons.workspace_premium_rounded, size: 18, color: AppTheme.accentCyan),
                      const SizedBox(width: 10),
                      Text('Suscripcion', style: TextStyle(color: AppTheme.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'tenant',
                    child: Row(children: [
                      Icon(Icons.business_rounded, size: 18, color: AppTheme.accentBlue),
                      const SizedBox(width: 10),
                      Text('Mi negocio', style: TextStyle(color: AppTheme.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'users',
                    child: Row(children: [
                      Icon(Icons.group_rounded, size: 18, color: AppTheme.accentPurple),
                      const SizedBox(width: 10),
                      Text('Usuarios y tecnicos', style: TextStyle(color: AppTheme.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'catalog',
                    child: Row(children: [
                      Icon(Icons.devices_rounded, size: 18, color: AppTheme.accentOrange),
                      const SizedBox(width: 10),
                      Text('Catalogo equipos', style: TextStyle(color: AppTheme.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'printer',
                    child: Row(children: [
                      Icon(Icons.print_rounded, size: 18, color: AppTheme.accentGreen),
                      const SizedBox(width: 10),
                      Text('Impresora', style: TextStyle(color: AppTheme.textPrimary)),
                    ]),
                  ),
                  const PopupMenuDivider(),
                ]);
              }

              items.add(PopupMenuItem(
                value: 'theme',
                child: Row(children: [
                  Icon(context.read<ThemeCubit>().isDark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded, size: 18, color: AppTheme.accentOrange),
                  const SizedBox(width: 10),
                  Text(context.read<ThemeCubit>().isDark
                      ? 'Tema claro'
                      : 'Tema oscuro', style: TextStyle(color: AppTheme.textPrimary)),
                ]),
              ));
              items.add(const PopupMenuDivider());
              items.add(const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout_rounded,
                      size: 18, color: AppTheme.accentRed),
                  SizedBox(width: 10),
                  Text('Cerrar sesion',
                      style: TextStyle(color: AppTheme.accentRed)),
                ]),
              ));

              return items;
            },
          ),
          SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.gradientPrimary,
          ),
        ),
        child: SafeArea(
          child: isWide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _currentIndex,
                      onDestinationSelected: (i) =>
                          setState(() => _currentIndex = i),
                      labelType: NavigationRailLabelType.all,
                      leading: Padding(
                        padding: EdgeInsets.only(bottom: 16, top: 8),
                        child: ScaleTransition(
                          scale: _fabController,
                          child: FloatingActionButton(
                            heroTag: 'nav_fab',
                            onPressed: _navigateToCreateOrder,
                            child: Icon(Icons.add_rounded),
                          ),
                        ),
                      ),
                      destinations: _navRailDests,
                    ),
                    Container(width: 1, color: AppTheme.dividerColor),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: pages[_currentIndex],
                      ),
                    ),
                  ],
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: pages[_currentIndex],
                ),
        ),
      ),
      floatingActionButton: !isWide
          ? ScaleTransition(
              scale: _fabController,
              child: FloatingActionButton.extended(
                heroTag: 'main_fab',
                onPressed: _navigateToCreateOrder,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nueva Orden'),
              ),
            )
          : null,
      bottomNavigationBar: !isWide
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) =>
                  setState(() => _currentIndex = i),
              destinations: _navBarDests,
            )
          : null,
    );
  }

}

// ============================================================
//  DASHBOARD HOME
// ============================================================

class _DashboardHome extends StatelessWidget {
  final User user;
  const _DashboardHome({required this.user});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersBloc, OrdersState>(
      builder: (context, state) {
        if (state is OrdersLoading) {
          return Center(
            child: CircularProgressIndicator(color: AppTheme.accentCyan),
          );
        }
        if (state is OrdersError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_rounded,
                    size: 56, color: AppTheme.accentRed),
                SizedBox(height: 16),
                Text(state.message,
                    style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.read<OrdersBloc>().add(OrdersLoadRequested()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }
        if (state is OrdersLoaded) {
          return _buildContent(context, state.orders);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildContent(BuildContext context, List<ServiceOrder> orders) {
    // Count by individual equipment status when multi-device, else by order status
    final counts = <String, int>{};
    for (final o in orders) {
      if (o.equipments.isNotEmpty) {
        for (final eq in o.equipments) {
          counts[eq.status] = (counts[eq.status] ?? 0) + 1;
        }
      } else {
        counts[o.status] = (counts[o.status] ?? 0) + 1;
      }
    }

    // Count items (equipment-aware)
    final today = DateTime.now();
    int totalItems = 0;
    int todayOrders = 0;
    int pendingOrders = 0;
    for (final o in orders) {
      final itemCount = o.equipments.isNotEmpty ? o.equipments.length : 1;
      totalItems += itemCount;
      if (o.createdAt.year == today.year && o.createdAt.month == today.month && o.createdAt.day == today.day) {
        todayOrders += itemCount;
      }
      if (o.equipments.isNotEmpty) {
        pendingOrders += o.equipments.where((eq) =>
            eq.status != 'delivered' && eq.status != 'returned' && eq.status != 'closed').length;
      } else if (o.status != 'delivered' && o.status != 'returned' && o.status != 'closed') {
        pendingOrders++;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final crossCount = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 4
                : constraints.maxWidth > 400
                    ? 3
                    : 2;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isWide ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting with stats
              Text(
                'Hola, ${user.fullName}',
                style: TextStyle(
                  fontSize: isWide ? 26 : 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '$pendingOrders pendientes | $todayOrders hoy | $totalItems total',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Status cards
              GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  _StatCard('Recibidos', counts['received'] ?? 0,
                      Icons.inbox_rounded, AppTheme.accentBlue),
                  _StatCard('Diagnostico', counts['diagnosing'] ?? 0,
                      Icons.search_rounded, AppTheme.accentOrange),
                  _StatCard('Reparacion', counts['repairing'] ?? 0,
                      Icons.build_rounded, AppTheme.accentPurple),
                  _StatCard('Listos', counts['ready'] ?? 0,
                      Icons.check_circle_rounded, AppTheme.accentGreen),
                  _StatCard('Entregados', counts['delivered'] ?? 0,
                      Icons.local_shipping_rounded, AppTheme.accentCyan),
                ],
              ),
              SizedBox(height: 24),

              // Recent orders
              Text(
                'Ordenes recientes',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 12),

              if (orders.isEmpty)
                GlassCard(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.assignment_outlined,
                            size: 48,
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.5)),
                        SizedBox(height: 12),
                        Text('Sin ordenes aun',
                            style:
                                TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                )
              else
                ...orders.take(10).map((o) => _OrderTile(order: o)),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
//  STATUS CARD
// ============================================================

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _StatCard(this.label, this.count, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(10),
      borderColor: color.withValues(alpha: 0.25),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  ORDER TILE
// ============================================================

Color statusColor(String status) {
  switch (status) {
    case 'received':
      return AppTheme.accentBlue;
    case 'diagnosing':
      return AppTheme.accentOrange;
    case 'repairing':
      return AppTheme.accentPurple;
    case 'ready':
      return AppTheme.accentGreen;
    case 'returned':
      return AppTheme.accentRed;
    case 'delivered':
      return AppTheme.accentCyan;
    default:
      return AppTheme.textSecondary;
  }
}

class _OrderTile extends StatelessWidget {
  final ServiceOrder order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(order.status);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: context.read<OrdersBloc>(),
                  child: OrderDetailScreen(order: order),
                ),
              ),
            );
          },
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order.orderNumber}  ${order.device?.brand ?? ''} ${order.device?.model ?? ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3),
                  Text(
                    order.customer?.fullName ?? '',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            StatusBadge(label: order.statusLabel, color: color),
          ],
        ),
      ),
    );
  }
}
