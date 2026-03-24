# Tiger

Flutter app per gestione allenamenti.

## Setup Sicurezza (Store)

### 1) Chiavi runtime con dart-define
Non usare `.env` in produzione. Passa le chiavi in build-time:

- `FIREBASE_KEY_ANDROID`
- `FIREBASE_KEY_IOS`
- `FIREBASE_KEY_WEB`
- `AI_PROXY_BASE_URL`

`GEMINI_API_KEY` non deve stare nel client: va impostata solo su Firebase Functions come secret.

Esempio Android release:

```bash
flutter build appbundle \
	--dart-define=AI_PROXY_BASE_URL=https://europe-west1-<project-id>.cloudfunctions.net \
	--dart-define=FIREBASE_KEY_ANDROID=... \
	--dart-define=FIREBASE_KEY_IOS=... \
	--dart-define=FIREBASE_KEY_WEB=...
```

### 1.1) Deploy Proxy AI su Firebase Functions

> Nota: questo percorso richiede piano Blaze.

```bash
cd functions
npm install
cd ..
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions
```

Endpoint usati dall'app:

- `POST {AI_PROXY_BASE_URL}/analyzeWorkoutPhoto`
- `POST {AI_PROXY_BASE_URL}/reviewWorkoutFolder`

### 1.2) Alternativa Gratis: Cloudflare Workers

Se non vuoi usare Blaze, puoi usare il proxy gratis su Cloudflare.

```bash
cd ai-proxy-worker
npm install
npx wrangler login
npx wrangler secret put GEMINI_API_KEY
npx wrangler deploy
```

Dopo il deploy ottieni un URL tipo:

`https://tiger-ai-proxy.<account>.workers.dev`

Passalo all'app in build:

```bash
flutter build apk \
	--dart-define=AI_PROXY_BASE_URL=https://tiger-ai-proxy.<account>.workers.dev \
	--dart-define=FIREBASE_KEY_ANDROID=... \
	--dart-define=FIREBASE_KEY_IOS=... \
	--dart-define=FIREBASE_KEY_WEB=...
```

### 2) Firma release Android

1. Crea il keystore di release.
2. Copia `android/key.properties.example` in `android/key.properties`.
3. Compila i campi:
	 - `storeFile`
	 - `storePassword`
	 - `keyAlias`
	 - `keyPassword`

Nota: se `android/key.properties` non esiste, la build usa fallback debug solo per test locale.

### 3) Regole Firebase

Sono presenti file locali:

- `firestore.rules`
- `storage.rules`

Deploy regole:

```bash
firebase deploy --only firestore:rules,storage
```

## Checklist Pre-Pubblicazione

- Nessun segreto in assets o repository.
- Build release firmata con keystore di produzione.
- Privacy policy aggiornata (uso AI / upload immagini).
- Test release Android/iOS su device reale.

## Sync Progressi Atleti (Gratis su Spark)

Per evitare Blaze puoi sincronizzare i progressi senza Storage e senza Functions,
usando solo Firestore + Auth.

Schema consigliato:

- `coaches/{coachId}/athletes/{athleteId}`
- `coaches/{coachId}/athletes/{athleteId}/progress/{yyyyMMdd}`
- `coaches/{coachId}/athletes/{athleteId}/stats/current`

Nel progetto trovi il servizio pronto:

- `lib/services/athlete_progress_service.dart`

Uso rapido (Dart):

```dart
final service = AthleteProgressService();

await service.saveProgressEntry(
	coachId: coachId,
	athleteId: athleteId,
	payload: {
		'pesoKg': 78.4,
		'note': 'Sessione completata',
		'workoutDone': true,
	},
);

final page1 = await service.getRecentProgress(
	coachId: coachId,
	athleteId: athleteId,
	limit: 30,
);
```

Deploy regole Firestore:

```bash
firebase deploy --only firestore:rules --project palestrai-5856f
```
