import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/image_helper.dart';
import '../../data/reviews_repository.dart';
import '../../domain/review_model.dart';

/// A screen that displays a list of all reviews for a specific user.
class UserReviewsScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const UserReviewsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<UserReviewsScreen> createState() => _UserReviewsScreenState();
}

class _UserReviewsScreenState extends State<UserReviewsScreen> {
  late Future<List<Review>> _reviewsFuture;

  @override
  void initState() {
    super.initState();
    // Fetch the reviews when the screen is initialized.
    _reviewsFuture = context.read<ReviewsRepository>().getUserReviews(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Reviews for ${widget.userName}"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<List<Review>>(
        future: _reviewsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final reviews = snapshot.data ?? [];
          if (reviews.isEmpty) {
            return const Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.star_border, size: 60, color: Colors.grey),
                SizedBox(height: 16),
                Text("This user has no reviews yet."),
              ]),
            );
          }

          // Display the list of reviews.
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final review = reviews[index];
              return _buildReviewItem(review);
            },
          );
        },
      ),
    );
  }

  /// Builds a single item in the review list.
  Widget _buildReviewItem(Review review) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[200],
              backgroundImage: ImageHelper.getProvider(review.author?.photoUrl),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(review.author?.name ?? "Deleted User", style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(DateFormat.yMMMd().format(review.createdAt), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ]),
            ),
            _buildStaticStars(review.rating),
          ],
        ),
        if (review.comment.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(review.comment, style: const TextStyle(color: Colors.black87)),
        ],
      ],
    );
  }

  /// Builds a compact, non-interactive star rating display.
  Widget _buildStaticStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // Format rating to remove trailing ".0" (e.g., "4.0" -> "4").
          rating.toString().replaceAll(RegExp(r"([.]*0)(?!.*\d)"), ""),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFC107)),
        ),
        const Icon(Icons.star, size: 16, color: Color(0xFFFFC107)),
      ],
    );
  }
}
