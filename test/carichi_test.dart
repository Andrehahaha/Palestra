import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/models/serie.dart';
import 'package:palestra/services/carichi.dart';

Esercizio _esPerc({
  String nome = 'Panca Piana',
  double? perc = 80,
  double? rm,
  List<Serie>? serie,
}) {
  return Esercizio(
    nome: nome,
    avvicinamento: 0,
    workingSet: 2,
    ripetizioni: '5',
    recupero: '2m',
    modalitaIntensita: 'percentuale',
    percentualeMassimale: perc,
    massimaleKg: rm,
    serieAttive: serie ?? [Serie(tipo: 'Working Set'), Serie(tipo: 'Working Set')],
  );
}

void main() {
  group('riconosciBig3', () {
    test('nomi italiani e varianti', () {
      expect(Carichi.riconosciBig3('Panca Piana'), Big3.panca);
      expect(Carichi.riconosciBig3('panca'), Big3.panca);
      expect(Carichi.riconosciBig3('Panca piana con bilanciere (presa media)'), Big3.panca);
      expect(Carichi.riconosciBig3('Squat completo con bilanciere'), Big3.squat);
      expect(Carichi.riconosciBig3('Stacco da Terra'), Big3.stacco);
      expect(Carichi.riconosciBig3('Stacco con bilanciere'), Big3.stacco);
    });

    test('nomi inglesi', () {
      expect(Carichi.riconosciBig3('Bench Press'), Big3.panca);
      expect(Carichi.riconosciBig3('Back Squat'), Big3.squat);
      expect(Carichi.riconosciBig3('Conventional Deadlift'), Big3.stacco);
    });

    test('non Big 3', () {
      expect(Carichi.riconosciBig3('Curl con manubri'), isNull);
      expect(Carichi.riconosciBig3('Panca inclinata con manubri'), isNull);
      expect(Carichi.riconosciBig3('Front squat con bilanciere'), isNull);
    });
  });

  test('nomeCanonico usa il nome Big 3 o il nome pulito', () {
    expect(Carichi.nomeCanonico('Bench Press'), 'Panca Piana');
    expect(Carichi.nomeCanonico('  Curl con manubri '), 'Curl con manubri');
  });

  group('trovaPr', () {
    test('trova il PR tramite alias e prende il valore massimo', () {
      final prs = {
        'Panca piana con bilanciere (presa media)': 100.0,
        'Panca Piana': 105.0,
        'Squat': 150.0,
      };
      expect(Carichi.trovaPr(prs, 'Bench Press'), 105.0);
      expect(Carichi.trovaPr(prs, 'Squat completo con bilanciere'), 150.0);
    });

    test('null se non Big 3 o PR assente', () {
      expect(Carichi.trovaPr({'Squat': 150.0}, 'Curl'), isNull);
      expect(Carichi.trovaPr({'Squat': 150.0}, 'Stacco da Terra'), isNull);
    });
  });

  test('recordPerPr scrive tutti gli alias', () {
    final r = Carichi.recordPerPr('Stacco da Terra', 200);
    expect(r['Stacco da Terra'], 200);
    expect(r['Deadlift'], 200);
    expect(r.values.toSet(), {200.0});
  });

  group('estraiPercentualeDaTesto', () {
    test('riconosce % e forme testuali', () {
      expect(Carichi.estraiPercentualeDaTesto('5x5 80%'), 80);
      expect(Carichi.estraiPercentualeDaTesto('al 72,5 del massimale'), 72.5);
      expect(Carichi.estraiPercentualeDaTesto('75 percento'), 75);
    });

    test('ignora valori fuori range', () {
      expect(Carichi.estraiPercentualeDaTesto('200%'), isNull);
      expect(Carichi.estraiPercentualeDaTesto('niente'), isNull);
    });
  });

  group('applicaPrAScheda', () {
    test('riempie massimale, carico target e pesi vuoti', () {
      final es = _esPerc();
      final scheda = Scheda(nome: 'A', livello: 'Base', esercizi: [es]);
      final changed = Carichi.applicaPrAScheda(scheda, {'Panca Piana': 100});
      expect(changed, isTrue);
      expect(es.massimaleKg, 100);
      expect(es.caricoTargetKg, 80);
      expect(es.serieAttive.map((s) => s.peso), ['80.0', '80.0']);
      expect(es.serieAttive.map((s) => s.percentualeTarget), ['80', '80']);
    });

    test('non tocca pesi custom e massimale già presente', () {
      final es = _esPerc(rm: 120, serie: [Serie(tipo: 'Working Set', peso: '90')]);
      final scheda = Scheda(nome: 'A', livello: 'Base', esercizi: [es]);
      Carichi.applicaPrAScheda(scheda, {'Panca Piana': 100});
      expect(es.massimaleKg, 120);
      expect(es.serieAttive.single.peso, '90');
    });

    test('ricava la percentuale dal testo se manca', () {
      final es = Esercizio(
        nome: 'Squat',
        avvicinamento: 0,
        workingSet: 1,
        ripetizioni: '3 @ 85%',
        recupero: '3m',
        modalitaIntensita: 'percentuale',
        serieAttive: [Serie(tipo: 'Working Set')],
      );
      Carichi.applicaPrAScheda(Scheda(nome: 'B', livello: 'Base', esercizi: [es]), {'Squat': 200});
      expect(es.percentualeMassimale, 85);
      expect(es.serieAttive.single.peso, '170.0');
    });

    test('ignora esercizi RIR e avvicinamenti', () {
      final rir = Esercizio(nome: 'Panca Piana', avvicinamento: 0, workingSet: 1, ripetizioni: '5', recupero: '2m');
      final perc = _esPerc(serie: [Serie(tipo: 'Avvicinamento'), Serie(tipo: 'Working Set')]);
      Carichi.applicaPrAScheda(Scheda(nome: 'C', livello: 'Base', esercizi: [rir, perc]), {'Panca Piana': 100});
      expect(rir.massimaleKg, isNull);
      expect(perc.serieAttive.first.peso, '');
      expect(perc.serieAttive.last.peso, '80.0');
    });
  });

  group('impostaMassimale', () {
    test('aggiorna pesi vuoti o auto-calcolati, lascia quelli custom', () {
      final es = _esPerc(rm: 100, serie: [
        Serie(tipo: 'Working Set', peso: '80.0', percentualeTarget: '80'),
        Serie(tipo: 'Working Set', peso: '77.5', percentualeTarget: '80'),
        Serie(tipo: 'Working Set', percentualeTarget: '90'),
      ]);
      Carichi.impostaMassimale(es, 110);
      expect(es.massimaleKg, 110);
      expect(es.caricoTargetKg, 88);
      expect(es.serieAttive.map((s) => s.peso), ['88.0', '77.5', '99.0']);
    });
  });

  group('impostaPercentualeSerie', () {
    test('ricalcola il peso se era auto-calcolato', () {
      final s = Serie(tipo: 'Working Set', peso: '80.0', percentualeTarget: '80');
      final es = _esPerc(rm: 100, serie: [s]);
      Carichi.impostaPercentualeSerie(es, s, '85%');
      expect(s.percentualeTarget, '85');
      expect(s.peso, '85.0');
    });

    test('non sovrascrive un peso custom', () {
      final s = Serie(tipo: 'Working Set', peso: '70', percentualeTarget: '80');
      final es = _esPerc(rm: 100, serie: [s]);
      Carichi.impostaPercentualeSerie(es, s, '85');
      expect(s.percentualeTarget, '85');
      expect(s.peso, '70');
    });
  });

  test('kgAttesoSerie', () {
    final s = Serie(tipo: 'Working Set', percentualeTarget: '75');
    final es = _esPerc(rm: 100, serie: [s]);
    expect(Carichi.kgAttesoSerie(es, s), 75);
    expect(Carichi.kgAttesoSerie(es, Serie(tipo: 'Avvicinamento')), isNull);
  });
}
