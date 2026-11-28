// Esegui con: node --test functions/
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const ai = require('./ai_shared');

function fakeFetch(responses) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, body: JSON.parse(init.body) });
    const r = responses.shift();
    return { ok: r.status >= 200 && r.status < 300, status: r.status, text: async () => r.text };
  };
  return { fetchImpl, calls };
}

const gemini = (text) => JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] });

test('analyze: restituisce gli items e usa il prompt con la lista esercizi', async () => {
  const { fetchImpl, calls } = fakeFetch([{ status: 200, text: gemini('[{"nome":"A","esercizi":[]}]') }]);
  const res = await ai.analyzeWorkoutPhoto('k', { imageBase64: 'x', nomiUfficiali: ['Squat'] }, { fetchImpl });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.items, [{ nome: 'A', esercizi: [] }]);
  const prompt = calls[0].body.contents[0].parts[0].text;
  assert.match(prompt, /"Squat"/);
  assert.match(prompt, /BIG 3/);
});

test('analyze: accetta JSON dentro recinti markdown', async () => {
  const { fetchImpl } = fakeFetch([{ status: 200, text: gemini('```json\n[{"nome":"B"}]\n```') }]);
  const res = await ai.analyzeWorkoutPhoto('k', { imageBase64: 'x', nomiUfficiali: [] }, { fetchImpl });
  assert.deepEqual(res.body.items, [{ nome: 'B' }]);
});

test('analyze: risposta non JSON diventa 422', async () => {
  const { fetchImpl } = fakeFetch([{ status: 200, text: gemini('non so') }]);
  const res = await ai.analyzeWorkoutPhoto('k', { imageBase64: 'x', nomiUfficiali: [] }, { fetchImpl });
  assert.equal(res.status, 422);
});

test('analyze: payload non valido diventa 400 senza chiamare Gemini', async () => {
  const { fetchImpl, calls } = fakeFetch([]);
  const res = await ai.analyzeWorkoutPhoto('k', { nomiUfficiali: [] }, { fetchImpl });
  assert.equal(res.status, 400);
  assert.equal(calls.length, 0);
});

test('callGemini: passa al modello successivo se il primo non esiste', async () => {
  const { fetchImpl, calls } = fakeFetch([
    { status: 404, text: 'not found' },
    { status: 200, text: gemini('ok') },
  ]);
  const res = await ai.reviewWorkoutFolder('k', { nomeCartella: 'C', schede: [] }, { fetchImpl });
  assert.equal(res.body.text, 'ok');
  assert.equal(calls.length, 2);
});

test('callGemini: 429 non fa fallback e conserva lo status', async () => {
  const { fetchImpl, calls } = fakeFetch([{ status: 429, text: 'quota' }]);
  await assert.rejects(
    ai.reviewWorkoutFolder('k', { nomeCartella: 'C', schede: [] }, { fetchImpl }),
    (e) => e instanceof ai.HttpError && e.status === 429,
  );
  assert.equal(calls.length, 1);
});

// --- import da file: PDF, immagini, testo (Word) ---

function partiInviate(calls) {
  return calls[0].body.contents[0].parts;
}

test('analyze: PDF inviato con il suo mime type', async () => {
  const { fetchImpl, calls } = fakeFetch([{ status: 200, text: gemini('[{"nome":"GG1"}]') }]);
  const res = await ai.analyzeWorkoutPhoto('k', { fileBase64: 'x', mimeType: 'application/pdf', nomiUfficiali: [] }, { fetchImpl });
  assert.equal(res.status, 200);
  const file = partiInviate(calls).find((p) => p.inline_data);
  assert.equal(file.inline_data.mime_type, 'application/pdf');
});

test('analyze: testo del Word inviato come testo, senza file', async () => {
  const { fetchImpl, calls } = fakeFetch([{ status: 200, text: gemini('[{"nome":"GG1"}]') }]);
  await ai.analyzeWorkoutPhoto('k', { testo: 'GG1\tPanca\t3x8', nomiUfficiali: [] }, { fetchImpl });
  const parti = partiInviate(calls);
  assert.equal(parti.some((p) => p.inline_data), false);
  assert.ok(parti.some((p) => (p.text || '').includes('GG1\tPanca\t3x8')));
});

test('analyze: vecchio formato imageBase64 resta jpeg', async () => {
  const { fetchImpl, calls } = fakeFetch([{ status: 200, text: gemini('[]') }]);
  await ai.analyzeWorkoutPhoto('k', { imageBase64: 'x', nomiUfficiali: [] }, { fetchImpl });
  assert.equal(partiInviate(calls).find((p) => p.inline_data).inline_data.mime_type, 'image/jpeg');
});

test('analyze: mime type non supportato -> 400 senza chiamare Gemini', async () => {
  const { fetchImpl, calls } = fakeFetch([]);
  const res = await ai.analyzeWorkoutPhoto('k', { fileBase64: 'x', mimeType: 'application/zip', nomiUfficiali: [] }, { fetchImpl });
  assert.equal(res.status, 400);
  assert.equal(calls.length, 0);
});

test('analyze: il prompt chiede programma e progressione senza inventare', () => {
  const p = ai.buildAnalyzePrompt([]);
  assert.match(p, /"programma"/);
  assert.match(p, /"progressione"/);
  assert.match(p, /non inventare/i);
});

test('analyze: il prompt chiede settimane numerate, calendario, durata e ripartenza', () => {
  const p = ai.buildAnalyzePrompt([]);
  assert.match(p, /1, 2, 3/);
  assert.match(p, /alternan/i);
  assert.match(p, /"calendario"/);
  assert.match(p, /"rirDelta"/);
  assert.match(p, /"scarico"/);
  assert.match(p, /"durataSettimane"/);
  assert.match(p, /"ripartiDaSettimana"/);
  assert.doesNotMatch(p, /cicloSettimane/);
  assert.doesNotMatch(p, /"4": \[/);
});

test('callGemini: il primo tentativo usa v1beta (la modalità JSON non esiste su v1)', async () => {
  const { fetchImpl, calls } = fakeFetch([{ status: 200, text: gemini('[]') }]);
  await ai.analyzeWorkoutPhoto('k', { fileBase64: 'x', mimeType: 'application/pdf', nomiUfficiali: [] }, { fetchImpl });
  assert.match(calls[0].url, /\/v1beta\//);
});

test('callGemini: "JSON mode is not enabled for api version" passa all endpoint successivo', async () => {
  const { fetchImpl, calls } = fakeFetch([
    { status: 400, text: '{"error":{"message":"JSON mode is not enabled for api version v1. Use api version v1beta instead."}}' },
    { status: 200, text: gemini('ok') },
  ]);
  const res = await ai.reviewWorkoutFolder('k', { nomeCartella: 'C', schede: [] }, {
    fetchImpl,
    endpoints: ['https://x/v1/models/a:generateContent', 'https://x/v1beta/models/a:generateContent'],
  });
  assert.equal(res.body.text, 'ok');
  assert.equal(calls.length, 2);
});

test('analyze: ragionamento di Gemini spento (estrazione, deve essere veloce)', async () => {
  const { fetchImpl, calls } = fakeFetch([{ status: 200, text: gemini('[]') }]);
  await ai.analyzeWorkoutPhoto('k', { fileBase64: 'x', mimeType: 'application/pdf', nomiUfficiali: [] }, { fetchImpl });
  assert.equal(calls[0].body.generationConfig.thinkingConfig.thinkingBudget, 0);
  assert.equal(calls[0].body.generationConfig.responseMimeType, 'application/json');
});

test('analyze: prompt su nomi (nomeOriginale, niente forzature), cicli e settimane complete', () => {
  const p = ai.buildAnalyzePrompt([]);
  assert.match(p, /"nomeOriginale"/);
  assert.match(ai.buildAnalyzePrompt(['Squat']), /stesso movimento/i);
  assert.match(p, /prima settimana di quel ciclo/i);
  assert.match(p, /lista completa/i);
});

test('analyze: tecniche negli esercizi, filtro per settimana nel calendario', () => {
  const p = ai.buildAnalyzePrompt([]);
  assert.match(p, /"tecniche": \[\]/);
  assert.match(p, /"tecniche": \["LP"\]/);
  assert.match(p, /solo per l'esercizio sotto cui è scritta/i);
  assert.match(p, /per braccio/i);
});

test('analyze: la categoria è il titolo del programma', () => {
  const p = ai.buildAnalyzePrompt([]);
  assert.match(p, /titolo del programma/i);
  assert.doesNotMatch(p, /"categoria": "Importata AI"/);
});

// --- abbinamento nomi in un secondo passaggio ---

test('analyze: senza lista di nomi funziona e il prompt chiede il nome del documento', async () => {
  const { fetchImpl, calls } = fakeFetch([{ status: 200, text: gemini('[{"nome":"GG1"}]') }]);
  const res = await ai.analyzeWorkoutPhoto('k', { fileBase64: 'x', mimeType: 'application/pdf' }, { fetchImpl });
  assert.equal(res.status, 200);
  const prompt = calls[0].body.contents[0].parts[0].text;
  assert.doesNotMatch(prompt, /LISTA ESERCIZI UFFICIALI/);
  assert.match(prompt, /come scritto nel documento/i);
});

test('match: sceglie fra i candidati, scarta nomi non in lista', async () => {
  const risposta = JSON.stringify([
    { originale: 'Spinte con manubri su panca piana', scelto: 'Panca piana con manubri' },
    { originale: 'Croci ai cavi dal basso', scelto: 'Nome inventato' },
    { originale: 'Rematore con appoggio al petto', scelto: null },
  ]);
  const { fetchImpl, calls } = fakeFetch([{ status: 200, text: gemini(risposta) }]);
  const res = await ai.matchExerciseNames('k', {
    esercizi: [
      { originale: 'Spinte con manubri su panca piana', candidati: ['Panca piana con manubri', 'Spinte Alternate con Manubri in Piedi'] },
      { originale: 'Croci ai cavi dal basso', candidati: ['Croci ai Cavi Alti'] },
      { originale: 'Rematore con appoggio al petto', candidati: ['Rematore con Bilanciere'] },
    ],
  }, { fetchImpl });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.scelte, [
    { originale: 'Spinte con manubri su panca piana', scelto: 'Panca piana con manubri' },
    { originale: 'Croci ai cavi dal basso', scelto: null },
    { originale: 'Rematore con appoggio al petto', scelto: null },
  ]);
  const prompt = calls[0].body.contents[0].parts[0].text;
  assert.match(prompt, /stesso movimento/i);
  assert.match(prompt, /Spinte Alternate con Manubri in Piedi/);
  assert.equal(calls[0].body.generationConfig.responseMimeType, 'application/json');
});

test('match: payload non valido -> 400', async () => {
  const { fetchImpl, calls } = fakeFetch([]);
  const res = await ai.matchExerciseNames('k', { esercizi: 'boh' }, { fetchImpl });
  assert.equal(res.status, 400);
  assert.equal(calls.length, 0);
});

test('analyze: LP (parziali in allungamento) è tra le tecniche', () => {
  const p = ai.buildAnalyzePrompt([]);
  assert.match(p, /LP \(parziali in allungamento\)/);
  assert.match(p, /Ultima serie: LP/);
});
