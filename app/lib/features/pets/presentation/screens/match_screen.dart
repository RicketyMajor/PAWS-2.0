import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../bloc/pets_bloc.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';
import '../widgets/pet_card.dart';
import 'pet_detail_screen.dart'; // <--- Necesario para navegar

class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          PetsBloc(repository: RepositoryProvider.of<PetsRepository>(context))
            ..add(LoadSwipeDeck()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Descubrir"),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFFE91E63),
          centerTitle: true,
          actions: [
            // --- SOLUCIÓN: Usamos un Builder para heredar el contexto del BLoC ---
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(
                  Icons.refresh,
                  semanticLabel: 'Recargar mascotas',
                ),
                tooltip: 'Recargar mascotas',
                onPressed: () => ctx.read<PetsBloc>().add(LoadSwipeDeck()),
              ),
            ),
          ],
        ),
        body: const MatchView(),
      ),
    );
  }
}

class MatchView extends StatelessWidget {
  const MatchView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PetsBloc, PetsState>(
      builder: (context, state) {
        if (state is PetsLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFE91E63)),
          );
        } else if (state is PetsError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text("Ups: ${state.message}", textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<PetsBloc>().add(LoadSwipeDeck()),
                    child: const Text("Reintentar"),
                  ),
                ],
              ),
            ),
          );
        } else if (state is PetsLoaded) {
          if (state.pets.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildSwiper(context, state.pets);
        }
        return Container();
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          const Text(
            "¡No hay más mascotas por aquí!",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          OutlinedButton(
            onPressed: () => context.read<PetsBloc>().add(LoadSwipeDeck()),
            child: const Text("Buscar de nuevo"),
          ),
        ],
      ),
    );
  }

  Widget _buildSwiper(BuildContext context, List<Pet> pets) {
    final CardSwiperController controller = CardSwiperController();
    final int stackCount = pets.length < 3 ? pets.length : 3;

    return Column(
      children: [
        Expanded(
          child: CardSwiper(
            controller: controller,
            cardsCount: pets.length,
            numberOfCardsDisplayed: stackCount,
            isLoop: false,
            onSwipe: (previousIndex, currentIndex, direction) {
              final pet = pets[previousIndex];
              if (direction == CardSwiperDirection.right) {
                context.read<PetsBloc>().add(
                  SwipePetEvent(petId: pet.id, isLike: true),
                );
              } else if (direction == CardSwiperDirection.left) {
                context.read<PetsBloc>().add(
                  SwipePetEvent(petId: pet.id, isLike: false),
                );
              }
              return true;
            },
            onEnd: () {
              context.read<PetsBloc>().add(LoadSwipeDeck());
            },
            cardBuilder:
                (context, index, percentThresholdX, percentThresholdY) {
                  final pet = pets[index];

                  // --- EL TRUCO: Detectar Tap para expandir ---
                  return GestureDetector(
                    onTap: () {
                      // Navegamos al detalle "Estilo Instagram"
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PetDetailScreen(pet: pet),
                        ),
                      );
                    },
                    child: PetCard(pet: pet),
                  );
                  // ---------------------------------------------
                },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: Icons.close,
                label: 'Descartar esta mascota',
                color: Colors.red,
                onPressed: () => controller.swipe(CardSwiperDirection.left),
              ),
              _ActionButton(
                icon: Icons.favorite,
                label: 'Enviar solicitud de adopción',
                color: const Color(0xFFE91E63),
                onPressed: () => controller.swipe(CardSwiperDirection.right),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: IconButton(
        iconSize: 40,
        // Both are needed: tooltip is the long-press hint for sighted users and
        // lands on the semantics node as `tooltip`, which is NOT the accessible
        // name. Only Icon.semanticLabel fills `label`; without it the button is
        // announced as an unnamed button. Measured, not assumed.
        //
        // ponytail: on Flutter web both render into the same node, so a screen
        // reader reads the name twice ("Mostrar contraseña\nMostrar contraseña",
        // measured in production). Ceiling: verbose, not broken -- read twice
        // beats not read at all. Upgrade path: drop the tooltip if a web-DOM
        // measurement ever shows tooltip alone also names the button there; the
        // framework tree says it does not, and finding out costs a deploy.
        tooltip: label,
        icon: Icon(icon, color: color, semanticLabel: label),
        onPressed: onPressed,
      ),
    );
  }
}
