import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/regola_progressione.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/models/settimana_piano.dart';
import 'package:palestra/services/riepilogo_import.dart';

Esercizio _es(String nome, int serie, String rip, String? rir, {List<String> tecniche = const ['Classico']}) =>
    Esercizio(nome: nome, avvicinamento: 0, workingSet: serie, ripetizioni: rip, recupero: '180', rirTarget: rir, tecniche: tecniche);

void main() {
  test('riepilogo leggibile di una scheda importata', () {
    final upper = Scheda(
      nome: 'Upper',
      livello: 'Intermedio',
      categoria: 'Ipertrofia 15 settimane',
      esercizi: [
        _es('Panca inclinata', 4, '4-6', '1-2')
          ..progressione = const RegolaProgressione(daSettimana: 2, incrementoKg: 2.5, nota: '+2,5 kg'),
        _es('Croci ai cavi', 2, '12-15', '0-1', tecniche: ['LP']),
      ],
      programma: {
        1: [
          _es('Panca inclinata', 4, '4-6', '1-2')
            ..progressione = const RegolaProgressione(daSettimana: 2, incrementoKg: 2.5, nota: '+2,5 kg'),
          _es('Croci ai cavi', 2, '12-15', '0-1', tecniche: ['LP']),
        ],
        6: [_es('Panca inclinata', 5, '4-6', '1-2')],
      },
      calendario: {
        1: const SettimanaPiano(rirDelta: 2, tecniche: []),
        2: const SettimanaPiano(tecniche: ['LP']),
        5: const SettimanaPiano(scarico: true),
      },
      durataProgramma: 15,
      ripartiDaSettimana: 6,
    );

    final testo = RiepilogoImport.testo([upper]);

    expect(testo, contains('Upper'));
    expect(testo, contains('Ipertrofia 15 settimane'));
    expect(testo, contains('durata 15'));
    expect(testo, contains('riparte dalla W6'));
    expect(testo, contains('W1 RIR +2 nessuna tecnica'));
    expect(testo, contains('W2 solo LP'));
    expect(testo, contains('W5 scarico'));
    expect(testo, contains('Panca inclinata 4x4-6 RIR 1-2'));
    // La W1 del log è quella del piano: tecniche comprese, filtrate poi dal calendario.
    expect(testo, contains('Croci ai cavi 2x12-15 RIR 0-1 [LP] rec 180'));
    expect(testo, contains('progressione da W2: +2.5 kg'));
    expect(testo, contains('W6'));
    expect(testo, contains('Panca inclinata 5x4-6'));
  });

  test('scheda senza piano: solo gli esercizi', () {
    final s = Scheda(nome: 'Push', livello: 'Base', esercizi: [_es('Panca Piana', 3, '8', null)]);
    final testo = RiepilogoImport.testo([s]);
    expect(testo, contains('Push'));
    expect(testo, contains('Panca Piana 3x8'));
    expect(testo, isNot(contains('calendario')));
  });

  test('elenco dei nomi cambiati', () {
    final t = RiepilogoImport.nomiCambiati([('Pressa 45°', 'Chest Press alla Macchina')]);
    expect(t, contains('Pressa 45° -> Chest Press alla Macchina'));
    expect(RiepilogoImport.nomiCambiati([]), isEmpty);
  });
}
