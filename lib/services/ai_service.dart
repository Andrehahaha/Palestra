import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 👈 Import per leggere il .env

import '../models/scheda.dart';
import '../services/api_esercizi.dart'; 
import '../services/dizionario_esercizi.dart';

class AiService {

  static final RegExp _separatori = RegExp(r'[^a-z0-9àèéìòù]');
  static const Set<String> _stopWords = {
    'con', 'al', 'allo', 'alla', 'ai', 'agli', 'alle', 'a', 'da', 'di', 'del', 'della', 'dello',
    'dei', 'degli', 'delle', 'in', 'su', 'per', 'ed', 'e', 'the', 'of',
  };

  static String _normalizza(String input) {
    final lower = input.toLowerCase().trim();
    final replaced = lower
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');
    return replaced.replaceAll(_separatori, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Set<String> _tokenizza(String input) {
    return _normalizza(input)
        .split(' ')
        .where((token) => token.isNotEmpty && !_stopWords.contains(token))
        .toSet();
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.generate(b.length + 1, (j) => j);
    final current = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      current[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      for (int j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }

  static double _similaritaToken(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }

  static String _risolviNomeEsercizio(String rawName, List<String> ufficiali) {
    final input = rawName.trim();
    if (input.isEmpty) return rawName;

    final normalizedInput = _normalizza(input);

    for (final nome in ufficiali) {
      if (_normalizza(nome) == normalizedInput) return nome;
    }

    final daDizionario = DizionarioEsercizi.daIngleseAItaliano[input] ??
        DizionarioEsercizi.daIngleseAItaliano.entries
            .where((e) => _normalizza(e.key) == normalizedInput || _normalizza(e.value) == normalizedInput)
            .map((e) => e.value)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);

    if (daDizionario != null) {
      final normalizedDict = _normalizza(daDizionario);
      for (final nome in ufficiali) {
        if (_normalizza(nome) == normalizedDict) return nome;
      }
    }

    final inputTokens = _tokenizza(input);
    String best = input;
    double bestScore = -1;

    for (final candidato in ufficiali) {
      final normCand = _normalizza(candidato);
      final candTokens = _tokenizza(candidato);

      double score = 0;

      if (normCand.contains(normalizedInput) || normalizedInput.contains(normCand)) {
        score += 0.25;
      }

      final tokenScore = _similaritaToken(inputTokens, candTokens);
      score += tokenScore * 0.45;

      final lev = _levenshtein(normalizedInput, normCand);
      final maxLen = normalizedInput.length > normCand.length ? normalizedInput.length : normCand.length;
      final levScore = maxLen == 0 ? 0 : (1 - (lev / maxLen));
      score += levScore * 0.30;

      if (score > bestScore) {
        bestScore = score;
        best = candidato;
      }
    }

    return bestScore >= 0.55 ? best : input;
  }

  static void _normalizzaEserciziJson(List<dynamic> jsonDecodificato, List<String> ufficiali) {
    for (final scheda in jsonDecodificato) {
      if (scheda is! Map<String, dynamic>) continue;
      final esercizi = scheda['esercizi'];
      if (esercizi is! List) continue;

      for (final esercizio in esercizi) {
        if (esercizio is! Map<String, dynamic>) continue;
        final nomeRaw = esercizio['nome']?.toString() ?? '';
        esercizio['nome'] = _risolviNomeEsercizio(nomeRaw, ufficiali);
      }
    }
  }
  
  // FUNZIONE 1: ANALISI FOTO SCHEDA
  static Future<List<Scheda>?> analizzaFotoScheda(XFile foto) async {
    try {
      // 👈 Pesca la chiave dal .env in modo sicuro!
      final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        debugPrint('⚠️ Errore: GEMINI_API_KEY non trovata nel .env');
        return null;
      }

      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final imageBytes = await foto.readAsBytes();
      final database = await ApiEsercizi.ottieniEserciziTradotti();
      final List<String> nomiUfficiali = database.map((e) => e['nome'].toString()).toSet().toList();
      
      final prompt = TextPart('''Sei un personal trainer esperto in protocolli di forza e bodybuilding. Analizza questa immagine che contiene una scheda di allenamento.

        ATTENZIONE: L'allenamento potrebbe essere diviso in più giorni (es. Giorno A, Giorno B, Day 1, Day 2).
        Estrai i dati e restituisci SOLO un ARRAY JSON valido contenente un oggetto per ogni giorno di allenamento trovato.

        🟢 REGOLE PER I NOMI DEGLI ESERCIZI (FONDAMENTALE):
        Qui sotto ti fornisco l'elenco ESATTO degli esercizi supportati dalla mia app.
        Per ogni esercizio che leggi dalla foto, DEVI trovare il nome corrispondente in questa lista e scriverlo ESATTAMENTE in quel modo, copiandolo lettera per lettera. 
        Non aggiungere dettagli tipo "con bilanciere" o "libero" se non sono presenti nella lista.
        Se l'esercizio nella foto è completamente introvabile in lista, usa una traduzione italiana standard.

        LISTA ESERCIZI UFFICIALI:
        ${jsonEncode(nomiUfficiali)}

        🟢 REGOLE PER LE TECNICHE (Mappa il testo trovato in uno o più di questi 20 valori):
        [Classico, Back off, Drop Set, Super Set, Rest Pause, Piramidale, Giant Set, Cluster Set, Top Set, Feeder Set, Warm Up, Myo-reps, AMRAP, Negative, Isometria, Stripping, Trisets, Pre-stancaggio, EMOM, Burnouts].

        🟢 REGOLE PER L'RPE (Rate of Perceived Exertion):
        Se nella foto per un esercizio è indicato un valore di difficoltà come "@8", "RPE 8", "RIR 2" o simili, estrai solo il numero (es. "8") e salvalo nel campo "rpe". Se non è indicato nulla, lascia una stringa vuota "".

        🟢 STRUTTURA JSON DA RESTITUIRE ESATTAMENTE COSÌ:
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

        🟢 NOTE AGGIUNTIVE:
        - Se trovi abbreviazioni come "S.S." o "SS", scrivi "Super Set".
        - Se trovi "R.P.", scrivi "Rest Pause".
        - Il campo "tecniche" deve essere un array di stringhe. Se un esercizio non ha tecniche speciali, metti ["Classico"].
        - "avvicinamento" e "workingSet" devono essere NUMERI interi.
        - Se l'immagine contiene un solo giorno, restituisci comunque un array con un solo oggetto. 
        - Non aggiungere testo fuori dal JSON.
      ''');
      
      final imagePart = DataPart('image/jpeg', imageBytes);
      final response = await model.generateContent([Content.multi([prompt, imagePart])]);
      String testoRisposta = response.text ?? '';
      int startIndex = testoRisposta.indexOf('[');
      int endIndex = testoRisposta.lastIndexOf(']');

      if (startIndex != -1 && endIndex != -1) {
        String soloJson = testoRisposta.substring(startIndex, endIndex + 1);
        final List<dynamic> jsonDecodificato = jsonDecode(soloJson);

        _normalizzaEserciziJson(jsonDecodificato, nomiUfficiali);

        return jsonDecodificato.map((e) => Scheda.fromJson(e)).toList();
      }
      return null;
    } catch (e) {
      debugPrint('Errore AI Foto: $e'); 
      return null;
    }
  }

  // --- FUNZIONE 2: VALUTAZIONE SCHEDA ---
  static Future<String?> valutaCartella(String nomeCartella, List<Scheda> schede) async {
    try {
      // 👈 Anche qui peschiamo dal .env!
      final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        return "Errore: Chiave API non configurata.";
      }

      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      
      String schedeStr = jsonEncode(schede.map((s) => s.toJson()).toList());
      
      final prompt = TextPart('''
        Sei un Senior Personal Trainer e preparatore atletico.
        Un tuo atleta ti ha chiesto di valutare il suo programma di allenamento chiamato "$nomeCartella".
        Ecco il dettaglio in formato JSON delle giornate di allenamento:
        $schedeStr

        Analizza la scheda e fornisci un responso discorsivo, amichevole ma tecnico.
        Struttura la risposta in questo modo usando le emoji:
        ⚖️ **Bilanciamento Generale**: È una buona scheda? C'è logica nella suddivisione?
        📊 **Volume e Intensità**: Il numero di serie totali per gruppo muscolare è corretto, troppo alto o troppo basso?
        ⚠️ **Gruppi Muscolari Carenti/Eccessivi**: C'è qualche muscolo ignorato (es. polpacci, femorali) o allenato troppo?
        💡 **Consiglio del Coach**: Dammi 1 o 2 consigli mirati per migliorare questa specifica routine.
        
        Rispondi in italiano. Non usare codice. Usa testo pulito e formattato bene con spazi.
      ''');

      final response = await model.generateContent([Content.text(prompt.text)]);
      return response.text;
    } catch (e) {
      debugPrint('Errore AI Valutazione: $e');
      return "Errore di connessione all'IA. Controlla la rete e riprova.";
    }
  }
}