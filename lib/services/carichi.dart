import '../models/esercizio.dart';
import '../models/scheda.dart';
import '../models/serie.dart';
import 'dizionario_esercizi.dart';
import 'workload_calculator.dart';

/// I tre sollevamenti per cui l'app traccia un PR usato come 1RM.
enum Big3 {
  panca('Panca Piana', [
    'Panca Piana',
    'Panca piana con bilanciere(presa media)',
    'Panca piana con bilanciere - presa media',
    'Panca piana con bilanciere (presa media)',
  ]),
  squat('Squat', [
    'Squat',
    'Squat Completo con Bilanciere',
    'Squat completo con bilanciere',
  ]),
  stacco('Stacco da Terra', [
    'Stacco da Terra',
    'Stacco da Terra con Bilanciere',
    'Stacco da terra con bilanciere',
    'Deadlift',
    'Conventional Deadlift',
  ]);

  const Big3(this.nome, this.alias);

  /// Nome mostrato all'utente.
  final String nome;

  /// Chiavi con cui il PR viene salvato in `personal_records`.
  final List<String> alias;
}

/// PR & Carichi: riconoscimento dei Big 3, lookup dei PR e calcolo dei
/// carichi per gli esercizi in modalità `percentuale` (%1RM).
///
/// Regole uniche per tutta l'app: le schermate non devono reimplementarle.
abstract final class Carichi {
  /// Differenza massima (kg) entro cui un peso è considerato "auto-calcolato"
  /// e quindi aggiornabile quando cambiano massimale o percentuale.
  static const double tolleranzaPesoAuto = 0.26;

  /// Minuscolo, senza accenti né simboli, spazi compattati.
  static String normalizza(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Traduce un nome inglese in italiano tramite il dizionario (case-insensitive).
  static String traduci(String nome) {
    final lower = nome.toLowerCase().trim();
    for (final entry in DizionarioEsercizi.daIngleseAItaliano.entries) {
      if (entry.key.toLowerCase().trim() == lower || entry.value.toLowerCase().trim() == lower) {
        return entry.value;
      }
    }
    return nome;
  }

  /// Big 3 a cui appartiene l'esercizio, o `null`. Accetta nomi IT o EN.
  static Big3? riconosciBig3(String nomeEsercizio) {
    return _riconosci(normalizza(nomeEsercizio)) ?? _riconosci(normalizza(traduci(nomeEsercizio)));
  }

  static Big3? _riconosci(String n) {
    if (n.isEmpty) return null;
    final pancaPresaMedia = n.contains('panca') && n.contains('bilanciere') && n.contains('presa media');
    if (n.contains('panca piana') || n.contains('bench press') || n == 'panca' || pancaPresaMedia) {
      return Big3.panca;
    }
    final squatCompleto = n.contains('squat') && n.contains('completo') && n.contains('bilanciere');
    if (n == 'squat' || n.contains('back squat') || squatCompleto) return Big3.squat;
    final staccoBilanciere = n.contains('stacco') && n.contains('bilanciere');
    if (n.contains('stacco da terra') || n.contains('deadlift') || n == 'stacco' || staccoBilanciere) {
      return Big3.stacco;
    }
    return null;
  }

  /// Nome del Big 3 se riconosciuto, altrimenti il nome tradotto e ripulito.
  static String nomeCanonico(String nome) {
    return riconosciBig3(nome)?.nome ?? traduci(nome).trim();
  }

  /// PR (kg) dell'esercizio, cercato fra tutti gli alias: il valore più alto.
  /// `null` se l'esercizio non è un Big 3 o non c'è un PR.
  static double? trovaPr(Map<String, double> prs, String nomeEsercizio) {
    final lift = riconosciBig3(nomeEsercizio);
    if (lift == null) return null;
    double? best;
    for (final entry in prs.entries) {
      if (entry.value <= 0 || riconosciBig3(entry.key) != lift) continue;
      if (best == null || entry.value > best) best = entry.value;
    }
    return best;
  }

  /// Le voci da scrivere in `personal_records` per un nuovo PR:
  /// tutti gli alias se è un Big 3, altrimenti il solo nome.
  static Map<String, double> recordPerPr(String nomeEsercizio, double kg) {
    final lift = riconosciBig3(nomeEsercizio);
    if (lift == null) return {nomeEsercizio: kg};
    return {for (final a in lift.alias) a: kg};
  }

  /// Legge una percentuale scritta dall'utente ("80", "80%", "72,5").
  static double? parsePercentuale(String raw) {
    final cleaned = raw.replaceAll('%', '').replaceAll(',', '.').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Trova una percentuale (0–110) in un testo libero ("5x5 80%", "al 75").
  static double? estraiPercentualeDaTesto(String text) {
    final t = text.toLowerCase();
    final patterns = <RegExp>[
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*%'),
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*percento'),
      RegExp(r'(\d{1,3}(?:[\.,]\d+)?)\s*per\s*cento'),
      RegExp(r'al\s*(\d{1,3}(?:[\.,]\d+)?)\b'),
      RegExp(r'at\s*(\d{1,3}(?:[\.,]\d+)?)\b'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(t);
      if (m == null) continue;
      final parsed = parsePercentuale(m.group(1)!);
      if (parsed != null && parsed > 0 && parsed <= 110) return parsed;
    }
    return null;
  }

  /// Percentuale dell'esercizio: quella esplicita, poi quella di una serie,
  /// poi quella scritta in ripetizioni/note.
  static double? inferisciPercentuale(Esercizio es) {
    final existing = es.percentualeMassimale;
    if (existing != null && existing > 0) return existing;
    for (final s in es.serieAttive.where(_isWorking)) {
      final p = parsePercentuale(s.percentualeTarget);
      if (p != null && p > 0 && p <= 110) return p;
    }
    return estraiPercentualeDaTesto('${es.ripetizioni} ${es.note ?? ''}');
  }

  /// Kg attesi per la serie in base a massimale e percentuale, o `null`.
  static double? kgAttesoSerie(Esercizio es, Serie serie) {
    if (es.modalitaIntensita != 'percentuale' || !_isWorking(serie)) return null;
    final rm = es.massimaleKg;
    if (rm == null || rm <= 0) return null;
    final perc = parsePercentuale(serie.percentualeTarget) ?? es.percentualeMassimale;
    if (perc == null || perc <= 0) return null;
    return _kg(rm, perc);
  }

  /// Per ogni esercizio a percentuale senza massimale usa il PR dell'atleta,
  /// poi calcola carico target e pesi delle serie ancora vuote.
  /// I pesi già scritti non vengono toccati. Restituisce `true` se ha cambiato qualcosa.
  static bool applicaPrAScheda(Scheda scheda, Map<String, double> prs) {
    var changed = false;
    for (final es in scheda.esercizi) {
      if (es.modalitaIntensita != 'percentuale') continue;
      if (es.massimaleKg == null || es.massimaleKg! <= 0) {
        final pr = trovaPr(prs, es.nome);
        if (pr != null) {
          es.massimaleKg = pr;
          changed = true;
        }
      }
      changed = _ricalcola(es, massimalePrecedente: null) || changed;
    }
    return changed;
  }

  /// Imposta un nuovo massimale e ricalcola i pesi vuoti o auto-calcolati
  /// col massimale precedente. I pesi scritti a mano restano.
  static bool impostaMassimale(Esercizio es, double kg) {
    if (kg <= 0) return false;
    final precedente = es.massimaleKg;
    es.massimaleKg = kg;
    _ricalcola(es, massimalePrecedente: precedente);
    return true;
  }

  /// L'utente ha scritto una nuova percentuale per la serie: la salva e
  /// ricalcola il peso se era vuoto o auto-calcolato.
  static void impostaPercentualeSerie(Esercizio es, Serie serie, String input) {
    final rm = es.massimaleKg;
    final oldPerc = parsePercentuale(serie.percentualeTarget) ?? es.percentualeMassimale;
    final parsed = parsePercentuale(input);
    serie.percentualeTarget = parsed != null ? _fmtPerc(parsed) : input.replaceAll('%', '').trim();

    if (rm == null || rm <= 0 || parsed == null || parsed <= 0 || !_isWorking(serie)) return;
    final oldExpected = (oldPerc != null && oldPerc > 0) ? _kg(rm, oldPerc) : null;
    if (_pesoAggiornabile(serie, oldExpected)) {
      serie.peso = _kg(rm, parsed).toStringAsFixed(1);
    }
  }

  static bool _ricalcola(Esercizio es, {required double? massimalePrecedente}) {
    var changed = false;
    if (es.percentualeMassimale == null) {
      final inferita = inferisciPercentuale(es);
      if (inferita != null) {
        es.percentualeMassimale = inferita;
        changed = true;
      }
    }
    final rm = es.massimaleKg;
    final perc = es.percentualeMassimale;
    if (rm == null || rm <= 0) return changed;
    if (perc != null && perc > 0) {
      final target = _kg(rm, perc);
      if (es.caricoTargetKg != target) {
        es.caricoTargetKg = target;
        changed = true;
      }
    }

    for (final serie in es.serieAttive.where(_isWorking)) {
      final percSerie = parsePercentuale(serie.percentualeTarget) ?? perc;
      if (percSerie == null || percSerie <= 0) continue;
      if (serie.percentualeTarget.trim().isEmpty) {
        serie.percentualeTarget = _fmtPerc(percSerie);
        changed = true;
      }
      final oldAuto = (massimalePrecedente != null && massimalePrecedente > 0)
          ? _kg(massimalePrecedente, percSerie)
          : null;
      if (_pesoAggiornabile(serie, oldAuto)) {
        final nuovo = _kg(rm, percSerie).toStringAsFixed(1);
        if (serie.peso != nuovo) {
          serie.peso = nuovo;
          changed = true;
        }
      }
    }
    return changed;
  }

  static bool _pesoAggiornabile(Serie serie, double? pesoAutoPrecedente) {
    if (serie.peso.trim().isEmpty) return true;
    final attuale = double.tryParse(serie.peso.replaceAll(',', '.').trim());
    return pesoAutoPrecedente != null &&
        attuale != null &&
        (attuale - pesoAutoPrecedente).abs() <= tolleranzaPesoAuto;
  }

  static bool _isWorking(Serie s) => s.tipo != 'Avvicinamento';

  static double _kg(double rm, double perc) =>
      WorkloadCalculator.calculateFromMaxAndPercentage(oneRepMax: rm, percentage: perc);

  static String _fmtPerc(double p) => p.toStringAsFixed(p % 1 == 0 ? 0 : 1);
}
