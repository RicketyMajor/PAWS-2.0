import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../data/auth_repository.dart';
import '../bloc/login_bloc.dart';
import 'register_screen.dart';
import 'password_recovery_screen.dart';
import '../../../../core/presentation/main_layout_screen.dart';
import '../../../admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../../features/user/data/user_repository.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          LoginBloc(authRepository: context.read<AuthRepository>()),
      child: const _LoginForm(),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _rememberMe = false; // Estado del checkbox

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginBloc, LoginState>(
      listener: (context, state) async {
        if (state is LoginFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error), backgroundColor: Colors.red),
          );
        } else if (state is LoginSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Bienvenido!'),
              backgroundColor: Colors.green,
            ),
          );

          try {
            String? fcmToken = await FirebaseMessaging.instance.getToken();
            if (fcmToken != null && mounted) {
              await context.read<UserRepository>().saveDeviceToken(fcmToken);
            }
          } catch (e) {
            print("Error configurando notificaciones: $e");
          }

          if (!mounted) return;

          final authRepo = context.read<AuthRepository>();
          final token = await authRepo.getToken();

          if (token != null) {
            Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
            String role = decodedToken['role'] ?? 'adopter';

            if (role == 'admin') {
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminDashboardScreen(),
                  ),
                  (route) => false,
                );
              }
            } else {
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MainLayoutScreen(role: role),
                  ),
                  (route) => false,
                );
              }
            }
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SingleChildScrollView(
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.pets,
                            size: 80,
                            color: Color(0xFFE91E63),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Bienvenido a PAWS',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFE91E63),
                                ),
                          ),
                          const SizedBox(height: 48),
                          TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Correo Electrónico',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),
                          // --- CHECKBOX RECÚERDAME ---
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v!),
                                activeColor: const Color(0xFFE91E63),
                              ),
                              const Text("Recordar usuario"),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // --- BOTÓN INICIAR SESIÓN (MODIFICADO) ---
                          BlocBuilder<LoginBloc, LoginState>(
                            builder: (context, state) {
                              if (state is LoginLoading) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return FilledButton(
                                onPressed: () {
                                  // AQUÍ ESTÁ EL CAMBIO: Enviamos rememberMe al Bloc
                                  context.read<LoginBloc>().add(
                                    LoginButtonPressed(
                                      email: _emailController.text,
                                      password: _passwordController.text,
                                      rememberMe: _rememberMe,
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  backgroundColor: const Color(0xFFE91E63),
                                ),
                                child: const Text(
                                  'INICIAR SESIÓN',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),

                          // Botón Registro
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              '¿No tienes cuenta? Regístrate aquí',
                            ),
                          ),

                          // Botón Recuperar
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PasswordRecoveryScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey,
                            ),
                            child: const Text("¿Olvidaste tu contraseña?"),
                          ),
                          const SizedBox(height: 20), // Espacio final
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
