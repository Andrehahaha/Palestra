// Logica AI condivisa dai due proxy: Firebase Functions (functions/index.js)
// e Cloudflare Worker (ai-proxy-worker/src/index.js, che importa questo file).
// Prompt, chiamata a Gemini e parsing della risposta stanno solo qui.
'use strict';

// v1beta per primo: la modalità JSON (responseMimeType) su v1 non esiste.
const GEMINI_ENDPOINTS = [
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
  'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent',
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent',
];

class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.details = details;
  }
}

/**
 * Chiama Gemini provando gli endpoint in ordine: passa al successivo solo se
 * il modello non esiste o non è supportato. Altri errori diventano HttpError
 * con lo status di Gemini (es. 429).
 */
async function callGemini(apiKey, requestBody, { fetchImpl = fetch, endpoints = GEMINI_ENDPOINTS } = {}) {
  const fallbackLog = [];

  for (const endpoint of endpoints) {
    const resp = await fetchImpl(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify(requestBody),
    });

    const text = await resp.text();
    if (resp.ok) return JSON.parse(text);

    fallbackLog.push(`${endpoint} -> ${resp.status}`);
    const canFallback = resp.status === 404
      || (resp.status === 400 && /model|unsupported|not found|api version/i.test(text));
    if (canFallback) continue;

    throw new HttpError(resp.status, `Gemini error ${resp.status}`, text);
  }

  throw new HttpError(502, 'Nessun endpoint Gemini compatibile disponibile', fallbackLog.join(' | '));
}

function extractModelText(geminiResp) {
  const parts = geminiResp?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return '';
  return parts.map((p) => p?.text || '').join('');
}

/** Testo JSON della risposta, senza eventuali recinti ```json ... ```. */
function extractJsonPayload(raw) {
  const trimmed = (raw || '').trim();
  if (!trimmed) return '';
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (fenced?.[1]) return fenced[1].trim();
  return trimmed;
}

function sezioneNomi(nomiUfficiali) {
  if (!Array.isArray(nomiUfficiali) || nomiUfficiali.length === 0) {
    return `REGOLE PER I NOMI DEGLI ESERCIZI:
In "nome" e in "nomeOriginale" scrivi il nome dell'esercizio come scritto nel documento (senza tag come LIFT, MULTI, ISO). L'abbinamento al database lo fa l'app.
`;
  }
  return `REGOLE PER I NOMI DEGLI ESERCIZI (FONDAMENTALE):
Qui sotto ti fornisco l'elenco ESATTO degli esercizi supportati dalla mia app.
Per ogni esercizio, se nella lista c'è lo STESSO MOVIMENTO (stesso gesto e stesso gruppo muscolare), scrivi in "nome" il nome della lista ESATTAMENTE in quel modo.
Se nella lista non c'è lo stesso movimento, in "nome" lascia il nome del documento: è meglio un nome non in lista che un esercizio sbagliato (es. una pressa per le gambe non è una chest press).
In "nomeOriginale" scrivi sempre il nome come appare nel documento.

LISTA ESERCIZI UFFICIALI:
${JSON.stringify(nomiUfficiali)}
`;
}

function buildAnalyzePrompt(nomiUfficiali) {
  return `Sei un personal trainer esperto in protocolli di forza e bodybuilding. Analizza questo documento (foto, PDF o testo estratto da Word) che contiene una scheda di allenamento.

ATTENZIONE: L'allenamento potrebbe essere diviso in più giorni (es. Giorno A, Giorno B, Day 1, Day 2).
Estrai i dati e restituisci SOLO un ARRAY JSON valido contenente un oggetto per ogni giorno di allenamento trovato.

${sezioneNomi(nomiUfficiali)}
REGOLE PER LE TECNICHE:
[Classico, Back off, Drop Set, Super Set, Rest Pause, Piramidale, Giant Set, Cluster Set, Top Set, Feeder Set, Warm Up, Myo-reps, AMRAP, Negative, Isometria, Stripping, Trisets, Pre-stancaggio, EMOM, Burnouts].

REGOLE PER L'RPE:
Se nella foto per un esercizio è indicato un valore come @8, RPE 8, RIR 2, estrai solo il numero.

REGOLE PER LE NUOVE MODALITA:
- Ogni scheda deve avere:
  - "continuativa": true
  - "settimanaCorrente": 1
- Ogni esercizio deve avere "modalitaIntensita":
  - usa "rir" se trovi indicazioni RIR/RPE
  - usa "percentuale" se trovi % o riferimento al massimale
- Se modalitaIntensita = "rir", compila "rirTarget" (solo numero o stringa breve)
- Se modalitaIntensita = "percentuale", compila quando possibile:
  - "percentualeMassimale" (numero)
  - "massimaleKg" (numero, se presente nel testo)
  - "caricoTargetKg" (numero, se già esplicitato)

REGOLE SPECIFICHE BIG 3 (OBBLIGATORIO):
- Per "Panca Piana", "Squat" e "Stacco da Terra" (o equivalenti inglesi), se trovi una percentuale tipo 75%, 82.5%, @70%, devi sempre compilare:
  - "modalitaIntensita": "percentuale"
  - "percentualeMassimale": numero della percentuale
- Se nello stesso testo trovi anche il massimale (es. 1RM 120kg), compila anche "massimaleKg".

PROGRAMMAZIONE SU PIÙ SETTIMANE:
- Spesso lo stesso giorno cambia nel tempo; il ciclo può durare 2, 3, 4 o più settimane.
- Restituisci UN oggetto per giorno (non uno per settimana).
- In "categoria" metti il TITOLO DEL PROGRAMMA come scritto nel documento (es. "Scheda ipertrofia 3 giorni"), uguale per tutti i giorni. In "nome" il nome del giorno (es. "Upper - Lunedì").
- Numera SEMPRE le settimane 1, 2, 3, ... dall'inizio del programma, qualunque sia l'etichetta nel documento ("Sett. 2", "W2", "Microciclo 2", "Week 2" diventano 2).
- In "esercizi" metti la settimana 1.
- In "programma" metti SOLO le settimane scritte esplicitamente nel documento e diverse dalla precedente, con la LISTA COMPLETA degli esercizi del giorno (anche quelli che non cambiano): chiave = numero della settimana come stringa ("2", "3", ...).
- Indicazioni come "dal ciclo 2" (es. "5 serie dal ciclo 2", "drop set dal ciclo 2") valgono dalla PRIMA SETTIMANA DI QUEL CICLO secondo la tabella della progressione (es. ciclo 2 = settimana 6): metti lì la settimana in "programma", non nelle settimane del ciclo 1.
- Se un intervallo dice "settimane 1-3" e poi cambia dalla successiva, metti solo la settimana in cui cambia: quelle non scritte ripetono la precedente.
- Se c'è una sola settimana, "programma" è {}.

IL RIR NEGLI ESERCIZI:
- In "rirTarget" di ogni esercizio metti il RIR scritto nella tabella del giorno (es. "1-2", "0-1", "2-3"), senza applicare le variazioni settimanali.

CALENDARIO DELLE SETTIMANE (uguale per tutti i giorni, ripetilo su ogni giorno):
- Se il documento indica per settimana una variazione del RIR rispetto alla tabella (es. "Tabella +2", "Tabella +1", "Tabella"), metti in "calendario" la settimana con "rirDelta": 2, 1, 0.
- Se una settimana è di scarico/deload, metti "scarico": true. Non riscrivere gli esercizi dello scarico: lo calcola l'app.
- Chiave = numero della settimana come stringa; per un intervallo puoi usare "7-9".
- Se il documento non indica nulla del genere, "calendario" è {}.

DURATA E RIPARTENZA:
- "durataSettimane": numero totale di settimane del programma (es. 15), se indicato.
- "ripartiDaSettimana": se il documento dice da dove ricominciare a programma finito (es. "poi riparti dal ciclo 2", dove il ciclo 2 inizia alla settimana 6 -> 6), altrimenti null.

SCHEDE CHE SI ALTERNANO:
- Se il documento dice che due o più schede si alternano a settimane (es. "scheda A e scheda B alternate"), restituiscile come UN solo giorno: settimana 1 = A in "esercizi", settimana 2 = B in "programma", e così via.
- In quel caso "durataSettimane" = numero di schede che si alternano (es. 2) e "ripartiDaSettimana": 1.

REGOLE DI PROGRESSIONE:
- Se il documento indica come progredire (es. "+2,5 kg a settimana", "+5% ogni settimana", "RIR 2 dalla settimana 3"), aggiungi all'esercizio "progressione": {"daSettimana": n, "aSettimana": n o null, "incrementoKg": numero o null, "incrementoPercentuale": numero o null, "rirTarget": stringa o null, "nota": "testo originale della regola"}.
- Se la regola non è esprimibile con questi campi, compila solo "daSettimana" e "nota".
- Se la regola vale per tutti gli esercizi, ripetila su ognuno.
- NON inventare settimane né regole: se il documento non le scrive, non metterle.

STRUTTURA JSON:
[
  {
    "nome": "Nome Scheda - Giorno 1",
    "livello": "Intermedio",
    "categoria": "Titolo del programma",
    "continuativa": true,
    "settimanaCorrente": 1,
    "esercizi": [
      {
        "nome": "nome dell'esercizio",
        "nomeOriginale": "nome come scritto nel documento",
        "avvicinamento": 0,
        "workingSet": 3,
        "ripetizioni": "8-10",
        "recupero": "90",
        "rpe": "8",
        "modalitaIntensita": "rir",
        "rirTarget": "2",
        "percentualeMassimale": null,
        "massimaleKg": null,
        "caricoTargetKg": null,
        "note": "eventuali note",
        "metodo": "Classico",
        "tecniche": ["Classico"],
        "progressione": null
      }
    ],
    "programma": {
      "2": [ { "nome": "...", "workingSet": 4, "ripetizioni": "6", "tecniche": ["Classico"] } ]
    },
    "calendario": {
      "1": { "rirDelta": 2 },
      "2": { "scarico": true }
    },
    "durataSettimane": null,
    "ripartiDaSettimana": null
  }
]

NOTA:
- Non aggiungere testo fuori dal JSON.`;
}

function buildReviewPrompt(nomeCartella, schede) {
  return `Sei un Senior Personal Trainer e preparatore atletico.
Un tuo atleta ti ha chiesto di valutare il suo programma di allenamento chiamato "${nomeCartella}".
Ecco il dettaglio in formato JSON delle giornate di allenamento:
${JSON.stringify(schede)}

Analizza la scheda e fornisci un responso discorsivo, amichevole ma tecnico.
Struttura la risposta in questo modo usando le emoji:
⚖️ Bilanciamento Generale
📊 Volume e Intensità
⚠️ Gruppi Muscolari Carenti/Eccessivi
💡 Consiglio del Coach

Rispondi in italiano. Non usare codice.`;
}

/**
 * Analizza la foto di una scheda. Restituisce `{ status, body }` pronto per
 * la risposta HTTP. Errori Gemini: lancia HttpError.
 */
const MIME_AMMESSI = ['image/jpeg', 'image/png', 'image/heic', 'application/pdf'];

/** Parte con il contenuto della scheda: file (foto/PDF) o testo (Word). `null` se non valido. */
function parteDocumento(payload) {
  if (typeof payload?.testo === 'string' && payload.testo.trim()) {
    return { text: `DOCUMENTO (testo estratto da Word, celle separate da tab):
${payload.testo}` };
  }
  if (payload?.fileBase64) {
    if (!MIME_AMMESSI.includes(payload.mimeType)) return null;
    return { inline_data: { mime_type: payload.mimeType, data: payload.fileBase64 } };
  }
  if (payload?.imageBase64) {
    // Formato delle versioni dell'app precedenti all'import da file.
    return { inline_data: { mime_type: 'image/jpeg', data: payload.imageBase64 } };
  }
  return null;
}

async function analyzeWorkoutPhoto(apiKey, payload, options) {
  const nomiUfficiali = Array.isArray(payload?.nomiUfficiali) ? payload.nomiUfficiali : [];
  const documento = parteDocumento(payload);
  if (!documento) {
    return { status: 400, body: { error: 'Payload non valido' } };
  }

  const geminiResp = await callGemini(apiKey, {
    contents: [
      {
        role: 'user',
        parts: [{ text: buildAnalyzePrompt(nomiUfficiali) }, documento],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      // Estrazione di dati: il "ragionamento" di 2.5 Flash la rallentava oltre i 2 minuti.
      thinkingConfig: { thinkingBudget: 0 },
    },
  }, options);

  let items;
  try {
    items = JSON.parse(extractJsonPayload(extractModelText(geminiResp)));
  } catch (_) {
    items = null;
  }
  if (!Array.isArray(items)) {
    return { status: 422, body: { error: 'Risposta AI non valida' } };
  }
  return { status: 200, body: { items } };
}

/** Recensione testuale di una cartella di schede. Come analyzeWorkoutPhoto. */
async function reviewWorkoutFolder(apiKey, payload, options) {
  const nomeCartella = payload?.nomeCartella;
  const schede = payload?.schede;
  if (!nomeCartella || !Array.isArray(schede)) {
    return { status: 400, body: { error: 'Payload non valido' } };
  }

  const geminiResp = await callGemini(apiKey, {
    contents: [{ role: 'user', parts: [{ text: buildReviewPrompt(nomeCartella, schede) }] }],
  }, options);

  return { status: 200, body: { text: extractModelText(geminiResp).trim() } };
}

function buildMatchPrompt(esercizi) {
  return `Abbina ogni esercizio di una scheda di palestra al nome giusto del database dell'app.
Per ogni esercizio hai il nome scritto nella scheda ("originale") e alcuni candidati del database.
Scegli un candidato SOLO se è lo STESSO MOVIMENTO: stesso gesto, stesso gruppo muscolare, stessa posizione (in piedi, seduto, su panca piana o inclinata) e stesso attrezzo se la scheda lo indica.
Se nessun candidato è lo stesso movimento, "scelto" è null. Meglio null che un esercizio sbagliato.
Copia il nome scelto ESATTAMENTE come nei candidati.

ESERCIZI:
${JSON.stringify(esercizi)}

Rispondi SOLO con un array JSON: [{"originale": "...", "scelto": "..." oppure null}]`;
}

/** Secondo passaggio: abbina i nomi della scheda al database, scegliendo fra candidati dati dall'app. */
async function matchExerciseNames(apiKey, payload, options) {
  const esercizi = payload?.esercizi;
  if (!Array.isArray(esercizi) || esercizi.some((e) => typeof e?.originale !== 'string' || !Array.isArray(e?.candidati))) {
    return { status: 400, body: { error: 'Payload non valido' } };
  }
  if (esercizi.length === 0) return { status: 200, body: { scelte: [] } };

  const geminiResp = await callGemini(apiKey, {
    contents: [{ role: 'user', parts: [{ text: buildMatchPrompt(esercizi) }] }],
    // Qui il ragionamento serve: la richiesta è piccola, quindi resta veloce.
    generationConfig: { responseMimeType: 'application/json', thinkingConfig: { thinkingBudget: 1024 } },
  }, options);

  let risposte;
  try {
    risposte = JSON.parse(extractJsonPayload(extractModelText(geminiResp)));
  } catch (_) {
    risposte = [];
  }
  const perOriginale = new Map((Array.isArray(risposte) ? risposte : []).map((r) => [r?.originale, r?.scelto]));
  const scelte = esercizi.map(({ originale, candidati }) => {
    const scelto = perOriginale.get(originale);
    return { originale, scelto: candidati.includes(scelto) ? scelto : null };
  });
  return { status: 200, body: { scelte } };
}

module.exports = {
  matchExerciseNames,
  buildMatchPrompt,
  GEMINI_ENDPOINTS,
  HttpError,
  callGemini,
  extractModelText,
  extractJsonPayload,
  buildAnalyzePrompt,
  buildReviewPrompt,
  analyzeWorkoutPhoto,
  reviewWorkoutFolder,
};
