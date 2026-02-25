import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_helper.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';

class PetDetailScreen extends StatefulWidget {
  final Pet pet;

  const PetDetailScreen({super.key, required this.pet});

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  // Control para el carrusel de fotos
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    // --- DEBUG LOG ---
    print("DETAIL_DEBUG: Abriendo detalle de ${widget.pet.name}");
    print(
      "DETAIL_DEBUG: Cantidad de imágenes en objeto Pet: ${widget.pet.images.length}",
    );
    print("DETAIL_DEBUG: URLs: ${widget.pet.images}");
  }

  void _nextImage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _prevImage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _deletePet(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar Mascota?"),
        content: const Text("Esta acción no se puede deshacer."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Borrar"),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await context.read<PetsRepository>().deletePet(widget.pet.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Mascota eliminada")));
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Construimos la galería asegurándonos de tener al menos una foto
    final List<String> gallery = widget.pet.images.isNotEmpty
        ? widget.pet.images
        : (widget.pet.imageUrl != null ? [widget.pet.imageUrl!] : []);

    // --- DEBUG LOG VISUAL ---
    print(
      "DETAIL_DEBUG: Galería final a mostrar tiene ${gallery.length} elementos.",
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white54,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.white54,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deletePet(context),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- CARRUSEL DE IMÁGENES MEJORADO ---
            SizedBox(
              height: 400,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. El Visor de Fotos
                  PageView.builder(
                    controller: _pageController,
                    itemCount: gallery.isEmpty ? 1 : gallery.length,
                    onPageChanged: (index) {
                      setState(() => _currentImageIndex = index);
                    },
                    itemBuilder: (context, index) {
                      final url = gallery.isNotEmpty ? gallery[index] : null;
                      return ImageHelper.getImage(
                        url,
                        width: double.infinity,
                        height: 400,
                        fit: BoxFit.cover,
                      );
                    },
                  ),

                  // 2. Indicador Numérico (Chip "1/4") - Arriba Derecha
                  if (gallery.length > 1)
                    Positioned(
                      top: 100,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "${_currentImageIndex + 1}/${gallery.length}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  // 3. Flecha IZQUIERDA (Retroceder)
                  if (gallery.length > 1 && _currentImageIndex > 0)
                    Positioned(
                      left: 10,
                      child: _NavButton(
                        icon: Icons.arrow_back_ios_new,
                        onPressed: _prevImage,
                      ),
                    ),

                  // 4. Flecha DERECHA (Avanzar)
                  if (gallery.length > 1 &&
                      _currentImageIndex < gallery.length - 1)
                    Positioned(
                      right: 10,
                      child: _NavButton(
                        icon: Icons.arrow_forward_ios,
                        onPressed: _nextImage,
                      ),
                    ),

                  // 5. Indicador de Puntos (Dots) - Abajo Centro
                  if (gallery.length > 1)
                    Positioned(
                      bottom: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(gallery.length, (index) {
                          return Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentImageIndex == index
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),

            // --- INFORMACIÓN DE LA MASCOTA ---
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
                    // Cabecera: Nombre y Raza
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.pet.name,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D3436),
                                ),
                              ),
                              Text(
                                widget.pet.breed,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE91E63).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            "${widget.pet.age} años",
                            style: const TextStyle(
                              color: Color(0xFFE91E63),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Ficha Clínica
                    const Text(
                      "Ficha Clínica",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _HealthBadge(
                          label: "Vacunado",
                          isActive: widget.pet.isVaccinated,
                          icon: Icons.vaccines,
                        ),
                        _HealthBadge(
                          label: "Esterilizado",
                          isActive: widget.pet.isSterilized,
                          icon: Icons.pets,
                        ),
                        _HealthBadge(
                          label: "Desparasitado", // <-- Etiqueta corregida
                          isActive: widget
                              .pet
                              .isDewormed, // <-- Lógica corregida (sin el '!')
                          icon:
                              Icons.bug_report, // <-- Icono más representativo
                        ),
                      ],
                    ),
                    if (widget.pet.specialNeeds.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Atención: ${widget.pet.specialNeeds}",
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Estilo de Vida
                    const Text(
                      "Estilo de Vida",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Generador dinámico para traducir la energía
                        _TagChip(
                          label:
                              "Energía: ${() {
                                switch (widget.pet.energyLevel.toLowerCase()) {
                                  case 'low':
                                    return 'Baja';
                                  case 'high':
                                    return 'Alta';
                                  default:
                                    return 'Media';
                                }
                              }()}",
                          color: Colors.blue,
                        ),
                        if (widget.pet.goodWithKids)
                          const _TagChip(
                            label: "Apto Niños",
                            color: Colors.green,
                          ),
                        if (widget.pet.goodWithDogs)
                          const _TagChip(
                            label: "Apto Perros",
                            color: Colors.green,
                          ),
                        if (widget.pet.requiresYard)
                          const _TagChip(
                            label: "Requiere Patio",
                            color: Colors.purple,
                          ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Historia
                    const Text(
                      "Historia",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.pet.description,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Colors.black87,
                      ),
                    ),

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
}

// Botón de navegación (Flecha)
class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _NavButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8), // Semi-transparente
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black87),
        onPressed: onPressed,
      ),
    );
  }
}

class _HealthBadge extends StatelessWidget {
  final String label;
  final bool isActive;
  final IconData icon;

  const _HealthBadge({
    required this.label,
    required this.isActive,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey[100],
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isActive ? Colors.green : Colors.grey,
            size: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.black87 : Colors.grey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final MaterialColor color;

  const _TagChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color[800],
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
