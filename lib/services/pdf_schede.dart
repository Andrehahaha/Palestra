import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/scheda.dart';

/// Export PDF di una cartella di schede: una sezione per scheda, con righe
/// vuote "kg x reps" da compilare in palestra.
abstract final class PdfSchede {
  static Future<Uint8List> cartella(String nomeCategoria, List<Scheda> schede) async {
    final pdf = pw.Document();
    final purpleColor = PdfColor.fromHex('#9C27B0');
    final greyText = PdfColor.fromHex('#757575');
    final dividerColor = PdfColor.fromHex('#E0E0E0');

    for (var scheda in schede) {
      pdf.addPage(
        pw.MultiPage(
          maxPages: 100,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          build: (pw.Context _) {
            List<pw.Widget> foglio = [];
            foglio.add(
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(scheda.nome.toUpperCase(), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.Text(nomeCategoria, style: pw.TextStyle(fontSize: 12, color: greyText)),
                ],
              ),
            );
            foglio.add(pw.Divider(thickness: 1, color: dividerColor));

            if (scheda.livello.isNotEmpty) {
              foglio.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 20, top: 4),
                  child: pw.Text(
                    'Livello: ${scheda.livello}',
                    style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: greyText),
                  ),
                ),
              );
            } else {
              foglio.add(pw.SizedBox(height: 20));
            }

            for (int i = 0; i < scheda.esercizi.length; i++) {
              var es = scheda.esercizi[i];
              int numAvvicinamento = es.serieAttive.where((s) => s.tipo == 'Avvicinamento').length;
              int numWorking = es.serieAttive.where((s) => s.tipo != 'Avvicinamento').length;
              if (numWorking == 0) numWorking = es.serieAttive.length;

              bool isSuperSet = es.tecniche.any((t) => t.toLowerCase().contains('super'));
              bool prevIsSuperSet = i > 0 && scheda.esercizi[i - 1].tecniche.any((t) => t.toLowerCase().contains('super'));
              var altreTecniche = es.tecniche.where((t) => !t.toLowerCase().contains('super')).toList();

              if (isSuperSet && !prevIsSuperSet) {
                foglio.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 8, bottom: 8),
                    child: pw.Text(
                      '>>> INIZIO SUPERSET',
                      style: pw.TextStyle(color: purpleColor, fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ),
                );
              }

              foglio.add(
                pw.Padding(
                  padding: pw.EdgeInsets.only(left: isSuperSet ? 20 : 0, bottom: 16),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('- ${es.nome}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(width: 10),
                          pw.Text('$numWorking set  |  ${es.ripetizioni} reps  |  Rec: ${es.recupero}s', style: const pw.TextStyle(fontSize: 11)),
                        ],
                      ),
                      if (numAvvicinamento > 0 || altreTecniche.isNotEmpty || (es.note != null && es.note!.isNotEmpty))
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 12, top: 4),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              if (numAvvicinamento > 0) pw.Text('Avvicinamento: $numAvvicinamento set', style: pw.TextStyle(fontSize: 10, color: greyText)),
                              if (altreTecniche.isNotEmpty) pw.Text('Tecniche: ${altreTecniche.join(", ")}', style: pw.TextStyle(fontSize: 10, color: greyText)),
                              if (es.note != null && es.note!.isNotEmpty)
                                pw.Text('Note: ${es.note}', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: greyText)),
                            ],
                          ),
                        ),
                      pw.SizedBox(height: 8),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 12),
                        child: pw.Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: List.generate(
                            numWorking,
                            (idx) => pw.Text('Set ${idx + 1}:  ____ kg  x  ____', style: const pw.TextStyle(fontSize: 11, color: PdfColors.black)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return foglio;
          },
        ),
      );
    }
    return pdf.save();
  }
}
