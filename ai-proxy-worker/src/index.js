import { jwtVerify, importX509 } from 'jose';

const GEMINI_ENDPOINTS = [
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent',
];
const FIREBASE_CERTS_URL = 'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

const WORKOUT_SERIE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    s: { type: 'INTEGER' },
    r: { type: 'STRING' },
    kg: { type: 'STRING' },
    rest: { type: 'STRING' },
  },
  required: ['s'],
};

const WORKOUT_EXERCISE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    id_es: { type: 'STRING' },
    status: {
      type: 'STRING',
      enum: ['active', 'removed'],
    },
    old_id_es: { type: 'STRING' },
    idx: { type: 'INTEGER' },
    pos: { type: 'INTEGER' },
    note: { type: 'STRING' },
    metodo: { type: 'STRING' },
    tecniche: {
      type: 'ARRAY',
      items: { type: 'STRING' },
    },
    modalitaIntensita: {
      type: 'STRING',
      enum: ['rir', 'percentuale'],
    },
    rirTarget: { type: 'STRING' },
    percentualeMassimale: { type: 'NUMBER' },
    massimaleKg: { type: 'NUMBER' },
    caricoTargetKg: { type: 'NUMBER' },
    serie: {
      type: 'ARRAY',
      items: WORKOUT_SERIE_SCHEMA,
    },
  },
  required: ['id_es'],
};

const WORKOUT_WEEKS_SCHEMA = {
  type: 'OBJECT',
  properties: {
    w1: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w2: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w3: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w4: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w5: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w6: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w7: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w8: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w9: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w10: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w11: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w12: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w13: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
    w14: {
      type: 'ARRAY',
      items: WORKOUT_EXERCISE_SCHEMA,
    },
  },
  required: ['w1'],
};

const WORKOUT_SESSION_SCHEMA = {
  type: 'OBJECT',
  properties: {
    id_allenamento: { type: 'STRING' },
    titolo: { type: 'STRING' },
    weeks: WORKOUT_WEEKS_SCHEMA,
  },
  required: ['id_allenamento', 'titolo', 'weeks'],
};

const WORKOUT_RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    scheda_id: { type: 'STRING' },
    nome_scheda: { type: 'STRING' },
    allenamenti: {
      type: 'ARRAY',
      items: WORKOUT_SESSION_SCHEMA,
    },
  },
  required: ['scheda_id', 'nome_scheda', 'allenamenti'],
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
    },
  });
}

class AuthError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AuthError';
  }
}

class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.details = details;
  }
}

function formatErrorForDetails(error) {
  if (error instanceof HttpError) {
    return error.details ? `${error.message} | ${error.details}` : error.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

async function getFirebaseSigningKey(kid) {
  const certsResp = await fetch(FIREBASE_CERTS_URL);
  if (!certsResp.ok) {
    throw new Error(`Failed to load Firebase certs: ${certsResp.status}`);
  }
  const certs = await certsResp.json();
  const certPem = certs[kid];
  if (!certPem) {
    throw new Error('Unknown Firebase token key id');
  }
  return importX509(certPem, 'RS256');
}

function decodeJwtHeader(token) {
  const [header] = token.split('.');
  if (!header) throw new Error('Invalid JWT');
  const decoded = JSON.parse(atob(header.replace(/-/g, '+').replace(/_/g, '/')));
  return decoded;
}

async function verifyFirebaseIdToken(request, projectId) {
  const authHeader = request.headers.get('Authorization') || '';
  if (!authHeader.startsWith('Bearer ')) {
    throw new AuthError('Missing bearer token');
  }

  const token = authHeader.slice('Bearer '.length);
  const header = decodeJwtHeader(token);
  const kid = header.kid;
  if (!kid) {
    throw new AuthError('JWT kid missing');
  }

  const key = await getFirebaseSigningKey(kid);

  const { payload } = await jwtVerify(token, key, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });

  if (!payload.sub) {
    throw new AuthError('Invalid Firebase token subject');
  }

  return payload;
}

async function callGemini(apiKey, requestBody) {
  let fallbackLog = [];
  let lastRetryableError = null;
  let lastRetryableErrorScore = -1;

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  const toReadableGeminiError = (rawText) => {
    if (!rawText) return '';
    try {
      const parsed = JSON.parse(rawText);
      const message = parsed?.error?.message;
      if (typeof message === 'string' && message.trim()) {
        return message.trim();
      }
    } catch (_) {
      // Keep raw text fallback.
    }
    return rawText;
  };

  const shouldFallback = (status, detailText) => {
    if (status === 404) return true;

    // Transient upstream failures should fallback to the next endpoint/model.
    if (status === 408 || status === 429) return true;
    if (status >= 500) return true;

    if (status !== 400) return false;

    const lower = (detailText || '').toLowerCase();
    const nonRetryable = /(api key|permission|forbidden|billing|quota|rate limit|unauth|credential)/i.test(lower);
    if (nonRetryable) return false;

    // Many endpoint/model mismatches return generic INVALID_ARGUMENT 400.
    return true;
  };

  const shouldRetrySameEndpoint = (status, detailText) => {
    if (status === 408 || status === 429) return true;
    if ([500, 502, 503, 504, 520, 522, 523, 524, 525, 526, 527, 530].includes(status)) {
      return true;
    }

    const lower = (detailText || '').toLowerCase();
    return /(timeout|timed out|deadline|temporar|try again|connection reset|broken pipe|upstream)/i.test(lower);
  };

  const retryablePriority = (status, detailText) => {
    const lower = (detailText || '').toLowerCase();
    if (status === 429 || /(quota|rate limit|resource exhausted|too many requests)/i.test(lower)) {
      return 1000;
    }
    if (status === 408) return 950;
    if (status >= 500) return 900;
    if (status === 404) return 500;
    if (status === 400) return 400;
    return 100;
  };

  const rememberRetryableError = (status, message, detail) => {
    const score = retryablePriority(status, detail);
    if (score >= lastRetryableErrorScore) {
      lastRetryableError = new HttpError(status, message, detail);
      lastRetryableErrorScore = score;
    }
  };

  const mapKeysDeep = (value, mapper) => {
    if (Array.isArray(value)) {
      return value.map((v) => mapKeysDeep(v, mapper));
    }
    if (value && typeof value === 'object') {
      const out = {};
      for (const [k, v] of Object.entries(value)) {
        out[mapper(k)] = mapKeysDeep(v, mapper);
      }
      return out;
    }
    return value;
  };

  const payloadForEndpoint = (endpoint) => {
    const isV1 = endpoint.includes('/v1/models/');
    if (!isV1) return requestBody;

    // v1 endpoints are stricter and prefer camelCase part fields.
    return mapKeysDeep(requestBody, (key) => {
      if (key === 'inline_data') return 'inlineData';
      if (key === 'mime_type') return 'mimeType';
      return key;
    });
  };

  for (const endpoint of GEMINI_ENDPOINTS) {
    const maxEndpointAttempts = 2;
    const endpointPayload = JSON.stringify(payloadForEndpoint(endpoint));

    for (let attempt = 1; attempt <= maxEndpointAttempts; attempt += 1) {
      try {
        const resp = await fetch(endpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: endpointPayload,
        });

        const text = await resp.text();
        if (resp.ok) {
          return JSON.parse(text);
        }

        const detail = toReadableGeminiError(text);
        fallbackLog.push(`${endpoint} -> ${resp.status} (try ${attempt})`);

        const canRetrySameEndpoint = shouldRetrySameEndpoint(resp.status, detail) && attempt < maxEndpointAttempts;
        if (canRetrySameEndpoint) {
          await sleep(300 * attempt);
          continue;
        }

        if (shouldFallback(resp.status, detail)) {
          rememberRetryableError(resp.status, `Gemini error ${resp.status}`, detail);
          break;
        }

        throw new HttpError(resp.status, `Gemini error ${resp.status}`, detail);
      } catch (error) {
        const isHttpError = error instanceof HttpError;
        if (isHttpError) {
          throw error;
        }

        const message = error instanceof Error ? error.message : String(error);
        fallbackLog.push(`${endpoint} -> fetch_error (try ${attempt}): ${message}`);

        if (attempt < maxEndpointAttempts) {
          await sleep(300 * attempt);
          continue;
        }

        rememberRetryableError(503, 'Gemini upstream non raggiungibile', message);
        break;
      }
    }
  }

  if (lastRetryableError) {
    throw new HttpError(
      lastRetryableError.status,
      lastRetryableError.message,
      `${lastRetryableError.details} | fallback: ${fallbackLog.join(' | ')}`,
    );
  }

  throw new HttpError(
    502,
    'Nessun endpoint Gemini compatibile disponibile',
    fallbackLog.join(' | '),
  );
}

function extractModelText(geminiResp) {
  const parts = geminiResp?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return '';
  return parts.map((p) => p?.text || '').join('');
}

function extractJsonPayload(raw) {
  const trimmed = (raw || '').trim();
  if (!trimmed) return '';

  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (fenced?.[1]) return fenced[1].trim();
  return trimmed;
}

function cloneJsonValue(value) {
  return JSON.parse(JSON.stringify(value));
}

function asText(value, fallback = '') {
  const text = value === undefined || value === null ? '' : String(value).trim();
  return text || fallback;
}

function toIntMaybe(value, fallback = null) {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
  const parsed = Number.parseInt(String(value).trim(), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toNullableNumber(value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const normalized = String(value).trim().replace(',', '.');
  if (!/^[-+]?\d+(?:\.\d+)?$/.test(normalized)) return null;
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function extractSetRepHintFromText(value) {
  const text = asText(value, '').toLowerCase();
  if (!text) return { sets: null, reps: null };

  const patterns = [
    /(\d{1,2})\s*[x×]\s*(\d{1,3}(?:\s*[-/]\s*\d{1,3})?)/i,
    /(\d{1,2})\s*(?:set|sets|serie)\s*(?:x|da)?\s*(\d{1,3}(?:\s*[-/]\s*\d{1,3})?)/i,
    /(?:set|sets|serie)\s*[:=\-]?\s*(\d{1,2})\D{0,10}(?:reps?|rip(?:etizioni)?|x)\s*(\d{1,3}(?:\s*[-/]\s*\d{1,3})?)/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match) continue;

    const sets = toIntMaybe(match[1], null);
    const repsRaw = asText(match[2], '').replace(/\s+/g, '');
    const reps = repsRaw || null;

    if ((sets !== null && sets > 0) || reps) {
      return {
        sets: sets !== null && sets > 0 ? sets : null,
        reps,
      };
    }
  }

  return { sets: null, reps: null };
}

function isSetRepTechniqueLabel(value) {
  const text = asText(value, '').toLowerCase();
  if (!text) return false;

  return (
    /^\d{1,2}\s*[x×]\s*\d{1,3}(?:\s*[-/]\s*\d{1,3})?(?:\s*(?:@|al|at).*)?$/.test(text)
    || /^\d{1,2}\s*(?:set|sets|serie)\b/.test(text)
    || /^(?:set|sets|serie)\s*[:=\-]?\s*\d{1,2}\b/.test(text)
  );
}

function sanitizeTechniqueLabels(labels) {
  if (!Array.isArray(labels)) return [];

  const cleaned = [];
  for (const raw of labels) {
    const label = asText(raw, '');
    if (!label) continue;
    if (isSetRepTechniqueLabel(label)) continue;

    const already = cleaned.some((existing) => existing.toLowerCase() === label.toLowerCase());
    if (!already) cleaned.push(label);
  }

  return cleaned;
}

function parseWeekNumberFromKey(weekKey, fallback = 1) {
  const match = String(weekKey || '').match(/(\d+)/);
  if (!match?.[1]) return fallback;
  const parsed = Number.parseInt(match[1], 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function parseWeekCountFromValue(value) {
  if (value === undefined || value === null) return null;

  if (typeof value === 'number' && Number.isFinite(value)) {
    const v = Math.trunc(value);
    return v > 0 ? Math.min(v, 14) : null;
  }

  if (typeof value === 'object' && !Array.isArray(value)) {
    const keys = Object.keys(value);
    const weekNumbers = keys
      .map((k) => parseWeekNumberFromKey(k, 0))
      .filter((n) => Number.isFinite(n) && n > 0);
    if (weekNumbers.length > 0) {
      return Math.min(Math.max(...weekNumbers), 14);
    }
  }

  const text = asText(value, '').toLowerCase();
  if (!text) return null;

  const direct = Number.parseInt(text, 10);
  if (Number.isFinite(direct) && direct > 0) {
    return Math.min(direct, 14);
  }

  const candidates = [];
  const explicitDuration = text.match(/(\d{1,2})\s*(?:settimane|settimana|weeks|week)\b/i);
  if (explicitDuration?.[1]) {
    const parsed = Number.parseInt(explicitDuration[1], 10);
    if (Number.isFinite(parsed) && parsed > 0) candidates.push(parsed);
  }

  const weekRefs = Array.from(text.matchAll(/\bw\s*[-_ ]*(\d{1,2})\b/gi));
  for (const match of weekRefs) {
    const parsed = Number.parseInt(match[1], 10);
    if (Number.isFinite(parsed) && parsed > 0) candidates.push(parsed);
  }

  if (candidates.length === 0) return null;
  return Math.min(Math.max(...candidates), 14);
}

function resolveDesiredWeekCount(parsedRoot, allenamento, defaultWeeks = 14) {
  const candidates = [
    parseWeekCountFromValue(parsedRoot?.numero_settimane),
    parseWeekCountFromValue(parsedRoot?.n_settimane),
    parseWeekCountFromValue(parsedRoot?.settimane_totali),
    parseWeekCountFromValue(parsedRoot?.durata_settimane),
    parseWeekCountFromValue(parsedRoot?.weeks_count),
    parseWeekCountFromValue(parsedRoot?.total_weeks),
    parseWeekCountFromValue(parsedRoot?.weeks),
    parseWeekCountFromValue(parsedRoot?.nome_scheda),
    parseWeekCountFromValue(allenamento?.numero_settimane),
    parseWeekCountFromValue(allenamento?.settimane_totali),
    parseWeekCountFromValue(allenamento?.weeks_count),
    parseWeekCountFromValue(allenamento?.total_weeks),
    parseWeekCountFromValue(allenamento?.weeks),
    parseWeekCountFromValue(allenamento?.titolo),
  ].filter((v) => Number.isFinite(v) && v > 0);

  if (candidates.length === 0) return defaultWeeks;
  return Math.min(Math.max(...candidates), 14);
}

function sortWeekKeys(weeksObject) {
  if (!weeksObject || typeof weeksObject !== 'object' || Array.isArray(weeksObject)) {
    return [];
  }

  const strictWeekKeys = Object.keys(weeksObject).filter((key) => /^w\d+$/i.test(key.trim()));
  const keys = strictWeekKeys.length > 0
    ? strictWeekKeys
    : Object.entries(weeksObject)
        .filter(([, value]) => Array.isArray(value))
        .map(([key]) => key);

  return keys.sort((a, b) => parseWeekNumberFromKey(a, 0) - parseWeekNumberFromKey(b, 0));
}

function exerciseIdToDisplayName(idEs) {
  const raw = asText(idEs, '');
  if (!raw) return 'Esercizio';
  return raw
    .replace(/[_-]+/g, ' ')
    .split(' ')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function normalizePlanSet(rawSet, fallbackSet = {}, defaultIndex = 1) {
  const setRaw = rawSet && typeof rawSet === 'object' ? rawSet : {};
  const setBase = fallbackSet && typeof fallbackSet === 'object' ? fallbackSet : {};

  const s = toIntMaybe(setRaw.s, toIntMaybe(setBase.s, defaultIndex));
  return {
    s,
    r: setRaw.r !== undefined ? setRaw.r : (setBase.r ?? null),
    kg: setRaw.kg !== undefined ? setRaw.kg : (setBase.kg ?? null),
    rest: setRaw.rest !== undefined ? setRaw.rest : (setBase.rest ?? null),
  };
}

function normalizePlanSeries(rawSerie, fallbackSerie = []) {
  const baselineMap = new Map();
  if (Array.isArray(fallbackSerie)) {
    fallbackSerie.forEach((setRow, index) => {
      const normalized = normalizePlanSet(setRow, {}, index + 1);
      baselineMap.set(normalized.s, normalized);
    });
  }

  if (!Array.isArray(rawSerie) || rawSerie.length === 0) {
    return Array.from(baselineMap.values()).sort((a, b) => a.s - b.s);
  }

  const mergedMap = new Map();
  for (const [setIndex, baselineSet] of baselineMap.entries()) {
    mergedMap.set(setIndex, cloneJsonValue(baselineSet));
  }

  rawSerie.forEach((setRow, index) => {
    if (!setRow || typeof setRow !== 'object') return;
    const idx = toIntMaybe(setRow.s, index + 1);
    const base = mergedMap.get(idx) || baselineMap.get(idx) || { s: idx };
    const normalized = normalizePlanSet(setRow, base, idx);
    mergedMap.set(idx, normalized);
  });

  return Array.from(mergedMap.values()).sort((a, b) => a.s - b.s);
}

function buildSeriesFromLegacyFields(rawExercise, defaults = {}) {
  const getText = (primary, fallback = '') => asText(primary, asText(fallback, ''));

  const workingSet = toIntMaybe(
    rawExercise.workingSet
      ?? rawExercise.workingSets
      ?? rawExercise.serieAllenanti
      ?? rawExercise.serieLavoro
      ?? rawExercise.sets
      ?? rawExercise.set
      ?? defaults.workingSet
      ?? defaults.workingSets
      ?? defaults.serieAllenanti
      ?? defaults.serieLavoro
      ?? defaults.sets
      ?? defaults.set,
    null,
  );

  const reps = getText(
    rawExercise.ripetizioni ?? rawExercise.reps ?? rawExercise.rep,
    defaults.ripetizioni ?? defaults.reps ?? defaults.rep,
  );
  const kg = getText(
    rawExercise.kg ?? rawExercise.peso ?? rawExercise.carico,
    defaults.kg ?? defaults.peso ?? defaults.carico,
  );
  const rest = getText(
    rawExercise.recupero ?? rawExercise.rest ?? rawExercise.pausa,
    defaults.recupero ?? defaults.rest ?? defaults.pausa,
  );

  if (workingSet === null && !reps && !kg && !rest) {
    return [];
  }

  const setCount = Math.max(1, workingSet ?? 3);
  const repsValue = reps || '8-10';
  const restValue = rest || '90';

  return Array.from({ length: setCount }, (_, idx) => ({
    s: idx + 1,
    r: repsValue,
    kg: kg || null,
    rest: restValue,
  }));
}

function normalizePlanExercise(rawExercise, defaults = {}) {
  if (!rawExercise || typeof rawExercise !== 'object') return null;

  const defaultId = asText(defaults.id_es, '');
  const id_es = asText(rawExercise.id_es, defaultId);
  const statusRaw = asText(rawExercise.status, asText(defaults.status, 'active')).toLowerCase();
  const status = statusRaw === 'removed' ? 'removed' : 'active';

  if (!id_es) return null;

  const modalitaRaw = asText(rawExercise.modalitaIntensita, asText(defaults.modalitaIntensita, 'rir')).toLowerCase();
  const modalitaIntensita = modalitaRaw === 'percentuale' ? 'percentuale' : 'rir';
  const metodo = asText(rawExercise.metodo, asText(defaults.metodo, 'Classico'));
  const tecniche = Array.isArray(rawExercise.tecniche)
    ? rawExercise.tecniche.map((t) => asText(t, '')).filter(Boolean)
    : Array.isArray(defaults.tecniche)
      ? defaults.tecniche.map((t) => asText(t, '')).filter(Boolean)
      : [];

  const fallbackSeries = Array.isArray(defaults.serie) ? defaults.serie : [];
  const rawSeries = Array.isArray(rawExercise.serie) ? rawExercise.serie : undefined;
  let serie = normalizePlanSeries(rawSeries, fallbackSeries);

  if ((!Array.isArray(rawSeries) || rawSeries.length === 0) && serie.length === 0) {
    const synthesized = buildSeriesFromLegacyFields(rawExercise, defaults);
    if (synthesized.length > 0) {
      serie = normalizePlanSeries(synthesized, fallbackSeries);
    }
  }

  return {
    id_es,
    status,
    serie,
    note: asText(rawExercise.note, asText(defaults.note, '')),
    metodo,
    tecniche: tecniche.length > 0 ? tecniche : [metodo || 'Classico'],
    modalitaIntensita,
    rirTarget: asText(rawExercise.rirTarget, asText(defaults.rirTarget, '')),
    percentualeMassimale: toNullableNumber(rawExercise.percentualeMassimale ?? defaults.percentualeMassimale),
    massimaleKg: toNullableNumber(rawExercise.massimaleKg ?? defaults.massimaleKg),
    caricoTargetKg: toNullableNumber(rawExercise.caricoTargetKg ?? defaults.caricoTargetKg),
  };
}

function extractPercentFromKgValue(value) {
  const text = asText(value, '');
  if (!text) return null;
  const match = text.match(/([-+]?\d+(?:[.,]\d+)?)\s*%/);
  if (!match?.[1]) return null;
  const parsed = Number.parseFloat(match[1].replace(',', '.'));
  return Number.isFinite(parsed) ? parsed : null;
}

function isSimpleRepText(value) {
  const compact = asText(value, '').toLowerCase().replace(/\s+/g, '');
  return /^\d{1,3}(?:[-/]\d{1,3})?$/.test(compact);
}

function hasProgressionTableHint(...sources) {
  const text = sources
    .flatMap((s) => (Array.isArray(s) ? s : [s]))
    .map((s) => asText(s, '').toLowerCase())
    .filter(Boolean)
    .join(' ');

  if (!text) return false;

  return (
    /(?:tabella|table).{0,24}(?:progress|progression)/i.test(text)
    || /(?:progress|progression).{0,24}(?:tabella|table)/i.test(text)
    || /(?:guarda|vedi|see|consulta).{0,20}(?:tabella|table)/i.test(text)
  );
}

function looksLikeProgressionTableLabel(value) {
  const text = asText(value, '').toLowerCase();
  if (!text) return false;
  const hasTable = /\b(?:tabella|table)\b/i.test(text);
  const hasProgress = /\bprogress(?:ione|ion)?\b/i.test(text);
  return hasTable && hasProgress;
}

function planExerciseToLegacyExercise(planExercise) {
  if (!planExercise || typeof planExercise !== 'object') return null;

  const series = Array.isArray(planExercise.serie)
    ? planExercise.serie
        .filter((row) => row && typeof row === 'object')
        .sort((a, b) => toIntMaybe(a.s, 0) - toIntMaybe(b.s, 0))
    : [];

  const normalizedSeries = series.length > 0 ? series : [{ s: 1, r: '8-10', kg: null, rest: '90' }];
  const seriesByIndex = new Map();
  for (let idx = 0; idx < normalizedSeries.length; idx += 1) {
    const row = normalizedSeries[idx];
    const setIndex = Math.max(1, toIntMaybe(row?.s, idx + 1));
    if (!seriesByIndex.has(setIndex)) {
      seriesByIndex.set(setIndex, row);
    }
  }

  const firstSet = seriesByIndex.get(1) || normalizedSeries[0] || { s: 1, r: '8-10', kg: null, rest: '90' };
  const progressionHint = hasProgressionTableHint(
    planExercise.note,
    planExercise.metodo,
    planExercise.tecniche,
    firstSet.r,
  );

  const firstSetHint = extractSetRepHintFromText(firstSet.r);
  const noteHint = extractSetRepHintFromText(planExercise.note);
  const metodoHint = extractSetRepHintFromText(planExercise.metodo);
  const tecnicheHints = Array.isArray(planExercise.tecniche)
    ? planExercise.tecniche.map((t) => extractSetRepHintFromText(t))
    : [];

  const hintedWorkingSet = [firstSetHint, noteHint, metodoHint, ...tecnicheHints]
    .map((hint) => hint?.sets)
    .find((value) => Number.isFinite(value) && value > 0) || null;

  const kgFromFirst = toNullableNumber(firstSet.kg);
  const percentFromKg = extractPercentFromKgValue(firstSet.kg);
  const modalitaIntensita = planExercise.modalitaIntensita === 'percentuale' || percentFromKg !== null
    ? 'percentuale'
    : 'rir';

  const percentualeMassimale =
    planExercise.percentualeMassimale !== null && planExercise.percentualeMassimale !== undefined
      ? planExercise.percentualeMassimale
      : percentFromKg;

  const rawTecniche = Array.isArray(planExercise.tecniche) && planExercise.tecniche.length > 0
    ? planExercise.tecniche
    : [asText(planExercise.metodo, 'Classico')];
  const tecniche = sanitizeTechniqueLabels(rawTecniche);

  const maxSetIndex = normalizedSeries.reduce(
    (max, row, idx) => Math.max(max, Math.max(1, toIntMaybe(row?.s, idx + 1))),
    0,
  );
  let workingSet = Math.max(normalizedSeries.length, maxSetIndex, hintedWorkingSet || 0, 1);
  if (progressionHint && workingSet <= 1) {
    workingSet = 3;
  }

  let ripetizioni = asText(firstSetHint.reps || firstSet.r, '8-10');
  const contextRepHint = [noteHint, metodoHint, ...tecnicheHints]
    .map((hint) => hint?.reps)
    .find((value) => asText(value, '') && asText(value, '') !== '1') || null;

  if (looksLikeProgressionTableLabel(ripetizioni)) {
    ripetizioni = 'Guarda tabella progressione';
  }
  const repsCompact = asText(ripetizioni, '').toLowerCase().replace(/\s+/g, '');
  const looksSinglePlaceholder =
    repsCompact === ''
    || repsCompact === '1'
    || repsCompact === '1rep'
    || repsCompact === '1reps'
    || repsCompact === 'x1'
    || repsCompact === '1x1';

  if (looksSinglePlaceholder && contextRepHint) {
    ripetizioni = contextRepHint;
  }

  if (progressionHint && looksSinglePlaceholder) {
    ripetizioni = 'Guarda tabella progressione';
  }

  const seriesForLegacy = [];
  const defaultRest = asText(firstSet.rest, '90');
  const defaultRepValue = isSimpleRepText(ripetizioni) ? ripetizioni : asText(firstSet.r, '');

  for (let setNumber = 1; setNumber <= workingSet; setNumber += 1) {
    const source = seriesByIndex.get(setNumber) || {};
    const repValue = asText(source.r, '') || defaultRepValue;
    seriesForLegacy.push({
      s: setNumber,
      r: repValue,
      kg: source.kg ?? null,
      rest: asText(source.rest, defaultRest),
    });
  }

  const serieAttive = seriesForLegacy.map((row) => {
    const percentualeTarget = extractPercentFromKgValue(row.kg);
    return {
      tipo: 'Working Set',
      peso: percentualeTarget !== null ? '' : asText(row.kg, ''),
      ripetizioniFatte: asText(row.r, ''),
      isCompletata: false,
      rpe: '',
      percentualeTarget: percentualeTarget !== null ? String(percentualeTarget) : '',
    };
  });

  const noteParts = [];
  const kgText = asText(firstSet.kg, '');
  if (kgText && /[a-z]/i.test(kgText) && !kgText.includes('%') && toNullableNumber(kgText) === null) {
    noteParts.push(`Carico: ${kgText}`);
  }
  const noteRaw = asText(planExercise.note, '');
  if (noteRaw) noteParts.push(noteRaw);

  return {
    nome: exerciseIdToDisplayName(planExercise.id_es),
    avvicinamento: 0,
    workingSet,
    ripetizioni,
    recupero: asText(firstSet.rest, '90'),
    rpe: '',
    modalitaIntensita,
    rirTarget: modalitaIntensita === 'rir' ? (asText(planExercise.rirTarget, '') || null) : null,
    percentualeMassimale: modalitaIntensita === 'percentuale' ? percentualeMassimale : null,
    massimaleKg: modalitaIntensita === 'percentuale' ? planExercise.massimaleKg : null,
    caricoTargetKg: modalitaIntensita === 'percentuale' ? null : (planExercise.caricoTargetKg ?? kgFromFirst),
    note: noteParts.length > 0 ? noteParts.join(' | ') : null,
    metodo: asText(planExercise.metodo, 'Classico'),
    tecniche: tecniche.length > 0 ? tecniche : [asText(planExercise.metodo, 'Classico')],
    serieAttive,
  };
}

function buildAutoProgressionDeltas(baselineExercises, weekOffset) {
  const deltas = [];

  for (const exercise of baselineExercises) {
    if (!exercise || typeof exercise !== 'object') continue;
    if (asText(exercise.status, 'active').toLowerCase() === 'removed') continue;

    const firstSet = Array.isArray(exercise.serie) && exercise.serie.length > 0
      ? exercise.serie[0]
      : { s: 1, r: 8, kg: null, rest: 90 };

    const deltaSet = { s: toIntMaybe(firstSet.s, 1) };
    const kgValue = toNullableNumber(firstSet.kg);

    if (kgValue !== null) {
      const increased = Math.round((kgValue * (1 + 0.025 * weekOffset)) * 2) / 2;
      deltaSet.kg = Number.isFinite(increased) ? increased : kgValue;
    } else {
      const reps = toIntMaybe(firstSet.r, null);
      if (reps !== null) {
        deltaSet.r = reps + weekOffset;
      } else {
        deltaSet.r = asText(firstSet.r, `${8 + weekOffset}`);
      }
    }

    deltas.push({
      id_es: exercise.id_es,
      serie: [deltaSet],
    });
  }

  return deltas;
}

function applyWeekDeltas(baselineExercises, weekDeltasRaw) {
  const current = baselineExercises.map((exercise) => cloneJsonValue(exercise));
  const usedIndexes = new Set();
  const deltas = Array.isArray(weekDeltasRaw) ? weekDeltasRaw : [];

  for (const deltaRaw of deltas) {
    if (!deltaRaw || typeof deltaRaw !== 'object') continue;

    const deltaId = asText(deltaRaw.id_es, '').toLowerCase();
    const status = asText(deltaRaw.status, '').toLowerCase();
    let targetIndex = -1;

    const idxValue = deltaRaw.idx ?? deltaRaw.index ?? deltaRaw.pos ?? deltaRaw.position;
    const parsedIdx = toIntMaybe(idxValue, null);
    if (parsedIdx !== null) {
      if (parsedIdx >= 1 && parsedIdx <= current.length) {
        targetIndex = parsedIdx - 1;
      } else if (parsedIdx >= 0 && parsedIdx < current.length) {
        targetIndex = parsedIdx;
      }
    }

    if (targetIndex < 0) {
      const oldId = asText(deltaRaw.old_id_es ?? deltaRaw.replace_id_es ?? deltaRaw.target_id_es, '').toLowerCase();
      if (oldId) {
        targetIndex = current.findIndex((exercise) => asText(exercise.id_es, '').toLowerCase() === oldId);
      }
    }

    if (targetIndex < 0 && deltaId) {
      targetIndex = current.findIndex((exercise) => asText(exercise.id_es, '').toLowerCase() === deltaId);
    }

    if (status === 'removed') {
      if (targetIndex >= 0) {
        current[targetIndex] = {
          ...current[targetIndex],
          status: 'removed',
        };
        usedIndexes.add(targetIndex);
      }
      continue;
    }

    if (targetIndex < 0 && deltaId) {
      targetIndex = current.findIndex((_, index) => !usedIndexes.has(index));
    }

    const fallback = targetIndex >= 0
      ? current[targetIndex]
      : (deltaRaw.id_es ? { id_es: deltaRaw.id_es, status: 'active', serie: [] } : {});

    const merged = normalizePlanExercise(deltaRaw, fallback);
    if (!merged || !merged.id_es) continue;

    merged.status = 'active';
    if (targetIndex >= 0) {
      current[targetIndex] = merged;
      usedIndexes.add(targetIndex);
    } else {
      current.push(merged);
    }
  }

  return current.filter((exercise) => asText(exercise.status, 'active').toLowerCase() !== 'removed');
}

function convertSchedaAllenamentiDeltaToItems(parsedRoot) {
  if (!parsedRoot || typeof parsedRoot !== 'object') {
    return { items: null, error: 'Root JSON non valido' };
  }

  const nomeScheda = asText(parsedRoot.nome_scheda, 'Scheda Importata');
  const folderCategory = nomeScheda;
  const allenamenti = Array.isArray(parsedRoot.allenamenti) ? parsedRoot.allenamenti : [];
  if (allenamenti.length === 0) {
    return { items: null, error: 'Campo allenamenti mancante o vuoto' };
  }

  const items = [];

  for (let sessionIndex = 0; sessionIndex < allenamenti.length; sessionIndex += 1) {
    const allenamento = allenamenti[sessionIndex];
    if (!allenamento || typeof allenamento !== 'object') {
      return { items: null, error: `allenamenti[${sessionIndex}] non valido` };
    }

    const idAllenamento = asText(allenamento.id_allenamento, String.fromCharCode(65 + (sessionIndex % 26)));
    const titolo = asText(allenamento.titolo, `Allenamento ${idAllenamento}`);
    const desiredWeekCount = resolveDesiredWeekCount(parsedRoot, allenamento, 14);
    const weeksRaw = allenamento.weeks;

    if (!weeksRaw || typeof weeksRaw !== 'object' || Array.isArray(weeksRaw)) {
      return { items: null, error: `allenamento ${idAllenamento}: campo weeks non valido` };
    }

    let weekMap = { ...weeksRaw };
    let weekKeys = sortWeekKeys(weekMap);
    if (weekKeys.length === 0) {
      return { items: null, error: `allenamento ${idAllenamento}: weeks vuote` };
    }

    const baselineKey = weekKeys.find((key) => key.toLowerCase() === 'w1') || weekKeys[0];
    const baselineRaw = Array.isArray(weekMap[baselineKey]) ? weekMap[baselineKey] : [];
    if (baselineRaw.length === 0) {
      return { items: null, error: `allenamento ${idAllenamento}: ${baselineKey} senza esercizi` };
    }

    const baselineExercises = baselineRaw
      .map((exercise) => normalizePlanExercise(exercise))
      .filter((exercise) => exercise && asText(exercise.status, 'active').toLowerCase() !== 'removed');

    if (baselineExercises.length === 0) {
      return { items: null, error: `allenamento ${idAllenamento}: baseline senza esercizi validi` };
    }

    const baselineWeekNumber = parseWeekNumberFromKey(baselineKey, 1);
    const maxExistingWeekNumber = weekKeys.reduce(
      (max, key) => Math.max(max, parseWeekNumberFromKey(key, 0)),
      0,
    );
    const targetWeekCount = Math.max(
      desiredWeekCount,
      maxExistingWeekNumber,
      baselineWeekNumber,
    );

    if (targetWeekCount > maxExistingWeekNumber) {
      for (let week = baselineWeekNumber + 1; week <= targetWeekCount; week += 1) {
        const key = `w${week}`;
        if (Array.isArray(weekMap[key])) continue;
        weekMap[key] = buildAutoProgressionDeltas(
          baselineExercises,
          week - baselineWeekNumber,
        );
      }
      weekKeys = sortWeekKeys(weekMap);
    }

    for (const weekKey of weekKeys) {
      const weekDelta = Array.isArray(weekMap[weekKey]) ? weekMap[weekKey] : [];
      const isBaseline = weekKey.toLowerCase() === baselineKey.toLowerCase();
      const fullWeekExercises = isBaseline
        ? baselineExercises.map((exercise) => cloneJsonValue(exercise))
        : applyWeekDeltas(baselineExercises, weekDelta);

      const legacyExercises = fullWeekExercises
        .map((exercise) => planExerciseToLegacyExercise(exercise))
        .filter(Boolean);

      if (legacyExercises.length === 0) continue;

      const weekNumber = parseWeekNumberFromKey(weekKey, 1);
      const titoloScheda = `${nomeScheda} - ${idAllenamento} ${titolo}`;

      items.push({
        nome: `${titoloScheda} - ${weekKey.toUpperCase()}`,
        livello: 'Intermedio',
        categoria: folderCategory,
        continuativa: true,
        settimanaCorrente: weekNumber,
        esercizi: legacyExercises,
      });
    }
  }

  return { items, error: null };
}

function normalizeExerciseForImport(exercise, defaults = {}) {
  if (!exercise || typeof exercise !== 'object') return null;

  const nome = (exercise.nome || '').toString().trim();
  if (!nome) return null;

  const toInt = (value, fallback) => {
    if (typeof value === 'number' && Number.isFinite(value)) return Math.trunc(value);
    const parsed = Number.parseInt(String(value || '').trim(), 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  };

  const toNullableNumber = (value) => {
    if (value === null || value === undefined || value === '') return null;
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    const parsed = Number.parseFloat(String(value).replace(',', '.'));
    return Number.isFinite(parsed) ? parsed : null;
  };

  const textOr = (value, fallback = '') => {
    const text = value === undefined || value === null ? '' : String(value).trim();
    return text || fallback;
  };

  const modalitaRaw = textOr(exercise.modalitaIntensita, '').toLowerCase();
  const modalitaDefault = defaults.modalitaIntensita === 'percentuale' ? 'percentuale' : 'rir';
  const modalitaIntensita = modalitaRaw === 'rir' || modalitaRaw === 'percentuale'
    ? modalitaRaw
    : modalitaDefault;

  const tecnicheRaw = Array.isArray(exercise.tecniche)
    ? exercise.tecniche.map((t) => String(t || '').trim()).filter(Boolean)
    : [];
  const metodo = textOr(exercise.metodo, textOr(defaults.metodo, 'Classico'));
  const tecniche = tecnicheRaw.length > 0
    ? tecnicheRaw
    : (metodo ? [metodo] : ['Classico']);

  return {
    nome,
    avvicinamento: toInt(exercise.avvicinamento, toInt(defaults.avvicinamento, 0)),
    workingSet: toInt(exercise.workingSet, toInt(defaults.workingSet, 3)),
    ripetizioni: textOr(exercise.ripetizioni, textOr(defaults.ripetizioni, '8-10')),
    recupero: textOr(exercise.recupero, textOr(defaults.recupero, '90')),
    rpe: textOr(exercise.rpe, textOr(defaults.rpe, '')),
    modalitaIntensita,
    rirTarget:
      modalitaIntensita === 'rir'
        ? textOr(exercise.rirTarget, textOr(defaults.rirTarget, '')) || null
        : null,
    percentualeMassimale:
      modalitaIntensita === 'percentuale'
        ? toNullableNumber(exercise.percentualeMassimale ?? defaults.percentualeMassimale)
        : null,
    massimaleKg:
      modalitaIntensita === 'percentuale'
        ? toNullableNumber(exercise.massimaleKg ?? defaults.massimaleKg)
        : null,
    caricoTargetKg: toNullableNumber(exercise.caricoTargetKg ?? defaults.caricoTargetKg),
    note: textOr(exercise.note, textOr(defaults.note, '')) || null,
    metodo: metodo || 'Classico',
    tecniche,
    serieAttive: Array.isArray(exercise.serieAttive)
      ? exercise.serieAttive.filter((s) => s && typeof s === 'object')
      : Array.isArray(defaults.serieAttive)
        ? defaults.serieAttive.filter((s) => s && typeof s === 'object')
        : [],
  };
}

function convertProgrammaDeltaToItems(programmaRaw) {
  if (!Array.isArray(programmaRaw)) {
    return { items: null, error: 'programma deve essere un array' };
  }

  const items = [];

  for (let blockIndex = 0; blockIndex < programmaRaw.length; blockIndex += 1) {
    const scheda = programmaRaw[blockIndex];
    if (!scheda || typeof scheda !== 'object') {
      return { items: null, error: `programma[${blockIndex}] non e un oggetto valido` };
    }

    const blockId = String(scheda.id || `scheda-${blockIndex + 1}`).trim() || `scheda-${blockIndex + 1}`;
    const blockFolderCategory = String(scheda.nome || scheda.nome_scheda || blockId).trim() || blockId;
    const obiettivo = String(scheda.obiettivo || '').trim() || 'Intermedio';
    const settimane = scheda.settimane;

    if (!Array.isArray(settimane) || settimane.length === 0) {
      return { items: null, error: `scheda ${blockId} senza settimane` };
    }

    const baselineWeek = settimane[0];
    if (!baselineWeek || typeof baselineWeek !== 'object') {
      return { items: null, error: `scheda ${blockId}: settimana baseline non valida` };
    }

    const baselineId = String(baselineWeek.id || '').trim();
    if (!baselineId) {
      return { items: null, error: `scheda ${blockId}: settimana baseline senza id` };
    }

    const baselineExercisesRaw = Array.isArray(baselineWeek.esercizi) ? baselineWeek.esercizi : [];
    if (baselineExercisesRaw.length === 0) {
      return { items: null, error: `scheda ${blockId}: settimana baseline senza esercizi` };
    }

    const baselineMap = new Map();
    for (const rawExercise of baselineExercisesRaw) {
      const normalized = normalizeExerciseForImport(rawExercise);
      if (!normalized) continue;
      baselineMap.set(normalized.nome.toLowerCase(), normalized);
    }

    if (baselineMap.size === 0) {
      return { items: null, error: `scheda ${blockId}: settimana baseline senza esercizi validi` };
    }

    for (let weekIndex = 0; weekIndex < settimane.length; weekIndex += 1) {
      const settimana = settimane[weekIndex];
      if (!settimana || typeof settimana !== 'object') {
        return { items: null, error: `scheda ${blockId}: settimana indice ${weekIndex} non valida` };
      }

      const weekId = String(settimana.id || `week-${weekIndex + 1}`).trim() || `week-${weekIndex + 1}`;
      const weekExercisesRaw = Array.isArray(settimana.esercizi) ? settimana.esercizi : [];

      const mergedMap = new Map();
      for (const [key, baseExercise] of baselineMap.entries()) {
        mergedMap.set(key, { ...baseExercise });
      }

      for (const deltaExerciseRaw of weekExercisesRaw) {
        const deltaName = String(deltaExerciseRaw?.nome || '').trim();
        if (!deltaName) continue;

        const key = deltaName.toLowerCase();
        const baselineExercise = mergedMap.get(key) || baselineMap.get(key) || { nome: deltaName };
        const merged = normalizeExerciseForImport(deltaExerciseRaw, baselineExercise);
        if (!merged) continue;
        mergedMap.set(key, merged);
      }

      const eserciziMerged = Array.from(mergedMap.values());
      const settimanaNumero = Number.parseInt(String(weekId).replace(/[^0-9]/g, ''), 10);
      const settimanaCorrente = Number.isFinite(settimanaNumero) && settimanaNumero > 0
        ? settimanaNumero
        : weekIndex + 1;

      items.push({
        nome: `${blockId} - ${weekId}`,
        livello: obiettivo,
        categoria: blockFolderCategory,
        continuativa: true,
        settimanaCorrente,
        esercizi: eserciziMerged,
      });
    }
  }

  return { items, error: null };
}

function parseWorkoutResponse(raw) {
  try {
    const parsed = JSON.parse(raw);

    // Priorita: formato strutturato scheda/allenamenti.
    if (parsed && typeof parsed === 'object' && Array.isArray(parsed.allenamenti)) {
      const converted = convertSchedaAllenamentiDeltaToItems(parsed);
      if (!converted.items) {
        return {
          items: null,
          structuredPlan: null,
          error: converted.error || 'scheda/allenamenti non convertibile',
          format: 'scheda-allenamenti-delta',
        };
      }
      return {
        items: converted.items,
        structuredPlan: parsed,
        error: null,
        format: 'scheda-allenamenti-delta',
      };
    }

    // Fallback: formato array legacy diretto.
    if (Array.isArray(parsed)) {
      return { items: parsed, structuredPlan: null, error: null, format: 'legacy-array' };
    }

    // Fallback: formato programma.
    const programma = parsed?.programma;
    if (Array.isArray(programma)) {
      const converted = convertProgrammaDeltaToItems(programma);
      if (!converted.items) {
        return {
          items: null,
          structuredPlan: null,
          error: converted.error || 'programma non convertibile',
          format: 'programma-delta',
        };
      }
      return {
        items: converted.items,
        structuredPlan: null,
        error: null,
        format: 'programma-delta',
      };
    }

    return {
      items: null,
      structuredPlan: null,
      error: 'JSON root non e un array, ne una scheda con allenamenti, ne un oggetto con campo programma',
      format: 'unknown',
    };
  } catch (error) {
    return {
      items: null,
      structuredPlan: null,
      error: error instanceof Error ? error.message : String(error),
      format: 'invalid-json',
    };
  }
}

function parseItemsArray(raw) {
  const parsed = parseWorkoutResponse(raw);
  return {
    items: parsed.items,
    structuredPlan: parsed.structuredPlan,
    error: parsed.error,
    format: parsed.format,
  };
}

function extractLikelyArrayPayload(raw) {
  const trimmed = (raw || '').trim();
  if (!trimmed) return '';

  // If payload already looks like an object root, keep it as-is so programma parser can handle it.
  if (trimmed.startsWith('{')) {
    return trimmed;
  }

  const start = trimmed.indexOf('[');
  const end = trimmed.lastIndexOf(']');
  if (start >= 0 && end > start) {
    return trimmed.slice(start, end + 1).trim();
  }
  return trimmed;
}

function sanitizeJsonLikePayload(raw) {
  const text = (raw || '').replace(/\u0000/g, '');
  if (!text) return '';

  let out = '';
  let inString = false;
  let escaped = false;

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];

    if (inString) {
      if (ch === '\n' || ch === '\r') {
        out += '\\n';
        escaped = false;
        continue;
      }

      out += ch;
      if (escaped) {
        escaped = false;
        continue;
      }

      if (ch === '\\') {
        escaped = true;
        continue;
      }

      if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
      out += ch;
      continue;
    }

    out += ch;
  }

  return out;
}

function autoCloseTruncatedJsonArray(raw) {
  let out = sanitizeJsonLikePayload((raw || '').trim());
  if (!out) return '';

  const start = out.indexOf('[');
  if (start > 0) {
    out = out.slice(start);
  }
  out = out.trim();

  const stack = [];
  let inString = false;
  let escaped = false;

  for (let i = 0; i < out.length; i += 1) {
    const ch = out[i];

    if (inString) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === '\\') {
        escaped = true;
        continue;
      }
      if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
      continue;
    }

    if (ch === '{' || ch === '[') {
      stack.push(ch);
      continue;
    }

    if (ch === '}' || ch === ']') {
      const top = stack[stack.length - 1];
      if ((ch === '}' && top === '{') || (ch === ']' && top === '[')) {
        stack.pop();
      }
    }
  }

  out = out.replace(/,\s*$/, '');
  while (/:\s*$/.test(out)) {
    out = out.replace(/:\s*$/, '');
    out = out.replace(/,\s*$/, '');
  }

  if (inString) {
    out += '"';
  }

  for (let i = stack.length - 1; i >= 0; i -= 1) {
    out += stack[i] === '{' ? '}' : ']';
  }

  out = out.replace(/,\s*([}\]])/g, '$1');
  return out.trim();
}

function truncateToLastCompleteArrayElement(raw) {
  const text = (raw || '').trim();
  if (!text) return '';

  const start = text.indexOf('[');
  if (start < 0) return '';

  let inString = false;
  let escaped = false;
  let depth = 0;
  let sawArrayStart = false;
  let lastElementEnd = -1;

  for (let i = start; i < text.length; i += 1) {
    const ch = text[i];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
      continue;
    }

    if (ch === '[' || ch === '{') {
      depth += 1;
      if (ch === '[' && !sawArrayStart) {
        sawArrayStart = true;
      }
      continue;
    }

    if (ch === '}' || ch === ']') {
      const depthBefore = depth;
      depth = Math.max(0, depth - 1);

      if (sawArrayStart && ch === '}' && depthBefore === 2 && depth === 1) {
        lastElementEnd = i;
      }

      if (sawArrayStart && ch === ']' && depth === 0) {
        return text.slice(start, i + 1).trim();
      }
    }
  }

  if (lastElementEnd >= 0) {
    const head = text.slice(start, lastElementEnd + 1).trim().replace(/,\s*$/, '');
    return `${head}]`;
  }

  return '';
}

async function repairInvalidJsonArray(apiKey, brokenPayload, sourceType = 'documento') {
  const limitedInput = (brokenPayload || '').slice(0, 40000);
  const repairPrompt = `Ricevi un JSON malformato estratto da una scheda di allenamento (${sourceType}).
Correggilo mantenendo i dati originali il piu possibile.

Regole:
- Rispondi SOLO con JSON valido.
- Non aggiungere testo fuori dal JSON.
- Non inventare campi nuovi non presenti.
- Se una stringa e troncata, chiudila in modo minimale.
- Mantieni il formato originale: se era una scheda con "scheda_id", "nome_scheda" e "allenamenti", conserva quella gerarchia.

INPUT MALFORMATO:
${limitedInput}`;

  const baseRequest = {
    contents: [{ role: 'user', parts: [{ text: repairPrompt }] }],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0,
      maxOutputTokens: 3600,
    },
  };

  try {
    const repairedWithSchema = await callGemini(apiKey, {
      ...baseRequest,
      generationConfig: {
        ...baseRequest.generationConfig,
        responseSchema: WORKOUT_RESPONSE_SCHEMA,
      },
    });
    return extractModelText(repairedWithSchema);
  } catch (schemaError) {
    try {
      const repairedPlain = await callGemini(apiKey, baseRequest);
      return extractModelText(repairedPlain);
    } catch (plainError) {
      throw new Error(
        `schema repair failed: ${formatErrorForDetails(schemaError)} | plain repair failed: ${formatErrorForDetails(plainError)}`,
      );
    }
  }
}

function buildAnalyzePrompt(nomiUfficiali, sourceType = 'documento') {
  return `Sei un coach tecnico specializzato in programmazione forza/ipertrofia.
Analizza questo ${sourceType} e restituisci ESCLUSIVAMENTE JSON formattato con questa gerarchia:

Scheda > Allenamento > Week > Esercizio > Serie

SCHEMA ROOT OBBLIGATORIO:
{
  "scheda_id": "ipertrofia_pro_01",
  "nome_scheda": "Meso di Volume",
  "allenamenti": [
    {
      "id_allenamento": "A",
      "titolo": "Upper Push",
      "weeks": {
        "w1": [ ... ],
        "w2": [ ... ],
        "w3": [ ... ],
        "w4": [ ... ],
        "w5": [ ... ],
        "w14": [ ... ]
      }
    }
  ]
}

SCHEMA ESERCIZIO:
{
  "id_es": "chest_press",
  "status": "active",
  "serie": [
    { "s": 1, "r": "10", "kg": "50", "rest": "90" }
  ]
}

REGOLE ID ESERCIZIO:
- Usa solo "id_es" in snake_case (minuscolo, underscore).
- Deriva "id_es" dal nome esercizio ufficiale piu vicino disponibile.
- Se l'esercizio non esiste in lista, usa una variante standard coerente in snake_case.

LISTA ESERCIZI UFFICIALI:
${JSON.stringify(nomiUfficiali)}

REGOLE WEEK (OBBLIGATORIE):
- Determina il numero settimane N dal documento e crea ESATTAMENTE le week w1..wN (senza saltare week).
- Se N non e esplicitato nel documento, usa default N=14 (w1..w14).
- Ogni week deve avere esercizi con serie esplicite: in ogni oggetto "serie" inserisci sempre almeno "s" e "r".
- Se presenti, aggiungi anche "kg" e "rest".
- Evita week vuote: ogni week deve rappresentare una seduta realmente compilata.
- Se un esercizio viene sostituito, inserisci il nuovo "id_es" (facoltativo: "old_id_es" per chiarire il rimpiazzo).
- Se un esercizio va rimosso in una week, usa: { "id_es": "...", "status": "removed" }.

REGOLE PROGRESSIONE AUTOMATICA:
- Se il PDF NON specifica cambi tra settimane, completa le week fino a N con progressione logica:
  - preferisci +2.5% carico su esercizi con kg numerico
  - altrimenti +1 rep
- Se il documento contiene una tabella progressione, TRASCRIVI i valori week-by-week (serie/ripetizioni/carichi) nelle week corrette.
- Non usare etichette placeholder come "Guarda tabella progressione" se i valori week sono leggibili dal documento.

REGOLE TECNICHE:
- Mantieni output compatto: niente testo superfluo.
- NON inserire schema serie/ripetizioni (es. "4x10", "3 serie") nei campi tecniche/metodo/tag.
- Serie e reps devono stare nei campi strutturati nell'array "serie".
- Non usare markdown, commenti, separatori, backticks o testo fuori dal JSON.
- Restituisci solo JSON valido.`;
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

async function handleAnalyzeDocument(request, env, { payloadField, mimeType, sourceType }) {
  const payload = await request.json();
  const encodedData = payload?.[payloadField];
  const nomiUfficiali = payload?.nomiUfficiali;
  const fastMode = payload?.fastMode === true;
  const debugJsonRead = payload?.debugJsonRead === true;

  const cut = (text, max = 2000) => {
    if (typeof text !== 'string') return '';
    return text.length > max ? `${text.slice(0, max)}...` : text;
  };

  const debug = debugJsonRead
    ? {
        sourceType,
        mimeType,
        fastMode,
        payloadField,
        inputBase64Length: typeof encodedData === 'string' ? encodedData.length : 0,
        parseSteps: [],
      }
    : null;

  if (!encodedData || !Array.isArray(nomiUfficiali)) {
    return json(400, {
      error: 'Payload non valido',
      ...(debug ? { debugJsonRead: debug } : {}),
    });
  }

  const prompt = buildAnalyzePrompt(nomiUfficiali, sourceType);
  const promptWithMode = fastMode
    ? `${prompt}\n\nVINCOLO PRESTAZIONI: privilegia risposta compatta e veloce mantenendo il JSON valido completo.\nVINCOLO COPERTURA: includi tutti gli allenamenti e tutte le settimane necessarie (w1..wN).\nVINCOLO WEEK COMPLETE: per ogni week inserisci serie con s e r esplicite per ogni esercizio.\nVINCOLO COMPATTEZZA: evita campi ridondanti ma non omettere reps/serie delle week.`
    : prompt;

  const requestWithSchema = {
    contents: [
      {
        role: 'user',
        parts: [
          { text: promptWithMode },
          { inline_data: { mime_type: mimeType, data: encodedData } },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: WORKOUT_RESPONSE_SCHEMA,
      temperature: 0,
      maxOutputTokens: fastMode ? 2600 : 6144,
    },
  };

  const requestWithoutSchema = {
    contents: requestWithSchema.contents,
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0,
      maxOutputTokens: fastMode ? 2600 : 6144,
    },
  };

  let geminiResp;
  let schemaFallbackUsed = false;
  try {
    geminiResp = await callGemini(env.GEMINI_API_KEY, requestWithSchema);
  } catch (error) {
    const details = error instanceof HttpError
      ? `${error.message} ${error.details || ''}`.toLowerCase()
      : '';
    const shouldRetryWithoutSchema =
      error instanceof HttpError
      && error.status === 400
      && /(invalid argument|response\s*schema|json\s*schema)/i.test(details);

    if (!shouldRetryWithoutSchema) {
      throw error;
    }

    schemaFallbackUsed = true;
    geminiResp = await callGemini(env.GEMINI_API_KEY, requestWithoutSchema);
  }

  const firstCandidate = geminiResp?.candidates?.[0] || null;
  const finishReasonUpper = String(firstCandidate?.finishReason || '').toUpperCase();
  const raw = extractModelText(geminiResp);
  const jsonPayload = extractJsonPayload(raw);

  if (debug) {
    debug.modelVersion = geminiResp?.modelVersion || null;
    debug.schemaFallbackUsed = schemaFallbackUsed;
    debug.finishReason = firstCandidate?.finishReason || null;
    debug.promptFeedbackBlockReason = geminiResp?.promptFeedback?.blockReason || null;
    debug.rawTextLength = typeof raw === 'string' ? raw.length : 0;
    debug.extractedPayloadLength = typeof jsonPayload === 'string' ? jsonPayload.length : 0;
    debug.rawTextPreview = cut(raw, 3000);
    debug.extractedPayloadPreview = cut(jsonPayload, 3000);
  }

  let parsed = parseItemsArray(jsonPayload);
  if (debug) {
    debug.parseSteps.push({
      step: 'parse-extracted-payload',
      ok: !!parsed.items,
      error: parsed.error || null,
      format: parsed.format || null,
    });
  }

  if (!parsed.items) {
    const likelyArray = extractLikelyArrayPayload(jsonPayload);
    parsed = parseItemsArray(likelyArray);
    if (debug) {
      debug.likelyArrayPreview = cut(likelyArray, 3000);
      debug.parseSteps.push({
        step: 'parse-likely-array-slice',
        ok: !!parsed.items,
        error: parsed.error || null,
        format: parsed.format || null,
      });
    }
  }

  if (!parsed.items) {
    const autoClosed = autoCloseTruncatedJsonArray(jsonPayload);
    parsed = parseItemsArray(autoClosed);
    if (debug) {
      debug.autoClosedPreview = cut(autoClosed, 3000);
      debug.parseSteps.push({
        step: 'parse-auto-closed-payload',
        ok: !!parsed.items,
        error: parsed.error || null,
        format: parsed.format || null,
      });
    }
  }

  if (!parsed.items) {
    const truncated = truncateToLastCompleteArrayElement(jsonPayload);
    parsed = parseItemsArray(truncated);
    if (debug) {
      debug.truncatedPreview = cut(truncated, 3000);
      debug.parseSteps.push({
        step: 'parse-truncated-last-complete-item',
        ok: !!parsed.items,
        error: parsed.error || null,
        format: parsed.format || null,
      });
    }
  }

  if (!parsed.items) {
    try {
      const repairedRaw = await repairInvalidJsonArray(env.GEMINI_API_KEY, jsonPayload, sourceType);
      const repairedPayload = extractJsonPayload(repairedRaw);
      if (debug) {
        debug.repairUsed = true;
        debug.repairedRawPreview = cut(repairedRaw, 3000);
        debug.repairedPayloadPreview = cut(repairedPayload, 3000);
      }
      parsed = parseItemsArray(repairedPayload);
      if (debug) {
        debug.parseSteps.push({
          step: 'parse-repaired-payload',
          ok: !!parsed.items,
          error: parsed.error || null,
          format: parsed.format || null,
        });
      }
      if (!parsed.items) {
        const likelyArray = extractLikelyArrayPayload(repairedPayload);
        parsed = parseItemsArray(likelyArray);
        if (debug) {
          debug.repairedLikelyArrayPreview = cut(likelyArray, 3000);
          debug.parseSteps.push({
            step: 'parse-repaired-likely-array-slice',
            ok: !!parsed.items,
            error: parsed.error || null,
            format: parsed.format || null,
          });
        }
      }
    } catch (repairError) {
      return json(422, {
        error: 'Risposta AI non valida',
        details: `Impossibile riparare il JSON AI: ${formatErrorForDetails(repairError)}`,
        ...(debug ? { debugJsonRead: debug } : {}),
      });
    }
  }

  if (!parsed.items) {
    return json(422, {
      error: 'Risposta AI non valida',
      details: `JSON malformato dal modello: ${parsed.error || 'errore non specificato'}`,
      ...(debug ? { debugJsonRead: debug } : {}),
    });
  }

  const likelyCutByModel = finishReasonUpper.includes('MAX_TOKENS');

  if (sourceType === 'PDF' && likelyCutByModel) {
    if (debug) {
      debug.truncatedGuardTriggered = true;
    }
    return json(422, {
      error: 'Risposta AI troncata',
      details: `Output potenzialmente incompleto (${firstCandidate?.finishReason}). Possibile perdita di week/sedute.`,
      ...(debug ? { debugJsonRead: debug } : {}),
    });
  }

  if (debug) {
    debug.parsedFormat = parsed.format || null;
    debug.itemCount = parsed.items.length;
    const first = parsed.items[0];
    if (first && typeof first === 'object') {
      const firstExercise = Array.isArray(first.esercizi) && first.esercizi.length > 0
        ? first.esercizi[0]
        : null;
      debug.firstItemSummary = {
        nome: first.nome || null,
        categoria: first.categoria || null,
        settimanaCorrente: first.settimanaCorrente || null,
        firstExercise: firstExercise
          ? {
              nome: firstExercise.nome || null,
              workingSet: firstExercise.workingSet || null,
              ripetizioni: firstExercise.ripetizioni || null,
            }
          : null,
      };
    }
  }

  return json(200, {
    items: parsed.items,
    ...(parsed.structuredPlan ? { structuredPlan: parsed.structuredPlan } : {}),
    ...(debug ? { debugJsonRead: debug } : {}),
  });
}

async function handleAnalyzePhoto(request, env) {
  return handleAnalyzeDocument(request, env, {
    payloadField: 'imageBase64',
    mimeType: 'image/jpeg',
    sourceType: 'immagine',
  });
}

async function handleAnalyzePdf(request, env) {
  return handleAnalyzeDocument(request, env, {
    payloadField: 'pdfBase64',
    mimeType: 'application/pdf',
    sourceType: 'PDF',
  });
}

async function handleReview(request, env) {
  const payload = await request.json();
  const nomeCartella = payload?.nomeCartella;
  const schede = payload?.schede;

  if (!nomeCartella || !Array.isArray(schede)) {
    return json(400, { error: 'Payload non valido' });
  }

  const geminiResp = await callGemini(env.GEMINI_API_KEY, {
    contents: [{ role: 'user', parts: [{ text: buildReviewPrompt(nomeCartella, schede) }] }],
  });

  const text = extractModelText(geminiResp).trim();
  if (!text) {
    return json(502, { error: 'Risposta AI vuota' });
  }
  return json(200, { text });
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== 'POST') {
      return json(405, { error: 'Method not allowed' });
    }

    try {
      const projectId = env.FIREBASE_PROJECT_ID;
      if (!projectId) {
        return json(500, { error: 'FIREBASE_PROJECT_ID non configurato' });
      }

      if (!env.GEMINI_API_KEY) {
        return json(500, { error: 'GEMINI_API_KEY non configurata' });
      }

      await verifyFirebaseIdToken(request, projectId);

      const url = new URL(request.url);
      const normalizedPath = url.pathname.replace(/\/+$/, '').toLowerCase();

      const inferEndpointFromPayload = async () => {
        try {
          const body = await request.clone().json();
          if (body && typeof body === 'object') {
            if (typeof body.pdfBase64 === 'string' && body.pdfBase64.trim().length > 0) {
              return 'pdf';
            }
            if (typeof body.imageBase64 === 'string' && body.imageBase64.trim().length > 0) {
              return 'photo';
            }
            if (Array.isArray(body.schede) && typeof body.nomeCartella === 'string') {
              return 'review';
            }
          }
        } catch (_) {
          // Ignore parse errors for endpoint inference.
        }
        return null;
      };

      if (normalizedPath.endsWith('/analyzeworkoutphoto')) {
        return await handleAnalyzePhoto(request, env);
      }

      if (normalizedPath.endsWith('/analyzeworkoutpdf')) {
        return await handleAnalyzePdf(request, env);
      }

      if (normalizedPath.endsWith('/reviewworkoutfolder')) {
        return await handleReview(request, env);
      }

      // Fallback routing: if path is missing/mutated, infer the intended endpoint
      // from payload shape to keep mobile clients resilient.
      const inferredEndpoint = await inferEndpointFromPayload();
      if (inferredEndpoint === 'pdf') {
        return await handleAnalyzePdf(request, env);
      }
      if (inferredEndpoint === 'photo') {
        return await handleAnalyzePhoto(request, env);
      }
      if (inferredEndpoint === 'review') {
        return await handleReview(request, env);
      }

      return json(404, {
        error: 'Endpoint non trovato',
        details: `path=${url.pathname}`,
      });
    } catch (error) {
      if (error instanceof AuthError) {
        return json(401, { error: error.message });
      }
      if (error instanceof HttpError) {
        return json(error.status, { error: error.message, details: error.details });
      }

      return json(500, { error: `Errore interno proxy AI: ${error.message}` });
    }
  },
};
