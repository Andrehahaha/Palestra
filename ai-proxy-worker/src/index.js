import { jwtVerify, importX509 } from 'jose';

const GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
const FIREBASE_CERTS_URL = 'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

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
    throw new Error('Missing bearer token');
  }

  const token = authHeader.slice('Bearer '.length);
  const header = decodeJwtHeader(token);
  const kid = header.kid;
  if (!kid) {
    throw new Error('JWT kid missing');
  }

  const key = await getFirebaseSigningKey(kid);

  const { payload } = await jwtVerify(token, key, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });

  if (!payload.sub) {
    throw new Error('Invalid Firebase token subject');
  }

  return payload;
}

async function callGemini(apiKey, requestBody) {
  const resp = await fetch(GEMINI_ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    },
    body: JSON.stringify(requestBody),
  });

  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`Gemini error ${resp.status}: ${text}`);
  }

  return JSON.parse(text);
}

function extractModelText(geminiResp) {
  const parts = geminiResp?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return '';
  return parts.map((p) => p?.text || '').join('');
}

function buildAnalyzePrompt(nomiUfficiali) {
  return `Sei un personal trainer esperto in protocolli di forza e bodybuilding. Analizza questa immagine che contiene una scheda di allenamento.

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

STRUTTURA JSON:
[
  {
    "nome": "Nome Scheda - Giorno 1",
    "livello": "Intermedio",
    "categoria": "Importata AI",
    "esercizi": [
      {
        "nome": "NOME PRESO DALLA LISTA UFFICIALE",
        "avvicinamento": 0,
        "workingSet": 3,
        "ripetizioni": "8-10",
        "recupero": "90",
        "rpe": "8",
        "note": "eventuali note",
        "metodo": "Classico",
        "tecniche": ["Classico"]
      }
    ]
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

async function handleAnalyze(request, env) {
  const payload = await request.json();
  const imageBase64 = payload?.imageBase64;
  const nomiUfficiali = payload?.nomiUfficiali;

  if (!imageBase64 || !Array.isArray(nomiUfficiali)) {
    return json(400, { error: 'Payload non valido' });
  }

  const geminiResp = await callGemini(env.GEMINI_API_KEY, {
    contents: [
      {
        role: 'user',
        parts: [
          { text: buildAnalyzePrompt(nomiUfficiali) },
          { inline_data: { mime_type: 'image/jpeg', data: imageBase64 } },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
    },
  });

  const raw = extractModelText(geminiResp);
  const items = JSON.parse(raw);
  if (!Array.isArray(items)) {
    return json(422, { error: 'Risposta AI non valida' });
  }

  return json(200, { items });
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
      if (url.pathname.endsWith('/analyzeWorkoutPhoto')) {
        return await handleAnalyze(request, env);
      }

      if (url.pathname.endsWith('/reviewWorkoutFolder')) {
        return await handleReview(request, env);
      }

      return json(404, { error: 'Endpoint non trovato' });
    } catch (error) {
      return json(401, { error: `Unauthorized: ${error.message}` });
    }
  },
};
