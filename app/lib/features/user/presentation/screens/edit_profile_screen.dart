import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/image_helper.dart';
import '../../data/user_repository.dart';
import '../../domain/user_model.dart';
import '../../../security/presentation/screens/blacklist_search_screen.dart';
import '../../../reviews/presentation/screens/user_reviews_screen.dart';
import '../../../auth/presentation/screens/register_screen.dart';
import '../../../../core/presentation/main_layout_screen.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../auth/data/auth_repository.dart';

/// Screen for viewing and editing the user's own profile.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // --- Text Editing Controllers ---
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // --- Dropdown Options ---
  static const List<String> _housingTypesOptions = ["House", "Apartment", "Parcel"];
  static const List<String> _ownershipOptions = ["Owned", "Rented"];
  static const List<String> _familyOptions = ["Single", "Couple", "Family w/Kids", "Seniors"];
  static const List<String> _petsOptions = ["None", "Dogs", "Cats", "Both"];
  static const List<String> _timeOptions = ["Low", "Medium", "High"];
  static const List<String> _expOptions = ["Beginner", "Intermediate", "Expert"];

  // --- Form State Variables ---
  String _housingType = _housingTypesOptions[0];
  String _housingOwnership = _ownershipOptions[0];
  bool _hasYard = false;
  bool _hasFence = false;
  String _familyComposition = _familyOptions[0];
  String _otherPets = _petsOptions[0];
  String _timeAvailability = _timeOptions[1];
  String _experience = _expOptions[0];
  
  // --- User & UI State ---
  double _averageRating = 0.0;
  int _reviewCount = 0;
  int _userId = 0;
  String _currentRole = 'adopter';
  String _currentEmail = '';
  String _currentRun = '';
  String? _currentPhotoUrl;
  XFile? _newPhotoFile;
  bool _isLoading = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  /// Loads the user's profile data and populates the form fields.
  Future<void> _loadProfile() async {
    try {
      final data = await context.read<UserRepository>().getProfile();
      final user = User.fromJson(data);

      if (mounted) {
        setState(() {
          _userId = user.id;
          _currentRole = user.role;
          _currentEmail = user.email;
          _currentRun = data['run'] ?? '';
          _averageRating = user.averageRating;
          _reviewCount = user.reviewCount;
          _nameCtrl.text = user.name;
          _bioCtrl.text = user.bio;
          _phoneCtrl.text = user.phone;
          _currentPhotoUrl = user.photoUrl;
          _housingType = _validateOption(user.housingType, _housingTypesOptions);
          _housingOwnership = _validateOption(user.housingOwnership, _ownershipOptions);
          _hasYard = user.hasYard;
          _hasFence = user.hasFence;
          _familyComposition = _validateOption(user.familyComposition, _familyOptions);
          _otherPets = _validateOption(user.otherPets, _petsOptions);
          _timeAvailability = _validateOption(user.timeAvailability, _timeOptions);
          _experience = _validateOption(user.experience, _expOptions);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        print("Error loading profile: $e");
      }
    }
  }

  /// A helper to ensure the value from the database exists in the options list.
  String _validateOption(String? value, List<String> options) {
    return (value != null && options.contains(value)) ? value : options[0];
  }
  
  // =========================================================================
  //  User Actions
  // =========================================================================

  /// Opens the image gallery to pick a new profile photo.
  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _newPhotoFile = pickedFile);
  }
  
  /// Saves all edited profile information.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final repo = context.read<UserRepository>();
      String finalPhotoUrl = _currentPhotoUrl ?? "";

      if (_newPhotoFile != null) {
        finalPhotoUrl = await repo.uploadProfilePicture(_newPhotoFile!);
      }

      await repo.updateProfile(
        name: _nameCtrl.text, bio: _bioCtrl.text, phone: _phoneCtrl.text,
        photoUrl: finalPhotoUrl, housingType: _housingType, housingOwnership: _housingOwnership,
        hasYard: _hasYard, hasFence: _hasFence, familyComposition: _familyComposition,
        otherPets: _otherPets, timeAvailability: _timeAvailability, experience: _experience,
      );

      if (mounted) {
        setState(() {
          _isLoading = false; _isEditing = false;
          _currentPhotoUrl = finalPhotoUrl; _newPhotoFile = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  /// Handles the logic for switching to the user's alternate role.
  Future<void> _handleSwitchRole() async {
    setState(() => _isLoading = true);
    try {
      final authRepo = context.read<AuthRepository>();
      final newUserMap = await authRepo.switchRole();

      if (newUserMap != null) {
        if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => MainLayoutScreen(role: newUserMap['role'])), (route) => false);
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          _showCreateAccountDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  /// Logs the user out and clears the navigation stack.
  void _confirmLogout() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Log Out"),
      content: const Text("Are you sure you want to log out?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await context.read<AuthRepository>().logout();
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
          },
          child: const Text("Yes, Log Out", style: TextStyle(color: Colors.red)),
        ),
      ],
    ));
  }
  
  /// Shows a dialog prompting the user to create their alternate role profile.
  void _showCreateAccountDialog() {
    final targetRoleName = _currentRole == 'adopter' ? 'Rescuer' : 'Adopter';
    final targetRoleCode = _currentRole == 'adopter' ? 'rescuer' : 'adopter';

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("Activate $targetRoleName Mode"),
      content: Text("You don't have a $targetRoleName profile yet.\n\nWould you like to activate it now using your current data?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(
              initialName: _nameCtrl.text, initialEmail: _currentEmail,
              initialRun: _currentRun, initialRole: targetRoleCode,
            )));
          },
          child: const Text("Yes, Activate"),
        ),
      ],
    ));
  }

  // =========================================================================
  //  Build Method & UI Helpers
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final targetRoleLabel = _currentRole == 'adopter' ? 'Rescuer Mode' : 'Adopter Mode';
    final targetColor = _currentRole == 'adopter' ? Colors.purple : Colors.orange;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit),
            onPressed: _isLoading ? null : (_isEditing ? _save : () => setState(() => _isEditing = true)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings, color: Colors.blueGrey),
            onSelected: (value) {
              if (value == 'logout') _confirmLogout();
              else if (value == 'blacklist') Navigator.push(context, MaterialPageRoute(builder: (_) => const BlacklistSearchScreen()));
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'blacklist', child: Row(children: [Icon(Icons.security, size: 20, color: Colors.blueGrey), SizedBox(width: 10), Text("Check Blacklist")])),
              const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.exit_to_app, size: 20, color: Colors.red), SizedBox(width: 10), Text("Log Out", style: TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileHeader(targetColor, targetRoleLabel),
                    const SizedBox(height: 24),
                    _buildSectionTitle("Personal Information"),
                    _buildTextField(_nameCtrl, "Full Name", Icons.person),
                    const SizedBox(height: 16),
                    _buildTextField(_bioCtrl, "Biography", Icons.description, maxLines: 3),
                    const SizedBox(height: 16),
                    _buildTextField(_phoneCtrl, "Phone", Icons.phone, isPhone: true),
                    const Divider(height: 40),
                    _buildSectionTitle("Home & Environment"),
                    Row(children: [
                      Expanded(child: _buildDropdown("Housing Type", _housingType, _housingTypesOptions, (v) => setState(() => _housingType = v!))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown("Ownership", _housingOwnership, _ownershipOptions, (v) => setState(() => _housingOwnership = v!))),
                    ]),
                    SwitchListTile(title: const Text("Has Yard"), value: _hasYard, onChanged: _isEditing ? (v) => setState(() => _hasYard = v) : null),
                    SwitchListTile(title: const Text("Has Fence / Safety Net"), value: _hasFence, onChanged: _isEditing ? (v) => setState(() => _hasFence = v) : null),
                    const Divider(height: 40),
                    _buildSectionTitle("Family & Routine"),
                    _buildDropdown("Family Composition", _familyComposition, _familyOptions, (v) => setState(() => _familyComposition = v!)),
                    const SizedBox(height: 16),
                    _buildDropdown("Other Pets", _otherPets, _petsOptions, (v) => setState(() => _otherPets = v!)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: _buildDropdown("Free Time", _timeAvailability, _timeOptions, (v) => setState(() => _timeAvailability = v!))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown("Experience", _experience, _expOptions, (v) => setState(() => _experience = v!))),
                    ]),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProfileHeader(Color targetColor, String targetRoleLabel) {
    return Column(children: [
      Center(child: GestureDetector(onTap: _pickImage, child: Stack(alignment: Alignment.bottomRight, children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.grey[300],
          backgroundImage: _newPhotoFile != null
              ? (kIsWeb ? NetworkImage(_newPhotoFile!.path) : FileImage(File(_newPhotoFile!.path))) as ImageProvider
              : ImageHelper.getProvider(_currentPhotoUrl),
        ),
        if (_isEditing) const CircleAvatar(backgroundColor: Color(0xFFE91E63), radius: 18, child: Icon(Icons.camera_alt, color: Colors.white, size: 18)),
      ]))),
      const SizedBox(height: 16),
      Center(child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: targetColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
        onPressed: _handleSwitchRole,
        icon: const Icon(Icons.swap_horiz),
        label: Text("Switch to $targetRoleLabel"),
      )),
      const SizedBox(height: 16),
      Center(child: InkWell(
        onTap: () {
          if (_userId != 0) Navigator.push(context, MaterialPageRoute(builder: (_) => UserReviewsScreen(userId: _userId, userName: "My")));
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.shade200)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star, color: Colors.amber, size: 20),
            const SizedBox(width: 6),
            Text(_reviewCount > 0 ? "${_averageRating.toStringAsFixed(1)}/5 ($_reviewCount Reviews)" : "No ratings yet", style: TextStyle(color: Colors.amber[900], fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: Colors.amber[900]),
          ]),
        ),
      )),
    ]);
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {int maxLines = 1, bool isPhone = false}) {
    return TextFormField(
      controller: ctrl,
      enabled: _isEditing,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _isEditing ? const Color(0xFFE91E63) : Colors.grey),
        border: const OutlineInputBorder(),
        filled: !_isEditing,
        fillColor: Colors.grey.shade50,
      ),
      maxLines: maxLines,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      validator: (v) => v!.isEmpty ? "Required" : null,
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    // A local helper to translate dropdown keys to display values.
    String translate(String val) {
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

    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), filled: !_isEditing, fillColor: Colors.grey.shade50),
      value: value,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(translate(e)))).toList(),
      onChanged: _isEditing ? onChanged : null,
    );
  }
}
