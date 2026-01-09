import 'package:paws_app/features/pets/domain/pet_model.dart';
import 'package:paws_app/features/user/domain/user_model.dart';

class Match {
  final int id;
  final int adopterId;
  final int petId;
  final String
  status; // 'pending', 'accepted', 'rejected', 'adopter_left', 'rescuer_left', 'pet_deleted'
  final String? message;
  final DateTime? createdAt;

  // Relaciones (pueden venir null dependiendo del endpoint)
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
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      adopterId: json['adopter_id'] is int
          ? json['adopter_id']
          : int.parse(json['adopter_id'].toString()),
      petId: json['pet_id'] is int
          ? json['pet_id']
          : int.parse(json['pet_id'].toString()),
      status: json['status'] ?? 'pending',
      message: json['message'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,

      // Mapeo seguro de objetos anidados
      pet: json['pet'] != null ? Pet.fromJson(json['pet']) : null,
      // Nota: Asegúrate de tener un User.fromJson en tu user_model.dart,
      // si no, puedes dejar esto como null o mapearlo manualmente por ahora.
      adopter: json['adopter'] != null ? User.fromJson(json['adopter']) : null,
    );
  }

  // --- GETTERS INTELIGENTES PARA LA UI ---

  /// Indica si el chat está activo y se puede escribir.
  bool get isChatActive => status == 'accepted';

  /// Indica si la mascota fue eliminada.
  bool get isPetDeleted => status == 'pet_deleted';

  /// Indica si el otro usuario abandonó (lógica depende de quién soy yo, se valida en UI/Bloc).
  bool get isAdopterLeft => status == 'adopter_left';
  bool get isRescuerLeft => status == 'rescuer_left';

  /// Mensaje amigable para mostrar por qué está bloqueado
  String get blockReason {
    switch (status) {
      case 'pet_deleted':
        return 'Esta publicación ha sido eliminada.';
      case 'adopter_left':
        return 'El adoptante ha abandonado el chat.';
      case 'rescuer_left':
        return 'El rescatista ha abandonado el chat.';
      case 'rejected':
        return 'Esta solicitud fue rechazada.';
      case 'pending':
        return 'Solicitud pendiente de aceptación.';
      default:
        return '';
    }
  }
}
