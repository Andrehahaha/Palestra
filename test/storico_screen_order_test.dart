import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/allenamento.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/screens/storico_screen.dart';

Allenamento _makeAllenamento({
  required String nomeScheda,
  required DateTime data,
}) {
  final esercizio = Esercizio(
    nome: 'Panca Piana',
    avvicinamento: 0,
    workingSet: 1,
    ripetizioni: '5',
    recupero: '120',
  );

  final scheda = Scheda(
    nome: nomeScheda,
    livello: 'Intermedio',
    esercizi: [esercizio],
  );

  return Allenamento(data: data, scheda: scheda);
}

void main() {
  testWidgets('StoricoScreen shows newest workout first', (tester) async {
    final oldWorkout = _makeAllenamento(
      nomeScheda: 'Scheda Vecchia',
      data: DateTime(2025, 1, 1, 10, 0),
    );
    final newWorkout = _makeAllenamento(
      nomeScheda: 'Scheda Nuova',
      data: DateTime(2025, 1, 2, 10, 0),
    );

    // Deliberately pass unsorted data to ensure UI sorting is applied.
    final storico = <Allenamento>[oldWorkout, newWorkout];

    await tester.pumpWidget(
      MaterialApp(
        home: StoricoScreen(
          storico: storico,
          onUpdate: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ExpansionTile>(find.byType(ExpansionTile)).toList();
    expect(tiles.isNotEmpty, true);

    final firstTitle = tiles.first.title as Text;
    expect(firstTitle.data, 'Scheda Nuova');
  });
}
