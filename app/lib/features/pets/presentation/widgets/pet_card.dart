import 'package:flutter/material.dart';
import '../../../../core/utils/image_helper.dart'; // <--- El salvavidas
import '../../domain/pet_model.dart';

class PetCard extends StatelessWidget {
  final Pet pet;

  const PetCard({super.key, required this.pet});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- FOTO DE LA MASCOTA ---
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              // Usamos ImageHelper para arreglar URLs y mostrar placeholders si falla
              child: ImageHelper.getImage(
                pet.imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),

          // --- INFORMACIÓN ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "${pet.name}, ${pet.age} años",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Chip de Sexo o Tipo (Opcional, si tu modelo lo tuviera)
                    Icon(
                      pet.type == 'Dog' ? Icons.pets : Icons.cruelty_free,
                      color: Colors.grey,
                    ),
                  ],
                ),
                Text(
                  pet.breed,
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  pet.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 12),

                // --- ETIQUETAS (TAGS) ---
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (pet.goodWithKids)
                      _buildTag("Apto niños", Colors.greenAccent),
                    if (pet.requiresYard)
                      _buildTag("Patio", Colors.orangeAccent),
                    if (pet.goodWithDogs)
                      _buildTag("Apto perros", Colors.blueAccent),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color.withOpacity(0.8),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
