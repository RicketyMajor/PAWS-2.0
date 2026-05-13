import '../../user/domain/user_model.dart';

class Review {
  final int id;
  final int matchId;
  final int authorId;
  final int targetId;
  final double rating;
  final String comment;
  final DateTime createdAt;
  final User? author;

  Review({
    required this.id,
    required this.matchId,
    required this.authorId,
    required this.targetId,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.author,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] ?? 0,
      matchId: json['match_id'] ?? 0,
      authorId: json['author_id'] ?? 0,
      targetId: json['target_id'] ?? 0,
      rating: (json['rating'] ?? 0).toDouble(), // Aseguramos double
      comment: json['comment'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      author: json['author'] != null ? User.fromJson(json['author']) : null,
    );
  }
}
