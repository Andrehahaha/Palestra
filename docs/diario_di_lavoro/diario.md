# Diario di lavoro — Tiger

Appunti su cosa ho cambiato, perché, e cosa avevo in testa mentre lo facevo.

---

## 25–26 novembre 2026 — Rimettere ordine

Sono ripartito guardando quali file cambiavo più spesso: `main.dart`,
`ai_service.dart`, `dettaglio_scheda_screen.dart`, i quattro pezzi di
`workouts_screen`, PR mode, profilo, dolore. Ogni volta che toccavo una cosa
dovevo ricordarmi di sistemarla in altri tre posti. Ho deciso di fermarmi e
sistemare la struttura prima di aggiungere altro.

### Le regole dei carichi erano copiate sei volte

Riconoscere panca, squat e stacco, trovare il PR giusto e calcolare i kg in
percentuale: lo facevano workouts, dettaglio scheda, PR mode, home, ai_service
e la schermata della settimana successiva. Ognuno a modo suo. La tolleranza
per capire se un peso era "calcolato in automatico" era 0.26 in un posto e
0.11 in un altro, Home aveva la sua lista di alias.

Ho messo tutto in `lib/services/carichi.dart` e ho scritto i test prima di
spostare il codice. Adesso se cambio una regola la cambio una volta.

### Le schede sparivano dopo aver cambiato la zona del dolore

Questo era il bug più fastidioso. Cambiando la zona del dolore, al riavvio
perdevo le modifiche fatte offline. Il motivo: sei schermate scrivevano pezzi
di `app_state` su Firestore da sole, ognuna con un nuovo `updated_at`, ma solo
Workouts aggiornava il timestamp sul telefono. Al caricamento il cloud
sembrava più nuovo e sovrascriveva tutto.

Soluzione: un unico `ArchivioAtleta` che carica e salva lo stato intero, e a
ogni salvataggio aggiorna anche il timestamp locale. Firestore sta dietro
un'interfaccia, così nei test uso un cloud finto e il bug ha il suo test.

Già che c'ero ho tolto una cosa sbagliata: Home mandava nel cloud come PR la
serie più pesante a qualsiasi numero di ripetizioni, e le altre schermate la
usavano come massimale.

### Un allenamento scriveva due documenti

Finendo un allenamento finivano in `storico_atleti` due documenti: uno
completo e uno ridotto. Poi lo storico locale veniva sovrascritto e le note si
perdevano. Prima di togliere quello ridotto ho controllato a cosa servisse: è
quello che legge la dashboard del coach. Quindi ora c'è un solo documento che
contiene tutte e due le forme, con un id fisso per sessione. Due allenamenti
nello stesso giorno non si fondono più nel progress del coach.

### Dolore e stretching

Il punteggio del mini-test sul dolore e la scelta degli stretching erano
dentro le schermate e non potevo testarli. Li ho spostati in
`valutazione_dolore.dart` e `stretching_scheda.dart`.

### Due backend AI con due prompt diversi

Ho il proxy sia su Firebase Functions sia su Cloudflare Worker. I due prompt
si erano già separati: quello delle Functions non conosceva Big 3 e %1RM. Ho
messo prompt, chiamata a Gemini e lettura della risposta in
`functions/ai_shared.js`, usato da tutti e due. Nell'app `AiService` ora riceve
il collegamento al proxy dall'esterno e ogni chiamata restituisce o il
risultato o un messaggio d'errore leggibile.

### workouts_screen di nuovo in un file

Lo avevo diviso in quattro file, ma era solo codice spostato. Ora che i dati
stanno altrove l'ho riunito e ho tolto l'export PDF in `pdf_schede.dart`.
Bug trovato per strada: duplicando una scheda la copia condivideva lo storico
settimane con l'originale.

### Chiavi Firebase

Ho scoperto che le chiavi API erano finite nella storia del repo su GitHub in
due vecchi commit. Le ho ruotate dalla Google Cloud Console e ora le passo con
`--dart-define-from-file=dart_defines.json`, che non entra nel repo.

---

## 26 novembre 2026 — Importare le schede da file

### Il problema

I coach mi mandano le schede in PDF, in foto o in Word. L'app sapeva leggere
solo una foto presa dalla galleria e ne tirava fuori una scheda "base". Ma le
schede vere sono programmazioni: GG1 alla settimana 1 ha 3 serie di panca,
alla settimana 4 ne ha 6, alla 10 torna a 3 ma con stripping. E spesso da
qualche parte c'è scritto come progredire (+2,5 kg a settimana, +5%, RIR).
Se importo solo la prima settimana, tutto il resto lo devo ricostruire a mano.

### Cosa voglio

- Importare da PDF, immagine (jpg, png, heic) o Word (.docx), sia come
  atleta sia come coach.
- Tenere le settimane scritte esplicitamente nel foglio.
- Se il foglio dice come progredire, usare quella regola per precompilare la
  progressione dell'app.
- Se una settimana non è scritta e non c'è una regola, è uguale a quella
  prima.
- Quando il coach manda la scheda all'atleta, il piano deve arrivare intero.

Cosa non voglio: che sia l'AI a calcolare i kg delle settimane. Sbaglia con i
numeri e me ne accorgerei solo arrivato a quella settimana. L'AI legge, i
conti li fa l'app con la logica di progressione che già ho e che è testata.

### Come ho pensato di farlo

Ho valutato tre strade:

1. **Un solo "Importa da file", e il Word lo converto io nell'app.** Foto e
   PDF li mando al proxy così come sono (Gemini legge i PDF). Dal .docx tiro
   fuori il testo, con le righe delle tabelle separate da tab. Scelta questa.
2. Convertire il Word nel proxy: dovrei farlo in due backend diversi. No.
3. Leggere il Word a colonne fisse senza AI: funziona solo se tutti i coach
   usano la stessa tabella. No.

Il piano del coach lo metto dentro la scheda (`programma`: settimana →
esercizi) e la regola dentro l'esercizio (`progressione`: incremento in kg o
in %, RIR, da che settimana a che settimana, più il testo originale). Così
viaggia da solo con l'invio al coach, la libreria e i backup.

Quando passo alla settimana dopo, l'app decide in quest'ordine:

1. ho già modificato io quella settimana → uso la mia;
2. la settimana è scritta nel piano → uso quella;
3. c'è una regola che vale per quella settimana → apro la progressione già
   compilata, controllo e confermo;
4. altrimenti → copio la settimana precedente.

Le schede create a mano continuano a funzionare come prima.

Altre cose da non dimenticare:

- modificando una scheda importata il piano non deve perdersi (oggi la
  schermata di modifica ricostruisce la scheda da zero);
- il coach oggi invia solo la prima scheda letta: con un programma di più
  giorni deve poterli mandare tutti;
- il proxy deve continuare ad accettare la vecchia richiesta con la sola
  foto, finché non aggiorno l'app installata;
- file oltre 15 MB o Word senza testo: messaggio chiaro, niente chiamata al
  proxy.

### Ordine di lavoro

1. Modello: `programma` sulla scheda, `progressione` sull'esercizio.
2. La decisione "cosa succede alla settimana dopo", come funzione a parte.
3. Collegarla al dettaglio scheda e precompilare la schermata di
   progressione.
4. Leggere il testo dai .docx.
5. Proxy: accettare PDF, immagini e testo, e chiedere le settimane.
6. `AiService.analizzaFile`.
7. Interfaccia: "Importa da file" per atleta e coach, invio di tutti i
   giorni, modifica che conserva il piano.
