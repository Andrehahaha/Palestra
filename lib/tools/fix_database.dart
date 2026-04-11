import 'dart:convert';
import 'dart:io';

void main() async {
  stdout.writeln(
    '🕵️ Avvio operazione "Riconoscimento Facciale" per riparare il DB...',
  );

  // 1. Leggiamo il tuo file italiano "corrotto"
  final fileIta = File('assets/esercizi_master_tiger.json');
  if (!await fileIta.exists()) {
    stdout.writeln('❌ Errore: File italiano non trovato!');
    return;
  }
  List<dynamic> dbIta = jsonDecode(await fileIta.readAsString());

  // 2. Scarichiamo il file originale inglese fresco fresco
  stdout.writeln('⬇️ Scarico il database originale inglese...');
  final url = Uri.parse(
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json',
  );
  final request = await HttpClient().getUrl(url);
  final response = await request.close();
  final stringData = await response.transform(utf8.decoder).join();
  List<dynamic> dbEng = jsonDecode(stringData);

  int riparati = 0;
  int saltati = 0;

  // 3. Ripariamo le immagini unendo i due file tramite IL NOME DELLA FOTO
  for (var esIta in dbIta) {
    List<dynamic> imgsIta = esIta['images'] ?? esIta['immagini'] ?? [];

    if (imgsIta.isNotEmpty) {
      String imgItaStr = imgsIta[0].toString();

      // Cerchiamo l'originale inglese usando la cartella dell'immagine (es. "0015/")
      var matchEng = dbEng.firstWhere((esEng) {
        List<dynamic> imgsEng = esEng['images'] ?? [];
        if (imgsEng.isEmpty) return false;

        // L'immagine originale è tipo "0015/0.jpg". Estraiamo "0015/"
        String cartellaOriginale = '${imgsEng[0].toString().split('/').first}/';

        // Se l'immagine italiana contiene "0015/", è lui!
        return imgItaStr.contains(cartellaOriginale);
      }, orElse: () => null);

      if (matchEng != null) {
        // BOOM! Sovrascriviamo le immagini sballate con quelle originali inglesi
        esIta['images'] = matchEng['images'];

        // Bonus: RIPRISTINIAMO L'ID PERDUTO! Così il DB torna perfetto
        esIta['id'] = matchEng['id'];

        riparati++;
      } else {
        saltati++;
      }
    } else {
      saltati++;
    }
  }

  // 4. Salviamo il nuovo file perfetto (con 2 spazi di indentazione corretti)
  final filePerfetto = File('assets/esercizi_it_riparato.json');
  await filePerfetto.writeAsString(JsonEncoder.withIndent('  ').convert(dbIta));

  stdout.writeln('\n✅ FATTO! Riparati e ripristinati $riparati esercizi!');
  if (saltati > 0) {
    stdout.writeln(
      '⚠️ Saltati $saltati esercizi (non avevano immagini valide da usare come riferimento).',
    );
  }
  stdout.writeln(
    'Ora cancella il vecchio "esercizi_it.json", rinomina questo nuovo e avvialo!',
  );
}
