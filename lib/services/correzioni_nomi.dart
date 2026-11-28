import '../models/esercizio.dart';
import '../models/scheda.dart';

/// Un nome letto dal documento e quello scelto per l'app.
class VoceNome {
  const VoceNome({required this.originale, required this.scelto, required this.nelDatabase});

  final String originale;
  final String scelto;

  /// Se [scelto] ha foto e scheda nel database degli esercizi.
  final bool nelDatabase;

  bool get cambiato => originale != scelto;
}

/// Revisione dei nomi dopo un import: cosa far controllare e come applicare
/// le correzioni a tutte le settimane.
abstract final class CorrezioniNomi {
  /// Nomi da controllare: cambiati rispetto al documento o non trovati nel
  /// database. Uno per nome del documento, nell'ordine in cui compaiono.
  static List<VoceNome> daRivedere(List<Scheda> schede, Set<String> database) {
    final voci = <String, VoceNome>{};
    for (final e in _tutti(schede)) {
      final originale = e.nomeOriginale;
      if (originale == null || voci.containsKey(originale)) continue;
      final voce = VoceNome(originale: originale, scelto: e.nome, nelDatabase: database.contains(e.nome));
      if (voce.cambiato || !voce.nelDatabase) voci[originale] = voce;
    }
    return voci.values.toList();
  }

  /// Rinomina, in tutte le settimane, gli esercizi letti come [scelte].keys.
  static void applica(List<Scheda> schede, Map<String, String> scelte) {
    Esercizio rinominato(Esercizio e) {
      final nuovo = scelte[e.nomeOriginale];
      return nuovo == null || nuovo == e.nome ? e : Esercizio.fromJson({...e.toJson(), 'nome': nuovo});
    }

    List<Esercizio> rinomina(List<Esercizio> lista) => lista.map(rinominato).toList();
    for (final s in schede) {
      s.esercizi = rinomina(s.esercizi);
      final programma = s.programma;
      if (programma == null) continue;
      for (final w in programma.keys.toList()) {
        programma[w] = rinomina(programma[w]!);
      }
    }
  }

  static Iterable<Esercizio> _tutti(List<Scheda> schede) sync* {
    for (final s in schede) {
      yield* s.esercizi;
      for (final lista in s.programma?.values ?? const <List<Esercizio>>[]) {
        yield* lista;
      }
    }
  }
}
