import '../models/esercizio.dart';
import '../models/regola_progressione.dart';
import '../models/scheda.dart';

/// Cosa fare passando a una nuova settimana.
sealed class PassoSettimana {
  const PassoSettimana();
}

/// L'atleta ha già quella settimana salvata: si usa la sua.
class UsaSnapshot extends PassoSettimana {
  const UsaSnapshot();
}

/// La settimana è scritta nel piano del coach.
class UsaProgramma extends PassoSettimana {
  const UsaProgramma(this.esercizi);

  /// Copie degli esercizi del piano, con le serie azzerate.
  final List<Esercizio> esercizi;
}

/// Ci sono regole di progressione valide: si apre la progressione già compilata.
class ProgressioneGuidata extends PassoSettimana {
  const ProgressioneGuidata(this.regole);

  /// Indice dell'esercizio nella scheda -> regola.
  final Map<int, RegolaProgressione> regole;
}

/// Scheda programmata senza indicazioni per quella settimana: uguale alla precedente.
class CopiaPrecedente extends PassoSettimana {
  const CopiaPrecedente();
}

/// Scheda fatta a mano: comportamento di sempre.
class FlussoManuale extends PassoSettimana {
  const FlussoManuale();
}

abstract final class ProgrammaSettimane {
  static PassoSettimana decidi(Scheda scheda, int destinazione, {required bool haSnapshotAtleta}) {
    if (haSnapshotAtleta) return const UsaSnapshot();
    final programma = scheda.programma;
    if (programma == null) return const FlussoManuale();

    final scritta = programma[destinazione];
    if (scritta != null) {
      return UsaProgramma(scritta.map(_copiaAzzerata).toList());
    }

    final regole = <int, RegolaProgressione>{};
    for (var i = 0; i < scheda.esercizi.length; i++) {
      final r = scheda.esercizi[i].progressione;
      if (r != null && r.valePer(destinazione)) regole[i] = r;
    }
    if (regole.isNotEmpty) return ProgressioneGuidata(regole);
    return const CopiaPrecedente();
  }

  /// La scheda passa a [destinazione] con gli stessi esercizi e le serie da rifare.
  static void copiaSettimana(Scheda scheda, int destinazione) {
    for (final s in scheda.esercizi.expand((e) => e.serieAttive)) {
      s.isCompletata = false;
    }
    scheda.settimanaCorrente = destinazione;
  }

  static Esercizio _copiaAzzerata(Esercizio e) {
    final copia = Esercizio.fromJson(e.toJson());
    for (final s in copia.serieAttive) {
      s.isCompletata = false;
    }
    return copia;
  }
}
