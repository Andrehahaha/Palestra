import '../models/scheda.dart';
import 'carichi.dart';

/// Stretching consigliati per una scheda.
class StretchingConsigliato {
  const StretchingConsigliato({required this.gruppi, required this.esercizi});

  /// Gruppi muscolari allenati dalla scheda (es. `petto`, `gambe`).
  final Set<String> gruppi;

  /// Esercizi di stretching dal database, ordinati per nome.
  final List<Map<String, dynamic>> esercizi;
}

/// Sceglie gli stretching del database adatti ai gruppi muscolari di una scheda.
abstract final class StretchingScheda {
  /// Raggruppa una categoria del database in un gruppo muscolare
  /// (`petto`, `schiena`, `spalle`, `braccia`, `gambe`, `core`, `total`, `altro`).
  static String gruppoMuscolare(String categoria) {
    final c = Carichi.normalizza(categoria);
    bool any(List<String> parole) => parole.any(c.contains);

    if (any(['petto', 'pettoral'])) return 'petto';
    if (any(['dorso', 'schiena', 'lombar', 'trapez', 'lat'])) return 'schiena';
    if (any(['spall', 'deltoid'])) return 'spalle';
    if (any(['bicip', 'tricip', 'avambr', 'bracci'])) return 'braccia';
    if (any(['gambe', 'quadric', 'femoral', 'glute', 'polpacc', 'addutt', 'abdutt'])) return 'gambe';
    if (any(['core', 'addom', 'obliqu'])) return 'core';
    if (c.contains('total')) return 'total';
    return 'altro';
  }

  /// Stretching per [scheda] presi da [database] (esercizi con `isStretching`).
  /// Se nessun gruppo della scheda è riconosciuto, propone tutti gli stretching.
  static StretchingConsigliato consiglia(Scheda scheda, List<Map<String, dynamic>> database) {
    final gruppi = _gruppiScheda(scheda, database);
    final tutti = database.where((es) => es['isStretching'] == true).toList();

    var risultati = gruppi.isEmpty
        ? tutti
        : tutti.where((es) {
            final g = gruppoMuscolare((es['categoria'] ?? '').toString());
            return gruppi.contains(g) || g == 'total';
          }).toList();
    if (risultati.isEmpty) risultati = tutti;

    risultati.sort((a, b) => (a['nome'] ?? '').toString().compareTo((b['nome'] ?? '').toString()));
    return StretchingConsigliato(
      gruppi: gruppi,
      esercizi: risultati.take(_limite(scheda, gruppi)).toList(),
    );
  }

  static Set<String> _gruppiScheda(Scheda scheda, List<Map<String, dynamic>> database) {
    final gruppi = <String>{};
    for (final es in scheda.esercizi) {
      final nome = Carichi.normalizza(Carichi.traduci(es.nome));
      for (final db in database) {
        if (Carichi.normalizza((db['nome'] ?? '').toString()) == nome) {
          gruppi.add(gruppoMuscolare((db['categoria'] ?? '').toString()));
          break;
        }
      }
    }
    gruppi.remove('altro');
    return gruppi;
  }

  static int _limite(Scheda scheda, Set<String> gruppi) {
    final nome = Carichi.normalizza(scheda.nome);
    final categoria = Carichi.normalizza(scheda.categoria);
    final fullBody = nome.contains('full body') ||
        nome.contains('total body') ||
        categoria.contains('full body') ||
        categoria.contains('total');
    if (fullBody) return 6;
    if (gruppi.length >= 4) return 7;
    if (gruppi.length >= 2) return 8;
    return 6;
  }
}
