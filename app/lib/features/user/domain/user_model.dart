// The domain layer contains the core models of the application.

/// Represents a user, combining data from the `User` and `UserProfile` backend models.
class User {
  final int id;
  final String name;
  final String email;
  final String photoUrl;
  final String bio;
  final String phone;
  final String role;
  final String run;

  // --- Reputation Data ---
  final double averageRating;
  final int reviewCount;

  // --- Adopter Profile: Housing Data ---
  final String housingType;
  final String housingOwnership;
  final bool hasYard;
  final bool hasFence;

  // --- Adopter Profile: Lifestyle Data ---
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
    required this.run,
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

  /// Creates a [User] from a JSON map.
  ///
  /// This factory is fault-tolerant and can handle both a flat JSON structure
  /// (from older API versions or different endpoints) and a nested structure
  /// where user and profile data are in separate objects (`{"user": ..., "profile": ...}`).
  factory User.fromJson(Map<String, dynamic> json) {
    // Determine the source of user and profile data, defaulting to the root object.
    final userData = json['user'] ?? json;
    final profileData = json['profile'] ?? json;

    return User(
      id: userData['ID'] ?? userData['id'] ?? 0,
      name: userData['name'] ?? 'User',
      email: userData['email'] ?? '',
      photoUrl: userData['photo_url'] ?? '',
      bio: userData['bio'] ?? '',
      phone: userData['phone'] ?? '',
      role: userData['role'] ?? 'adopter',
      run: userData['run'] ?? userData['rut'] ?? '',

      averageRating: (userData['average_rating'] ?? 0.0).toDouble(),
      reviewCount: userData['review_count'] ?? 0,

      // Read from profile data with safe defaults.
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
