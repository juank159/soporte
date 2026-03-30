import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/service_order.dart';
import '../../services/order_service.dart';

// Events
abstract class OrdersEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class OrdersLoadRequested extends OrdersEvent {
  final String? statusFilter;
  final String? search;
  final String? dateFrom;
  final String? dateTo;
  OrdersLoadRequested({this.statusFilter, this.search, this.dateFrom, this.dateTo});

  @override
  List<Object?> get props => [statusFilter, search, dateFrom, dateTo];
}

class OrderCreateRequested extends OrdersEvent {
  final String customerId;
  final String deviceType;
  final String deviceBrand;
  final String deviceModel;
  final String problemReported;
  final String? deviceSerial;
  final String? deviceImei;
  final String? deviceColor;
  final List<String>? accessories;
  final List<File>? photos;

  OrderCreateRequested({
    required this.customerId,
    required this.deviceType,
    required this.deviceBrand,
    required this.deviceModel,
    required this.problemReported,
    this.deviceSerial,
    this.deviceImei,
    this.deviceColor,
    this.accessories,
    this.photos,
  });

  @override
  List<Object?> get props => [customerId, deviceType, deviceBrand];
}

class OrderStatusUpdateRequested extends OrdersEvent {
  final String orderId;
  final String status;
  final String? notes;

  OrderStatusUpdateRequested({
    required this.orderId,
    required this.status,
    this.notes,
  });

  @override
  List<Object?> get props => [orderId, status];
}

// States
abstract class OrdersState extends Equatable {
  @override
  List<Object?> get props => [];
}

class OrdersInitial extends OrdersState {}

class OrdersLoading extends OrdersState {}

class OrdersLoaded extends OrdersState {
  final List<ServiceOrder> orders;
  OrdersLoaded(this.orders);

  @override
  List<Object?> get props => [orders.length];
}

class OrderCreated extends OrdersState {
  final ServiceOrder order;
  OrderCreated(this.order);

  @override
  List<Object?> get props => [order.id];
}

class OrdersError extends OrdersState {
  final String message;
  OrdersError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class OrdersBloc extends Bloc<OrdersEvent, OrdersState> {
  final OrderService _orderService = OrderService();

  OrdersBloc() : super(OrdersInitial()) {
    on<OrdersLoadRequested>(_onLoadRequested);
    on<OrderCreateRequested>(_onCreateRequested);
    on<OrderStatusUpdateRequested>(_onStatusUpdateRequested);
  }

  Future<void> _onLoadRequested(
    OrdersLoadRequested event,
    Emitter<OrdersState> emit,
  ) async {
    emit(OrdersLoading());
    try {
      final orders = await _orderService.getOrders(
          status: event.statusFilter,
          search: event.search,
          dateFrom: event.dateFrom,
          dateTo: event.dateTo);
      emit(OrdersLoaded(orders));
    } catch (e) {
      emit(OrdersError('Error al cargar órdenes'));
    }
  }

  Future<void> _onCreateRequested(
    OrderCreateRequested event,
    Emitter<OrdersState> emit,
  ) async {
    emit(OrdersLoading());
    try {
      final order = await _orderService.createOrder(
        customerId: event.customerId,
        deviceType: event.deviceType,
        deviceBrand: event.deviceBrand,
        deviceModel: event.deviceModel,
        problemReported: event.problemReported,
        deviceSerial: event.deviceSerial,
        deviceImei: event.deviceImei,
        deviceColor: event.deviceColor,
        accessories: event.accessories,
        photos: event.photos,
      );
      emit(OrderCreated(order));
    } catch (e) {
      emit(OrdersError('Error al crear la orden'));
    }
  }

  Future<void> _onStatusUpdateRequested(
    OrderStatusUpdateRequested event,
    Emitter<OrdersState> emit,
  ) async {
    try {
      await _orderService.updateStatus(event.orderId, event.status,
          notes: event.notes);
      add(OrdersLoadRequested());
    } catch (e) {
      emit(OrdersError('Error al actualizar estado'));
    }
  }
}
