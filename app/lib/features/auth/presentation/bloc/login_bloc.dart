import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/auth_repository.dart';

// --- EVENTOS ---
abstract class LoginEvent extends Equatable {
  const LoginEvent();
  @override
  List<Object> get props => [];
}

class LoginButtonPressed extends LoginEvent {
  final String email;
  final String password;
  final bool rememberMe; // <--- NUEVO CAMPO

  const LoginButtonPressed({
    required this.email,
    required this.password,
    required this.rememberMe,
  });

  @override
  List<Object> get props => [email, password, rememberMe];
}

// --- ESTADOS ---
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
      emit(LoginLoading());
      try {
        // Pasamos el rememberMe al repositorio
        await authRepository.login(
          event.email,
          event.password,
          rememberMe: event.rememberMe,
        );
        emit(LoginSuccess());
      } catch (e) {
        emit(LoginFailure(error: e.toString().replaceAll("Exception: ", "")));
      }
    });
  }
}
