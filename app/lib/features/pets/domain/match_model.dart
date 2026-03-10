// The domain layer contains the core models of the application.
import 'package:paws_app/features/pets/domain/pet_model.dart';
import 'package:paws_app/features/user/domain/user_model.dart';

/// Represents a match between an adopter and a pet.
class Match {
  final int id;
  final int adopterId;
  final int petId;
  final String status;
  final String? message;
  final DateTime? createdAt;
  final int unreadCount;

  // Associated models, preloaded from the API.
  final Pet? pet;
  final User? adopter;

  Match({
    required this.id,
    required this.adopterId,
    required this.petId,
    required this.status,
    this.message,
    this.createdAt,
    this.unreadCount = 0,
    this.pet,
    this.adopter,
  });

  /// Creates a [Match] from a JSON map.
  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: _parseInt(json['id']),
      adopterId: _parseInt(json['adopter_id']),
      petId: _parseInt(json['pet_id']),
      status: json['status'] ?? 'pending',
      message: json['message'],
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      unreadCount: _parseInt(json['unread_count']),
      pet: json['pet'] != null ? Pet.fromJson(json['pet']) : null,
      adopter: json['adopter'] != null ? User.fromJson(json['adopter']) : null,
    );
  }

  // =========================================================================
  //  Status Helpers
  // =========================================================================

  bool get isChatActive => status == 'accepted';
  bool get isPetDeleted => status == 'pet_deleted';
  bool get isAdopterLeft => status == 'adopter_left';
  bool get isRescuerLeft => status == 'rescuer_left';
  bool get isCancelled => status == 'cancelled';
  bool get hasUnreadMessages => unreadCount > 0;

  /// Provides a user-friendly reason if the chat is no longer active.
  String get blockReason {
    switch (status) {
      case 'pet_deleted': return 'This pet has been removed.';
      case 'adopter_left': return 'The adopter has left the chat.';
      case 'rescuer_left': return 'The rescuer has left the chat.';
      case 'cancelled': return 'This chat has ended.';
      case 'rejected': return 'This request was rejected.';
      default: return '';
    }
  }

  // =========================================================================
  //  Private Helpers
  // =========================================================================

  /// Safely parses a value to an integer, handling null, double, and string inputs.
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      if (value.toLowerCase() == 'null' || value.isEmpty) return 0;
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
