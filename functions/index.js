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

async function callGemini(apiKey, body) {
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Gemini ${response.status}: ${text}`);
  }
  return JSON.parse(text);
}

function extractModelText(geminiResp) {
  const parts = geminiResp?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return '';
  return parts.map((p) => p?.text || '').join('');
}

exports.analyzeWorkoutPhoto = onRequest(
  { region: 'europe-west1', secrets: [GEMINI_API_KEY], cors: true, maxInstances: 10 },
  async (req, res) => {
    if (req.method !== 'POST') {
      return jsonResponse(res, 405, { error: 'Method not allowed' });
    }

    try {
      const user = await verifyAuth(req);
      if (!user) return jsonResponse(res, 401, { error: 'Unauthorized' });

      const imageBase64 = req.body?.imageBase64;
      const nomiUfficiali = req.body?.nomiUfficiali;
      if (!imageBase64 || !Array.isArray(nomiUfficiali)) {
        return jsonResponse(res, 400, { error: 'Payload non valido' });
      }

      const prompt = `Sei un personal trainer esperto in protocolli di forza e bodybuilding. Analizza questa immagine che contiene una scheda di allenamento.

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

      const geminiResp = await callGemini(GEMINI_API_KEY.value(), {
        contents: [
          {
            role: 'user',
            parts: [
              { text: prompt },
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
        return jsonResponse(res, 422, { error: 'Risposta AI non valida' });
      }

      return jsonResponse(res, 200, { items });
    } catch (error) {
      console.error('analyzeWorkoutPhoto error', error);
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
      return jsonResponse(res, 200, { text });
    } catch (error) {
      console.error('reviewWorkoutFolder error', error);
      return jsonResponse(res, 500, { error: 'Errore interno AI' });
    }
  }
);
