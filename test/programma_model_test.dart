import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/regola_progressione.dart';
import 'package:palestra/models/scheda.dart';

Map<String, dynamic> _es(String nome, {int ws = 3}) =>
    Esercizio(nome: nome, avvicinamento: 0, workingSet: ws, ripetizioni: '8', recupero: '90').toJson();

void main() {
  group('RegolaProgressione', () {
    test('legge numeri con la virgola e vale solo nel suo intervallo', () {
      final r = RegolaProgressione.fromJson({'daSettimana': 2, 'aSettimana': 3, 'incrementoKg': '2,5'})!;
      expect(r.incrementoKg, 2.5);
      expect(r.valePer(2), isTrue);
      expect(r.valePer(3), isTrue);
      expect(r.valePer(4), isFalse);
      expect(r.valePer(1), isFalse);
    });

    test('intervallo rovesciato o senza numeri: solo nota, nessun calcolo', () {
      expect(RegolaProgressione.fromJson({'daSettimana': 5, 'aSettimana': 3, 'incrementoKg': 2})!.haCalcolo, isFalse);
      final soloNota = RegolaProgressione.fromJson({'daSettimana': 1, 'nota': 'scala se stanco'})!;
      expect(soloNota.haCalcolo, isFalse);
      expect(soloNota.nota, 'scala se stanco');
      expect(soloNota.valePer(1), isFalse);
    });

    test('senza fine vale per sempre', () {
      final r = RegolaProgressione.fromJson({'daSettimana': '2', 'incrementoPercentuale': 5})!;
      expect(r.valePer(50), isTrue);
    });

    test('input non valido diventa null', () {
      expect(RegolaProgressione.fromJson(null), isNull);
      expect(RegolaProgressione.fromJson('ciao'), isNull);
      expect(RegolaProgressione.fromJson({'incrementoKg': 2}), isNull);
      expect(RegolaProgressione.fromJson({'daSettimana': 0, 'incrementoKg': 2}), isNull);
    });
  });

  group('Scheda.programma', () {
    test('scarta settimane non valide', () {
      final s = Scheda.fromJson({
        'id': 'a',
        'nome': 'GG1',
        'esercizi': [_es('Panca Piana')],
        'programma': {
          '4': [_es('Panca Piana', ws: 6)],
          'x': [_es('Squat')],
          '0': [_es('Squat')],
          '-2': [_es('Squat')],
        },
      });
      expect(s.programma!.keys, [4]);
      expect(s.programma![4]!.single.workingSet, 6);
    });

    test('round trip conserva programma e progressione', () {
      final es = Esercizio.fromJson(_es('Panca Piana'))
        ..progressione = RegolaProgressione.fromJson({'daSettimana': 2, 'incrementoKg': 2.5, 'nota': '+2,5 kg'});
      final s = Scheda(nome: 'GG1', livello: 'Base', id: 'a', esercizi: [es], programma: {
        10: [Esercizio.fromJson(_es('Panca Piana'))],
      });
      final copia = Scheda.fromJson(s.toJson());
      expect(copia.programma!.keys, [10]);
      expect(copia.esercizi.single.progressione!.incrementoKg, 2.5);
      expect(copia.esercizi.single.progressione!.nota, '+2,5 kg');
    });

    test('cicloSettimane nel round trip', () {
      final s = Scheda(nome: 'GG1', livello: 'Base', id: 'c', esercizi: [], programma: {}, cicloSettimane: 2);
      expect(Scheda.fromJson(s.toJson()).cicloSettimane, 2);
      expect(Scheda.fromJson({'id': 'd', 'nome': 'X', 'esercizi': []}).cicloSettimane, isNull);
    });

    test('scheda fatta a mano: programma null', () {
      final s = Scheda.fromJson({'id': 'b', 'nome': 'X', 'esercizi': []});
      expect(s.programma, isNull);
      expect(Scheda.fromJson(s.toJson()).programma, isNull);
      expect(s.esercizi, isEmpty);
    });
  });
}
