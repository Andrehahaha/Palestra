import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/services/correzioni_nomi.dart';

Esercizio _es(String nome, String? originale, {int serie = 3}) => Esercizio(
      nome: nome,
      nomeOriginale: originale,
      avvicinamento: 0,
      workingSet: serie,
      ripetizioni: '10',
      recupero: '90',
    );

Scheda _lower() => Scheda(
      nome: 'Lower',
      livello: 'Intermedio',
      esercizi: [
        _es('Squat', 'Squat con bilanciere'),
        _es('Ponte Glutei', 'Hip thrust'),
        _es('Pressa 45°', 'Pressa 45°'),
        _es('Panca Piana', 'Panca Piana'),
        _es('Fatto a mano', null),
      ],
      programma: {
        6: [_es('Ponte Glutei', 'Hip thrust', serie: 3)],
      },
    );

void main() {
  const database = {'Squat', 'Ponte Glutei', 'Hip Thrust con Bilanciere', 'Panca Piana'};

  test('da rivedere: nomi cambiati e nomi fuori dal database, una volta sola', () {
    final voci = CorrezioniNomi.daRivedere([_lower()], database);
    expect(voci.map((v) => v.originale), ['Squat con bilanciere', 'Hip thrust', 'Pressa 45°']);
    expect(voci[2].cambiato, isFalse);
    expect(voci[2].nelDatabase, isFalse);
  });

  test('applica rinomina in tutte le settimane e tiene il resto', () {
    final s = _lower();
    CorrezioniNomi.applica([s], {'Hip thrust': 'Hip Thrust con Bilanciere', 'Squat con bilanciere': 'Squat'});
    expect(s.esercizi[1].nome, 'Hip Thrust con Bilanciere');
    expect(s.esercizi[1].nomeOriginale, 'Hip thrust');
    expect(s.programma![6]!.single.nome, 'Hip Thrust con Bilanciere');
    expect(s.programma![6]!.single.workingSet, 3);
    expect(s.esercizi[0].nome, 'Squat');
    expect(s.esercizi[4].nome, 'Fatto a mano');
  });

  test('nomeOriginale sopravvive al salvataggio', () {
    final copia = Esercizio.fromJson(_es('Ponte Glutei', 'Hip thrust').toJson());
    expect(copia.nomeOriginale, 'Hip thrust');
    expect(_es('A', null).toJson().containsKey('nomeOriginale'), isFalse);
  });
}
