import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/services/stretching_scheda.dart';
import 'package:palestra/services/valutazione_dolore.dart';

Esercizio _es(String nome) =>
    Esercizio(nome: nome, avvicinamento: 0, workingSet: 3, ripetizioni: '8', recupero: '90s');

void main() {
  group('ValutazioneDolore.suggerisci', () {
    test('nessuna risposta: contrattura con confidenza minima', () {
      final e = ValutazioneDolore.suggerisci(const RisposteTestDolore());
      expect(e.tipo, 'Contrattura muscolare');
      expect(e.confidenza, 35);
      expect(e.etichetta, 'Bassa');
    });

    test('dolore ritardato e lieve: DOMS', () {
      final e = ValutazioneDolore.suggerisci(const RisposteTestDolore(
        quando: '24-48h dopo',
        intensita: 'Bassa',
      ));
      expect(e.tipo, 'DOMS (indolenzimento ritardato)');
      expect(e.confidenza, 67);
      expect(e.etichetta, 'Media');
    });

    test('gesto brusco, fitta netta, alta, blocca: strappo con alta confidenza', () {
      final e = ValutazioneDolore.suggerisci(const RisposteTestDolore(
        quando: 'Dopo gesto brusco',
        dove: 'Fitta muscolare netta',
        intensita: 'Alta',
        andamento: 'Blocca il movimento',
      ));
      expect(e.tipo, 'Strappo (lacerazione)');
      expect(e.confidenza, 83);
      expect(e.etichetta, 'Alta');
    });

    test('tendine e carico ripetuto: tendinite', () {
      final e = ValutazioneDolore.suggerisci(const RisposteTestDolore(
        dove: 'Tendine/punto specifico',
        andamento: 'Peggiora con carico ripetuto',
      ));
      expect(e.tipo, 'Tendinite');
      expect(e.confidenza, 95);
    });

    test('ogni tipo suggeribile ha un profilo', () {
      for (final tipo in ValutazioneDolore.tipi) {
        expect(profiliDolore.containsKey(tipo), isTrue, reason: tipo);
      }
    });

    test('ogni opzione del test porta a un tipo con profilo', () {
      final risposte = [
        for (final o in RisposteTestDolore.opzioniQuando) RisposteTestDolore(quando: o),
        for (final o in RisposteTestDolore.opzioniDove) RisposteTestDolore(dove: o),
        for (final o in RisposteTestDolore.opzioniIntensita) RisposteTestDolore(intensita: o),
        for (final o in RisposteTestDolore.opzioniAndamento) RisposteTestDolore(andamento: o),
      ];
      for (final r in risposte) {
        expect(profiliDolore.containsKey(ValutazioneDolore.suggerisci(r).tipo), isTrue);
      }
    });
  });

  group('StretchingScheda.consiglia', () {
    final database = [
      {'nome': 'Panca Piana', 'categoria': 'Petto'},
      {'nome': 'Squat', 'categoria': 'Gambe - Quadricipiti'},
      {'nome': 'Allungamento pettorali', 'categoria': 'Petto', 'isStretching': true},
      {'nome': 'Allungamento quadricipiti', 'categoria': 'Quadricipiti', 'isStretching': true},
      {'nome': 'Allungamento dorsali', 'categoria': 'Dorso', 'isStretching': true},
      {'nome': 'Stretching total body', 'categoria': 'Total body', 'isStretching': true},
    ];

    test('filtra per gruppi della scheda, include total body', () {
      final scheda = Scheda(nome: 'Push', livello: 'Base', esercizi: [_es('Panca Piana')]);
      final c = StretchingScheda.consiglia(scheda, database);
      expect(c.gruppi, {'petto'});
      expect(c.esercizi.map((e) => e['nome']), ['Allungamento pettorali', 'Stretching total body']);
    });

    test('nessun gruppo riconosciuto: tutti gli stretching', () {
      final scheda = Scheda(nome: 'X', livello: 'Base', esercizi: [_es('Sconosciuto')]);
      final c = StretchingScheda.consiglia(scheda, database);
      expect(c.gruppi, isEmpty);
      expect(c.esercizi, hasLength(4));
    });

    test('limite: 8 con 2-3 gruppi, 6 per full body', () {
      final molti = [
        ...database,
        for (var i = 0; i < 10; i++) {'nome': 'Allungamento petto $i', 'categoria': 'Petto', 'isStretching': true},
      ];
      final dueGruppi = Scheda(nome: 'Misto', livello: 'Base', esercizi: [_es('Panca Piana'), _es('Squat')]);
      expect(StretchingScheda.consiglia(dueGruppi, molti).esercizi, hasLength(8));
      final full = Scheda(nome: 'Full Body A', livello: 'Base', esercizi: [_es('Panca Piana'), _es('Squat')]);
      expect(StretchingScheda.consiglia(full, molti).esercizi, hasLength(6));
    });

    test('gruppoMuscolare', () {
      expect(StretchingScheda.gruppoMuscolare('Dorso - Gran dorsale'), 'schiena');
      expect(StretchingScheda.gruppoMuscolare('Bicipiti'), 'braccia');
      expect(StretchingScheda.gruppoMuscolare('???'), 'altro');
    });
  });
}
