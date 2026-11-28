import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/regola_progressione.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/models/settimana_piano.dart';
import 'package:palestra/screens/crea_scheda.dart';

void main() {
  testWidgets('salvare una scheda importata non perde id, piano e regole', (tester) async {
    final originale = Scheda(
      id: 'sch_import_1',
      nome: 'GG1',
      livello: 'Principiante',
      categoria: 'Forza 12 settimane',
      esercizi: [
        Esercizio(
          nome: 'Panca Piana',
          avvicinamento: 0,
          workingSet: 3,
          ripetizioni: '8',
          recupero: '120',
          progressione: const RegolaProgressione(daSettimana: 2, incrementoKg: 2.5, nota: '+2,5 kg'),
        ),
      ],
      programma: {
        4: [Esercizio(nome: 'Panca Piana', avvicinamento: 0, workingSet: 6, ripetizioni: '6', recupero: '120')],
      },
    );

    Scheda? salvata;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              salvata = await Navigator.push<Scheda>(
                context,
                MaterialPageRoute(builder: (_) => CreaSchedaScreen(schedaDaModificare: originale)),
              );
            },
            child: const Text('apri'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SALVA SCHEDA'));
    await tester.pumpAndSettle();

    expect(salvata, isNotNull);
    expect(salvata!.id, 'sch_import_1');
    expect(salvata!.programma!.keys, [4]);
    expect(salvata!.programma![4]!.single.workingSet, 6);
    expect(salvata!.esercizi.single.progressione!.incrementoKg, 2.5);
  });

  testWidgets('modificare la settimana 1 aggiorna la W1 del piano', (tester) async {
    final originale = Scheda(
      id: 'ab',
      nome: 'GG1',
      livello: 'Principiante',
      esercizi: [Esercizio(nome: 'Squat', avvicinamento: 0, workingSet: 3, ripetizioni: '5', recupero: '180')],
      programma: {
        1: [Esercizio(nome: 'Squat', avvicinamento: 0, workingSet: 99, ripetizioni: '5', recupero: '180')],
        2: [Esercizio(nome: 'Stacco da Terra', avvicinamento: 0, workingSet: 4, ripetizioni: '4', recupero: '180')],
      },
      durataProgramma: 2,
      ripartiDaSettimana: 1,
    );

    Scheda? salvata;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            salvata = await Navigator.push<Scheda>(
              context,
              MaterialPageRoute(builder: (_) => CreaSchedaScreen(schedaDaModificare: originale)),
            );
          },
          child: const Text('apri'),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'GG1 rivisto');
    await tester.tap(find.text('SALVA SCHEDA'));
    await tester.pumpAndSettle();

    expect(salvata!.programma![1]!.single.workingSet, 3);
    expect(identical(salvata!.programma![1]!.single, salvata!.esercizi.single), isFalse);
    expect(salvata!.programma![2]!.single.nome, 'Stacco da Terra');
    expect(salvata!.durataProgramma, 2);
    expect(salvata!.ripartiDaSettimana, 1);
  });

  testWidgets('salvare in W1 non toglie dal piano le tecniche nascoste dal calendario', (tester) async {
    Esercizio croci(List<String> tecniche) =>
        Esercizio(nome: 'Croci ai cavi', avvicinamento: 0, workingSet: 2, ripetizioni: '12-15', recupero: '120', tecniche: tecniche);
    final originale = Scheda(
      id: 'lp',
      nome: 'Upper',
      livello: 'Intermedio',
      esercizi: [croci(['Classico'])],
      programma: {1: [croci(['LP'])]},
      calendario: {1: const SettimanaPiano(rirDelta: 2, tecniche: [])},
    );

    Scheda? salvata;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            salvata = await Navigator.push<Scheda>(
              context,
              MaterialPageRoute(builder: (_) => CreaSchedaScreen(schedaDaModificare: originale)),
            );
          },
          child: const Text('apri'),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SALVA SCHEDA'));
    await tester.pumpAndSettle();

    expect(salvata!.programma![1]!.single.tecniche, ['LP']);
    expect(salvata!.esercizi.single.tecniche, ['Classico']);
  });
}
