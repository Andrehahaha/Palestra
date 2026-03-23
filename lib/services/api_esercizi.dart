import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ApiEsercizi {
  static String _normalizza(String value) {
    final lower = value.toLowerCase();
    return lower
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');
  }

  static bool _isStretchingExercise(Map<String, dynamic> exercise) {
    final nome = _normalizza((exercise['nome'] ?? '').toString());
    final categoria = _normalizza((exercise['categoria'] ?? '').toString());

    // Evita falsi positivi su esercizi classici (es. preacher curl) le cui note
    // contengono parole come "allungamento" ma non sono esercizi di stretching.
    const List<String> esclusioniForza = [
      'curl',
      'press',
      'squat',
      'deadlift',
      'row',
      'rematore',
      'panca',
      'lat machine',
      'trazioni',
      'pushdown',
      'affondi',
      'stacco',
      'dip',
      'pulldown',
      'alzate',
    ];

    for (final keyword in esclusioniForza) {
      if (nome.contains(keyword)) return false;
    }

    const List<String> indicatoriStretching = [
      'stretch',
      'allungamento',
      'allung',
      'mobilita',
      'flessibilita',
      'yoga',
    ];

    for (final keyword in indicatoriStretching) {
      if (nome.contains(keyword) || categoria.contains(keyword)) {
        return true;
      }
    }

    return false;
  }

  static String _slugDaUrlImmagine(String url) {
    final reg = RegExp(r'/exercises/([^/]+)/', caseSensitive: false);
    final match = reg.firstMatch(url);
    if (match == null) return '';
    return _normalizza(match.group(1) ?? '').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static bool _urlImmagineCoerenteConNome(String nome, String url) {
    if (url.isEmpty) return false;

    final nomeNorm = _normalizza(nome).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final slug = _slugDaUrlImmagine(url);
    if (slug.isEmpty) return false;

    // Match diretto su token importanti.
    const tokenDiretti = [
      'curl', 'squat', 'deadlift', 'row', 'bench', 'press', 'dip', 'lunge',
      'pull', 'push', 'raise', 'extension', 'fly', 'crunch', 'plank', 'stretch'
    ];
    for (final token in tokenDiretti) {
      if (nomeNorm.contains(token) && slug.contains(token)) return true;
    }

    // Sinonimi ITA -> ENG comuni.
    final sinonimi = <String, List<String>>{
      'stacco': ['deadlift'],
      'rematore': ['row'],
      'panca': ['bench', 'press'],
      'trazioni': ['pull', 'pulldown', 'chin'],
      'affondo': ['lunge', 'split'],
      'alzate': ['raise'],
      'spinte': ['press', 'push'],
      'estension': ['extension'],
      'addom': ['ab', 'crunch', 'core'],
      'core': ['core', 'ab'],
      'bicip': ['bicep', 'curl'],
      'tricip': ['tricep', 'extension', 'pushdown'],
      'spall': ['shoulder', 'press', 'raise'],
      'schiena': ['back', 'row', 'pull'],
      'dors': ['lat', 'back', 'row', 'pull'],
      'glute': ['glute', 'hip'],
      'polpacc': ['calf'],
      'quadric': ['quad'],
      'hamstring': ['hamstring'],
      'stretch': ['stretch'],
      'allung': ['stretch'],
      'mobilita': ['mobility', 'stretch'],
    };

    for (final entry in sinonimi.entries) {
      if (!nomeNorm.contains(entry.key)) continue;
      for (final english in entry.value) {
        if (slug.contains(english)) return true;
      }
    }

    // Fallback: almeno un token non banale in comune.
    final nomeTokens = nomeNorm.split(' ').where((t) => t.length >= 4).toSet();
    final slugTokens = slug.split(' ').where((t) => t.length >= 4).toSet();
    final intersezione = nomeTokens.intersection(slugTokens);
    return intersezione.isNotEmpty;
  }

  static String _immagineCoerente({required String nome, required String url}) {
    if (url.isEmpty) return '';
    return _urlImmagineCoerenteConNome(nome, url) ? url : '';
  }

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
        final isStretching = _isStretchingExercise(es);

        final nomeEsercizio = (es['nome'] ?? 'Esercizio Sconosciuto').toString();
        final img1Raw = (es['immagine1'] ?? '').toString();
        final img2Raw = (es['immagine2'] ?? '').toString();

        final img1 = _immagineCoerente(nome: nomeEsercizio, url: img1Raw);
        final img2 = _immagineCoerente(nome: nomeEsercizio, url: img2Raw);

        return {
          'nome': nomeEsercizio,
          'categoria': mappaMuscoli[targetGreggio] ?? targetGreggio.toUpperCase(),
          'video': img1, // Mostra solo immagini coerenti con l'esercizio.
          'video2': img2,
          'note': es['note'] ?? '',
          'isStretching': isStretching,
        };
      }).toList();
    } catch (e) {
      debugPrint('Errore caricamento database Tiger: $e');
      return [];
    }
  }
}