# Diario di lavoro — Tiger

Note brevi su cosa ho cambiato e perché.

## 25–26 novembre 2026 — Riordino del codice

Partito dai file che cambiavo più spesso. Ogni modifica andava ripetuta in
più posti, quindi prima di aggiungere funzioni ho riordinato.

- **Carichi %1RM.** La logica Big 3 / PR / percentuali era copiata in sei
  schermate, con valori diversi. Ora sta in `lib/services/carichi.dart`.
- **Stato dell'atleta.** Più schermate scrivevano pezzi di `app_state` su
  Firestore per conto loro, e solo una aggiornava il timestamp locale: al
  riavvio il cloud poteva sovrascrivere le modifiche offline. Ora carica e
  salva tutto `ArchivioAtleta`. Tolto anche l'invio al cloud dei "PR" ricavati
  dalla serie più pesante, che venivano usati come massimale.
- **Allenamenti completati.** Ogni sessione scriveva due documenti e perdeva
  le note. Ora un documento solo, con id fisso, che contiene anche il formato
  letto dalla dashboard del coach.
- **Dolore e stretching.** Logica spostata fuori dalle schermate per poterla
  testare.
- **Proxy AI.** I due backend avevano prompt diversi. Ora condividono
  `functions/ai_shared.js`.
- **workouts_screen.** Riunito in un file; export PDF in `pdf_schede.dart`.
  Corretto il duplicato di scheda che condivideva le settimane con
  l'originale.
- **Chiavi Firebase.** Erano nella storia del repo: ruotate e ora passate con
  `--dart-define-from-file`.

## 26 novembre 2026 — Import da file

**Problema.** Le schede arrivano in PDF, foto o Word e sono programmazioni:
lo stesso giorno cambia nelle settimane (es. panca 3 serie in settimana 1, 6
in settimana 4, 3 con stripping in settimana 10), spesso con una regola di
progressione scritta. L'import leggeva solo una foto e solo la prima
settimana.

**Ragionamento.**
- Un solo "Importa da file". Foto e PDF vanno al proxy così come sono; il
  testo del Word lo estraggo nell'app, perché Gemini non legge i `.docx` e
  non volevo duplicare la conversione nei due backend.
- L'AI legge, l'app calcola: l'AI restituisce le settimane scritte e la
  regola (+kg, +%, RIR, intervallo, testo originale). I numeri li fa la
  logica di progressione che c'era già.
- Il piano sta dentro la scheda (`programma`), così arriva all'atleta quando
  il coach la invia, senza altro lavoro.
- Passando alla settimana dopo: settimana già salvata dall'atleta, poi
  settimana del piano, poi progressione precompilata se c'è una regola,
  altrimenti uguale alla precedente. Schede fatte a mano invariate.
- L'import dalla galleria usa ancora la vecchia richiesta, così funziona
  anche prima di ridistribuire il proxy.

**Fatto.**
1. `programma` sulla scheda e `progressione` sull'esercizio.
2. `ProgrammaSettimane`: decide cosa succede alla settimana dopo.
3. Dettaglio scheda collegato; progressione precompilata con il testo del
   coach.
4. Lettura del testo dai `.docx` (tabelle come righe separate da tab).
5. Proxy: accetta PDF, immagini e testo; prompt per settimane e regole.
6. `AiService.analizzaFile` con limite di 15 MB e controllo del formato.
7. Pulsante "Importa da file" per atleta e coach; il coach invia tutti i
   giorni; la modifica di una scheda non perde più id e piano.

**Correzione: cicli e schede alternate.** La durata del ciclo non è fissa
(2, 3, 4 settimane...) e spesso le schede A e B si alternano. Ora un giorno
alternato è W1 = A, W2 = B con la lunghezza del ciclo, e l'app lo ripete.
Le settimane vanno numerate 1, 2, 3; all'import controllo comunque: dalle
etichette tengo il numero, se manca la W1 la prima settimana diventa la W1,
e il ciclo lo tengo solo se ha senso.

**Da tenere d'occhio.**
- Va ridistribuito il proxy (Worker e Functions) per usare PDF e Word.
- Una regola del coach non si può ancora togliere dall'app.
