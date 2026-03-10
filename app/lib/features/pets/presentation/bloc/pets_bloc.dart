// The presentation layer contains the BLoCs (business logic), screens (UI), and widgets.
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';

// =========================================================================
// Events
// =========================================================================

abstract class PetsEvent extends Equatable {
  @override
  List<Object> get props => [];
}

/// Dispatched to load the initial deck of pets for swiping.
class LoadSwipeDeck extends PetsEvent {}

/// Dispatched when a user swipes left or right on a pet.
class SwipePetEvent extends PetsEvent {
  final int petId;
  final bool isLike;

  SwipePetEvent({required this.petId, required this.isLike});
}

// =========================================================================
// States
// =========================================================================

abstract class PetsState extends Equatable {
  @override
  List<Object> get props => [];
}

class PetsInitial extends PetsState {}
class PetsLoading extends PetsState {}

/// State when the list of pets has been successfully loaded.
class PetsLoaded extends PetsState {
  final List<Pet> pets;
  PetsLoaded(this.pets);

  @override
  List<Object> get props => [pets];
}

/// State for when an error occurs.
class PetsError extends PetsState {
  final String message;
  PetsError(this.message);
}

// =========================================================================
// BLoC
// =========================================================================

/// Manages the business logic for the pet swiping screen.
class PetsBloc extends Bloc<PetsEvent, PetsState> {
  final PetsRepository repository;

  PetsBloc({required this.repository}) : super(PetsInitial()) {
    
    // Handler for loading the swipe deck.
    on<LoadSwipeDeck>((event, emit) async {
      emit(PetsLoading());
      try {
        double? lat, lon;

        // 1. Attempt to get the user's current location.
        try {
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (serviceEnabled) {
            LocationPermission permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
            }

            if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
              // Get position with a timeout to avoid blocking the UI indefinitely.
              Position position = await Geolocator.getCurrentPosition(
                timeLimit: const Duration(seconds: 5),
              );
              lat = position.latitude;
              lon = position.longitude;
              print("Location obtained: $lat, $lon");
            }
          }
        } catch (e) {
          // If GPS fails, proceed without location data. This is not a fatal error.
          print("Could not get GPS (using locationless mode): $e");
        }

        // 2. Call the repository to get the swipe deck, with or without coordinates.
        final pets = await repository.getSwipeDeck(lat: lat, lon: lon);
        emit(PetsLoaded(pets));

      } catch (e) {
        emit(PetsError("Error loading pets: $e"));
      }
    });

    // Handler for the swipe action. This is an optimistic update.
    on<SwipePetEvent>((event, emit) async {
      if (state is PetsLoaded) {
        // Send the request to the backend in the background.
        // The UI is already updated by the card swiper, so we don't need to
        // wait for the response or change the state here.
        repository.swipePet(petId: event.petId, isLike: event.isLike);
      }
    });
  }
}
