import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../bloc/pets_bloc.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';
import '../widgets/pet_card.dart'; // <--- Importamos nuestra nueva carta

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
          title: const Text("Descubrir"), // Título más descriptivo
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFFE91E63),
          centerTitle: true,
          actions: [
            // Botón de recarga manual por si acaso
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<PetsBloc>().add(LoadSwipeDeck()),
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
          const Text(
            "Vuelve más tarde para ver nuevos amigos.",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
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

    // Evita crash si hay pocas cartas
    final int stackCount = pets.length < 3 ? pets.length : 3;

    return Column(
      children: [
        Expanded(
          child: CardSwiper(
            controller: controller,
            cardsCount: pets.length,
            numberOfCardsDisplayed: stackCount,
            isLoop: false, // Importante: No repetir cartas infinitamente
            // Acciones al deslizar
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
              // Cuando se acaban, intentamos cargar más
              context.read<PetsBloc>().add(LoadSwipeDeck());
            },

            // Constructor de la carta usando nuestro nuevo Widget
            cardBuilder:
                (context, index, percentThresholdX, percentThresholdY) {
                  return PetCard(pet: pets[index]);
                },
          ),
        ),

        // Botones de acción inferior
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: Icons.close,
                color: Colors.red,
                onPressed: () => controller.swipe(CardSwiperDirection.left),
              ),
              _ActionButton(
                icon: Icons.favorite,
                color: const Color(0xFFE91E63), // Pink PAWS
                onPressed: () => controller.swipe(CardSwiperDirection.right),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Botón circular bonito
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
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
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}
