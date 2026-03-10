// The presentation layer contains the BLoCs (business logic), screens (UI), and widgets.
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/auth_repository.dart';

// =========================================================================
// Events
// =========================================================================

/// The events that the [LoginBloc] can process.
abstract class LoginEvent extends Equatable {
  const LoginEvent();
  @override
  List<Object> get props => [];
}

/// Dispatched when the user presses the login button.
class LoginButtonPressed extends LoginEvent {
  final String email;
  final String password;
  final bool rememberMe;

  const LoginButtonPressed({
    required this.email,
    required this.password,
    required this.rememberMe,
  });

  @override
  List<Object> get props => [email, password, rememberMe];
}

// =========================================================================
// States
// =========================================================================

/// The states that the [LoginBloc] can be in.
abstract class LoginState extends Equatable {
  const LoginState();
  @override
  List<Object> get props => [];
}

/// The initial state.
class LoginInitial extends LoginState {}

/// State while the login request is in progress.
class LoginLoading extends LoginState {}

/// State for a successful login.
class LoginSuccess extends LoginState {}

/// State for a failed login.
class LoginFailure extends LoginState {
  final String error;
  const LoginFailure({required this.error});
  @override
  List<Object> get props => [error];
}

// =========================================================================
// BLoC
// =========================================================================

/// Manages the business logic for the login screen.
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final AuthRepository authRepository;

  LoginBloc({required this.authRepository}) : super(LoginInitial()) {
    on<LoginButtonPressed>((event, emit) async {
      emit(LoginLoading());
      try {
        // Pass the rememberMe flag to the repository.
        await authRepository.login(
          event.email,
          event.password,
          rememberMe: event.rememberMe,
        );
        emit(LoginSuccess());
      } catch (e) {
        // Clean up the exception message before showing it to the user.
        emit(LoginFailure(error: e.toString().replaceAll("Exception: ", "")));
      }
    });
  }
}
