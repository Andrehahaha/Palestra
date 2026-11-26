import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/regola_progressione.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/models/serie.dart';
import 'package:palestra/models/settimana_piano.dart';
import 'package:palestra/services/programma_settimane.dart';

Esercizio _es(
  String nome,
  int serie, {
  String? rir,
  String peso = '',
  bool fatte = false,
  List<String> tecniche = const ['Classico'],
  RegolaProgressione? regola,
}) =>
    Esercizio(
      nome: nome,
      avvicinamento: 0,
      workingSet: serie,
      ripetizioni: '4-6',
      recupero: '180',
      tecniche: tecniche,
      rirTarget: rir,
      serieAttive: List.generate(serie, (_) => Serie(tipo: 'Working Set', peso: peso, isCompletata: fatte)),
      progressione: regola,
    );

/// Il Lunedì della scheda ipertrofia: 15 settimane, scarichi, poi si riparte dalla 6.
Scheda _upper() => Scheda(
      nome: 'Upper',
      livello: 'Intermedio',
      id: 'upper',
      esercizi: [_es('Panca inclinata', 4, rir: '1-2'), _es('Croci ai cavi', 2, rir: '0-1', tecniche: ['LP'])],
      programma: {
        1: [_es('Panca inclinata', 4, rir: '1-2'), _es('Croci ai cavi', 2, rir: '0-1', tecniche: ['LP'])],
        6: [_es('Panca inclinata', 5, rir: '1-2'), _es('Croci ai cavi', 2, rir: '0-1', tecniche: ['Rest Pause'])],
      },
      calendario: {
        1: const SettimanaPiano(rirDelta: 2),
        2: const SettimanaPiano(rirDelta: 1),
        3: const SettimanaPiano(rirDelta: 0),
        4: const SettimanaPiano(rirDelta: 0),
        5: const SettimanaPiano(scarico: true),
        6: const SettimanaPiano(rirDelta: 1),
        7: const SettimanaPiano(rirDelta: 0),
        10: const SettimanaPiano(scarico: true),
        15: const SettimanaPiano(scarico: true),
      },
      durataProgramma: 15,
      ripartiDaSettimana: 6,
    );

/// Quello che l'atleta ha fatto nell'ultima settimana normale: 80 kg ovunque.
List<Esercizio> _fatta(int seriePanca) =>
    [_es('Panca inclinata', seriePanca, rir: '1-2', peso: '80', fatte: true), _es('Croci ai cavi', 2, rir: '0-1', peso: '20', fatte: true)];

List<Esercizio> _settimana(Scheda s, int w, {int seriePanca = 4}) =>
    (ProgrammaSettimane.decidi(s, w, haSnapshotAtleta: false, ultimaSettimanaNormale: _fatta(seriePanca)) as UsaProgramma)
        .esercizi;

void main() {
  group('settimanaEquivalente', () {
    test('dopo la fine si riparte dalla settimana indicata', () {
      final s = _upper();
      expect(ProgrammaSettimane.settimanaEquivalente(s, 3), 3);
      expect(ProgrammaSettimane.settimanaEquivalente(s, 15), 15);
      expect(ProgrammaSettimane.settimanaEquivalente(s, 16), 6);
      expect(ProgrammaSettimane.settimanaEquivalente(s, 25), 15);
      expect(ProgrammaSettimane.settimanaEquivalente(s, 26), 6);
    });

    test('schede A/B: durata 2, si riparte dalla 1', () {
      final s = _upper()
        ..durataProgramma = 2
        ..ripartiDaSettimana = 1;
      expect(ProgrammaSettimane.settimanaEquivalente(s, 3), 1);
      expect(ProgrammaSettimane.settimanaEquivalente(s, 4), 2);
    });

    test('senza ripartenza la settimana resta quella', () {
      final s = _upper()..ripartiDaSettimana = null;
      expect(ProgrammaSettimane.settimanaEquivalente(s, 20), 20);
    });
  });

  group('spostaRir', () {
    test('somma la differenza a valori e intervalli', () {
      expect(ProgrammaSettimane.spostaRir('1-2', 2), '3-4');
      expect(ProgrammaSettimane.spostaRir('0-1', 2), '2-3');
      expect(ProgrammaSettimane.spostaRir('2', 1), '3');
      expect(ProgrammaSettimane.spostaRir('1', -3), '0');
      expect(ProgrammaSettimane.spostaRir('1-2', 0), '1-2');
    });

    test('testo non numerico o vuoto resta com\'è', () {
      expect(ProgrammaSettimane.spostaRir('facile', 2), 'facile');
      expect(ProgrammaSettimane.spostaRir(null, 2), isNull);
    });
  });

  group('costruzione della settimana', () {
    test('W2: struttura del piano, RIR tabella +1, pesi dell\'ultima settimana, serie da rifare', () {
      final w2 = _settimana(_upper(), 2);
      expect(w2.first.workingSet, 4);
      expect(w2.first.rirTarget, '2-3');
      expect(w2.first.serieAttive.map((s) => s.peso), everyElement('80'));
      expect(w2.expand((e) => e.serieAttive).every((s) => !s.isCompletata), isTrue);
    });

    test('W5 scarico: metà delle serie per eccesso, RIR 4, niente tecniche, stessi carichi', () {
      final w5 = _settimana(_upper(), 5);
      expect(w5.first.workingSet, 2);
      expect(w5.first.serieAttive.where((s) => s.tipo != 'Avvicinamento'), hasLength(2));
      expect(w5[1].workingSet, 1);
      expect(w5.map((e) => e.rirTarget), everyElement('4'));
      expect(w5[1].tecniche, ['Classico']);
      expect(w5.first.serieAttive.map((s) => s.peso), everyElement('80'));
    });

    test('W6 dopo lo scarico: settimana scritta, 5 serie, pesi riportati anche sulla serie nuova', () {
      final w6 = _settimana(_upper(), 6);
      expect(w6.first.workingSet, 5);
      expect(w6.first.rirTarget, '2-3');
      expect(w6.first.serieAttive.map((s) => s.peso), everyElement('80'));
      expect(w6[1].tecniche, ['Rest Pause']);
    });

    test('W8: struttura della W6 (ultima scritta), RIR tabella', () {
      final w8 = _settimana(_upper(), 8, seriePanca: 5);
      expect(w8.first.workingSet, 5);
      expect(w8.first.rirTarget, '1-2');
    });

    test('W16 riparte dalla W6', () {
      final w16 = _settimana(_upper(), 16);
      expect(w16.first.workingSet, 5);
      expect(w16.first.rirTarget, '2-3');
    });

    test('schede A/B: W3 è di nuovo A', () {
      final ab = Scheda(
        nome: 'GG1',
        livello: 'Base',
        esercizi: [_es('Squat', 3)],
        programma: {
          1: [_es('Squat', 3)],
          2: [_es('Stacco da Terra', 4)],
        },
        durataProgramma: 2,
        ripartiDaSettimana: 1,
      );
      final w3 = (ProgrammaSettimane.decidi(ab, 3, haSnapshotAtleta: false, ultimaSettimanaNormale: [_es('Stacco da Terra', 4)])
              as UsaProgramma)
          .esercizi;
      expect(w3.single.nome, 'Squat');
      final w4 = (ProgrammaSettimane.decidi(ab, 4, haSnapshotAtleta: false, ultimaSettimanaNormale: w3) as UsaProgramma).esercizi;
      expect(w4.single.nome, 'Stacco da Terra');
    });
  });

  group('casi che restano come prima', () {
    test('una settimana già fatta dall\'atleta vince su tutto', () {
      expect(ProgrammaSettimane.decidi(_upper(), 2, haSnapshotAtleta: true, ultimaSettimanaNormale: _fatta(4)), isA<UsaSnapshot>());
    });

    test('regola di progressione valida e settimana non scritta: progressione guidata', () {
      final s = _upper()..calendario = null;
      s.esercizi[0].progressione = const RegolaProgressione(daSettimana: 2, aSettimana: 3, incrementoKg: 2.5);
      final passo = ProgrammaSettimane.decidi(s, 3, haSnapshotAtleta: false, ultimaSettimanaNormale: _fatta(4));
      expect(passo, isA<ProgressioneGuidata>());
      expect((passo as ProgressioneGuidata).regole.keys, [0]);
    });

    test('scheda fatta a mano: flusso di sempre', () {
      final s = _upper()..programma = null;
      expect(ProgrammaSettimane.decidi(s, 2, haSnapshotAtleta: false, ultimaSettimanaNormale: _fatta(4)), isA<FlussoManuale>());
    });
  });

  test('ultimaSettimanaNormale salta gli scarichi', () {
    final s = _upper();
    final settimane = {3: _fatta(4), 4: [_es('Panca inclinata', 4, peso: '82.5')], 5: [_es('Panca inclinata', 2, peso: '82.5')]};
    final ultima = ProgrammaSettimane.ultimaSettimanaNormale(s, settimane, corrente: 5, attuale: settimane[5]!);
    expect(ultima.single.workingSet, 4);
    expect(ProgrammaSettimane.ultimaSettimanaNormale(s, settimane, corrente: 4, attuale: settimane[4]!).single.workingSet, 4);
  });
}
