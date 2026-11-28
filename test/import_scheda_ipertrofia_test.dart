import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/services/ai_service.dart';
import 'package:palestra/services/programma_settimane.dart';

/// Il Lunedì (Upper) della scheda ipertrofia da 15 settimane, come l'AI lo
/// deve restituire: tecniche negli esercizi, calendario con RIR e tecniche
/// per settimana, ciclo 2 dalla W6, poi si riparte dalla 6.
Map<String, dynamic> _es(String nome, int serie, String rip, String rir, String rec, [List<String> tecniche = const ['Classico']]) =>
    {'nome': nome, 'workingSet': serie, 'ripetizioni': rip, 'rirTarget': rir, 'recupero': rec, 'tecniche': tecniche};

List<Map<String, dynamic>> _upper({required bool ciclo2}) => [
      _es('Panca inclinata 30-32° al Multipower', ciclo2 ? 5 : 4, '4-6', '1-2', "3-4'"),
      _es('Spinte con manubri su panca piana', 3, '8-10', '1', "2-3'"),
      _es('Croci ai cavi', 2, '12-15', '0-1', "2'", ciclo2 ? ['Rest Pause'] : ['LP']),
      _es('Trazioni alla sbarra', ciclo2 ? 4 : 3, '6-10', '1', "3'"),
      _es('Rematore con appoggio al petto', 3, '8-10', '0-1', "2-3'", ['LP']),
      _es('Parallele (dip)', 2, '6-12', '1', "2-3'"),
      _es('Alzate laterali ai cavi', 3, '12-15', '0-1', "90''", ciclo2 ? ['Drop Set'] : ['Classico']),
      _es('Reverse fly ai cavi', 3, '15-20', '0-1', "90''"),
      _es('Estensioni sopra la testa al cavo', 3, '10-12', '0-1', "2'"),
      _es('Curl alla panca Scott', 3, '10-12', '0-1', "90''", ['LP']),
    ];

final _rispostaAi = {
  'nome': 'Upper - Lunedì',
  'categoria': 'Scheda ipertrofia 3 giorni',
  'esercizi': _upper(ciclo2: false),
  'programma': {'6': _upper(ciclo2: true)},
  'calendario': {
    '1': {'rirDelta': 2, 'tecniche': []},
    '2': {'rirDelta': 1, 'tecniche': ['LP']},
    '3-4': {'rirDelta': 0, 'tecniche': ['LP']},
    '5': {'scarico': true},
    '6': {'rirDelta': 1},
    '7-9': {'rirDelta': 0},
    '10': {'scarico': true},
    '11': {'rirDelta': 1},
    '12-14': {'rirDelta': 0},
    '15': {'scarico': true},
  },
  'durataSettimane': 15,
  'ripartiDaSettimana': 6,
};

void main() {
  late Map<int, List<Esercizio>> settimane;

  setUpAll(() {
    final scheda = Scheda.fromJson(AiService.normalizzaSchedeImportate([_rispostaAi]).single);
    settimane = {1: scheda.esercizi};
    // L'atleta fa ogni settimana: carichi 50 kg dappertutto.
    for (final e in scheda.esercizi) {
      for (final s in e.serieAttive) {
        s.peso = '50';
      }
    }
    for (var w = 2; w <= 16; w++) {
      final passo = ProgrammaSettimane.decidi(
        scheda,
        w,
        haSnapshotAtleta: false,
        ultimaSettimanaNormale: ProgrammaSettimane.ultimaSettimanaNormale(scheda, settimane, corrente: w - 1, attuale: settimane[w - 1]!),
      );
      settimane[w] = (passo as UsaProgramma).esercizi;
    }
  });

  Esercizio es(int w, String inizio) => settimane[w]!.firstWhere((e) => e.nome.startsWith(inizio));

  test('W1: RIR della tabella +2, nessuna tecnica', () {
    expect(es(1, 'Panca inclinata').rirTarget, '3-4');
    expect(es(1, 'Croci').rirTarget, '2-3');
    expect(settimane[1]!.expand((e) => e.tecniche).toSet(), {'Classico'});
  });

  test('W2-4: solo LP, sugli esercizi che la indicano', () {
    for (final w in [2, 3, 4]) {
      expect(es(w, 'Croci').tecniche, ['LP'], reason: 'W$w');
      expect(es(w, 'Rematore').tecniche, ['LP'], reason: 'W$w');
      expect(es(w, 'Curl alla panca Scott').tecniche, ['LP'], reason: 'W$w');
      expect(es(w, 'Alzate laterali').tecniche, ['Classico'], reason: 'W$w');
    }
    expect(es(2, 'Panca inclinata').rirTarget, '2-3');
    expect(es(3, 'Panca inclinata').rirTarget, '1-2');
  });

  test('W5 scarico: metà serie, RIR 4, niente tecniche, stessi carichi', () {
    expect(es(5, 'Panca inclinata').workingSet, 2);
    expect(es(5, 'Croci').workingSet, 1);
    expect(es(5, 'Croci').tecniche, ['Classico']);
    expect(es(5, 'Panca inclinata').rirTarget, '4');
    expect(es(5, 'Panca inclinata').serieAttive.first.peso, '50');
  });

  test('W6 ciclo 2: serie in più, tecniche del ciclo 2, RIR +1, carichi della W4', () {
    expect(es(6, 'Panca inclinata').workingSet, 5);
    expect(es(6, 'Trazioni').workingSet, 4);
    expect(es(6, 'Croci').tecniche, ['Rest Pause']);
    expect(es(6, 'Alzate laterali').tecniche, ['Drop Set']);
    expect(es(6, 'Rematore').tecniche, ['LP']);
    expect(es(6, 'Panca inclinata').rirTarget, '2-3');
    expect(es(6, 'Panca inclinata').serieAttive.map((s) => s.peso).toSet(), {'50'});
  });

  test('W11 come il ciclo 2 con RIR +1; W15 scarico; W16 riparte dalla W6', () {
    expect(es(11, 'Panca inclinata').workingSet, 5);
    expect(es(11, 'Panca inclinata').rirTarget, '2-3');
    expect(es(11, 'Croci').tecniche, ['Rest Pause']);
    expect(es(15, 'Panca inclinata').workingSet, 3);
    expect(es(16, 'Panca inclinata').workingSet, 5);
    expect(es(16, 'Alzate laterali').tecniche, ['Drop Set']);
    expect(es(16, 'Panca inclinata').rirTarget, '2-3');
  });

  test('ogni import ha un id nuovo: niente storico di un import precedente', () {
    final a = AiService.normalizzaSchedeImportate([_rispostaAi, _rispostaAi]);
    final b = AiService.normalizzaSchedeImportate([_rispostaAi]);
    final ids = [...a, ...b].map((s) => Scheda.fromJson(s).id).toList();
    expect(ids.toSet().length, 3);
    expect(ids.every((id) => !id.startsWith('legacy_')), isTrue);
  });
}
