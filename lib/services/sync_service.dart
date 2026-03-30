import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../models/service_order.dart';
import '../models/customer.dart';
import 'api_service.dart';

/// Servicio de sincronización offline → online.
/// Usa last-write-wins con timestamp UTC. El servidor es la fuente de verdad.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;

  final AppDatabase _db = AppDatabase();
  final ApiService _api = ApiService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription? _connectivitySubscription;
  bool _syncing = false;
  String? _tenantId;

  // Stream to notify UI about sync status
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatus => _syncStatusController.stream;

  SyncService._internal();

  AppDatabase get database => _db;

  /// Initialize sync service and start listening for connectivity changes
  void initialize(String tenantId) {
    _tenantId = tenantId;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        final hasConnection = results.any((r) => r != ConnectivityResult.none);
        if (hasConnection) {
          syncAll();
        }
      },
    );
  }

  /// Check if we have internet connectivity
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Sync all pending data to the server
  Future<void> syncAll() async {
    if (_syncing || _tenantId == null) return;
    if (!await isOnline) return;

    _syncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    try {
      // 1. Push local changes to server
      await _pushPendingChanges();

      // 2. Pull latest data from server
      await _pullFromServer();

      _syncStatusController.add(SyncStatus.synced);
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
    }

    _syncing = false;
  }

  /// Push unsynced local changes to the server
  Future<void> _pushPendingChanges() async {
    final pendingItems = await _db.getPendingSyncItems();

    for (final item in pendingItems) {
      try {
        final payload = jsonDecode(item.payload) as Map<String, dynamic>;

        switch (item.entityType) {
          case 'customer':
            await _syncCustomer(item.action, payload);
            break;
          case 'order':
            await _syncOrder(item.action, payload);
            break;
        }

        // Success - remove from queue
        await _db.deleteSyncItem(item.id);
      } catch (e) {
        // Increment retry count
        await ((_db.update(_db.syncQueue))
              ..where((s) => s.id.equals(item.id)))
            .write(SyncQueueCompanion(
          retryCount: Value(item.retryCount + 1),
          lastError: Value(e.toString()),
        ));
      }
    }
  }

  Future<void> _syncCustomer(
      String action, Map<String, dynamic> payload) async {
    if (action == 'create') {
      await _api.dio.post('/customers', data: payload);
    } else if (action == 'update') {
      final id = payload.remove('id');
      await _api.dio.put('/customers/$id', data: payload);
    }
  }

  Future<void> _syncOrder(String action, Map<String, dynamic> payload) async {
    if (action == 'create') {
      await _api.dio.post('/orders', data: payload);
    } else if (action == 'update_status') {
      final id = payload.remove('id');
      await _api.dio.patch('/orders/$id/status', data: payload);
    }
  }

  /// Pull latest data from server and update local DB
  Future<void> _pullFromServer() async {
    try {
      // Pull customers
      final customersResponse = await _api.dio.get('/customers');
      final customers = (customersResponse.data as List)
          .map((e) => Customer.fromJson(e))
          .toList();

      for (final c in customers) {
        await _db.upsertCustomer(LocalCustomersCompanion(
          id: Value(c.id),
          tenantId: Value(_tenantId!),
          fullName: Value(c.fullName),
          idNumber: Value(c.idNumber),
          phone: Value(c.phone),
          email: Value(c.email),
          notes: Value(c.notes),
          synced: const Value(true),
        ));
      }

      // Pull orders
      final ordersResponse = await _api.dio.get('/orders');
      final orders = (ordersResponse.data as List)
          .map((e) => ServiceOrder.fromJson(e))
          .toList();

      for (final o in orders) {
        // Save device
        if (o.device != null) {
          await _db.upsertDevice(LocalDevicesCompanion(
            id: Value(o.device!.id),
            tenantId: Value(_tenantId!),
            type: Value(o.device!.type),
            brand: Value(o.device!.brand),
            model: Value(o.device!.model),
            serial: Value(o.device!.serial),
            imei: Value(o.device!.imei),
            color: Value(o.device!.color),
            accessories: Value(o.device!.accessories?.join(',') ?? ''),
            synced: const Value(true),
          ));
        }

        // Save order
        await _db.upsertOrder(LocalOrdersCompanion(
          id: Value(o.id),
          tenantId: Value(_tenantId!),
          orderNumber: Value(o.orderNumber),
          customerId: Value(o.customerId),
          deviceId: Value(o.deviceId),
          technicianId: Value(o.technicianId),
          status: Value(o.status),
          problemReported: Value(o.problemReported),
          diagnosis: Value(o.diagnosis),
          notes: Value(o.notes),
          laborCost: Value(o.laborCost),
          subtotal: Value(o.subtotal),
          tax: Value(o.tax),
          total: Value(o.total),
          warrantyDays: Value(o.warrantyDays),
          pdfUrl: Value(o.pdfUrl),
          deliveredAt: Value(o.deliveredAt),
          closedAt: Value(o.closedAt),
          synced: const Value(true),
        ));

        // Save order items
        for (final item in o.items) {
          await _db.upsertOrderItem(LocalOrderItemsCompanion(
            id: Value(item.id),
            orderId: Value(o.id),
            description: Value(item.description),
            qty: Value(item.qty),
            unitPrice: Value(item.unitPrice),
            total: Value(item.total),
            synced: const Value(true),
          ));
        }
      }
    } catch (_) {
      // Silently fail - we can try again later
    }
  }

  // --- Offline-first operations ---

  /// Create a customer locally and queue for sync
  Future<String> createCustomerOffline({
    required String tenantId,
    required String fullName,
    required String idNumber,
    required String phone,
    String? email,
  }) async {
    final id = _generateUuid();

    await _db.upsertCustomer(LocalCustomersCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      fullName: Value(fullName),
      idNumber: Value(idNumber),
      phone: Value(phone),
      email: Value(email),
      synced: const Value(false),
    ));

    await _db.addToSyncQueue(SyncQueueCompanion(
      entityType: const Value('customer'),
      entityId: Value(id),
      action: const Value('create'),
      payload: Value(jsonEncode({
        'fullName': fullName,
        'idNumber': idNumber,
        'phone': phone,
        'email': email,
      })),
    ));

    // Try immediate sync
    if (await isOnline) syncAll();

    return id;
  }

  /// Create an order locally and queue for sync
  Future<String> createOrderOffline({
    required String tenantId,
    required String customerId,
    required String deviceType,
    required String deviceBrand,
    required String deviceModel,
    required String problemReported,
    String? deviceSerial,
    String? deviceColor,
    List<String>? accessories,
  }) async {
    final orderId = _generateUuid();
    final deviceId = _generateUuid();
    final orderNumber = 'OFF-${DateTime.now().millisecondsSinceEpoch}';

    // Save device locally
    await _db.upsertDevice(LocalDevicesCompanion(
      id: Value(deviceId),
      tenantId: Value(tenantId),
      type: Value(deviceType),
      brand: Value(deviceBrand),
      model: Value(deviceModel),
      serial: Value(deviceSerial),
      color: Value(deviceColor),
      accessories: Value(accessories?.join(',') ?? ''),
      synced: const Value(false),
    ));

    // Save order locally
    await _db.upsertOrder(LocalOrdersCompanion(
      id: Value(orderId),
      tenantId: Value(tenantId),
      orderNumber: Value(orderNumber),
      customerId: Value(customerId),
      deviceId: Value(deviceId),
      status: const Value('received'),
      problemReported: Value(problemReported),
      synced: const Value(false),
    ));

    // Queue for sync
    await _db.addToSyncQueue(SyncQueueCompanion(
      entityType: const Value('order'),
      entityId: Value(orderId),
      action: const Value('create'),
      payload: Value(jsonEncode({
        'customerId': customerId,
        'deviceType': deviceType,
        'deviceBrand': deviceBrand,
        'deviceModel': deviceModel,
        'problemReported': problemReported,
        'deviceSerial': deviceSerial,
        'deviceColor': deviceColor,
        'accessories': accessories,
      })),
    ));

    if (await isOnline) syncAll();

    return orderId;
  }

  String _generateUuid() {
    // Simple UUID v4 generator without external dependency
    final now = DateTime.now().millisecondsSinceEpoch;
    return '${now.toRadixString(16)}-'
        '${(now ~/ 1000).toRadixString(16)}-'
        '4${(now % 0xFFF).toRadixString(16)}-'
        '${(0x8 + (now % 4)).toRadixString(16)}${(now % 0xFFF).toRadixString(16)}-'
        '${now.toRadixString(16)}${(now ~/ 100).toRadixString(16)}';
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
  }
}

enum SyncStatus {
  synced,
  syncing,
  offline,
  error,
}
