import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/regola_progressione.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/screens/settimana_successiva_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Esercizio _es(String nome) =>
    Esercizio(nome: nome, avvicinamento: 0, workingSet: 3, ripetizioni: '8', recupero: '90');

String _testoCampo(WidgetTester tester, String label) {
  final campo = find.ancestor(of: find.text(label), matching: find.byType(TextField));
  return tester.widget<TextField>(campo.first).controller!.text;
}

void main() {
  testWidgets('la regola del coach precompila la progressione', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final scheda = Scheda(nome: 'GG1', livello: 'Base', esercizi: [_es('Panca Piana'), _es('Squat')]);

    await tester.pumpWidget(MaterialApp(
      home: SettimanaSuccessivaScreen(
        scheda: scheda,
        regolePrecompilate: const {
          0: RegolaProgressione(daSettimana: 2, incrementoKg: 2.5, rirTarget: '2', nota: '+2,5 kg a settimana'),
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(_testoCampo(tester, 'Incremento carico opzionale (kg)'), '2.5');
    expect(_testoCampo(tester, 'Nuovo target RIR'), '2');
    expect(find.textContaining('+2,5 kg a settimana'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Squat'), 200, scrollable: find.byType(Scrollable).first);
    final campiKg = find.ancestor(of: find.text('Incremento carico opzionale (kg)'), matching: find.byType(TextField));
    expect(tester.widget<TextField>(campiKg.last).controller!.text, '');
  });
}
