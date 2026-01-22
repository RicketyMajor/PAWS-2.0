class User {
  final int id;
  final String name;
  final String email;
  final String photoUrl;
  final String bio;
  final String phone;
  final String role;

  // --- REPUTACIÓN (NUEVO) ---
  final double averageRating;
  final int reviewCount;

  // --- DATOS DE VIVIENDA ---
  final String housingType;
  final String housingOwnership;
  final bool hasYard;
  final bool hasFence;

  // --- ESTILO DE VIDA ---
  final String familyComposition;
  final String otherPets;
  final String timeAvailability;
  final String experience;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.bio,
    required this.phone,
    required this.role,

    // Valores por defecto para reputación
    this.averageRating = 0.0,
    this.reviewCount = 0,

    this.housingType = 'House',
    this.housingOwnership = 'Owned',
    this.hasYard = false,
    this.hasFence = false,
    this.familyComposition = 'Single',
    this.otherPets = 'None',
    this.timeAvailability = 'Medium',
    this.experience = 'Beginner',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['ID'] ?? json['id'] ?? 0,
      name: json['name'] ?? 'Usuario',
      email: json['email'] ?? '',
      photoUrl: json['photo_url'] ?? '',
      bio: json['bio'] ?? '',
      phone: json['phone'] ?? '',
      role: json['role'] ?? 'adopter',

      // Parseo seguro para rating (puede venir como int o double)
      averageRating: (json['average_rating'] ?? 0).toDouble(),
      reviewCount: json['review_count'] ?? 0,

      housingType: json['housing_type'] ?? 'House',
      housingOwnership: json['housing_ownership'] ?? 'Owned',
      hasYard: json['has_yard'] ?? false,
      hasFence: json['has_fence'] ?? false,
      familyComposition: json['family_composition'] ?? 'Single',
      otherPets: json['other_pets'] ?? 'None',
      timeAvailability: json['time_availability'] ?? 'Medium',
      experience: json['experience'] ?? 'Beginner',
    );
  }
}
