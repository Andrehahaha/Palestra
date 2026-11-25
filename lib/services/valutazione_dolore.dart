/// Valutazione Dolore: profili dei tipi di dolore e mini-test euristico
/// che suggerisce il tipo più probabile. Solo informativo, non diagnostico.
library;

/// Profili dei tipi di dolore: categoria, livello, descrizione e linee guida.
const Map<String, Map<String, dynamic>> profiliDolore = {
  'Bruciore da acido lattico': {
    'categoria': 'Dolori fisiologici (normali)',
    'livello': 'Basso',
    'descrizione': 'Sensazione acuta durante la serie, in genere si riduce in pochi minuti.',
    'stretching': [
      'Defaticamento attivo 3-5 minuti',
      'Respirazione controllata 2 x 6 respiri',
      'Stretch leggero 2 x 20-30 secondi',
    ],
    'esercizi': [
      'Riduci il carico e allunga il recupero tra le serie',
      'Passa a ROM controllato e ritmo piu lento',
      'Idratazione e pausa di 2-3 minuti prima del set successivo',
    ],
  },
  'DOMS (indolenzimento ritardato)': {
    'categoria': 'Dolori fisiologici (normali)',
    'livello': 'Basso',
    'descrizione': 'Rigidita e dolore sordo che compare 24-48 ore dopo l’allenamento.',
    'stretching': [
      'Mobilita dolce 2 x 8-10',
      'Stretch leggero senza dolore acuto 2 x 30 secondi',
      'Camminata blanda 8-12 minuti',
    ],
    'esercizi': [
      'Recupero attivo a bassa intensita',
      'Riduci volume e carico nella sessione successiva',
      'Evita eccentriche pesanti finche la rigidita cala',
    ],
  },
  'Dolore meccanico articolare': {
    'categoria': 'Infortuni articolari e tendinei',
    'livello': 'Medio',
    'descrizione': 'Fastidio/fitta interna all’articolazione (es. spalla, ginocchio, polso).',
    'stretching': [
      'Mobilita articolare lenta e controllata 2 x 8',
      'Evita forzature a fine ROM doloroso',
      'Decompressione/articolazione scarica 2-3 minuti',
    ],
    'esercizi': [
      'Riduci carichi 30-50% e lavora su tecnica',
      'Usa varianti stabili e senza dolore',
      'Stop immediato se il dolore aumenta durante il set',
    ],
  },
  'Tendinite': {
    'categoria': 'Infortuni articolari e tendinei',
    'livello': 'Medio',
    'descrizione': 'Infiammazione del tendine da ripetizione o sovraccarico.',
    'stretching': [
      'Stretch lieve e graduale senza dolore acuto',
      'Mobilita controllata 2 x 8-10',
      'Recupero con pause piu lunghe tra le serie',
    ],
    'esercizi': [
      'Isometrici leggeri sul distretto 3 x 20-30 secondi',
      'Eccentrici leggeri se tollerati 2 x 10',
      'Evita picchi di carico finche i sintomi non calano',
    ],
  },
  'Contrattura muscolare': {
    'categoria': 'Traumi muscolari acuti',
    'livello': 'Medio',
    'descrizione': 'Indurimento e tensione involontaria del muscolo, senza rottura di fibre.',
    'stretching': [
      'Respirazione lenta 2 x 6 respiri profondi',
      'Stretch progressivo 2-3 x 30 secondi',
      'Mobilita a ROM ridotto 2 x 8-10',
    ],
    'esercizi': [
      'Isometria leggera 3 x 20-30 secondi',
      'Movimento a carico minimo e ritmo lento 2-3 x 10',
      'Camminata/cyclette blanda 8-12 minuti',
    ],
  },
  'Elongazione (stiramento)': {
    'categoria': 'Traumi muscolari acuti',
    'livello': 'Alto',
    'descrizione': 'Eccessivo allungamento del muscolo con possibili micro-lacerazioni.',
    'stretching': [
      'Niente stretching aggressivo nelle prime 24-72h',
      'Solo mobilita molto dolce entro soglia non dolorosa',
      'Progressione graduale solo se i sintomi migliorano',
    ],
    'esercizi': [
      'Evita carichi esplosivi e allungamenti forzati',
      'Isometrie leggere solo se ben tollerate',
      'Valuta consulto professionale se il dolore persiste',
    ],
  },
  'Strappo (lacerazione)': {
    'categoria': 'Traumi muscolari acuti',
    'livello': 'Molto alto',
    'descrizione': 'Rottura parziale o totale delle fibre muscolari (grado 1-2-3).',
    'stretching': [
      'Sospendi stretching e carichi sul distretto coinvolto',
      'Proteggi l’area e limita i movimenti dolorosi',
      'Richiedi valutazione medica/fisioterapica',
    ],
    'esercizi': [
      'Nessun esercizio di carico finche non valutato',
      'Mantieni solo attivita non dolorose a distanza dal distretto',
      'Rientro graduale guidato da professionista',
    ],
  },
};

/// Risposte al mini-test. Ogni campo è `null` se la domanda non ha risposta.
class RisposteTestDolore {
  const RisposteTestDolore({this.quando, this.dove, this.intensita, this.andamento});

  final String? quando;
  final String? dove;
  final String? intensita;
  final String? andamento;

  static const opzioniQuando = ['Durante la serie', 'Subito dopo', '24-48h dopo', 'Dopo gesto brusco'];
  static const opzioniDove = ['Muscolo diffuso', 'Tendine/punto specifico', 'Dentro l’articolazione', 'Fitta muscolare netta'];
  static const opzioniIntensita = ['Bassa', 'Media', 'Alta'];
  static const opzioniAndamento = [
    'Migliora scaldandomi',
    'Peggiora con carico ripetuto',
    'Dolore con movimenti articolari',
    'Blocca il movimento',
  ];

  RisposteTestDolore copyWith({String? quando, String? dove, String? intensita, String? andamento}) {
    return RisposteTestDolore(
      quando: quando ?? this.quando,
      dove: dove ?? this.dove,
      intensita: intensita ?? this.intensita,
      andamento: andamento ?? this.andamento,
    );
  }
}

/// Esito del mini-test: tipo suggerito e confidenza (35–95%).
class EsitoTestDolore {
  const EsitoTestDolore(this.tipo, this.confidenza);

  final String tipo;
  final int confidenza;

  String get etichetta {
    if (confidenza >= 70) return 'Alta';
    if (confidenza >= 45) return 'Media';
    return 'Bassa';
  }
}

abstract final class ValutazioneDolore {
  static const _acido = 'Bruciore da acido lattico';
  static const _doms = 'DOMS (indolenzimento ritardato)';
  static const _articolare = 'Dolore meccanico articolare';
  static const _tendinite = 'Tendinite';
  static const _contrattura = 'Contrattura muscolare';
  static const _elongazione = 'Elongazione (stiramento)';
  static const _strappo = 'Strappo (lacerazione)';

  /// Tipi che il test può suggerire, in ordine di priorità a parità di punti.
  static const tipi = [_acido, _doms, _articolare, _tendinite, _contrattura, _elongazione, _strappo];

  /// Punti assegnati da ogni risposta. Massimo 3 punti per risposta.
  static const Map<String, Map<String, int>> _puntiQuando = {
    '24-48h dopo': {_doms: 3},
    'Durante la serie': {_acido: 2},
    'Dopo gesto brusco': {_elongazione: 2, _strappo: 2},
  };
  static const Map<String, Map<String, int>> _puntiDove = {
    'Dentro l’articolazione': {_articolare: 3},
    'Tendine/punto specifico': {_tendinite: 3},
    'Fitta muscolare netta': {_elongazione: 2, _strappo: 2},
    'Muscolo diffuso': {_contrattura: 2},
  };
  static const Map<String, Map<String, int>> _puntiIntensita = {
    'Bassa': {_acido: 1, _doms: 1},
    'Media': {_contrattura: 1, _tendinite: 1},
    'Alta': {_strappo: 3, _elongazione: 2},
  };
  static const Map<String, Map<String, int>> _puntiAndamento = {
    'Migliora scaldandomi': {_contrattura: 2},
    'Peggiora con carico ripetuto': {_tendinite: 3},
    'Dolore con movimenti articolari': {_articolare: 3},
    'Blocca il movimento': {_strappo: 3},
  };

  static EsitoTestDolore suggerisci(RisposteTestDolore r) {
    final punti = {for (final t in tipi) t: 0};
    var risposte = 0;
    void somma(String? risposta, Map<String, Map<String, int>> tabella) {
      if (risposta == null) return;
      risposte++;
      tabella[risposta]?.forEach((tipo, p) => punti[tipo] = punti[tipo]! + p);
    }

    somma(r.quando, _puntiQuando);
    somma(r.dove, _puntiDove);
    somma(r.intensita, _puntiIntensita);
    somma(r.andamento, _puntiAndamento);

    var migliore = _contrattura;
    var max = -1;
    for (final e in punti.entries) {
      if (e.value > max) {
        max = e.value;
        migliore = e.key;
      }
    }
    if (max <= 0) return const EsitoTestDolore(_contrattura, 35);

    final confidenza = (max / (risposte * 3) * 100).round().clamp(35, 95);
    return EsitoTestDolore(migliore, confidenza);
  }
}
