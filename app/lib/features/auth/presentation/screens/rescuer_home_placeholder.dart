import 'package:flutter/material.dart';

/// A placeholder screen for the Rescuer dashboard.
///
/// This widget is likely used as a temporary UI before the full
/// rescuer functionality is implemented.
class RescuerHomePlaceholder extends StatelessWidget {
  const RescuerHomePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rescuer Panel")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.volunteer_activism, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              "Hello, Rescuer!",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text("Here you will be able to manage your pets."),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // TODO: Implement actual logout logic.
                Navigator.of(context).pop();
              },
              child: const Text("Sign Out (Demo)"),
            ),
          ],
        ),
      ),
    );
  }
}
