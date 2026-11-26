import '../models/scheda.dart';

/// Cartelle delle schede (la categoria della scheda è la sua cartella).
abstract final class Cartelle {
  static const String predefinitaImport = 'Importata AI';

  static String _chiave(String nome) => nome.trim().toLowerCase();

  /// [titolo] se nessuna cartella si chiama così, altrimenti "titolo (2)", "(3)"...
  static String nomeLibero(String titolo, Iterable<String> esistenti) {
    final base = titolo.trim().isEmpty ? predefinitaImport : titolo.trim();
    final usati = esistenti.map(_chiave).toSet();
    if (!usati.contains(_chiave(base))) return base;
    var n = 2;
    while (usati.contains(_chiave('$base ($n)'))) {
      n++;
    }
    return '$base ($n)';
  }

  /// Dà alle schede importate cartelle che non esistono già. I giorni dello
  /// stesso programma (stessa categoria) restano nella stessa cartella.
  static void assegnaCartelleLibere(
    List<Scheda> importate, {
    required Iterable<Scheda> esistenti,
    required Iterable<String> cartelleVuote,
  }) {
    final occupate = {...esistenti.map((s) => s.categoria), ...cartelleVuote};
    final rinominate = <String, String>{};
    for (final s in importate) {
      final nuovo = rinominate.putIfAbsent(s.categoria, () {
        final libero = nomeLibero(s.categoria, occupate);
        occupate.add(libero);
        return libero;
      });
      s.categoria = nuovo;
    }
  }

  /// Toglie la cartella [nome] con tutte le sue schede. Restituisce le schede tolte.
  static List<Scheda> rimuoviCartella(
    String nome, {
    required List<Scheda> schede,
    required List<String> cartelleVuote,
  }) {
    final tolte = schede.where((s) => s.categoria == nome).toList();
    schede.removeWhere((s) => s.categoria == nome);
    cartelleVuote.remove(nome);
    return tolte;
  }
}
