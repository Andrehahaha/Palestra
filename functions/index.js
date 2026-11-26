const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const ai = require('./ai_shared');

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
  try {
    return await admin.auth().verifyIdToken(token);
  } catch (_) {
    return null;
  }
}

// Adapter Firebase: auth + HTTP. Prompt e chiamata a Gemini sono in ai_shared.js.
function endpoint(name, handler) {
  return onRequest(
    { region: 'europe-west1', secrets: [GEMINI_API_KEY], cors: true, maxInstances: 10 },
    async (req, res) => {
      if (req.method !== 'POST') {
        return jsonResponse(res, 405, { error: 'Method not allowed' });
      }
      try {
        const user = await verifyAuth(req);
        if (!user) return jsonResponse(res, 401, { error: 'Unauthorized' });

        const { status, body } = await handler(GEMINI_API_KEY.value(), req.body);
        return jsonResponse(res, status, body);
      } catch (error) {
        console.error(`${name} error`, error);
        if (error instanceof ai.HttpError) {
          return jsonResponse(res, error.status, { error: error.message });
        }
        return jsonResponse(res, 500, { error: 'Errore interno AI' });
      }
    }
  );
}

exports.analyzeWorkoutPhoto = endpoint('analyzeWorkoutPhoto', ai.analyzeWorkoutPhoto);
exports.reviewWorkoutFolder = endpoint('reviewWorkoutFolder', ai.reviewWorkoutFolder);
exports.matchExerciseNames = endpoint('matchExerciseNames', ai.matchExerciseNames);
