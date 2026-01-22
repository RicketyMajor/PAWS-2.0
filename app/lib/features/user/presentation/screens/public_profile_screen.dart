import 'package:flutter/material.dart';
import '../../../../core/utils/image_helper.dart';
import '../../domain/user_model.dart';
import '../../../reviews/presentation/screens/user_reviews_screen.dart'; // <--- IMPORTAR

class PublicProfileScreen extends StatelessWidget {
  final User user;

  const PublicProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Perfil del Adoptante"),
        foregroundColor: Colors.black,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- ENCABEZADO ---
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: ImageHelper.getProvider(user.photoUrl),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // --- BADGE DE ROL ---
                  if (user.role == 'rescuer')
                    Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "Rescatista",
                        style: TextStyle(
                          color: Colors.purple,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // --- BOTÓN DE REPUTACIÓN (NUEVO) ---
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserReviewsScreen(
                            userId: user.id,
                            userName: user.name,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            user.reviewCount > 0
                                ? "${user.averageRating.toStringAsFixed(1)}/5 (${user.reviewCount} Op)"
                                : "Nuevo en PAWS",
                            style: TextStyle(
                              color: Colors.amber[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Colors.amber[900],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // --- CONTACTO Y BIO ---
            _SectionTitle(title: "Acerca de"),
            const SizedBox(height: 8),
            Text(
              user.bio.isNotEmpty ? user.bio : "Sin biografía.",
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            if (user.phone.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone, color: Color(0xFFE91E63)),
                title: Text(user.phone),
              ),

            const Divider(height: 40),

            // --- FICHA DE HOGAR ---
            _SectionTitle(title: "Hogar y Entorno"),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  label: _translate(user.housingType),
                  icon: Icons.home,
                  color: Colors.blue,
                ),
                _InfoChip(
                  label: _translate(user.housingOwnership),
                  icon: Icons.key,
                  color: Colors.orange,
                ),
                if (user.hasYard)
                  _InfoChip(
                    label: "Tiene Patio",
                    icon: Icons.grass,
                    color: Colors.green,
                  ),
                if (user.hasFence)
                  _InfoChip(
                    label: "Cerco Seguro",
                    icon: Icons.security,
                    color: Colors.green,
                  ),
                if (!user.hasYard)
                  _InfoChip(
                    label: "Sin Patio",
                    icon: Icons.block,
                    color: Colors.grey,
                  ),
              ],
            ),

            const Divider(height: 40),

            // --- ESTILO DE VIDA ---
            _SectionTitle(title: "Familia y Rutina"),
            const SizedBox(height: 12),
            _InfoRow(
              label: "Familia",
              value: _translate(user.familyComposition),
            ),
            _InfoRow(
              label: "Otras Mascotas",
              value: _translate(user.otherPets),
            ),
            _InfoRow(
              label: "Tiempo Libre",
              value: _translate(user.timeAvailability),
            ),
            _InfoRow(label: "Experiencia", value: _translate(user.experience)),
          ],
        ),
      ),
    );
  }

  String _translate(String val) {
    const map = {
      'House': 'Casa',
      'Apartment': 'Depto',
      'Parcel': 'Parcela',
      'Owned': 'Propia',
      'Rented': 'Arriendo',
      'Single': 'Vive Solo',
      'Couple': 'Pareja',
      'Family w/Kids': 'Familia c/Niños',
      'Seniors': 'Adultos Mayores',
      'None': 'Ninguna',
      'Dogs': 'Perros',
      'Cats': 'Gatos',
      'Both': 'Ambos',
      'Low': 'Poco',
      'Medium': 'Medio',
      'High': 'Mucho',
      'Beginner': 'Principiante',
      'Intermediate': 'Intermedio',
      'Expert': 'Experto',
    };
    return map[val] ?? val;
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final MaterialColor color;
  const _InfoChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color[800]),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color[900], fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
