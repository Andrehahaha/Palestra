const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();

const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

function jsonResponse(res, status, payload) {
  res.status(status).set('Content-Type', 'application/json').send(JSON.stringify(payload));
}

async function verifyAuth(req) {
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) return null;
  const token = authHeader.substring('Bearer '.length);
  if (!token) return null;
  return admin.auth().verifyIdToken(token);
}

async function callGemini(apiKey, body, options = {}) {
  const {
    model = 'gemini-3.1-flash-lite-preview',
    fallbackModels = ['gemini-2.0-flash', 'gemini-1.5-flash'],
  } = options;

  const modelsToTry = [model, ...fallbackModels];
  let lastError = null;

  for (const modelName of modelsToTry) {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent`;

    try {
      // Validate body before sending
      if (!body.contents || !Array.isArray(body.contents) || body.contents.length === 0) {
        throw new Error('Contenuti non validi per Gemini');
      }

      // Sanitize parts to remove null/undefined
      const sanitizedBody = JSON.parse(JSON.stringify(body, (key, value) => {
        if (value === null || value === undefined) return undefined;
        if (typeof value === 'string' && value.trim() === '') return undefined;
        return value;
      }));

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify(sanitizedBody),
      });

      const text = await response.text();

      if (!response.ok) {
        const errorData = (() => {
          try {
            return JSON.parse(text);
          } catch {
            return { error: text };
          }
        })();

        const errorMessage = errorData.error?.message || errorData.error || text;
        const errorCode = errorData.error?.code || response.status;

        // Handle 400 Invalid Argument specifically
        if (response.status === 400) {
          // Check if it's a content policy violation
          if (errorMessage.toLowerCase().includes('content policy') ||
              errorMessage.toLowerCase().includes('safety') ||
              errorMessage.toLowerCase().includes('blocked')) {
            throw new Error(`Gemini 400: Filtro sicurezza - ${errorMessage}`);
          }

          // Check if it's an image/PDF issue
          if (errorMessage.toLowerCase().includes('image') ||
              errorMessage.toLowerCase().includes('corrupt') ||
              errorMessage.toLowerCase().includes('decode')) {
            throw new Error(`Gemini 400: File non leggibile - ${errorMessage}`);
          }

          // Check if it's a model-specific issue
          if (errorMessage.toLowerCase().includes('model') ||
              errorMessage.toLowerCase().includes('not found for api')) {
            // Try next model
            lastError = new Error(`Gemini 400 (${modelName}): ${errorMessage}`);
            continue;
          }
        }

        throw new Error(`Gemini ${response.status} (${modelName}): ${errorMessage}`);
      }

      return JSON.parse(text);
    } catch (error) {
      lastError = error;

      // If it's a 404 model not found, try next fallback
      if (error.message.includes('404') || error.message.includes('not found')) {
        console.log(`Model ${modelName} not found, trying next fallback...`);
        continue;
      }

      // For other errors, rethrow immediately
      if (error.message.includes('400') && !error.message.includes('model')) {
        throw error;
      }
    }
  }

  // All models failed
  throw lastError || new Error('Tutti i modelli Gemini hanno fallito');
}

function extractModelText(geminiResp) {
  const parts = geminiResp?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return '';
  return parts.map((p) => p?.text || '').join('');
}

function extractJsonPayload(raw) {
  const trimmed = (raw || '').trim();
  if (!trimmed) {
    throw new Error('Risposta AI vuota');
  }

  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (fenced?.[1]) return fenced[1].trim();
  return trimmed;
}

function asText(value, fallback = '') {
  const text = value === undefined || value === null ? '' : String(value).trim();
  return text || fallback;
}

function toInt(value, fallback = null) {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  const parsed = Number.parseInt(String(value).trim(), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toNum(value, fallback = null) {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const parsed = Number.parseFloat(String(value).replace(',', '.').trim());
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseWeekNumberFromText(value, fallback = 1) {
  const text = asText(value, '').toLowerCase();
  if (!text) return fallback;

  const direct = toInt(text, null);
  if (direct !== null && direct > 0) return direct;

  const patterns = [
    /(?:\bweek\b|\bsettimana\b)\s*[:#\-]?\s*(\d{1,2})/i,
    /\bw\s*(\d{1,2})\b/i,
    /(\d{1,2})\s*(?:\bweek\b|\bsettimana\b)/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match?.[1]) continue;
    const parsed = toInt(match[1], null);
    if (parsed !== null && parsed > 0) return parsed;
  }

  return fallback;
}

function stripWeekMarkers(value) {
  const text = asText(value, '');
  if (!text) return '';
  return text
    .replace(/^\s*(?:w|week|settimana)\s*[-_ ]*\d+\s*(?:[-|:]\s*)?/i, '')
    .replace(/\s*(?:[-|:]\s*)?(?:w|week|settimana)\s*[-_ ]*\d+\b.*$/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractSetRepFromText(value) {
  const text = asText(value, '').toLowerCase();
  if (!text) return { sets: null, reps: null };

  const patterns = [
    /(\d{1,2})\s*[x×]\s*(\d{1,3}(?:\s*[-/]\s*\d{1,3})?)/i,
    /(\d{1,2})\s*(?:set|sets|serie)\s*(?:x|da)?\s*(\d{1,3}(?:\s*[-/]\s*\d{1,3})?)/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match) continue;
    const sets = toInt(match[1], null);
    const reps = asText(match[2], '').replace(/\s+/g, '');
    if ((sets !== null && sets > 0) || reps) {
      return { sets: sets && sets > 0 ? sets : null, reps: reps || null };
    }
  }

  return { sets: null, reps: null };
}

function normalizeTechniqueList(rawTecniche, metodo) {
  const source = Array.isArray(rawTecniche)
    ? rawTecniche
    : (asText(rawTecniche, '') ? [rawTecniche] : []);

  const cleaned = source
    .map((t) => asText(t, ''))
    .filter(Boolean)
    .filter((t) => !/^\d{1,2}\s*[x×]\s*\d{1,3}/i.test(t))
    .filter((t) => !/^\d{1,2}\s*(?:set|sets|serie)\b/i.test(t));

  if (cleaned.length > 0) return cleaned;
  if (metodo) return [metodo];
  return ['Classico'];
}

function normalizeSerieRows(existingRows, options) {
  const {
    avvicinamento,
    workingSet,
    modalita,
    percentualeMassimale,
    caricoTargetKg,
  } = options;

  if (Array.isArray(existingRows) && existingRows.length > 0) {
    return existingRows.map((row) => {
      const tipoRaw = asText(row?.tipo, 'Working Set').toLowerCase();
      const tipo = tipoRaw.includes('avvicin') ? 'Avvicinamento' : 'Working Set';
      return {
        tipo,
        peso: asText(row?.peso, ''),
        ripetizioniFatte: asText(row?.ripetizioniFatte, ''),
        isCompletata: false,
        rpe: asText(row?.rpe, ''),
        percentualeTarget: asText(row?.percentualeTarget, ''),
      };
    });
  }

  const rows = [];
  for (let i = 0; i < avvicinamento; i += 1) {
    rows.push({
      tipo: 'Avvicinamento',
      peso: '',
      ripetizioniFatte: '',
      isCompletata: false,
      rpe: '',
      percentualeTarget: '',
    });
  }

  const percentText =
    modalita === 'percentuale' && percentualeMassimale !== null
      ? String(Number(percentualeMassimale.toFixed(1))).replace(/\.0$/, '')
      : '';

  const pesoText =
    modalita !== 'percentuale' && caricoTargetKg !== null
      ? String(Number(caricoTargetKg.toFixed(1))).replace(/\.0$/, '')
      : '';

  for (let i = 0; i < workingSet; i += 1) {
    rows.push({
      tipo: 'Working Set',
      peso: pesoText,
      ripetizioniFatte: '',
      isCompletata: false,
      rpe: '',
      percentualeTarget: percentText,
    });
  }

  return rows;
}

function normalizeExercise(rawExercise) {
  const raw = rawExercise && typeof rawExercise === 'object' ? rawExercise : {};

  const setRepHint = extractSetRepFromText(raw.ripetizioni ?? raw.reps ?? raw.rep);
  const existingSerie = Array.isArray(raw.serieAttive) ? raw.serieAttive : [];
  const avvFromSerie = existingSerie.filter((s) => asText(s?.tipo, '').toLowerCase().includes('avvicin')).length;
  const workFromSerie = existingSerie.filter((s) => !asText(s?.tipo, '').toLowerCase().includes('avvicin')).length;

  const avvicinamento = Math.max(0, toInt(raw.avvicinamento, avvFromSerie) || 0);
  const workingSet = Math.max(
    1,
    toInt(raw.workingSet ?? raw.workingSets ?? raw.sets ?? raw.set, null)
      || setRepHint.sets
      || workFromSerie
      || 3,
  );

  const repsRaw = asText(raw.ripetizioni ?? raw.reps ?? raw.rep, '');
  const ripetizioni = repsRaw || setRepHint.reps || '8-10';

  const recupero = asText(raw.recupero ?? raw.rest ?? raw.pausa, '90');
  const metodo = asText(raw.metodo, 'Classico');
  const modalitaRaw = asText(raw.modalitaIntensita, '').toLowerCase();
  const percentualeMassimale = toNum(raw.percentualeMassimale ?? raw.percentuale, null);
  const massimaleKg = toNum(raw.massimaleKg ?? raw.massimale, null);

  let modalitaIntensita = modalitaRaw === 'percentuale' || modalitaRaw === 'rir'
    ? modalitaRaw
    : 'rir';
  if (modalitaRaw === '' && (percentualeMassimale !== null || massimaleKg !== null)) {
    modalitaIntensita = 'percentuale';
  }

  let caricoTargetKg = toNum(raw.caricoTargetKg ?? raw.kg ?? raw.peso ?? raw.carico, null);
  if (
    modalitaIntensita === 'percentuale'
    && caricoTargetKg === null
    && percentualeMassimale !== null
    && massimaleKg !== null
  ) {
    caricoTargetKg = (massimaleKg * percentualeMassimale) / 100;
  }

  const tecniche = normalizeTechniqueList(raw.tecniche, metodo);
  const serieAttive = normalizeSerieRows(existingSerie, {
    avvicinamento,
    workingSet,
    modalita: modalitaIntensita,
    percentualeMassimale,
    caricoTargetKg,
  });

  return {
    nome: asText(raw.nome, 'Esercizio'),
    avvicinamento,
    workingSet,
    ripetizioni,
    recupero,
    rpe: asText(raw.rpe, ''),
    modalitaIntensita,
    rirTarget: modalitaIntensita === 'rir' ? (asText(raw.rirTarget, '') || null) : null,
    percentualeMassimale: modalitaIntensita === 'percentuale' ? percentualeMassimale : null,
    massimaleKg: modalitaIntensita === 'percentuale' ? massimaleKg : null,
    caricoTargetKg,
    note: asText(raw.note, '') || null,
    metodo,
    tecniche,
    serieAttive,
  };
}

function normalizeAnalyzeItem(rawItem) {
  const raw = rawItem && typeof rawItem === 'object' ? rawItem : {};
  const week = parseWeekNumberFromText(
    raw.settimanaCorrente ?? raw.week ?? raw.settimana ?? `${asText(raw.nome, '')} ${asText(raw.categoria, '')}`,
    1,
  );

  const eserciziRaw = Array.isArray(raw.esercizi) ? raw.esercizi : [];
  const esercizi = eserciziRaw.map(normalizeExercise);

  // Extract session identifier from various possible fields
  const sedutaRaw = raw.seduta ?? raw.sessione ?? raw.session ?? raw.day ?? raw.giorno;
  const seduta = asText(sedutaRaw, '');

  // Build name with session if available
  let nome = asText(raw.nome, '');
  if (!nome) {
    if (seduta) {
      nome = `Week ${week} - Seduta ${seduta}`;
    } else {
      nome = `Week ${week} - Seduta`;
    }
  }

  return {
    nome,
    livello: asText(raw.livello, 'Intermedio'),
    categoria: 'Scheda Importata',
    continuativa: raw.continuativa !== false,
    settimanaCorrente: week,
    seduta: seduta || undefined,
    esercizi,
  };
}

function bumpRepsValue(reps, offset) {
  const text = asText(reps, '');
  if (!text || offset <= 0) return text;

  const rangeMatch = text.match(/^(\d{1,3})\s*[-/]\s*(\d{1,3})$/);
  if (rangeMatch) {
    const low = toInt(rangeMatch[1], 0) + offset;
    const high = toInt(rangeMatch[2], 0) + offset;
    return `${low}-${high}`;
  }

  const single = toInt(text, null);
  if (single !== null) {
    return String(single + offset);
  }

  return text;
}

function roundToHalf(value) {
  return Math.round(value * 2) / 2;
}

function applyProgressionToExercise(baseExercise, offset) {
  const ex = JSON.parse(JSON.stringify(baseExercise));
  if (offset <= 0) return ex;

  const hasNumericLoad = toNum(ex.caricoTargetKg, null) !== null;
  if (hasNumericLoad) {
    const baseLoad = toNum(ex.caricoTargetKg, 0);
    ex.caricoTargetKg = roundToHalf(baseLoad * (1 + 0.025 * offset));
  } else {
    ex.ripetizioni = bumpRepsValue(ex.ripetizioni, offset);
  }

  if (ex.modalitaIntensita === 'percentuale' && toNum(ex.percentualeMassimale, null) !== null) {
    ex.percentualeMassimale = Number((toNum(ex.percentualeMassimale, 0) + (2.5 * offset)).toFixed(1));
  }

  if (Array.isArray(ex.serieAttive)) {
    ex.serieAttive = ex.serieAttive.map((row) => {
      if (asText(row?.tipo, '').toLowerCase().includes('avvicin')) return row;
      const updated = { ...row };
      const rowLoad = toNum(updated.peso, null);
      if (rowLoad !== null) {
        updated.peso = String(roundToHalf(rowLoad * (1 + 0.025 * offset))).replace(/\.0$/, '');
      }
      return updated;
    });
  }

  return ex;
}

function withWeekInName(name, week) {
  const raw = asText(name, '').trim();
  if (!raw) return `Week ${week} - Seduta`;

  if (/(?:\bweek\b|\bsettimana\b|\bw\b)\s*[-_ ]*\d+/i.test(raw)) {
    return raw
      .replace(/(?:\bweek\b|\bsettimana\b|\bw\b)\s*[-_ ]*\d+/i, `Week ${week}`)
      .replace(/\s+/g, ' ')
      .trim();
  }

  return `Week ${week} - ${raw}`;
}

function buildSessionKey(item) {
  // First, try to use the explicit "seduta" field if available
  const seduta = asText(item.seduta ?? item.sessione ?? item.session ?? item.day ?? item.giorno, '');
  if (seduta) {
    // Use the first few exercises as additional discriminator for similar sessions
    const firstExercises = Array.isArray(item.esercizi)
      ? item.esercizi.slice(0, 2).map((e) => asText(e?.nome, '').toLowerCase()).join('|')
      : '';
    return `${seduta.toLowerCase()}|${firstExercises}`;
  }

  // Fallback: extract session from name (e.g., "Week 1 - Seduta A" -> "Seduta A")
  const nomeBase = stripWeekMarkers(item.nome).toLowerCase();
  if (nomeBase) {
    // Try to extract "Seduta X" or "Day X" pattern
    const sessionMatch = nomeBase.match(/(?:seduta|giorno|day)\s*[:\-]?\s*([a-z0-9]+)/i);
    if (sessionMatch?.[1]) {
      return sessionMatch[1];
    }
    return nomeBase;
  }

  // Last resort: use first exercises as signature
  const firstExercises = Array.isArray(item.esercizi)
    ? item.esercizi.slice(0, 3).map((e) => asText(e?.nome, '').toLowerCase()).join('|')
    : '';

  if (firstExercises) return firstExercises;

  // Deterministic fallback to avoid unstable grouping across runs.
  const categoriaBase = stripWeekMarkers(item.categoria).toLowerCase();
  const livello = asText(item.livello, '').toLowerCase();
  const metodo = asText(item.metodo, '').toLowerCase();
  const fallbackSignature = [categoriaBase, livello, metodo].filter(Boolean).join('|');
  return fallbackSignature || 'session_fallback';
}

function expandWeeksToTarget(items) {
  const normalized = items.map(normalizeAnalyzeItem);

  const hasWeekSignal = normalized.some((item) => {
    if (toInt(item.settimanaCorrente, 1) > 1) return true;
    const context = `${asText(item.nome, '')} ${asText(item.categoria, '')} ${asText(item.seduta, '')}`.toLowerCase();
    return /(?:\bweek\b|\bsettimana\b|\bw\s*\d+)/i.test(context);
  });

  if (!hasWeekSignal) {
    return normalized;
  }

  // Group by session type (e.g., "Seduta A", "Seduta B", "Giorno 1")
  const groupedBySession = new Map();
  for (const item of normalized) {
    const sessionKey = buildSessionKey(item);
    if (!groupedBySession.has(sessionKey)) {
      groupedBySession.set(sessionKey, []);
    }
    groupedBySession.get(sessionKey).push(item);
  }

  const expanded = [];
  const targetWeeks = 14;

  for (const [, groupItems] of groupedBySession.entries()) {
    // Build a map of week -> item for this session type
    const weekMap = new Map();
    for (const item of groupItems) {
      const week = toInt(item.settimanaCorrente, 1);
      // Avoid duplicates: if week already exists, prefer the one with more exercises
      const existing = weekMap.get(week);
      const existingExCount = Array.isArray(existing?.esercizi) ? existing.esercizi.length : 0;
      const newExCount = Array.isArray(item.esercizi) ? item.esercizi.length : 0;
      if (!existing || newExCount > existingExCount) {
        weekMap.set(week, item);
      }
    }

    const existingWeeks = Array.from(weekMap.keys()).sort((a, b) => a - b);
    if (existingWeeks.length === 0) continue;

    const baselineWeek = existingWeeks.includes(1) ? 1 : existingWeeks[0];
    const baseline = weekMap.get(baselineWeek) || groupItems[0];

    for (let week = 1; week <= targetWeeks; week += 1) {
      const current = weekMap.get(week);
      if (current) {
        // Use explicit data from AI for this week
        expanded.push({
          ...current,
          settimanaCorrente: week,
          categoria: 'Scheda Importata',
          nome: withWeekInName(current.nome, week),
        });
        continue;
      }

      // Generate progression for missing weeks only if we have a baseline
      const offset = week - baselineWeek;
      const generated = {
        ...JSON.parse(JSON.stringify(baseline)),
        settimanaCorrente: week,
        categoria: 'Scheda Importata',
        nome: withWeekInName(baseline.nome, week),
        esercizi: Array.isArray(baseline.esercizi)
          ? baseline.esercizi.map((ex) => applyProgressionToExercise(ex, offset))
          : [],
      };
      expanded.push(generated);
    }
  }

  expanded.sort((a, b) => {
    const wa = toInt(a.settimanaCorrente, 1);
    const wb = toInt(b.settimanaCorrente, 1);
    if (wa !== wb) return wa - wb;
    return asText(a.nome, '').localeCompare(asText(b.nome, ''));
  });

  return expanded;
}

function buildAnalyzePrompt(nomiUfficiali, sourceType = 'documento') {
  return `Sei un personal trainer esperto in protocolli di forza e bodybuilding.
Analizza questo ${sourceType} e restituisci SOLO un ARRAY JSON valido (nessun testo fuori dal JSON).

FORMATO OBBLIGATORIO:
[
  {
    "nome": "Week 1 - Seduta A",
    "livello": "Intermedio",
    "categoria": "Scheda Importata",
    "continuativa": true,
    "settimanaCorrente": 1,
    "seduta": "A",
    "esercizi": [
      {
        "nome": "NOME ESATTO DALLA LISTA",
        "avvicinamento": 0,
        "workingSet": 3,
        "ripetizioni": "8-10",
        "recupero": "90",
        "rpe": "",
        "modalitaIntensita": "rir",
        "rirTarget": "2",
        "percentualeMassimale": null,
        "massimaleKg": null,
        "caricoTargetKg": null,
        "note": "",
        "metodo": "Classico",
        "tecniche": ["Classico"],
        "serieAttive": [
          {
            "tipo": "Working Set",
            "peso": "",
            "ripetizioniFatte": "",
            "isCompletata": false,
            "rpe": "",
            "percentualeTarget": ""
          }
        ]
      }
    ]
  }
]

LISTA ESERCIZI UFFICIALI (USA NOMI ESATTI, NON INVENTARE):
${JSON.stringify(nomiUfficiali)}

REGOLE FONDAMENTALI - LEGGERE CON ATTENZIONE:

1) STRUTTURA SCHEDE PER SEDUTA:
- Ogni SEDUTA diversa deve diventare una scheda SEPARATA nel JSON.
- Se il programma ha 3 giorni/settimana, devi creare 3 schede distinte per OGNI settimana.
- Esempio: Programma da 3 giorni x 4 settimane = 12 schede totali (3 schede per settimana).
- Usa il campo "seduta" per identificare la giornata (es. "A", "B", "C" o "Giorno 1", "Giorno 2", "Giorno 3").
- Il campo "nome" deve essere: "Week N - Seduta X" (es. "Week 1 - Seduta A").

2) NUMERO DI SETTIMANE:
- Se il documento specifica N settimane, restituisci TUTTE le N settimane complete.
- Se il documento NON specifica N ma e una programmazione periodizzata, assumi N=14 settimane.
- Massimo supportato: 14 settimane.
- "settimanaCorrente" deve essere il numero progressivo reale (1, 2, 3, ... N).

3) SERIE E RIPETIZIONI - OBBLIGATORIE E ESPLICITE:
- Per OGNI esercizio di OGNI settimana, devi specificare SERIE e RIPETIZIONI in modo ESPPLICITO.
- "workingSet": numero ESATTO di serie allenanti (mai 1 a meno che non sia un test massimale).
- "ripetizioni": deve essere un valore ESPlicito (es. "5", "8-10", "3-5", "12-15").
- NON usare diciture vaghe come "vedi tabella", "guarda progressione", "come da schema".
- Se c'e una progressione, calcola e scrivi i valori ESATTI per ogni settimana.
- Esempio progressione: Week 1: "8-10", Week 2: "9-11", Week 3: "10-12", ecc.

4) PROGRESSIONE SETTIMANALE:
- Per ogni settimana successiva, aumenta carichi o ripetizioni in modo coerente.
- Se la settimana 1 ha 3x8-10 @ 100kg, la settimana 2 puo avere 3x9-11 @ 102.5kg.
- Mostra SEMPRE valori numerici ESPliciti per ogni settimana.

5) CAMPI OBBLIGATORI PER OGNI ESERCIZIO:
- "nome": USA SOLO nomi dalla lista ufficiale fornita.
- "avvicinamento": numero di serie di avvicinamento (0 se non previste).
- "workingSet": numero di serie allenanti (3-5 tipicamente).
- "ripetizioni": SEMPRE esplicito, MAI riferimenti a tabelle esterne.
- "recupero": secondi di recupero tra le serie.
- "serieAttive": array con le serie effettive da compilare durante l'allenamento.

6) REGOLE TECNICHE:
- In "tecniche" metti solo etichette tecniche reali (es. "Drop Set", "Superset", "Tempo").
- NON inserire stringhe set/reps tipo "4x10" dentro tecniche.
- Se non ci sono tecniche speciali, usa ["Classico"].

7) REGOLE OUTPUT:
- Nessun markdown, nessun commento, nessun testo extra.
- Restituisci SOLO JSON valido.
- Ogni scheda deve avere un "nome" univoco che include settimana E seduta.
- La categoria deve essere sempre "Scheda Importata" (non "Week N").

ESEMPIO OUTPUT CORRETTO per programma 3 giorni x 2 settimane:
[
  {"nome": "Week 1 - Seduta A", "seduta": "A", "settimanaCorrente": 1, ...},
  {"nome": "Week 1 - Seduta B", "seduta": "B", "settimanaCorrente": 1, ...},
  {"nome": "Week 1 - Seduta C", "seduta": "C", "settimanaCorrente": 1, ...},
  {"nome": "Week 2 - Seduta A", "seduta": "A", "settimanaCorrente": 2, ...},
  {"nome": "Week 2 - Seduta B", "seduta": "B", "settimanaCorrente": 2, ...},
  {"nome": "Week 2 - Seduta C", "seduta": "C", "settimanaCorrente": 2, ...}
]`;
}

function parseAnalyzeItems(geminiResp) {
  const raw = extractModelText(geminiResp);
  const jsonPayload = extractJsonPayload(raw);
  let parsed;
  try {
    parsed = JSON.parse(jsonPayload);
  } catch (error) {
    throw new Error(`JSON AI non valido: ${error instanceof Error ? error.message : String(error)}`);
  }

  const items = Array.isArray(parsed)
    ? parsed
    : (Array.isArray(parsed?.items) ? parsed.items : null);

  if (!Array.isArray(items)) {
    throw new Error('Risposta AI non valida: root JSON non array/items[]');
  }

  return expandWeeksToTarget(items);
}

async function handleAnalyzeDocument(req, res, { payloadField, mimeType, sourceType }) {
  const user = await verifyAuth(req);
  if (!user) return jsonResponse(res, 401, { error: 'Unauthorized' });

  const encodedData = req.body?.[payloadField];
  const nomiUfficiali = req.body?.nomiUfficiali;

  if (!encodedData || typeof encodedData !== 'string') {
    return jsonResponse(res, 400, {
      error: 'Dati mancanti',
      details: `Il campo '${payloadField}' e obbligatorio e deve essere una stringa base64 valida.`,
    });
  }

  if (!Array.isArray(nomiUfficiali) || nomiUfficiali.length === 0) {
    return jsonResponse(res, 400, {
      error: 'Lista esercizi mancante',
      details: 'Il campo nomiUfficiali e obbligatorio per l\'analisi.',
    });
  }

  // Validate base64 data
  if (!/^[A-Za-z0-9+/=]+$/.test(encodedData)) {
    return jsonResponse(res, 400, {
      error: 'Dati non validi',
      details: 'Il campo dati deve essere una stringa base64 valida.',
    });
  }

  const requestPayload = {
    contents: [
      {
        role: 'user',
        parts: [
          { text: buildAnalyzePrompt(nomiUfficiali, sourceType) },
          { inline_data: { mime_type: mimeType, data: encodedData } },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0.1,
      maxOutputTokens: 8192,
    },
  };

  let geminiResp;
  try {
    geminiResp = await callGemini(GEMINI_API_KEY.value(), requestPayload, {
      model: 'gemini-3.1-flash-lite-preview',
      fallbackModels: ['gemini-2.0-flash', 'gemini-1.5-flash'],
    });
  } catch (error) {
    console.error('Gemini call error:', error);

    const errorMsg = error instanceof Error ? error.message : String(error);
    const statusCode = errorMsg.includes('400') ? 400 :
                       errorMsg.includes('404') ? 404 :
                       errorMsg.includes('429') ? 429 : 500;

    return jsonResponse(res, statusCode, {
      error: 'Errore elaborazione AI',
      details: errorMsg,
    });
  }

  let items;
  try {
    items = parseAnalyzeItems(geminiResp);
  } catch (error) {
    console.error('Parse error:', error);
    return jsonResponse(res, 422, {
      error: 'Risposta AI non valida',
      details: error instanceof Error ? error.message : String(error),
    });
  }

  return jsonResponse(res, 200, { items });
}

exports.analyzeWorkoutPhoto = onRequest(
  { region: 'europe-west1', secrets: [GEMINI_API_KEY], cors: true, maxInstances: 10 },
  async (req, res) => {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'Method not allowed' });
    }

    try {
      return await handleAnalyzeDocument(req, res, {
        payloadField: 'imageBase64',
        mimeType: 'image/jpeg',
        sourceType: 'immagine',
      });
    } catch (error) {
      console.error('analyzeWorkoutPhoto error', error);
      return jsonResponse(res, 500, { error: 'Errore interno AI' });
    }
  }
);

exports.analyzeWorkoutPdf = onRequest(
  { region: 'europe-west1', secrets: [GEMINI_API_KEY], cors: true, maxInstances: 10 },
  async (req, res) => {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'Method not allowed' });
    }

    try {
      return await handleAnalyzeDocument(req, res, {
        payloadField: 'pdfBase64',
        mimeType: 'application/pdf',
        sourceType: 'PDF',
      });
    } catch (error) {
      console.error('analyzeWorkoutPdf error', error);
      return jsonResponse(res, 500, { error: 'Errore interno AI' });
    }
  }
);

exports.reviewWorkoutFolder = onRequest(
  { region: 'europe-west1', secrets: [GEMINI_API_KEY], cors: true, maxInstances: 10 },
  async (req, res) => {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'Method not allowed' });
    }

    try {
      const user = await verifyAuth(req);
      if (!user) return jsonResponse(res, 401, { error: 'Unauthorized' });

      const nomeCartella = req.body?.nomeCartella;
      const schede = req.body?.schede;
      if (!nomeCartella || !Array.isArray(schede)) {
        return jsonResponse(res, 400, { error: 'Payload non valido' });
      }

      const prompt = `Sei un Senior Personal Trainer e preparatore atletico.
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

      const geminiResp = await callGemini(GEMINI_API_KEY.value(), {
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
      });

      const text = extractModelText(geminiResp).trim();
      if (!text) {
        return jsonResponse(res, 502, { error: 'Risposta AI vuota' });
      }
      return jsonResponse(res, 200, { text });
    } catch (error) {
      console.error('reviewWorkoutFolder error', error);
      return jsonResponse(res, 500, { error: 'Errore interno AI' });
    }
  }
);
