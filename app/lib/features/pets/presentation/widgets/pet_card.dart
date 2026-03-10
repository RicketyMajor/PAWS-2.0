// The presentation layer contains the BLoCs (business logic), screens (UI), and widgets.
import 'package:flutter/material.dart';
import '../../../../core/utils/image_helper.dart';
import '../../domain/pet_model.dart';

/// A card widget to display a summary of a pet's profile, used in the swipe deck.
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
          // --- Image and Owner Section (using a Stack) ---
          Expanded(
            child: Stack(
              children: [
                // 1. Pet's main photo
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: ImageHelper.getImage(pet.imageUrl, width: double.infinity, fit: BoxFit.cover),
                  ),
                ),

                // 2. Gradient overlay for text visibility
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                      ),
                    ),
                  ),
                ),

                // 3. Owner (Rescuer) information
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                        child: CircleAvatar(radius: 14, backgroundColor: Colors.grey[300], backgroundImage: ImageHelper.getProvider(pet.ownerPhotoUrl)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        pet.ownerName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- Pet Information Section ---
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
                        "${pet.name}, ${pet.age} years",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Species indicator (Dog/Cat)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: pet.type == 'Dog' ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(pet.type == 'Dog' ? Icons.pets : Icons.cruelty_free, color: pet.type == 'Dog' ? Colors.blue : Colors.orange, size: 16),
                        const SizedBox(width: 4),
                        Text(pet.type, style: TextStyle(color: pet.type == 'Dog' ? Colors.blue : Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                      ]),
                    ),
                  ],
                ),
                Text(pet.breed, style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text(pet.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 12),
                
                // Compatibility and lifestyle tags
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (pet.goodWithKids) _buildTag("Good with kids", Colors.greenAccent),
                    if (pet.requiresYard) _buildTag("Requires yard", Colors.orangeAccent),
                    if (pet.goodWithDogs) _buildTag("Good with dogs", Colors.blueAccent),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A helper widget to build a styled tag chip.
  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color.withOpacity(0.8), fontWeight: FontWeight.bold)),
    );
  }
}
