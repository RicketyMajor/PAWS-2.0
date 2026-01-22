import 'package:flutter/material.dart';

class StarRatingInput extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final double size;
  final Color color;

  const StarRatingInput({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 36,
    this.color = const Color(0xFFFFC107), // Amber/Gold
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        // Valor de la estrella actual (1, 2, 3, 4, 5)
        final starValue = index + 1;

        IconData iconData;
        if (rating >= starValue) {
          iconData = Icons.star;
        } else if (rating >= starValue - 0.5) {
          iconData = Icons.star_half;
        } else {
          iconData = Icons.star_border;
        }

        return GestureDetector(
          onTap: () {
            // LÓGICA LETTERBOXD:
            // Si toco la estrella que ya está llena (ej: 4.0 y toco la 4ta), baja a media (3.5).
            // Si toco una estrella media (3.5 y toco la 4ta), sube a llena (4.0).
            // Si toco cualquier otra estrella, salta a ese valor lleno.

            double newRating;
            if (rating == starValue.toDouble()) {
              newRating = starValue - 0.5;
            } else {
              newRating = starValue.toDouble();
            }
            onChanged(newRating);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Icon(iconData, color: color, size: size),
          ),
        );
      }),
    );
  }
}
