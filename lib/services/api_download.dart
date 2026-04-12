/*import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() async {
  final String apiKey = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  if (apiKey.isEmpty) {
    print('⚠️ Errore: passa GEMINI_API_KEY via --dart-define.');
    return;
  }

  // 2. CONFIGURA IL MODELLO (Forziamo l'uscita in JSON nativo!)
  final model = GenerativeModel(
    model: 'gemini-2.5-flash-lite', 
    apiKey: apiKey,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json', // 👈 Niente più sbattimenti per tagliare il testo!
    ),
  );

  final fileOriginale = File('assets/esercizi_it.json');
  final fileFinale = File('assets/esercizi_master_tiger.json');
  
  final String jsonString = await fileOriginale.readAsString();
  final List<dynamic> datiGrezzi = jsonDecode(jsonString);

  List<dynamic> databaseTradotto = [];
  int startIndex = 0;

  if (await fileFinale.exists()) {
    try {
      final savedData = await fileFinale.readAsString();
      databaseTradotto = jsonDecode(savedData);
      startIndex = databaseTradotto.length;
      print('🔄 Trovato salvataggio! Riprendo da $startIndex...');
    } catch (e) {
      print('⚠️ Errore lettura file. Riparto da 0.');
    }
  }

  int chunkSize = 5; 
  
  if (startIndex >= datiGrezzi.length) {
    print('✅ Completato!');
    return;
  }

  print('🚀 Inizio traduzione da $startIndex a ${datiGrezzi.length}...');

  for (int i = startIndex; i < datiGrezzi.length; i += chunkSize) {
    int fine = (i + chunkSize < datiGrezzi.length) ? i + chunkSize : datiGrezzi.length;
    List<dynamic> chunk = datiGrezzi.sublist(i, fine);

    print('🔄 Traduzione blocco $i - $fine...');

    // PRE-FILTRAGGIO: Mandiamo all'AI SOLO quello che deve tradurre (risparmio token!)
    List<Map<String, String>> payloadDaTradurre = chunk.map((es) {
      String nomeGrezzo = (es['name'] ?? es['nome'] ?? '').toString();
      String categoriaGrezza = (es['primaryMuscles'] != null && es['primaryMuscles'].isNotEmpty) ? es['primaryMuscles'][0].toString() : 'altro';
      var noteRaw = es['instructions'] ?? es['istruzioni'];
      String note = noteRaw is List ? noteRaw.join(' ') : noteRaw?.toString() ?? '';
      
      return {
        'nome': nomeGrezzo,
        'cat': categoriaGrezza,
        'istruzioni': note
      };
    }).toList();

    String prompt = '''
Traduci i seguenti 5 esercizi in italiano. Restituisci un array JSON valido in cui ogni oggetto ha queste chiavi:
"nome": Tradotto in gergo da palestra italiano.
"categoria": Gruppo muscolare tradotto.
"note": Istruzioni tradotte in italiano tecnico, precedute da "GUIDA ALL'ESECUZIONE:\\n\\n".

Dati da tradurre:
${jsonEncode(payloadDaTradurre)}
''';

    bool successo = false;
    int tentativi = 0;

    while (!successo && tentativi < 5) {
      try {
        final response = await model.generateContent([Content.text(prompt)]);
        String testoRisposta = response.text ?? '[]';

        // L'output è già un JSON perfetto grazie al responseMimeType
        List<dynamic> chunkTradotto = jsonDecode(testoRisposta);

        // POST-ELABORAZIONE IN DART (Montiamo le immagini qui, è immediato e infallibile)
        for (int j = 0; j < chunkTradotto.length; j++) {
          List<dynamic> immaginiRaw = chunk[j]['images'] ?? chunk[j]['immagini'] ?? [];
          String idFoto = immaginiRaw.isNotEmpty ? immaginiRaw[0].toString().split('/')[0] : '';

          if (idFoto.isNotEmpty) {
            chunkTradotto[j]['immagine1'] = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/$idFoto/0.jpg";
            chunkTradotto[j]['immagine2'] = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/$idFoto/1.jpg";
          } else {
            chunkTradotto[j]['immagine1'] = "";
            chunkTradotto[j]['immagine2'] = "";
          }
        }

        databaseTradotto.addAll(chunkTradotto);
        await fileFinale.writeAsString(jsonEncode(databaseTradotto));

        print('✅ Blocco completato e SALVATO! (Totale: ${databaseTradotto.length})');
        successo = true;

        await Future.delayed(const Duration(seconds: 25));

      } catch (e) {
        tentativi++;
        print('⚠️ Errore tentativo $tentativi: $e');
        
        if (tentativi < 5) {
          int attesa = 30 * tentativi; 
          print('🛑 Limite raggiunto. Pausa di $attesa secondi...');
          await Future.delayed(Duration(seconds: attesa));
        } else {
          print('❌ Blocco fallito. Riprova più tardi.');
          return; 
        }
      }
    }
  }

  print('\n🎯 MISSIONE COMPIUTA!');
}*/