import 'package:flutter/material.dart';

class RescuerHomePlaceholder extends StatelessWidget {
  const RescuerHomePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Panel de Rescatista")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.volunteer_activism, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              "¡Hola Rescatista!",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text("Aquí podrás gestionar tus mascotas."),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // TODO: Implementar Logout
                Navigator.of(context).pop();
              },
              child: const Text("Cerrar Sesión (Demo)"),
            ),
          ],
        ),
      ),
    );
  }
}
