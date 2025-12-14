import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/pets_repository.dart';
import '../../domain/pet_model.dart';

// --- EVENTOS ---
abstract class PetsEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class LoadPets extends PetsEvent {}

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
  @override
  List<Object> get props => [message];
}

// --- BLOC ---
class PetsBloc extends Bloc<PetsEvent, PetsState> {
  final PetsRepository repository;

  PetsBloc(this.repository) : super(PetsInitial()) {
    on<LoadPets>((event, emit) async {
      emit(PetsLoading());
      try {
        final pets = await repository.getPets();
        emit(PetsLoaded(pets));
      } catch (e) {
        emit(PetsError(e.toString()));
      }
    });
  }
}
