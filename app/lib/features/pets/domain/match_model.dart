import 'package:paws_app/features/pets/domain/pet_model.dart';
import 'package:paws_app/features/user/domain/user_model.dart';

class Match {
  final int id;
  final int adopterId;
  final int petId;
  final String status;
  final String? message;
  final DateTime? createdAt;

  final Pet? pet;
  final User? adopter;

  Match({
    required this.id,
    required this.adopterId,
    required this.petId,
    required this.status,
    this.message,
    this.createdAt,
    this.pet,
    this.adopter,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      // Parseo seguro de enteros para evitar crash con "null"
      id: _parseInt(json['id']),
      adopterId: _parseInt(json['adopter_id']),
      petId: _parseInt(json['pet_id']),

      status: json['status'] ?? 'pending',
      message: json['message'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,

      pet: json['pet'] != null ? Pet.fromJson(json['pet']) : null,
      adopter: json['adopter'] != null ? User.fromJson(json['adopter']) : null,
    );
  }

  // --- Helpers de Estado ---
  bool get isChatActive => status == 'accepted';
  bool get isPetDeleted => status == 'pet_deleted';
  bool get isAdopterLeft => status == 'adopter_left';
  bool get isRescuerLeft => status == 'rescuer_left';
  bool get isCancelled => status == 'cancelled';

  String get blockReason {
    switch (status) {
      case 'pet_deleted':
        return 'Esta publicación ha sido eliminada.';
      case 'adopter_left':
        return 'El adoptante ha abandonado el chat.';
      case 'rescuer_left':
        return 'El rescatista ha abandonado el chat.';
      case 'cancelled':
        return 'Chat finalizado.';
      case 'rejected':
        return 'Solicitud rechazada.';
      default:
        return '';
    }
  }

  // --- Helper Privado Seguro ---
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
