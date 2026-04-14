//lib/screens/orders/create_order_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../blocs/orders/orders_bloc.dart';
import '../../models/service_order.dart';
import '../../config/theme.dart';
import '../../models/customer.dart';
import '../../services/customer_service.dart';
import '../../services/device_catalog_service.dart';
import '../../services/api_service.dart';
import '../../services/ticket_printer_service.dart';
import '../../models/tenant.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/ticket_preview_widget.dart';

/// Holds all data for one device being added to the order
class _DeviceEntry {
  String typeName;
  String? typeIcon;
  String brandName;
  String model;
  String serial;
  String? color;
  List<String> accessories;
  String problem;
  List<File> photos;

  _DeviceEntry({
    required this.typeName,
    this.typeIcon,
    required this.brandName,
    required this.model,
    required this.serial,
    this.color,
    required this.accessories,
    required this.problem,
    required this.photos,
  });

  String get summary => '$typeName $brandName $model';
}

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  // Customer
  int _customerMode = 0; // 0=search, 1=new, 2=express
  Customer? _selectedCustomer;
  final _customerSearchCtrl = TextEditingController();
  List<Customer> _customerResults = [];
  bool _searchingCustomers = false;
  final _newNameCtrl = TextEditingController();
  final _newIdCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();

  // Device catalog
  List<DeviceTypeModel> _deviceTypes = [];
  List<DeviceBrandModel> _allBrands = [];
  bool _loadingCatalog = true;

  // Current device form
  DeviceTypeModel? _selectedType;
  DeviceBrandModel? _selectedBrand;
  final _deviceModelCtrl = TextEditingController();
  final _deviceSerialCtrl = TextEditingController();
  final _deviceColorCtrl = TextEditingController();
  final _accessoriesCtrl = TextEditingController();
  final _problemCtrl = TextEditingController();
  final List<File> _photos = [];
  bool _showDeviceForm = true; // show form vs only list

  // Editing existing device
  int? _editingIndex;

  // Devices list
  final List<_DeviceEntry> _devices = [];
  int? _expandedDevice; // which card is expanded, null = all collapsed

  // Technician (global, one per order)
  List<Map<String, dynamic>> _technicians = [];
  String? _selectedTechnicianId;

  final _imagePicker = ImagePicker();
  final _customerService = CustomerService();
  final _catalogService = DeviceCatalogService();
  final _api = ApiService();
  final _printerService = TicketPrinterService();
  Tenant? _tenant;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadTechnicians();
    _loadTenant();
  }

  Future<void> _loadTenant() async {
    try {
      final res = await _api.dio.get('/tenants/me');
      _tenant = Tenant.fromJson(res.data);
    } catch (_) {}
  }

  Future<void> _loadCatalog() async {
    try {
      _deviceTypes = await _catalogService.getTypes();
      _allBrands = await _catalogService.getBrands();
      if (_deviceTypes.isEmpty) {
        await _catalogService.seedDefaults();
        _deviceTypes = await _catalogService.getTypes();
        _allBrands = await _catalogService.getBrands();
      }
    } catch (_) {}
    setState(() => _loadingCatalog = false);
  }

  Future<void> _loadTechnicians() async {
    try {
      final res = await _api.dio.get('/users');
      final users = res.data as List;
      setState(() {
        _technicians = users
            .where((u) => u['role'] == 'technician' || u['role'] == 'supervisor')
            .cast<Map<String, dynamic>>()
            .toList();
      });
    } catch (_) {}
  }

  List<DeviceBrandModel> get _filteredBrands {
    if (_selectedType == null) return _allBrands;
    return _allBrands.where((b) => b.deviceTypeId == _selectedType!.id).toList();
  }

  @override
  void dispose() {
    _customerSearchCtrl.dispose();
    _newNameCtrl.dispose();
    _newIdCtrl.dispose();
    _newPhoneCtrl.dispose();
    _newEmailCtrl.dispose();
    _deviceModelCtrl.dispose();
    _deviceSerialCtrl.dispose();
    _deviceColorCtrl.dispose();
    _accessoriesCtrl.dispose();
    _problemCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchCustomers(String q) async {
    if (q.length < 2) return;
    setState(() => _searchingCustomers = true);
    try {
      _customerResults = await _customerService.getCustomers(search: q);
    } catch (_) {}
    setState(() => _searchingCustomers = false);
  }

  static const _maxPhotos = 4;

  Future<void> _takePhoto() async {
    if (_photos.length >= _maxPhotos) {
      _showError('Maximo $_maxPhotos fotos por equipo');
      return;
    }
    final isDesktop = Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;

    ImageSource? source;
    if (isDesktop) {
      source = ImageSource.gallery;
    } else {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: AppTheme.surfaceColor,
        builder: (ctx) => SafeArea(
          child: Wrap(children: [
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: AppTheme.accentCyan),
              title: Text('Tomar foto', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: AppTheme.accentPurple),
              title: Text('Galeria', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ]),
        ),
      );
    }
    if (source == null) return;
    try {
      final picked = await _imagePicker.pickImage(
          source: source, imageQuality: 80, maxWidth: 1280);
      if (picked != null) setState(() => _photos.add(File(picked.path)));
    } catch (e) {
      debugPrint('Photo pick error: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.accentOrange));
  }

  bool _validateDeviceForm() {
    if (_selectedType == null) { _showError('Seleccione el tipo de equipo'); return false; }
    if (_selectedBrand == null) { _showError('Seleccione la marca'); return false; }
    if (_deviceModelCtrl.text.trim().isEmpty) { _showError('Ingrese el modelo'); return false; }
    if (_deviceSerialCtrl.text.trim().isEmpty) { _showError('Ingrese el serial / IMEI'); return false; }
    if (_accessoriesCtrl.text.trim().isEmpty) { _showError('Ingrese los accesorios'); return false; }
    if (_problemCtrl.text.trim().isEmpty) { _showError('Describa el problema'); return false; }
    return true;
  }

  void _saveDevice() {
    if (!_validateDeviceForm()) return;

    final accessories = _accessoriesCtrl.text.trim().isNotEmpty
        ? _accessoriesCtrl.text.split(',').map((e) => e.trim()).toList()
        : <String>[];

    final entry = _DeviceEntry(
      typeName: _selectedType!.name,
      typeIcon: _selectedType!.icon,
      brandName: _selectedBrand!.name,
      model: _deviceModelCtrl.text.trim(),
      serial: _deviceSerialCtrl.text.trim(),
      color: _deviceColorCtrl.text.trim().isNotEmpty ? _deviceColorCtrl.text.trim() : null,
      accessories: accessories,
      problem: _problemCtrl.text.trim(),
      photos: List<File>.from(_photos),
    );

    setState(() {
      if (_editingIndex != null) {
        _devices[_editingIndex!] = entry;
        _editingIndex = null;
      } else {
        _devices.add(entry);
      }
      _clearDeviceForm();
      _showDeviceForm = false;
      _expandedDevice = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Equipo guardado (${_devices.length} en total)'),
      backgroundColor: AppTheme.accentGreen,
      duration: Duration(seconds: 2),
    ));
  }

  void _editDevice(int index) {
    final d = _devices[index];
    setState(() {
      _editingIndex = index;
      _selectedType = _deviceTypes.where((t) => t.name == d.typeName).firstOrNull;
      _selectedBrand = _allBrands.where((b) => b.name == d.brandName).firstOrNull;
      _deviceModelCtrl.text = d.model;
      _deviceSerialCtrl.text = d.serial;
      _deviceColorCtrl.text = d.color ?? '';
      _accessoriesCtrl.text = d.accessories.join(', ');
      _problemCtrl.text = d.problem;
      _photos.clear();
      _photos.addAll(d.photos);
      _showDeviceForm = true;
      _expandedDevice = null;
    });
  }

  void _clearDeviceForm() {
    _selectedType = null;
    _selectedBrand = null;
    _deviceModelCtrl.clear();
    _deviceSerialCtrl.clear();
    _deviceColorCtrl.clear();
    _accessoriesCtrl.clear();
    _problemCtrl.clear();
    _photos.clear();
    _editingIndex = null;
  }

  Future<void> _createOrders() async {
    String customerId;

    if (_customerMode == 2) {
      try {
        final customers = await _customerService.getCustomers(search: 'EXPRESS');
        final express = customers.where((c) => c.idNumber == 'EXPRESS').firstOrNull;
        if (express != null) {
          customerId = express.id;
        } else {
          final c = await _customerService.createCustomer(
              fullName: 'Cliente Express', idNumber: 'EXPRESS', phone: '0000000000');
          customerId = c.id;
        }
      } catch (_) {
        if (mounted) _showError('Error con cliente express');
        return;
      }
    } else if (_customerMode == 1) {
      try {
        final c = await _customerService.createCustomer(
          fullName: _newNameCtrl.text.trim(),
          idNumber: _newIdCtrl.text.trim(),
          phone: _newPhoneCtrl.text.trim(),
          email: _newEmailCtrl.text.trim().isNotEmpty ? _newEmailCtrl.text.trim() : null,
        );
        customerId = c.id;
      } catch (_) {
        if (mounted) _showError('Error al crear cliente');
        return;
      }
    } else {
      if (_selectedCustomer == null) { _showError('Seleccione un cliente'); return; }
      customerId = _selectedCustomer!.id;
    }

    if (!mounted) return;

    final equipmentList = _devices.map((d) => EquipmentData(
      deviceType: d.typeName,
      deviceBrand: d.brandName,
      deviceModel: d.model,
      problemReported: d.problem,
      deviceSerial: d.serial,
      deviceColor: d.color,
      accessories: d.accessories.isNotEmpty ? d.accessories : null,
      photos: d.photos.isNotEmpty ? d.photos : null,
      technicianId: _selectedTechnicianId,
    )).toList();

    context.read<OrdersBloc>().add(OrderCreateRequested(
      customerId: customerId,
      equipments: equipmentList,
      photos: _devices.length == 1 && _devices[0].photos.isNotEmpty ? _devices[0].photos : null,
    ));
  }

  Future<void> _showTicketDialog(ServiceOrder order) async {
    final tenant = _tenant ?? Tenant(id: '', name: 'Servicio Tecnico', slug: 'default');
    final printerConnected = await _printerService.hasSavedPrinter;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Row(children: [
          Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Orden creada',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
              Text(order.orderNumber,
                  style: TextStyle(color: AppTheme.accentCyan, fontSize: 14)),
              if (_devices.length > 1)
                Text('${_devices.length} equipos registrados',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ]),
          ),
        ]),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: TicketPreviewWidget(order: order, tenant: tenant)),
              const SizedBox(height: 16),
              if (!printerConnected)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.print_disabled_rounded, color: AppTheme.accentOrange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Impresora no conectada.',
                          style: TextStyle(color: AppTheme.accentOrange, fontSize: 12)),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  context.read<OrdersBloc>().add(OrdersLoadRequested());
                },
                child: const Text('Cerrar'),
              ),
            ),
            if (printerConnected)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final success = await _printerService.printReceptionTicket(
                        order: order, tenant: tenant);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(success ? 'Ticket impreso' : 'Error al imprimir'),
                        backgroundColor: success ? AppTheme.accentGreen : AppTheme.accentRed,
                      ));
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                      context.read<OrdersBloc>().add(OrdersLoadRequested());
                    }
                  },
                  icon: Icon(Icons.print_rounded, size: 18),
                  label: Text('Imprimir'),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nueva Orden'),
        actions: [
          if (_devices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: Icon(Icons.devices_rounded, size: 16, color: AppTheme.accentCyan),
                label: Text('${_devices.length}', style: TextStyle(fontSize: 12)),
              ),
            ),
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
        child: BlocListener<OrdersBloc, OrdersState>(
          listener: (context, state) {
            if (state is OrderCreated) _showTicketDialog(state.order);
            if (state is OrdersError) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message), backgroundColor: AppTheme.accentRed));
            }
          },
          child: Form(
            key: _formKey,
            child: Theme(
              data: Theme.of(context).copyWith(canvasColor: AppTheme.surfaceColor),
              child: Stepper(
                currentStep: _currentStep,
                onStepContinue: () {
                  if (_currentStep == 0) {
                    if (_customerMode == 0 && _selectedCustomer == null) {
                      _showError('Seleccione un cliente');
                      return;
                    }
                    if (_customerMode == 1) {
                      if (_newNameCtrl.text.trim().isEmpty) { _showError('Ingrese el nombre'); return; }
                      if (_newIdCtrl.text.trim().isEmpty) { _showError('Ingrese la cedula'); return; }
                      if (_newPhoneCtrl.text.trim().isEmpty) { _showError('Ingrese el telefono'); return; }
                    }
                    setState(() => _currentStep++);
                  } else if (_currentStep == 1) {
                    if (_devices.isEmpty) { _showError('Agregue al menos un equipo'); return; }
                    setState(() => _currentStep++);
                  } else {
                    _createOrders();
                  }
                },
                onStepCancel: () {
                  if (_currentStep > 0) {
                    setState(() => _currentStep--);
                  } else {
                    Navigator.pop(context);
                  }
                },
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Row(children: [
                      BlocBuilder<OrdersBloc, OrdersState>(
                        builder: (context, state) => ElevatedButton(
                          onPressed: state is OrdersLoading ? null : details.onStepContinue,
                          child: Text(_currentStep == 2 ? 'Crear Orden' : 'Siguiente'),
                        ),
                      ),
                      SizedBox(width: 12),
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: Text(_currentStep == 0 ? 'Cancelar' : 'Anterior'),
                      ),
                    ]),
                  );
                },
                steps: [
                  Step(
                    title: Text('Cliente', style: TextStyle(color: AppTheme.textPrimary)),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                    content: _clientStep(),
                  ),
                  Step(
                    title: Text(
                      'Equipos${_devices.isNotEmpty ? ' (${_devices.length})' : ''}',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                    content: _devicesStep(),
                  ),
                  Step(
                    title: Text('Tecnico y confirmar', style: TextStyle(color: AppTheme.textPrimary)),
                    isActive: _currentStep >= 2,
                    content: _confirmStep(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // STEP 1: CLIENTE
  // =====================================================
  Widget _clientStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        ChoiceChip(
          avatar: const Icon(Icons.search_rounded, size: 16),
          label: const Text('Buscar'),
          selected: _customerMode == 0,
          onSelected: (_) => setState(() => _customerMode = 0),
        ),
        ChoiceChip(
          avatar: Icon(Icons.person_add_rounded, size: 16),
          label: Text('Nuevo'),
          selected: _customerMode == 1,
          onSelected: (_) => setState(() => _customerMode = 1),
        ),
        ChoiceChip(
          avatar: Icon(Icons.flash_on_rounded, size: 16),
          label: Text('Express'),
          selected: _customerMode == 2,
          onSelected: (_) => setState(() => _customerMode = 2),
        ),
      ]),
      SizedBox(height: 16),
      if (_customerMode == 0) ...[
        TextField(
          controller: _customerSearchCtrl,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Buscar por nombre, cedula o telefono',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: _searchCustomers,
        ),
        if (_searchingCustomers)
          Padding(padding: EdgeInsets.only(top: 4), child: LinearProgressIndicator(color: AppTheme.accentCyan)),
        ..._customerResults.map((c) => ListTile(
              title: Text(c.fullName, style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text('${c.idNumber} - ${c.phone}', style: TextStyle(color: AppTheme.textSecondary)),
              selected: _selectedCustomer?.id == c.id,
              onTap: () => setState(() {
                _selectedCustomer = c;
                _customerResults = [];
                _customerSearchCtrl.text = c.fullName;
              }),
            )),
        if (_selectedCustomer != null)
          GlassCard(
            borderColor: AppTheme.accentGreen.withValues(alpha: 0.4),
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen),
              SizedBox(width: 10),
              Expanded(
                child: Text('${_selectedCustomer!.fullName} | ${_selectedCustomer!.phone}',
                    style: TextStyle(color: AppTheme.textPrimary)),
              ),
            ]),
          ),
      ],
      if (_customerMode == 1) ...[
        _field(_newNameCtrl, 'Nombre completo *'),
        _field(_newIdCtrl, 'Cedula / NIT *'),
        _field(_newPhoneCtrl, 'Telefono *', keyboard: TextInputType.phone),
        _field(_newEmailCtrl, 'Email (opcional)', keyboard: TextInputType.emailAddress),
      ],
      if (_customerMode == 2)
        GlassCard(
          borderColor: AppTheme.accentOrange.withValues(alpha: 0.4),
          padding: EdgeInsets.all(14),
          child: Row(children: [
            Icon(Icons.flash_on_rounded, color: AppTheme.accentOrange),
            SizedBox(width: 10),
            Expanded(
              child: Text('Servicio Express - sin datos del cliente',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
    ]);
  }

  // =====================================================
  // STEP 2: EQUIPOS (collapsible cards + form)
  // =====================================================
  Widget _devicesStep() {
    if (_loadingCatalog) {
      return Center(child: CircularProgressIndicator(color: AppTheme.accentCyan));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Collapsed device cards
      ..._devices.asMap().entries.map((e) => _collapsibleDeviceCard(e.key, e.value)),

      // Device form (add new or edit existing)
      if (_showDeviceForm) ...[
        if (_devices.isNotEmpty) ...[
          Divider(color: AppTheme.dividerColor, height: 24),
          Row(children: [
            Icon(_editingIndex != null ? Icons.edit_rounded : Icons.add_rounded,
                color: AppTheme.accentCyan, size: 18),
            SizedBox(width: 8),
            Text(
              _editingIndex != null ? 'Editando equipo #${_editingIndex! + 1}' : 'Nuevo equipo',
              style: TextStyle(color: AppTheme.accentCyan, fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Spacer(),
            if (_editingIndex != null)
              TextButton(
                onPressed: () => setState(() {
                  _clearDeviceForm();
                  _showDeviceForm = _devices.isEmpty;
                }),
                child: Text('Cancelar', style: TextStyle(color: AppTheme.accentRed, fontSize: 12)),
              ),
          ]),
          SizedBox(height: 8),
        ],

        // Type
        Text('Tipo de equipo *',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _deviceTypes.map((t) {
            final selected = _selectedType?.id == t.id;
            return ChoiceChip(
              avatar: Icon(_getTypeIcon(t.icon), size: 16,
                  color: selected ? AppTheme.accentCyan : AppTheme.textSecondary),
              label: Text(t.name),
              selected: selected,
              onSelected: (_) => setState(() { _selectedType = t; _selectedBrand = null; }),
            );
          }).toList(),
        ),
        SizedBox(height: 16),

        // Brand
        if (_selectedType != null) ...[
          Text('Marca *',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filteredBrands.map((b) {
              final selected = _selectedBrand?.id == b.id;
              return ChoiceChip(
                label: Text(b.name),
                selected: selected,
                onSelected: (_) => setState(() => _selectedBrand = b),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],

        _field(_deviceModelCtrl, 'Modelo *'),
        _field(_deviceSerialCtrl, 'Serial / IMEI *'),
        _field(_deviceColorCtrl, 'Color (opcional)'),
        _field(_accessoriesCtrl, 'Accesorios *', hint: 'Cargador, Funda, Audifonos'),

        // Problem
        TextFormField(
          controller: _problemCtrl,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Problema de este equipo *',
            hintText: 'Describa la falla...',
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),

        // Photos
        Row(children: [
          Text('Fotos (opcional)',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          Spacer(),
          if (_photos.isNotEmpty)
            Text('${_photos.length}/$_maxPhotos',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ..._photos.asMap().entries.map((e) => Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(e.value, width: 64, height: 64, fit: BoxFit.cover),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: GestureDetector(
                    onTap: () => setState(() => _photos.removeAt(e.key)),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: AppTheme.accentRed, shape: BoxShape.circle),
                      child: Icon(Icons.close, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ])),
          if (_photos.length < _maxPhotos)
            InkWell(
              onTap: _takePhoto,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.add_a_photo_rounded, color: AppTheme.textSecondary, size: 20),
              ),
            ),
        ]),
        const SizedBox(height: 16),

        // Save device button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saveDevice,
            icon: Icon(_editingIndex != null ? Icons.check_rounded : Icons.add_rounded),
            label: Text(_editingIndex != null ? 'Guardar cambios' : 'Guardar equipo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPurple,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],

      // "Add another" button (when form is hidden)
      if (!_showDeviceForm && _devices.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _clearDeviceForm();
              _showDeviceForm = true;
            }),
            icon: Icon(Icons.add_rounded, size: 20),
            label: Text('Agregar otro equipo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentPurple,
              side: BorderSide(color: AppTheme.accentPurple),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _collapsibleDeviceCard(int index, _DeviceEntry device) {
    final isExpanded = _expandedDevice == index;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      borderColor: AppTheme.accentCyan.withValues(alpha: 0.4),
      child: Column(children: [
        // Header - always visible, tap to expand/collapse
        InkWell(
          onTap: () => setState(() => _expandedDevice = isExpanded ? null : index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.accentCyan.withValues(alpha: 0.2),
                child: Text('${index + 1}',
                    style: TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(device.summary,
                      style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('S/N: ${device.serial}',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ]),
              ),
              if (device.photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.photo_camera_rounded, color: AppTheme.accentOrange, size: 16),
                ),
              Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppTheme.textSecondary, size: 22),
            ]),
          ),
        ),

        // Expanded content
        if (isExpanded)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Divider(color: AppTheme.dividerColor, height: 1),
              const SizedBox(height: 10),
              _detailRow('Tipo', device.typeName),
              _detailRow('Marca', device.brandName),
              _detailRow('Modelo', device.model),
              if (device.color != null) _detailRow('Color', device.color!),
              _detailRow('Accesorios', device.accessories.join(', ')),
              _detailRow('Problema', device.problem),
              if (device.photos.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: device.photos.map((f) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(f, width: 48, height: 48, fit: BoxFit.cover),
                  )).toList(),
                ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editDevice(index),
                    icon: Icon(Icons.edit_rounded, size: 16),
                    label: Text('Editar', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyan,
                      side: BorderSide(color: AppTheme.accentCyan.withValues(alpha: 0.5)),
                      padding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _devices.removeAt(index);
                      _expandedDevice = null;
                      if (_devices.isEmpty) _showDeviceForm = true;
                    }),
                    icon: Icon(Icons.delete_rounded, size: 16),
                    label: Text('Eliminar', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentRed,
                      side: BorderSide(color: AppTheme.accentRed.withValues(alpha: 0.5)),
                      padding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: Text(value, style: TextStyle(color: AppTheme.textPrimary, fontSize: 11)),
        ),
      ]),
    );
  }

  // =====================================================
  // STEP 3: TECNICO + CONFIRMAR
  // =====================================================
  Widget _confirmStep() {
    final clientName = _customerMode == 2
        ? 'Cliente Express'
        : _customerMode == 1
            ? _newNameCtrl.text.trim()
            : _selectedCustomer?.fullName ?? '-';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Client summary
      GlassCard(
        borderColor: AppTheme.accentBlue.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.person_rounded, color: AppTheme.accentBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(clientName,
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
        ]),
      ),

      // Devices summary
      GlassCard(
        borderColor: AppTheme.accentCyan.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.devices_rounded, color: AppTheme.accentCyan, size: 18),
            SizedBox(width: 8),
            Text('${_devices.length} equipo(s)',
                style: TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          ..._devices.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Text('${e.key + 1}. ',
                  style: TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.w700, fontSize: 12)),
              Expanded(
                child: Text(e.value.summary,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
              ),
            ]),
          )),
        ]),
      ),

      // Technician selector
      GlassCard(
        borderColor: AppTheme.accentPurple.withValues(alpha: 0.3),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.engineering_rounded, color: AppTheme.accentPurple, size: 18),
            SizedBox(width: 8),
            Text('Asignar tecnico (opcional)',
                style: TextStyle(color: AppTheme.accentPurple, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          if (_technicians.isEmpty)
            Text('No hay tecnicos registrados',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: Text('Sin asignar'),
                selected: _selectedTechnicianId == null,
                onSelected: (_) => setState(() => _selectedTechnicianId = null),
              ),
              ..._technicians.map((t) {
                final selected = _selectedTechnicianId == t['id'];
                return ChoiceChip(
                  avatar: CircleAvatar(
                    radius: 12,
                    backgroundColor: selected ? AppTheme.accentPurple : AppTheme.surfaceColor,
                    child: Text((t['fullName'] as String)[0].toUpperCase(),
                        style: TextStyle(fontSize: 10, color: selected ? Colors.white : AppTheme.textSecondary)),
                  ),
                  label: Text(t['fullName'] as String),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedTechnicianId = t['id'] as String),
                );
              }),
            ]),
        ]),
      ),

      if (_devices.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.accentPurple, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Se creara 1 orden con ${_devices.length} equipos. Cada equipo tendra diagnostico y reparacion independiente.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ),
          ]),
        ),
    ]);
  }

  // =====================================================
  // HELPERS
  // =====================================================
  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboard, String? hint}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        style: TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(labelText: label, hintText: hint),
        keyboardType: keyboard,
      ),
    );
  }

  IconData _getTypeIcon(String? icon) {
    switch (icon) {
      case 'phone_android': return Icons.phone_android_rounded;
      case 'laptop': return Icons.laptop_rounded;
      case 'desktop_windows': return Icons.desktop_windows_rounded;
      case 'tablet': return Icons.tablet_rounded;
      case 'print': return Icons.print_rounded;
      case 'kitchen': return Icons.kitchen_rounded;
      case 'sports_esports': return Icons.sports_esports_rounded;
      default: return Icons.devices_rounded;
    }
  }
}
