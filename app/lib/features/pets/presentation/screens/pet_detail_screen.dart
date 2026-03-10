import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';

/// A screen that displays the detailed profile of a single pet.
class PetDetailScreen extends StatefulWidget {
  final Pet pet;

  const PetDetailScreen({super.key, required this.pet});

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

  /// Deletes the pet after showing a confirmation dialog.
  void _deletePet(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Pet?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await context.read<PetsRepository>().deletePet(widget.pet.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pet deleted")));
          Navigator.pop(context, true); // Return true to signal a refresh might be needed.
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure the gallery has at least one image to display.
    final List<String> gallery = widget.pet.images.isNotEmpty ? widget.pet.images : (widget.pet.imageUrl != null ? [widget.pet.imageUrl!] : []);

    return Scaffold(
      extendBodyBehindAppBar: true, // Allows the body to go behind the transparent app bar.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _buildAppBarButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _buildAppBarButton(
            icon: Icons.delete,
            color: Colors.red,
            onPressed: () => _deletePet(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Image Carousel ---
            _buildImageCarousel(gallery),

            // --- Pet Information Section ---
            Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPetHeader(),
                    const SizedBox(height: 24),
                    _buildHealthSection(),
                    const SizedBox(height: 24),
                    _buildLifestyleSection(),
                    const SizedBox(height: 24),
                    _buildStorySection(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  //  UI Builder Methods
  // =========================================================================
  
  Widget _buildAppBarButton({required IconData icon, Color? color, required VoidCallback onPressed}) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle),
      child: IconButton(icon: Icon(icon, color: color ?? Colors.black), onPressed: onPressed),
    );
  }
  
  Widget _buildImageCarousel(List<String> gallery) {
    return SizedBox(
      height: 400,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: gallery.isEmpty ? 1 : gallery.length,
            onPageChanged: (index) => setState(() => _currentImageIndex = index),
            itemBuilder: (context, index) {
              final url = gallery.isNotEmpty ? gallery[index] : null;
              return ImageHelper.getImage(url, width: double.infinity, height: 400, fit: BoxFit.cover);
            },
          ),
          if (gallery.length > 1) ...[
            // Page indicator (e.g., "1/4")
            Positioned(
              top: 100,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20)),
                child: Text("${_currentImageIndex + 1}/${gallery.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            // Previous image button
            if (_currentImageIndex > 0)
              Positioned(left: 10, child: _NavButton(icon: Icons.arrow_back_ios_new, onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut))),
            // Next image button
            if (_currentImageIndex < gallery.length - 1)
              Positioned(right: 10, child: _NavButton(icon: Icons.arrow_forward_ios, onPressed: () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut))),
            // Dot indicators
            Positioned(
              bottom: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(gallery.length, (index) => Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _currentImageIndex == index ? Colors.white : Colors.white.withOpacity(0.5)),
                )),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildPetHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.pet.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2D3436))),
            Row(children: [
              Icon(widget.pet.type == 'Dog' ? Icons.pets : Icons.cruelty_free, size: 16, color: widget.pet.type == 'Dog' ? Colors.blue : Colors.orange),
              const SizedBox(width: 4),
              Text(widget.pet.type, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: widget.pet.type == 'Dog' ? Colors.blue : Colors.orange)),
              const SizedBox(width: 6),
              Text("• ${widget.pet.breed}", style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            ]),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFE91E63).withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
          child: Text("${widget.pet.age} years", style: const TextStyle(color: Color(0xFFE91E63), fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildHealthSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Clinical Record", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _HealthBadge(label: "Vaccinated", isActive: widget.pet.isVaccinated, icon: Icons.vaccines),
        _HealthBadge(label: "Spayed", isActive: widget.pet.isSterilized, icon: Icons.pets),
        _HealthBadge(label: "Dewormed", isActive: widget.pet.isDewormed, icon: Icons.bug_report),
      ]),
      if (widget.pet.specialNeeds.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text("Attention: ${widget.pet.specialNeeds}")),
          ]),
        ),
    ]);
  }

  Widget _buildLifestyleSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Lifestyle", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _TagChip(label: "Energy: ${widget.pet.energyLevel.capitalize()}", color: Colors.blue),
        if (widget.pet.goodWithKids) const _TagChip(label: "Good with Kids", color: Colors.green),
        if (widget.pet.goodWithDogs) const _TagChip(label: "Good with Dogs", color: Colors.green),
        if (widget.pet.requiresYard) const _TagChip(label: "Requires Yard", color: Colors.purple),
      ]),
    ]);
  }

  Widget _buildStorySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Story", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(widget.pet.description, style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87)),
    ]);
  }
}

// =========================================================================
//  Private Helper Widgets
// =========================================================================

/// A navigation button for the image carousel.
class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _NavButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))]),
      child: IconButton(icon: Icon(icon, color: Colors.black87), onPressed: onPressed),
    );
  }
}

/// A badge for displaying a pet's health status.
class _HealthBadge extends StatelessWidget {
  final String label;
  final bool isActive;
  final IconData icon;
  const _HealthBadge({required this.label, required this.isActive, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey[100], shape: BoxShape.circle),
        child: Icon(icon, color: isActive ? Colors.green : Colors.grey, size: 28),
      ),
      const SizedBox(height: 8),
      Text(label, style: TextStyle(fontSize: 12, color: isActive ? Colors.black87 : Colors.grey, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
    ]);
  }
}

/// A styled chip for displaying lifestyle tags.
class _TagChip extends StatelessWidget {
  final String label;
  final MaterialColor color;
  const _TagChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(label, style: TextStyle(color: color[800], fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

extension on String {
    String capitalize() {
      return "${this[0].toUpperCase()}${this.substring(1).toLowerCase()}";
    }
}
