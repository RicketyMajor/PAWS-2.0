import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';
import 'package:geolocator/geolocator.dart';

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
    // Cargar mazo con GPS
    on<LoadSwipeDeck>((event, emit) async {
      emit(PetsLoading());
      try {
        double? lat, lon;

        // 1. Intentar obtener ubicación
        try {
          // Verificar servicio habilitado
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (serviceEnabled) {
            // Verificar permisos
            LocationPermission permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
            }

            if (permission == LocationPermission.whileInUse ||
                permission == LocationPermission.always) {
              // Obtener posición (Timeout de 5s para no bloquear la app)
              Position position = await Geolocator.getCurrentPosition(
                timeLimit: const Duration(seconds: 5),
              );
              lat = position.latitude;
              lon = position.longitude;
            }
          }
        } catch (e) {
          print("No se pudo obtener GPS (usando modo sin ubicación): $e");
          // No lanzamos error, simplemente cargamos sin geolocalización
        }

        // 2. Llamar al repo (con o sin coordenadas)
        final pets = await repository.getSwipeDeck(lat: lat, lon: lon);

        emit(PetsLoaded(pets));
      } catch (e) {
        emit(PetsError("Error cargando mascotas: $e"));
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
