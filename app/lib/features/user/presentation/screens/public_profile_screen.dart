import 'package:flutter/material.dart';
import '../../../../core/utils/image_helper.dart';
import '../../domain/user_model.dart';
import '../../../reviews/presentation/screens/user_reviews_screen.dart';

/// A read-only screen that displays the public profile of another user.
class PublicProfileScreen extends StatelessWidget {
  final User user;

  const PublicProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${user.name}'s Profile"),
        foregroundColor: Colors.black,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header Section ---
            _buildProfileHeader(context),
            const SizedBox(height: 30),

            // --- About Section ---
            _SectionTitle(title: "About"),
            const SizedBox(height: 8),
            Text(user.bio.isNotEmpty ? user.bio : "No biography provided.", style: const TextStyle(fontSize: 16, color: Colors.black87)),
            const SizedBox(height: 16),
            if (user.phone.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone, color: Color(0xFFE91E63)),
                title: Text(user.phone),
              ),
            const Divider(height: 40),

            // --- Home & Environment Section ---
            _SectionTitle(title: "Home & Environment"),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: _translate(user.housingType), icon: Icons.home, color: Colors.blue),
                _InfoChip(label: _translate(user.housingOwnership), icon: Icons.key, color: Colors.orange),
                if (user.hasYard) _InfoChip(label: "Has Yard", icon: Icons.grass, color: Colors.green),
                if (user.hasFence) _InfoChip(label: "Secure Fencing", icon: Icons.security, color: Colors.green),
                if (!user.hasYard) _InfoChip(label: "No Yard", icon: Icons.block, color: Colors.grey),
              ],
            ),
            const Divider(height: 40),

            // --- Lifestyle Section ---
            _SectionTitle(title: "Family & Routine"),
            const SizedBox(height: 12),
            _InfoRow(label: "Family", value: _translate(user.familyComposition)),
            _InfoRow(label: "Other Pets", value: _translate(user.otherPets)),
            _InfoRow(label: "Free Time", value: _translate(user.timeAvailability)),
            _InfoRow(label: "Experience", value: _translate(user.experience)),
          ],
        ),
      ),
    );
  }

  /// Builds the header section with the user's avatar, name, and reputation.
  Widget _buildProfileHeader(BuildContext context) {
    return Center(
      child: Column(
        children: [
          CircleAvatar(radius: 50, backgroundColor: Colors.grey[200], backgroundImage: ImageHelper.getProvider(user.photoUrl)),
          const SizedBox(height: 12),
          Text(user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          // Role badge
          if (user.role == 'rescuer')
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.purple[100], borderRadius: BorderRadius.circular(12)),
              child: const Text("Rescuer", style: TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 8),
          // Reputation button
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserReviewsScreen(userId: user.id, userName: user.name))),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.shade200)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star, color: Colors.amber, size: 20),
                const SizedBox(width: 6),
                Text(
                  user.reviewCount > 0 ? "${user.averageRating.toStringAsFixed(1)}/5 (${user.reviewCount} Reviews)" : "New to PAWS",
                  style: TextStyle(color: Colors.amber[900], fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: Colors.amber[900]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
  
  /// A helper function to translate database keys into user-friendly display strings.
  String _translate(String val) {
    const map = {
      'House': 'House', 'Apartment': 'Apartment', 'Parcel': 'Acreage',
      'Owned': 'Owned', 'Rented': 'Rented',
      'Single': 'Single', 'Couple': 'Couple', 'Family w/Kids': 'Family w/ Kids', 'Seniors': 'Seniors',
      'None': 'None', 'Dogs': 'Dogs', 'Cats': 'Cats', 'Both': 'Both',
      'Low': 'Low', 'Medium': 'Medium', 'High': 'High',
      'Beginner': 'Beginner', 'Intermediate': 'Intermediate', 'Expert': 'Expert',
    };
    return map[val] ?? val;
  }
}

// =========================================================================
//  Private Helper Widgets
// =========================================================================

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87));
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final MaterialColor color;
  const _InfoChip({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color[800]),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color[900], fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 16)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
    );
  }
}
