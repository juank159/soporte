import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// --- Tables ---

class LocalCustomers extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get fullName => text()();
  TextColumn get idNumber => text()();
  TextColumn get phone => text()();
  TextColumn get email => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalDevices extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get type => text()();
  TextColumn get brand => text()();
  TextColumn get model => text()();
  TextColumn get serial => text().nullable()();
  TextColumn get imei => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get accessories => text().nullable()(); // JSON array as string
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalOrders extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get orderNumber => text()();
  TextColumn get customerId => text()();
  TextColumn get deviceId => text()();
  TextColumn get technicianId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('received'))();
  TextColumn get problemReported => text()();
  TextColumn get diagnosis => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get laborCost => real().withDefault(const Constant(0))();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  IntColumn get warrantyDays => integer().withDefault(const Constant(30))();
  TextColumn get pdfUrl => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalOrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  TextColumn get description => text()();
  IntColumn get qty => integer().withDefault(const Constant(1))();
  RealColumn get unitPrice => real()();
  RealColumn get total => real()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSignatures extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  TextColumn get signerType => text()(); // 'customer' or 'technician'
  TextColumn get signerName => text()();
  TextColumn get svgPath => text().nullable()();
  TextColumn get pngData => text().nullable()(); // base64
  TextColumn get deviceInfo => text().nullable()();
  TextColumn get ipAddress => text().nullable()();
  DateTimeColumn get signedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalOrderPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  TextColumn get photoPath => text()(); // Local file path
  TextColumn get description => text().nullable()();
  TextColumn get takenAtStage => text().withDefault(const Constant('reception'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // 'customer', 'order', etc.
  TextColumn get entityId => text()();
  TextColumn get action => text()(); // 'create', 'update', 'delete'
  TextColumn get payload => text()(); // JSON
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

@DriftDatabase(tables: [
  LocalCustomers,
  LocalDevices,
  LocalOrders,
  LocalOrderItems,
  LocalSignatures,
  LocalOrderPhotos,
  SyncQueue,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'soporte_local');
  }

  // --- Customer operations ---

  Future<List<LocalCustomer>> getAllCustomers(String tenantId) =>
      (select(localCustomers)..where((c) => c.tenantId.equals(tenantId)))
          .get();

  Future<List<LocalCustomer>> searchCustomers(
      String tenantId, String query) =>
      (select(localCustomers)
            ..where((c) =>
                c.tenantId.equals(tenantId) &
                (c.fullName.like('%$query%') |
                    c.idNumber.like('%$query%') |
                    c.phone.like('%$query%'))))
          .get();

  Future<void> upsertCustomer(LocalCustomersCompanion customer) =>
      into(localCustomers).insertOnConflictUpdate(customer);

  // --- Order operations ---

  Future<List<LocalOrder>> getAllOrders(String tenantId, {String? status}) {
    final query = select(localOrders)
      ..where((o) => o.tenantId.equals(tenantId));
    if (status != null) {
      query.where((o) => o.status.equals(status));
    }
    query.orderBy([(o) => OrderingTerm.desc(o.createdAt)]);
    return query.get();
  }

  Future<LocalOrder?> getOrder(String id) =>
      (select(localOrders)..where((o) => o.id.equals(id))).getSingleOrNull();

  Future<void> upsertOrder(LocalOrdersCompanion order) =>
      into(localOrders).insertOnConflictUpdate(order);

  // --- Device operations ---

  Future<void> upsertDevice(LocalDevicesCompanion device) =>
      into(localDevices).insertOnConflictUpdate(device);

  Future<LocalDevice?> getDevice(String id) =>
      (select(localDevices)..where((d) => d.id.equals(id))).getSingleOrNull();

  // --- Order items ---

  Future<List<LocalOrderItem>> getOrderItems(String orderId) =>
      (select(localOrderItems)..where((i) => i.orderId.equals(orderId)))
          .get();

  Future<void> upsertOrderItem(LocalOrderItemsCompanion item) =>
      into(localOrderItems).insertOnConflictUpdate(item);

  // --- Photos ---

  Future<List<LocalOrderPhoto>> getOrderPhotos(String orderId) =>
      (select(localOrderPhotos)..where((p) => p.orderId.equals(orderId)))
          .get();

  Future<void> insertPhoto(LocalOrderPhotosCompanion photo) =>
      into(localOrderPhotos).insertOnConflictUpdate(photo);

  // --- Signatures ---

  Future<List<LocalSignature>> getOrderSignatures(String orderId) =>
      (select(localSignatures)..where((s) => s.orderId.equals(orderId)))
          .get();

  Future<void> upsertSignature(LocalSignaturesCompanion sig) =>
      into(localSignatures).insertOnConflictUpdate(sig);

  // --- Sync Queue ---

  Future<void> addToSyncQueue(SyncQueueCompanion entry) =>
      into(syncQueue).insert(entry);

  Future<List<SyncQueueData>> getPendingSyncItems() =>
      (select(syncQueue)
            ..where((s) => s.retryCount.isSmallerThanValue(5))
            ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
          .get();

  Future<void> deleteSyncItem(int id) =>
      (delete(syncQueue)..where((s) => s.id.equals(id))).go();

  Future<void> incrementRetry(int id, String error) =>
      (update(syncQueue)..where((s) => s.id.equals(id))).write(
        SyncQueueCompanion(
          retryCount: const Value(0), // Will be overridden
          lastError: Value(error),
        ),
      );

  // --- Unsynced counts ---

  Future<int> getUnsyncedCount() async {
    final orders = await (select(localOrders)
          ..where((o) => o.synced.equals(false)))
        .get();
    final customers = await (select(localCustomers)
          ..where((c) => c.synced.equals(false)))
        .get();
    return orders.length + customers.length;
  }

  // --- Cleanup ---

  Future<void> clearAllData() async {
    await delete(localOrderPhotos).go();
    await delete(localSignatures).go();
    await delete(localOrderItems).go();
    await delete(localOrders).go();
    await delete(localDevices).go();
    await delete(localCustomers).go();
    await delete(syncQueue).go();
  }
}
