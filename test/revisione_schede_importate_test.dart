import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/screens/import_da_file.dart';

Scheda _giorno(String nome, {int settimane = 0}) => Scheda(
      nome: nome,
      livello: 'Principiante',
      esercizi: [Esercizio(nome: 'Squat', avvicinamento: 0, workingSet: 3, ripetizioni: '5', recupero: '180')],
      programma: {for (var w = 2; w < 2 + settimane; w++) w: []},
    );

void main() {
  testWidgets('il coach vede tutti i giorni e li invia tutti', (tester) async {
    List<Scheda>? inviate;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            inviate = await Navigator.push<List<Scheda>>(
              context,
              MaterialPageRoute(
                builder: (_) => RevisioneSchedeImportateScreen(schede: [_giorno('GG1', settimane: 2), _giorno('GG2')]),
              ),
            );
          },
          child: const Text('apri'),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    expect(find.text('GG1'), findsOneWidget);
    expect(find.text('GG2'), findsOneWidget);
    expect(find.textContaining('2 settimane nel piano'), findsOneWidget);

    await tester.tap(find.text('Invia tutti (2)'));
    await tester.pumpAndSettle();
    expect(inviate!.map((s) => s.nome), ['GG1', 'GG2']);
  });

  testWidgets('modificare un giorno sostituisce quel giorno nella lista', (tester) async {
    List<Scheda>? inviate;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            inviate = await Navigator.push<List<Scheda>>(
              context,
              MaterialPageRoute(builder: (_) => RevisioneSchedeImportateScreen(schede: [_giorno('GG1'), _giorno('GG2')])),
            );
          },
          child: const Text('apri'),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GG2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'GG2 rivisto');
    await tester.tap(find.text('SALVA SCHEDA'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invia tutti (2)'));
    await tester.pumpAndSettle();
    expect(inviate!.map((s) => s.nome), ['GG1', 'GG2 rivisto']);
  });
}
