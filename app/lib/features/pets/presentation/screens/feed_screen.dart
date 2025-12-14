import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../../../chat/presentation/screens/chat_screen.dart';

import '../../data/pets_repository.dart';
import '../bloc/pets_bloc.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Inyectamos el PetsBloc solo para esta pantalla
    return BlocProvider(
      create: (context) =>
          PetsBloc(context.read<PetsRepository>())
            ..add(LoadPets()), // ¡Disparamos el evento de carga al iniciar!
      child: const _FeedView(),
    );
  }
}

class _FeedView extends StatelessWidget {
  const _FeedView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Descubre"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.chat_bubble_outline,
              color: Color(0xFFE91E63),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChatScreen()),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<PetsBloc, PetsState>(
        builder: (context, state) {
          // A. Estado CARGANDO
          if (state is PetsLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // B. Estado ERROR
          if (state is PetsError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(state.message, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => context.read<PetsBloc>().add(LoadPets()),
                    child: const Text("Reintentar"),
                  ),
                ],
              ),
            );
          }

          // C. Estado LISTO (Loaded)
          if (state is PetsLoaded) {
            if (state.pets.isEmpty) {
              return const Center(child: Text("No hay mascotas cercanas :("));
            }

            // Aquí está la magia del SWIPE
            return SafeArea(
              child: Column(
                children: [
                  Flexible(
                    child: CardSwiper(
                      cardsCount: state.pets.length,

                      // --- CORRECCIÓN AQUÍ ---
                      // Si hay menos de 3 mascotas, mostramos solo las que hay.
                      // Si hay más, mostramos una pila de 3.
                      numberOfCardsDisplayed: state.pets.length < 3
                          ? state.pets.length
                          : 3,

                      // -----------------------
                      onSwipe: (previousIndex, currentIndex, direction) {
                        if (direction == CardSwiperDirection.right) {
                          print(
                            "Me gusta la mascota: ${state.pets[previousIndex].name}",
                          );
                        } else {
                          print(
                            "Descartado: ${state.pets[previousIndex].name}",
                          );
                        }
                        return true;
                      },
                      cardBuilder:
                          (context, index, horizontalOffset, verticalOffset) {
                            final pet = state.pets[index];
                            return _PetCard(pet: pet);
                          },
                    ),
                  ),
                  const SizedBox(height: 20), // Espacio abajo
                ],
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// Widget auxiliar para diseñar la tarjeta individual
class _PetCard extends StatelessWidget {
  final dynamic
  pet; // Usamos dynamic para simplificar importación del modelo, o importa Pet
  const _PetCard({required this.pet});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Imagen de fondo
            CachedNetworkImage(
              imageUrl: pet.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey[200],
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),

            // 2. Sombra degradada (para que se lea el texto)
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: SizedBox(height: 150),
              ),
            ),

            // 3. Información del texto
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${pet.name}, ${pet.age} años",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${pet.breed} • ${pet.type}",
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
