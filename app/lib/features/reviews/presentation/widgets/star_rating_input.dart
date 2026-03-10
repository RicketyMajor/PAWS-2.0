import 'package:flutter/material.dart';

/// A widget for inputting a star rating, allowing for half-star increments.
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
    this.color = const Color(0xFFFFC107), // Amber
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;

        // Determine which icon to show (full, half, or empty star).
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
            // "Letterboxd-style" rating logic:
            // - Tapping a star that is already selected as a full value (e.g., 4.0)
            //   will decrease it to a half value (3.5).
            // - Tapping any other star will set the rating to that star's full value.
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
