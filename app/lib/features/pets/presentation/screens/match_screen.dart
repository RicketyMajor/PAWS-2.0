import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../bloc/pets_bloc.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';

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
          title: const Text("PAWS"),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFFE91E63),
          centerTitle: true,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  "Algo salió mal: ${state.message}",
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () =>
                      context.read<PetsBloc>().add(LoadSwipeDeck()),
                  child: const Text("Reintentar"),
                ),
              ],
            ),
          );
        } else if (state is PetsLoaded) {
          if (state.pets.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.pets, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "No hay mascotas nuevas cerca de ti.",
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "¡Vuelve a intentar más tarde!",
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<PetsBloc>().add(LoadSwipeDeck()),
                    child: const Text("Actualizar"),
                  ),
                ],
              ),
            );
          }
          return _buildSwiper(context, state.pets);
        }
        return Container();
      },
    );
  }

  Widget _buildSwiper(BuildContext context, List<Pet> pets) {
    final CardSwiperController controller = CardSwiperController();

    // LÓGICA DE SEGURIDAD:
    // Si tienes 1 mascota, muestra 1. Si tienes 10, muestra pila de 3.
    // Esto evita el error rojo.
    final int stackCount = pets.length < 3 ? pets.length : 3;

    return Column(
      children: [
        Expanded(
          child: CardSwiper(
            controller: controller,
            cardsCount: pets.length,
            // CORRECCIÓN 1: Usamos la variable calculada arriba
            numberOfCardsDisplayed: stackCount,
            onSwipe: (previousIndex, currentIndex, direction) {
              final pet = pets[previousIndex];

              if (direction == CardSwiperDirection.right) {
                // LIKE
                context.read<PetsBloc>().add(
                  SwipePetEvent(petId: pet.id, isLike: true),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Te gusta ${pet.name} ❤️"),
                    duration: const Duration(milliseconds: 500),
                  ),
                );
              } else if (direction == CardSwiperDirection.left) {
                // DISLIKE
                context.read<PetsBloc>().add(
                  SwipePetEvent(petId: pet.id, isLike: false),
                );
              }
              return true;
            },
            cardBuilder:
                (context, index, percentThresholdX, percentThresholdY) {
                  final pet = pets[index];
                  return _buildCard(pet);
                },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () => controller.swipe(CardSwiperDirection.left),
                icon: const Icon(Icons.close, color: Colors.red, size: 40),
              ),
              IconButton(
                onPressed: () => controller.swipe(CardSwiperDirection.right),
                icon: const Icon(Icons.favorite, color: Colors.green, size: 40),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Pet pet) {
    // URL base para el emulador Android
    const String baseUrl = 'http://10.0.2.2:8080';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              // CORRECCIÓN 2: Lógica visual para arreglar la URL de la imagen
              child: pet.imageUrl != null && pet.imageUrl!.isNotEmpty
                  ? Image.network(
                      pet.imageUrl!.startsWith('http')
                          ? pet.imageUrl!
                          : '$baseUrl${pet.imageUrl}',
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, _) =>
                          const Icon(Icons.pets, size: 100, color: Colors.grey),
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.pets,
                        size: 100,
                        color: Colors.grey,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${pet.name}, ${pet.age} años",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  pet.breed,
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  pet.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (pet.goodWithKids)
                      const Chip(
                        label: Text("Apto niños"),
                        backgroundColor: Colors.greenAccent,
                      ),
                    if (pet.requiresYard)
                      const Chip(
                        label: Text("Requiere patio"),
                        backgroundColor: Colors.orangeAccent,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
