// Logica AI condivisa dai due proxy: Firebase Functions (functions/index.js)
// e Cloudflare Worker (ai-proxy-worker/src/index.js, che importa questo file).
// Prompt, chiamata a Gemini e parsing della risposta stanno solo qui.
'use strict';

const GEMINI_ENDPOINTS = [
  'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent',
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
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
    const canFallback = resp.status === 404 || (resp.status === 400 && /model|unsupported|not found/i.test(text));
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

function buildAnalyzePrompt(nomiUfficiali) {
  return `Sei un personal trainer esperto in protocolli di forza e bodybuilding. Analizza questo documento (foto, PDF o testo estratto da Word) che contiene una scheda di allenamento.

ATTENZIONE: L'allenamento potrebbe essere diviso in più giorni (es. Giorno A, Giorno B, Day 1, Day 2).
Estrai i dati e restituisci SOLO un ARRAY JSON valido contenente un oggetto per ogni giorno di allenamento trovato.

REGOLE PER I NOMI DEGLI ESERCIZI (FONDAMENTALE):
Qui sotto ti fornisco l'elenco ESATTO degli esercizi supportati dalla mia app.
Per ogni esercizio che leggi dalla foto, DEVI trovare il nome corrispondente in questa lista e scriverlo ESATTAMENTE in quel modo.
Se l'esercizio nella foto è completamente introvabile in lista, usa una traduzione italiana standard.

LISTA ESERCIZI UFFICIALI:
${JSON.stringify(nomiUfficiali)}

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
- Spesso lo stesso giorno cambia nel tempo (es. GG1 settimana 1: panca 3 serie; settimana 4: 6 serie; settimana 10: 3 serie con Stripping).
- Restituisci UN oggetto per giorno (non uno per settimana).
- In "esercizi" metti la prima settimana scritta.
- In "programma" metti SOLO le altre settimane scritte esplicitamente nel documento, con la lista completa degli esercizi di quella settimana: chiave = numero della settimana come stringa.
- Se un intervallo dice "settimane 1-3" e poi cambia alla 4, metti solo la settimana 4 in "programma": le settimane non scritte ripetono la precedente.
- Se c'è una sola settimana, "programma" è {}.

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
    "categoria": "Importata AI",
    "continuativa": true,
    "settimanaCorrente": 1,
    "esercizi": [
      {
        "nome": "NOME PRESO DALLA LISTA UFFICIALE",
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
      "4": [ { "nome": "...", "workingSet": 6, "ripetizioni": "6", "tecniche": ["Classico"] } ]
    }
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
  const nomiUfficiali = payload?.nomiUfficiali;
  const documento = parteDocumento(payload);
  if (!documento || !Array.isArray(nomiUfficiali)) {
    return { status: 400, body: { error: 'Payload non valido' } };
  }

  const geminiResp = await callGemini(apiKey, {
    contents: [
      {
        role: 'user',
        parts: [{ text: buildAnalyzePrompt(nomiUfficiali) }, documento],
      },
    ],
    generationConfig: { responseMimeType: 'application/json' },
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

module.exports = {
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
