import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/models/serie.dart';
import 'package:palestra/services/pdf_schede.dart';

void main() {
  test('genera un PDF con una pagina per scheda', () async {
    Scheda scheda(String nome) => Scheda(
          nome: nome,
          livello: 'Intermedio',
          esercizi: [
            Esercizio(
              nome: 'Squat',
              avvicinamento: 1,
              workingSet: 3,
              ripetizioni: '5',
              recupero: '180',
              tecniche: const ['Super Set', 'Top Set'],
              note: 'Profondo',
              serieAttive: [Serie(tipo: 'Avvicinamento'), Serie(tipo: 'Working Set'), Serie(tipo: 'Working Set')],
            ),
          ],
        );

    final bytes = await PdfSchede.cartella('Blocco 1', [scheda('A'), scheda('B')]);
    final text = latin1.decode(bytes);
    expect(text.startsWith('%PDF'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
  });
}
