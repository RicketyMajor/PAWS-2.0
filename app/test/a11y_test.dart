// Accessibility guards for the adopter's main journey (F3).
//
// An icon-only button with no semanticLabel is announced as just "button", and
// text scaled to 200% must not blow the card's layout. Both were measured, not
// assumed: a card-merging test was written first and dropped after a mutation
// showed it passed with the code removed — Flutter already merges the card.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paws_app/features/pets/data/pets_repository.dart';
import 'package:paws_app/features/pets/domain/pet_model.dart';
import 'package:paws_app/features/pets/presentation/bloc/pets_bloc.dart';
import 'package:paws_app/features/pets/presentation/screens/match_screen.dart';
import 'package:paws_app/features/pets/presentation/widgets/pet_card.dart';

/// noSuchMethod keeps AuthRepository, Dio and secure storage out of the test.
class _StubRepo implements PetsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoadedPetsBloc extends PetsBloc {
  _LoadedPetsBloc(List<Pet> pets) : super(repository: _StubRepo()) {
    emit(PetsLoaded(pets));
  }
}

Pet _luna() => Pet(
  id: 1,
  name: 'Luna',
  type: 'Dog',
  breed: 'Labrador',
  age: 3,
  description: 'Tranquila y cariñosa.',
  // null keeps the widget on its placeholder: no network in a widget test.
  imageUrl: null,
  ownerName: 'Rescatista',
  goodWithKids: true,
);

Widget _screen(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 800, child: child)),
);

void main() {
  testWidgets('the deck action buttons carry an accessible name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final bloc = _LoadedPetsBloc([_luna()]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      _screen(
        BlocProvider<PetsBloc>.value(value: bloc, child: const MatchView()),
      ),
    );
    await tester.pump();

    // A tooltip alone lands on the node as `tooltip` and leaves `label` empty,
    // so these pass only while the icons also carry a semanticLabel.
    expect(find.bySemanticsLabel('Descartar esta mascota'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Enviar solicitud de adopción'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('the card survives text at 200% without overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _screen(PetCard(pet: _luna())),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
