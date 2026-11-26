import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/services/cartelle.dart';

Scheda _s(String nome, String cartella) => Scheda(nome: nome, livello: 'Base', categoria: cartella, esercizi: []);

void main() {
  group('nomeCartellaLibero', () {
    test('titolo libero resta com\'è', () {
      expect(Cartelle.nomeLibero('Ipertrofia 15 settimane', ['Forza']), 'Ipertrofia 15 settimane');
    });

    test('titolo già usato: numero progressivo', () {
      expect(Cartelle.nomeLibero('Ipertrofia', ['Ipertrofia']), 'Ipertrofia (2)');
      expect(Cartelle.nomeLibero('Ipertrofia', ['Ipertrofia', 'Ipertrofia (2)']), 'Ipertrofia (3)');
    });

    test('confronto senza maiuscole e spazi in più', () {
      expect(Cartelle.nomeLibero(' ipertrofia ', ['Ipertrofia']), 'ipertrofia (2)');
    });

    test('titolo vuoto: Importata AI', () {
      expect(Cartelle.nomeLibero('  ', []), 'Importata AI');
    });
  });

  test('le schede importate finiscono in cartelle non duplicate, giorni dello stesso programma insieme', () {
    final esistenti = [_s('Vecchio Upper', 'Ipertrofia')];
    final importate = [_s('Upper', 'Ipertrofia'), _s('Lower', 'Ipertrofia'), _s('Gambe', 'Forza')];

    Cartelle.assegnaCartelleLibere(importate, esistenti: esistenti, cartelleVuote: ['Forza']);

    expect(importate.map((s) => s.categoria), ['Ipertrofia (2)', 'Ipertrofia (2)', 'Forza (2)']);
    expect(esistenti.single.categoria, 'Ipertrofia');
  });

  test('rimuoviCartella toglie le schede della cartella e la cartella vuota', () {
    final schede = [_s('A', 'Ipertrofia'), _s('B', 'Forza'), _s('C', 'Ipertrofia')];
    final vuote = ['Ipertrofia', 'Mobilità'];

    final tolte = Cartelle.rimuoviCartella('Ipertrofia', schede: schede, cartelleVuote: vuote);

    expect(tolte.map((s) => s.nome), ['A', 'C']);
    expect(schede.map((s) => s.nome), ['B']);
    expect(vuote, ['Mobilità']);
  });
}
