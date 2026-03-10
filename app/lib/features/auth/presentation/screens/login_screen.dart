import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../data/auth_repository.dart';
import '../bloc/login_bloc.dart';
import 'register_screen.dart';
import 'password_recovery_screen.dart';
import '../../../../core/presentation/main_layout_screen.dart';
import '../../../admin/presentation/screens/admin_dashboard_screen.dart';
import '../../../../features/user/data/user_repository.dart';
import '../../../../features/security/presentation/screens/blacklist_search_screen.dart';

/// The main login screen widget. It provides the [LoginBloc] to its child, [_LoginForm].
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginBloc(authRepository: context.read<AuthRepository>()),
      child: const _LoginForm(),
    );
  }
}

/// The stateful widget containing the actual form and logic for the login screen.
class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _rememberMe = false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginBloc, LoginState>(
      // Listens for state changes in the LoginBloc to perform actions like navigation or showing snackbars.
      listener: (context, state) async {
        if (state is LoginFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error), backgroundColor: Colors.red),
          );
        } else if (state is LoginSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Welcome!'), backgroundColor: Colors.green),
          );

          // After successful login, try to get the FCM token and save it to the backend.
          try {
            String? fcmToken = await FirebaseMessaging.instance.getToken();
            if (fcmToken != null && mounted) {
              await context.read<UserRepository>().saveDeviceToken(fcmToken);
            }
          } catch (e) {
            print("Error setting up notifications: $e");
          }

          if (!mounted) return;

          // Decode the token to determine the user's role and navigate accordingly.
          final token = await context.read<AuthRepository>().getToken();
          if (token != null) {
            Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
            String role = decodedToken['role'] ?? 'adopter';

            if (role == 'admin') {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
                (route) => false,
              );
            } else {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => MainLayoutScreen(role: role)),
                (route) => false,
              );
            }
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Header ---
                    const Icon(Icons.pets, size: 80, color: Color(0xFFE91E63)),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome to PAWS',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFE91E63),
                          ),
                    ),
                    const SizedBox(height: 48),

                    // --- Form Fields ---
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // --- Remember Me Checkbox ---
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v!),
                          activeColor: const Color(0xFFE91E63),
                        ),
                        const Text("Remember me"),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // --- Login Button ---
                    BlocBuilder<LoginBloc, LoginState>(
                      builder: (context, state) {
                        if (state is LoginLoading) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        return FilledButton(
                          onPressed: () {
                            // Dispatch the event to the BLoC with form data.
                            context.read<LoginBloc>().add(
                                  LoginButtonPressed(
                                    email: _emailController.text,
                                    password: _passwordController.text,
                                    rememberMe: _rememberMe,
                                  ),
                                );
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: const Color(0xFFE91E63),
                          ),
                          child: const Text('SIGN IN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),

                    // --- Other Actions ---
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen())),
                      child: const Text('No account? Register here'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PasswordRecoveryScreen())),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                      child: const Text("Forgot your password?"),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BlacklistSearchScreen())),
                      icon: const Icon(Icons.shield_outlined, color: Colors.blueGrey),
                      label: const Text("Public Blacklist Search", style: TextStyle(color: Colors.blueGrey)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blueGrey)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
