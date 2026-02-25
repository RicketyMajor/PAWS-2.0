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
    // Tolerancia a fallos: soportar JSON plano (antiguo) o anidado (nuevo backend)
    final userData = json['user'] ?? json;
    final profileData = json['profile'] ?? json;

    return User(
      id: userData['ID'] ?? userData['id'] ?? 0,
      name: userData['name'] ?? 'Usuario',
      email: userData['email'] ?? '',
      photoUrl: userData['photo_url'] ?? '',
      bio: userData['bio'] ?? '',
      phone: userData['phone'] ?? '',
      role: userData['role'] ?? 'adopter',

      averageRating: (userData['average_rating'] ?? 0).toDouble(),
      reviewCount: userData['review_count'] ?? 0,

      // Lectura del perfil (asegurando valores predeterminados seguros)
      housingType: profileData['housing_type'] ?? 'House',
      housingOwnership: profileData['housing_ownership'] ?? 'Owned',
      hasYard: profileData['has_yard'] ?? false,
      hasFence: profileData['has_fence'] ?? false,
      familyComposition: profileData['family_composition'] ?? 'Single',
      otherPets: profileData['other_pets'] ?? 'None',
      timeAvailability: profileData['time_availability'] ?? 'Medium',
      experience: profileData['experience'] ?? 'Beginner',
    );
  }
}
