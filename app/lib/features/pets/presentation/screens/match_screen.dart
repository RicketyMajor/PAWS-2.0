import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../bloc/pets_bloc.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';
import '../widgets/pet_card.dart';
import 'pet_detail_screen.dart';

/// The main "discovery" screen where users can swipe through pet profiles.
class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PetsBloc(repository: RepositoryProvider.of<PetsRepository>(context))..add(LoadSwipeDeck()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Discover"),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFFE91E63),
          centerTitle: true,
          actions: [
            // Use a Builder to get a context that is a descendant of the BlocProvider.
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.refresh),
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

/// The main view that builds the UI based on the [PetsState].
class MatchView extends StatelessWidget {
  const MatchView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PetsBloc, PetsState>(
      builder: (context, state) {
        if (state is PetsLoading) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFE91E63)));
        }
        if (state is PetsError) {
          return _buildErrorState(context, state.message);
        }
        if (state is PetsLoaded) {
          if (state.pets.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildSwiper(context, state.pets);
        }
        return Container(); // Initial state
      },
    );
  }
  
  /// Builds the UI for an error state.
  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.broken_image, size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          Text("Oops: $message", textAlign: TextAlign.center),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => context.read<PetsBloc>().add(LoadSwipeDeck()),
            child: const Text("Retry"),
          ),
        ]),
      ),
    );
  }
  
  /// Builds the UI for when no more pets are available.
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.pets, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 20),
        const Text("No more pets around!", style: TextStyle(fontSize: 18, color: Colors.grey)),
        OutlinedButton(
          onPressed: () => context.read<PetsBloc>().add(LoadSwipeDeck()),
          child: const Text("Search Again"),
        ),
      ]),
    );
  }

  /// Builds the main card swiping interface.
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
              // Dispatch swipe event to the BLoC based on direction.
              if (direction == CardSwiperDirection.right) {
                context.read<PetsBloc>().add(SwipePetEvent(petId: pet.id, isLike: true));
              } else if (direction == CardSwiperDirection.left) {
                context.read<PetsBloc>().add(SwipePetEvent(petId: pet.id, isLike: false));
              }
              return true;
            },
            onEnd: () => context.read<PetsBloc>().add(LoadSwipeDeck()), // Load more pets when the deck is empty.
            cardBuilder: (context, index, percentThresholdX, percentThresholdY) {
              final pet = pets[index];
              // Allow tapping the card to navigate to the pet's detail screen.
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PetDetailScreen(pet: pet))),
                child: PetCard(pet: pet),
              );
            },
          ),
        ),
        // Action buttons for swiping left or right.
        Padding(
          padding: const EdgeInsets.only(bottom: 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(icon: Icons.close, color: Colors.red, onPressed: () => controller.swipe(CardSwiperDirection.left)),
              _ActionButton(icon: Icons.favorite, color: const Color(0xFFE91E63), onPressed: () => controller.swipe(CardSwiperDirection.right)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A reusable styled button for the swipe actions.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: IconButton(
        iconSize: 40,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}
