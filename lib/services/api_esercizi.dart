import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ApiEsercizi {
  static Future<List<Map<String, dynamic>>> ottieniEserciziTradotti() async {
    try {
      // 1. PUNTA AL NUOVO FILE MASTER
      final String jsonString = await rootBundle.loadString('assets/esercizi_master_tiger.json');
      final List<dynamic> dati = jsonDecode(jsonString);

      // Mappa muscoli aggiornata (più snella, perché Gemini ha già fatto gran parte del lavoro)
      Map<String, String> mappaMuscoli = {
        'abdominals': 'Addominali', 'quadriceps': 'Gambe', 'hamstrings': 'Femorali',
        'glutes': 'Glutei', 'adductors': 'Adduttori', 'calves': 'Polpacci',
        'chest': 'Petto', 'lats': 'Dorsali', 'middle back': 'Schiena',
        'lower back': 'Lombari', 'shoulders': 'Spalle', 'traps': 'Trapezio',
        'biceps': 'Bicipiti', 'triceps': 'Tricipiti', 'forearms': 'Avambracci'
      };

      return dati.map((es) {
        // 2. ADATTA I CAMPI AL FORMATO GENERATO DA GEMINI
        // Gemini ha già messo 'nome', 'categoria', 'note', 'immagine1', 'immagine2'
        
        String targetGreggio = (es['categoria'] ?? 'altro').toString().toLowerCase();

        return {
          'nome': es['nome'] ?? 'Esercizio Sconosciuto',
          'categoria': mappaMuscoli[targetGreggio] ?? targetGreggio.toUpperCase(),
          'video': es['immagine1'] ?? '', // Usiamo 'video' come nome chiave per non rompere la tua UI esistente
          'video2': es['immagine2'] ?? '',
          'note': es['note'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('Errore caricamento database Tiger: $e');
      return [];
    }
  }
}