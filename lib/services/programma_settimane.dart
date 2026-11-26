import '../models/esercizio.dart';
import '../models/regola_progressione.dart';
import '../models/scheda.dart';
import '../models/serie.dart';

/// Cosa fare passando a una nuova settimana.
sealed class PassoSettimana {
  const PassoSettimana();
}

/// L'atleta ha già quella settimana salvata: si usa la sua.
class UsaSnapshot extends PassoSettimana {
  const UsaSnapshot();
}

/// La settimana è costruita dal piano: questi sono gli esercizi da usare.
class UsaProgramma extends PassoSettimana {
  const UsaProgramma(this.esercizi);

  /// Copie nuove, con le serie da rifare.
  final List<Esercizio> esercizi;
}

/// Ci sono regole di progressione valide: si apre la progressione già compilata.
class ProgressioneGuidata extends PassoSettimana {
  const ProgressioneGuidata(this.regole);

  /// Indice dell'esercizio nella scheda -> regola.
  final Map<int, RegolaProgressione> regole;
}

/// Scheda fatta a mano: comportamento di sempre.
class FlussoManuale extends PassoSettimana {
  const FlussoManuale();
}

/// Settimane di una scheda importata con il piano del coach.
/// I conti (RIR, scarichi, pesi) li fa l'app, non l'AI.
abstract final class ProgrammaSettimane {
  /// Settimana del piano a cui corrisponde [settimana]: finito il programma si
  /// riparte da [Scheda.ripartiDaSettimana] (es. 16 -> 6, oppure 3 -> 1 per A/B).
  static int settimanaEquivalente(Scheda scheda, int settimana) {
    final durata = scheda.durataProgramma;
    final da = scheda.ripartiDaSettimana;
    if (durata == null || da == null || da < 1 || da > durata || settimana <= durata) return settimana;
    final giro = durata - da + 1;
    return da + (settimana - durata - 1) % giro;
  }

  static bool _scarico(Scheda scheda, int settimana) =>
      scheda.calendario?[settimanaEquivalente(scheda, settimana)]?.scarico ?? false;

  /// Decide la settimana [destinazione]. [ultimaSettimanaNormale] sono gli
  /// esercizi dell'ultima settimana non di scarico fatta dall'atleta: da lì
  /// vengono i pesi.
  static PassoSettimana decidi(
    Scheda scheda,
    int destinazione, {
    required bool haSnapshotAtleta,
    required List<Esercizio> ultimaSettimanaNormale,
  }) {
    if (haSnapshotAtleta) return const UsaSnapshot();
    final programma = scheda.programma;
    if (programma == null) return const FlussoManuale();

    final eq = settimanaEquivalente(scheda, destinazione);
    final info = scheda.calendario?[eq];
    final scritta = programma[eq];

    if (scritta == null && !(info?.scarico ?? false)) {
      final regole = <int, RegolaProgressione>{};
      for (var i = 0; i < scheda.esercizi.length; i++) {
        final r = scheda.esercizi[i].progressione;
        if (r != null && r.valePer(destinazione)) regole[i] = r;
      }
      if (regole.isNotEmpty) return ProgressioneGuidata(regole);
    }

    var esercizi = scritta != null
        ? scritta.map((e) => _conPesi(_copia(e), ultimaSettimanaNormale)).toList()
        : ultimaSettimanaNormale.map(_copia).toList();

    final delta = info?.rirDelta;
    if (delta != null) {
      final tabella = _settimanaDiRiferimento(programma, eq);
      for (final e in esercizi) {
        final base = tabella.where((t) => t.nome == e.nome).firstOrNull?.rirTarget ?? e.rirTarget;
        e.rirTarget = spostaRir(base, delta);
      }
    }
    if (info?.scarico ?? false) esercizi = esercizi.map(_scarica).toList();
    return UsaProgramma(esercizi);
  }

  /// Ultima settimana fatta dall'atleta che non sia uno scarico, partendo da
  /// [corrente] (i cui esercizi sono [attuale]) e andando indietro.
  static List<Esercizio> ultimaSettimanaNormale(
    Scheda scheda,
    Map<int, List<Esercizio>> settimane, {
    required int corrente,
    required List<Esercizio> attuale,
  }) {
    for (var w = corrente; w >= 1; w--) {
      final lista = w == corrente ? attuale : settimane[w];
      if (lista != null && !_scarico(scheda, w)) return lista;
    }
    return attuale;
  }

  /// RIR della tabella più [delta]: "1-2" +2 -> "3-4". Testo non numerico invariato.
  static String? spostaRir(String? rir, int delta) {
    if (rir == null) return null;
    final m = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+))?\s*$').firstMatch(rir);
    if (m == null) return rir;
    int sposta(String v) => (int.parse(v) + delta).clamp(0, 10);
    final a = sposta(m.group(1)!);
    return m.group(2) == null ? '$a' : '$a-${sposta(m.group(2)!)}';
  }

  static List<Esercizio> _settimanaDiRiferimento(Map<int, List<Esercizio>> programma, int eq) {
    final chiavi = programma.keys.where((k) => k <= eq).toList()..sort();
    return chiavi.isEmpty ? const [] : programma[chiavi.last]!;
  }

  static Esercizio _copia(Esercizio e) {
    final copia = Esercizio.fromJson(e.toJson());
    for (final s in copia.serieAttive) {
      s.isCompletata = false;
    }
    return copia;
  }

  /// Riporta i pesi dell'atleta sullo stesso esercizio (serie in più: ultimo peso).
  static Esercizio _conPesi(Esercizio e, List<Esercizio> precedente) {
    final prima = precedente.where((p) => p.nome == e.nome).firstOrNull;
    if (prima == null) return e;
    final pesi = prima.serieAttive.where(_lavoro).map((s) => s.peso).where((p) => p.trim().isNotEmpty).toList();
    if (pesi.isEmpty) return e;
    var i = 0;
    for (final s in e.serieAttive.where(_lavoro)) {
      if (s.peso.trim().isEmpty) s.peso = pesi[i < pesi.length ? i : pesi.length - 1];
      i++;
    }
    return e;
  }

  /// Scarico: metà delle serie di lavoro (per eccesso), stessi carichi, RIR 4, niente tecniche.
  static Esercizio _scarica(Esercizio e) {
    final tenute = (e.serieAttive.where(_lavoro).length / 2).ceil();
    var viste = 0;
    final serie = e.serieAttive.where((s) => !_lavoro(s) || viste++ < tenute).map((s) => s.toJson()).toList();
    return Esercizio.fromJson({
      ...e.toJson(),
      'workingSet': (e.workingSet / 2).ceil(),
      'serieAttive': serie,
      'rirTarget': '4',
      'tecniche': ['Classico'],
    });
  }

  static bool _lavoro(Serie s) => s.tipo != 'Avvicinamento';
}
