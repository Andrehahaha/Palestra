# Tiger

Flutter app per gestione allenamenti.

## Setup Sicurezza (Store)

### 1) Chiavi runtime con dart-define
Non usare `.env` in produzione. Passa le chiavi in build-time:

- `GEMINI_API_KEY`
- `FIREBASE_KEY_ANDROID`
- `FIREBASE_KEY_IOS`
- `FIREBASE_KEY_WEB`

Esempio Android release:

```bash
flutter build appbundle \
	--dart-define=GEMINI_API_KEY=... \
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
