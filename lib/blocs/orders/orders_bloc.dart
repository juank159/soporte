import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  final int page;
  final bool loadMore; // true = append to existing list
  OrdersLoadRequested({this.statusFilter, this.search, this.dateFrom, this.dateTo, this.page = 1, this.loadMore = false});

  @override
  List<Object?> get props => [statusFilter, search, dateFrom, dateTo, page, loadMore];
}

/// Data for a single equipment in a multi-device order
class EquipmentData {
  final String deviceType;
  final String deviceBrand;
  final String deviceModel;
  final String problemReported;
  final String? deviceSerial;
  final String? deviceColor;
  final List<String>? accessories;
  final List<File>? photos;
  final String? technicianId;

  EquipmentData({
    required this.deviceType,
    required this.deviceBrand,
    required this.deviceModel,
    required this.problemReported,
    this.deviceSerial,
    this.deviceColor,
    this.accessories,
    this.photos,
    this.technicianId,
  });
}

class OrderCreateRequested extends OrdersEvent {
  final String customerId;
  final List<EquipmentData> equipments;
  final List<File>? photos; // photos for single device (backward compat)

  OrderCreateRequested({
    required this.customerId,
    required this.equipments,
    this.photos,
  });

  @override
  List<Object?> get props => [customerId, equipments.length];
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
  final int total;
  final int page;
  final int totalPages;
  final bool hasMore;
  OrdersLoaded(this.orders, {this.total = 0, this.page = 1, this.totalPages = 1, this.hasMore = false});

  @override
  List<Object?> get props => [orders.length, page];
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
    // Only show full loading spinner on first page
    if (!event.loadMore) emit(OrdersLoading());
    try {
      final result = await _orderService.getOrders(
        status: event.statusFilter,
        search: event.search,
        dateFrom: event.dateFrom,
        dateTo: event.dateTo,
        page: event.page,
      );
      List<ServiceOrder> allOrders;
      if (event.loadMore && state is OrdersLoaded) {
        allOrders = [...(state as OrdersLoaded).orders, ...result.orders];
      } else {
        allOrders = result.orders;
      }
      emit(OrdersLoaded(
        allOrders,
        total: result.total,
        page: result.page,
        totalPages: result.totalPages,
        hasMore: result.page < result.totalPages,
      ));
    } catch (e) {
      debugPrint('LOAD ORDERS ERROR: $e');
      emit(OrdersError('Error al cargar ordenes: $e'));
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
        equipments: event.equipments,
        photos: event.photos,
      );
      emit(OrderCreated(order));
    } catch (e) {
      String errorMsg = '$e';
      if (e is DioException && e.response != null) {
        errorMsg = '${e.response?.statusCode}: ${e.response?.data}';
      }
      debugPrint('CREATE ORDER ERROR: $errorMsg');
      emit(OrdersError('Error: $errorMsg'));
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
