import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/regola_progressione.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/models/serie.dart';
import 'package:palestra/services/programma_settimane.dart';

Esercizio _es(String nome, int serie, {RegolaProgressione? regola, bool fatte = false}) => Esercizio(
      nome: nome,
      avvicinamento: 0,
      workingSet: serie,
      ripetizioni: '8',
      recupero: '90',
      serieAttive: List.generate(serie, (_) => Serie(tipo: 'Working Set', peso: '80', isCompletata: fatte)),
      progressione: regola,
    );

Scheda _programmata() => Scheda(
      nome: 'GG1',
      livello: 'Base',
      id: 'gg1',
      esercizi: [
        _es('Squat', 3, fatte: true),
        _es('Panca Piana', 3, fatte: true,
            regola: const RegolaProgressione(daSettimana: 2, aSettimana: 3, incrementoKg: 2.5)),
      ],
      programma: {
        4: [_es('Panca Piana', 6, fatte: true)],
      },
    );

void main() {
  test('una settimana già modificata dall\'atleta vince su tutto', () {
    expect(ProgrammaSettimane.decidi(_programmata(), 4, haSnapshotAtleta: true), isA<UsaSnapshot>());
  });

  test('settimana scritta nel piano: copia degli esercizi, serie azzerate', () {
    final s = _programmata();
    final passo = ProgrammaSettimane.decidi(s, 4, haSnapshotAtleta: false);
    expect(passo, isA<UsaProgramma>());
    final esercizi = (passo as UsaProgramma).esercizi;
    expect(esercizi.single.serieAttive, hasLength(6));
    expect(esercizi.single.serieAttive.every((x) => !x.isCompletata), isTrue);
    expect(identical(esercizi.single, s.programma![4]!.single), isFalse);
    expect(s.programma![4]!.single.serieAttive.first.isCompletata, isTrue);
  });

  test('regola valida: progressione guidata solo per gli esercizi coperti', () {
    final passo = ProgrammaSettimane.decidi(_programmata(), 3, haSnapshotAtleta: false);
    expect(passo, isA<ProgressioneGuidata>());
    expect((passo as ProgressioneGuidata).regole.keys, [1]);
    expect(passo.regole[1]!.incrementoKg, 2.5);
  });

  test('niente piano e niente regola: copia della precedente', () {
    expect(ProgrammaSettimane.decidi(_programmata(), 5, haSnapshotAtleta: false), isA<CopiaPrecedente>());
  });

  test('regola con intervallo rovesciato non vale', () {
    final s = _programmata();
    s.esercizi[1].progressione = const RegolaProgressione(daSettimana: 5, aSettimana: 3, incrementoKg: 2.5);
    expect(ProgrammaSettimane.decidi(s, 3, haSnapshotAtleta: false), isA<CopiaPrecedente>());
  });

  test('scheda fatta a mano: flusso di sempre', () {
    final s = _programmata()..programma = null;
    expect(ProgrammaSettimane.decidi(s, 2, haSnapshotAtleta: false), isA<FlussoManuale>());
  });

  test('copiaSettimana azzera le serie e cambia settimana, pesi invariati', () {
    final s = _programmata();
    ProgrammaSettimane.copiaSettimana(s, 5);
    expect(s.settimanaCorrente, 5);
    final serie = s.esercizi.expand((e) => e.serieAttive);
    expect(serie.every((x) => !x.isCompletata), isTrue);
    expect(serie.every((x) => x.peso == '80'), isTrue);
  });
}
