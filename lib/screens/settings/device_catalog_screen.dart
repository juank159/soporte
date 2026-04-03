import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/device_catalog_service.dart';
import '../../widgets/glass_card.dart';

class DeviceCatalogScreen extends StatefulWidget {
  const DeviceCatalogScreen({super.key});

  @override
  State<DeviceCatalogScreen> createState() => _DeviceCatalogScreenState();
}

class _DeviceCatalogScreenState extends State<DeviceCatalogScreen>
    with SingleTickerProviderStateMixin {
  final DeviceCatalogService _service = DeviceCatalogService();
  late final TabController _tabController;

  List<DeviceTypeModel> _types = [];
  List<DeviceBrandModel> _brands = [];
  bool _loading = true;
  DeviceTypeModel? _selectedType;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _types = await _service.getTypes();
      _brands = await _service.getBrands();
      if (_types.isEmpty) {
        await _service.seedDefaults();
        _types = await _service.getTypes();
        _brands = await _service.getBrands();
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _addType() async {
    final name = await _showInputDialog('Nuevo tipo de equipo', 'Nombre');
    if (name == null || name.isEmpty) return;
    await _service.createType(name);
    _load();
  }

  Future<void> _addBrand() async {
    final name = await _showInputDialog('Nueva marca', 'Nombre de la marca');
    if (name == null || name.isEmpty) return;
    await _service.createBrand(name, deviceTypeId: _selectedType?.id);
    _load();
  }

  Future<String?> _showInputDialog(String title, String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('Crear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Catalogo de equipos'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accentCyan,
          labelColor: AppTheme.accentCyan,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: [
            Tab(text: 'Tipos de equipo'),
            Tab(text: 'Marcas'),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.gradientPrimary,
          ),
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.accentCyan))
            : TabBarView(
                controller: _tabController,
                children: [_typesTab(), _brandsTab()],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _addType();
          } else {
            _addBrand();
          }
        },
        child: Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _typesTab() {
    if (_types.isEmpty) {
      return Center(
        child: Text('No hay tipos de equipo.\nToca + para crear uno.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _types.length,
      itemBuilder: (context, i) {
        final t = _types[i];
        final brandCount =
            _brands.where((b) => b.deviceTypeId == t.id).length;
        return GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getIcon(t.icon),
                    color: AppTheme.accentCyan, size: 22),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                    Text('$brandCount marcas',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.accentRed, size: 20),
                onPressed: () async {
                  await _service.deleteType(t.id);
                  _load();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _brandsTab() {
    return Column(
      children: [
        // Type filter
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('Todas'),
                  selected: _selectedType == null,
                  onSelected: (_) => setState(() => _selectedType = null),
                ),
              ),
              ..._types.map((t) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(t.name),
                      selected: _selectedType?.id == t.id,
                      onSelected: (_) => setState(() => _selectedType = t),
                    ),
                  )),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final filtered = _selectedType == null
                  ? _brands
                  : _brands
                      .where((b) => b.deviceTypeId == _selectedType!.id)
                      .toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text('No hay marcas. Toca + para crear.',
                      style: TextStyle(color: AppTheme.textSecondary)),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final b = filtered[i];
                  return GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              AppTheme.accentPurple.withValues(alpha: 0.12),
                          child: Text(
                            b.name[0].toUpperCase(),
                            style: TextStyle(
                                color: AppTheme.accentPurple,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(b.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppTheme.accentRed, size: 20),
                          onPressed: () async {
                            await _service.deleteBrand(b.id);
                            _load();
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIcon(String? icon) {
    switch (icon) {
      case 'phone_android':
        return Icons.phone_android_rounded;
      case 'laptop':
        return Icons.laptop_rounded;
      case 'desktop_windows':
        return Icons.desktop_windows_rounded;
      case 'tablet':
        return Icons.tablet_rounded;
      case 'print':
        return Icons.print_rounded;
      case 'kitchen':
        return Icons.kitchen_rounded;
      case 'sports_esports':
        return Icons.sports_esports_rounded;
      default:
        return Icons.devices_rounded;
    }
  }
}
