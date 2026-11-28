import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/screens/revisione_nomi.dart';
import 'package:palestra/services/correzioni_nomi.dart';

void main() {
  testWidgets('correggo un nome dal database e ne tengo uno del documento', (tester) async {
    Map<String, String>? scelte;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            scelte = await Navigator.push<Map<String, String>>(
              context,
              MaterialPageRoute(
                builder: (_) => const RevisioneNomiScreen(
                  voci: [
                    VoceNome(originale: 'Hip thrust', scelto: 'Ponte Glutei', nelDatabase: true),
                    VoceNome(originale: 'Croci ai cavi dal basso', scelto: 'Croci su Panca Piana', nelDatabase: true),
                  ],
                  database: ['Croci su Panca Piana', 'Hip Thrust con Bilanciere', 'Ponte Glutei'],
                ),
              ),
            );
          },
          child: const Text('apri'),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('Nel documento: Hip thrust'), findsOneWidget);

    await tester.tap(find.text('Ponte Glutei'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hip Thrust con Bilanciere'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Croci su Panca Piana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tieni "Croci ai cavi dal basso"'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conferma nomi'));
    await tester.pumpAndSettle();
    expect(scelte, {'Hip thrust': 'Hip Thrust con Bilanciere', 'Croci ai cavi dal basso': 'Croci ai cavi dal basso'});
  });
}
