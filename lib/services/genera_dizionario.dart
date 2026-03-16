import 'dart:convert';
import 'dart:io';

void main() async {
  print('🔄 Avvio mappatura intelligente (con Filtro Anti-Doppioni)...');

  final fileOriginale = File('assets/esercizi_it.json'); 
  final fileTradotto = File('assets/esercizi_master_tiger.json');

  List<dynamic> originali = jsonDecode(await fileOriginale.readAsString());
  List<dynamic> tradotti = jsonDecode(await fileTradotto.readAsString());

  // Schedario tramite immagini
  Map<String, String> schedarioVecchi = {};
  for (var es in originali) {
    String nomeVecchio = (es['name'] ?? es['nome'])?.toString().trim() ?? '';
    List<dynamic> immaginiRaw = es['images'] ?? es['immagini'] ?? [];
    if (nomeVecchio.isNotEmpty && immaginiRaw.isNotEmpty) {
      String chiaveImmagine = immaginiRaw[0].toString();
      schedarioVecchi[chiaveImmagine] = nomeVecchio;
    }
  }

  // NUOVO: Usiamo una vera Map di Dart per assicurarci che le chiavi siano UNICHE
  Map<String, String> mappaUnica = {};

  for (var es in tradotti) {
    String nomeNuovo = (es['nome'] ?? es['name'])?.toString().trim() ?? '';
    String imgNuova = (es['immagine1'] ?? es['video'])?.toString() ?? '';

    if (nomeNuovo.isNotEmpty && imgNuova.isNotEmpty) {
      String? nomeVecchioCorrispondente;

      for (var chiave in schedarioVecchi.keys) {
        if (imgNuova.contains(chiave)) {
          nomeVecchioCorrispondente = schedarioVecchi[chiave];
          break;
        }
      }

      if (nomeVecchioCorrispondente != null) {
        String safeEn = nomeVecchioCorrispondente.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');
        String safeIt = nomeNuovo.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');

        if (safeEn != safeIt) {
          // FILTRO ANTI-DOPPIONI: Aggiunge la traduzione solo se l'inglese non esiste già
          if (!mappaUnica.containsKey(safeEn)) {
            mappaUnica[safeEn] = safeIt;
          }
        }
      }
    }
  }

  // Prepariamo il file Dart scrivendo i dati dalla mappa univoca
  StringBuffer buffer = StringBuffer();
  buffer.writeln('// 🐯 DIZIONARIO BLINDATO ANTI-DOPPIONI 🐯');
  buffer.writeln('class DizionarioEsercizi {');
  buffer.writeln('  static const Map<String, String> daIngleseAItaliano = {');

  for (var entry in mappaUnica.entries) {
    buffer.writeln("    '${entry.key}': '${entry.value}',");
  }

  buffer.writeln('  };');
  buffer.writeln('}');

  final fileOutput = File('lib/services/dizionario_esercizi.dart');
  await fileOutput.writeAsString(buffer.toString());

  print('✅ FINITO! Dizionario generato con ${mappaUnica.length} voci univoche perfette.');
}