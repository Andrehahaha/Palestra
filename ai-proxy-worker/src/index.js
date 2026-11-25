import { jwtVerify, importX509 } from 'jose';
// Prompt, chiamata a Gemini e parsing condivisi con Firebase Functions.
import ai from '../../functions/ai_shared.js';

const { HttpError } = ai;

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

class AuthError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AuthError';
  }
}

async function getFirebaseSigningKey(kid) {
  const certsResp = await fetch(FIREBASE_CERTS_URL);
  if (!certsResp.ok) {
    throw new HttpError(502, `Failed to load Firebase certs: ${certsResp.status}`);
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

async function handleAnalyze(request, env) {
  const { status, body } = await ai.analyzeWorkoutPhoto(env.GEMINI_API_KEY, await request.json());
  return json(status, body);
}

async function handleReview(request, env) {
  const { status, body } = await ai.reviewWorkoutFolder(env.GEMINI_API_KEY, await request.json());
  return json(status, body);
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

      try {
        await verifyFirebaseIdToken(request, projectId);
      } catch (error) {
        // Token scaduto, firma non valida, kid sconosciuto: sempre 401, non 500.
        if (error instanceof AuthError || error instanceof HttpError) throw error;
        throw new AuthError(`Invalid Firebase token: ${error.message}`);
      }

      const url = new URL(request.url);
      if (url.pathname.endsWith('/analyzeWorkoutPhoto')) {
        return await handleAnalyze(request, env);
      }

      if (url.pathname.endsWith('/reviewWorkoutFolder')) {
        return await handleReview(request, env);
      }

      return json(404, { error: 'Endpoint non trovato' });
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
