import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/customer.dart';
import '../../services/customer_service.dart';

// Events
abstract class CustomersEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class CustomersLoadRequested extends CustomersEvent {
  final String? search;
  CustomersLoadRequested({this.search});

  @override
  List<Object?> get props => [search];
}

class CustomerCreateRequested extends CustomersEvent {
  final String fullName;
  final String idNumber;
  final String phone;
  final String? email;

  CustomerCreateRequested({
    required this.fullName,
    required this.idNumber,
    required this.phone,
    this.email,
  });

  @override
  List<Object?> get props => [fullName, idNumber, phone];
}

// States
abstract class CustomersState extends Equatable {
  @override
  List<Object?> get props => [];
}

class CustomersInitial extends CustomersState {}

class CustomersLoading extends CustomersState {}

class CustomersLoaded extends CustomersState {
  final List<Customer> customers;
  CustomersLoaded(this.customers);

  @override
  List<Object?> get props => [customers.length];
}

class CustomerCreated extends CustomersState {
  final Customer customer;
  CustomerCreated(this.customer);

  @override
  List<Object?> get props => [customer.id];
}

class CustomersError extends CustomersState {
  final String message;
  CustomersError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class CustomersBloc extends Bloc<CustomersEvent, CustomersState> {
  final CustomerService _customerService = CustomerService();

  CustomersBloc() : super(CustomersInitial()) {
    on<CustomersLoadRequested>(_onLoadRequested);
    on<CustomerCreateRequested>(_onCreateRequested);
  }

  Future<void> _onLoadRequested(
    CustomersLoadRequested event,
    Emitter<CustomersState> emit,
  ) async {
    emit(CustomersLoading());
    try {
      final customers =
          await _customerService.getCustomers(search: event.search);
      emit(CustomersLoaded(customers));
    } catch (e) {
      emit(CustomersError('Error al cargar clientes'));
    }
  }

  Future<void> _onCreateRequested(
    CustomerCreateRequested event,
    Emitter<CustomersState> emit,
  ) async {
    emit(CustomersLoading());
    try {
      final customer = await _customerService.createCustomer(
        fullName: event.fullName,
        idNumber: event.idNumber,
        phone: event.phone,
        email: event.email,
      );
      emit(CustomerCreated(customer));
    } catch (e) {
      emit(CustomersError('Error al crear cliente'));
    }
  }
}
