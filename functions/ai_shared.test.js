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
  const res = await ai.analyzeWorkoutPhoto('k', { imageBase64: 'x' }, { fetchImpl });
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
