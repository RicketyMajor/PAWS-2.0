import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';

// --- EVENTOS ---
abstract class PetsEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class LoadSwipeDeck extends PetsEvent {}

class SwipePetEvent extends PetsEvent {
  final int petId;
  final bool isLike;

  SwipePetEvent({required this.petId, required this.isLike});
}

// --- ESTADOS ---
abstract class PetsState extends Equatable {
  @override
  List<Object> get props => [];
}

class PetsInitial extends PetsState {}

class PetsLoading extends PetsState {}

class PetsLoaded extends PetsState {
  final List<Pet> pets;
  PetsLoaded(this.pets);

  @override
  List<Object> get props => [pets];
}

class PetsError extends PetsState {
  final String message;
  PetsError(this.message);
}

// --- BLOC ---
class PetsBloc extends Bloc<PetsEvent, PetsState> {
  final PetsRepository repository;

  PetsBloc({required this.repository}) : super(PetsInitial()) {
    // Cargar mazo
    on<LoadSwipeDeck>((event, emit) async {
      emit(PetsLoading());
      try {
        final pets = await repository.getSwipeDeck();
        emit(PetsLoaded(pets));
      } catch (e) {
        emit(PetsError(e.toString()));
      }
    });

    // Manejar Swipe (Optimista: no esperamos respuesta del server para actualizar UI)
    on<SwipePetEvent>((event, emit) async {
      if (state is PetsLoaded) {
        // Ejecutamos la petición al backend en background
        repository.swipePet(petId: event.petId, isLike: event.isLike);

        // Nota: flutter_card_swiper maneja la UI visualmente,
        // pero aquí podríamos remover la mascota de la lista local si quisiéramos.
      }
    });
  }
}
