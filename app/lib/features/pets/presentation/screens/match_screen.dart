import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart'; // Asegúrate de tener esta dependencia
import '../bloc/pets_bloc.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';
import '../../../chat/presentation/screens/chat_screen.dart';

class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Inyectamos el BLoC aquí mismo o en un nivel superior
    return BlocProvider(
      create: (context) =>
          PetsBloc(repository: RepositoryProvider.of<PetsRepository>(context))
            ..add(LoadSwipeDeck()), // Cargar al iniciar
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Encuentra tu compañero"),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
          actions: [
            IconButton(
              icon: const Icon(Icons.chat),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChatScreen(
                      matchId: 1,
                      peerName: "Rescatista Demo",
                    ),
                  ),
                );
              },
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
          return const Center(child: CircularProgressIndicator());
        } else if (state is PetsError) {
          return Center(child: Text("Error: ${state.message}"));
        } else if (state is PetsLoaded) {
          if (state.pets.isEmpty) {
            return const Center(child: Text("No hay más mascotas por hoy 🐶"));
          }
          return _buildSwiper(context, state.pets);
        }
        return Container();
      },
    );
  }

  Widget _buildSwiper(BuildContext context, List<Pet> pets) {
    final CardSwiperController controller = CardSwiperController();

    return Column(
      children: [
        Expanded(
          child: CardSwiper(
            controller: controller,
            cardsCount: pets.length,
            numberOfCardsDisplayed: 3,
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
        // Botones de control manual
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
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            // Imagen
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: pet.imageUrl != null && pet.imageUrl!.isNotEmpty
                  ? Image.network(
                      // Si usas localhost/emulador, asegúrate que la URL sea accesible
                      // Podrías necesitar reemplazar 'localhost' por tu IP aquí si el backend manda localhost
                      pet.imageUrl!,
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
                // Chips de características
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
