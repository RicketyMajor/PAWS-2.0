import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/auth_repository.dart';

// --- EVENTOS (Lo que sucede) ---
abstract class LoginEvent extends Equatable {
  const LoginEvent();
  @override
  List<Object> get props => [];
}

class LoginButtonPressed extends LoginEvent {
  final String email;
  final String password;

  const LoginButtonPressed({required this.email, required this.password});

  @override
  List<Object> get props => [email, password];
}

// --- ESTADOS (Cómo se ve la UI) ---
abstract class LoginState extends Equatable {
  const LoginState();
  @override
  List<Object> get props => [];
}

class LoginInitial extends LoginState {}

class LoginLoading extends LoginState {}

class LoginSuccess extends LoginState {}

class LoginFailure extends LoginState {
  final String error;
  const LoginFailure({required this.error});
  @override
  List<Object> get props => [error];
}

// --- LÓGICA (BLoC) ---
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final AuthRepository authRepository;

  LoginBloc({required this.authRepository}) : super(LoginInitial()) {
    on<LoginButtonPressed>((event, emit) async {
      emit(LoginLoading()); // 1. Mostramos ruedita de carga
      try {
        // 2. Intentamos login
        await authRepository.login(event.email, event.password);
        // 3. Si no explota, éxito
        emit(LoginSuccess());
      } catch (e) {
        // 4. Si falla, mostramos error
        emit(LoginFailure(error: e.toString().replaceAll("Exception: ", "")));
      }
    });
  }
}
