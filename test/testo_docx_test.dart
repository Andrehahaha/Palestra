import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/services/testo_docx.dart';

/// Crea un .docx minimo in memoria con il document.xml dato.
Uint8List docxDi(String bodyXml) {
  final xml = '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$bodyXml</w:body></w:document>';
  final archivio = Archive()..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
  return Uint8List.fromList(ZipEncoder().encode(archivio));
}

String _p(String testo) => '<w:p><w:r><w:t>$testo</w:t></w:r></w:p>';
String _riga(List<String> celle) => '<w:tr>${celle.map((c) => '<w:tc>${_p(c)}</w:tc>').join()}</w:tr>';

void main() {
  test('paragrafi su righe separate, celle di tabella separate da tab', () {
    final bytes = docxDi(
      '${_p('GG1 - Settimana 1')}'
      '<w:tbl>${_riga(['Esercizio', 'Serie', 'Intensità'])}${_riga(['Panca', '3x8', '75%'])}</w:tbl>'
      '${_p('Progressione: +2,5 kg a settimana')}',
    );
    final righe = estraiTestoDocx(bytes).split('\n');
    expect(righe, contains('GG1 - Settimana 1'));
    expect(righe, contains('Esercizio\tSerie\tIntensità'));
    expect(righe, contains('Panca\t3x8\t75%'));
    expect(righe, contains('Progressione: +2,5 kg a settimana'));
  });

  test('testo spezzato in più run resta unito', () {
    final bytes = docxDi('<w:p><w:r><w:t>Stac</w:t></w:r><w:r><w:t>co</w:t></w:r></w:p>');
    expect(estraiTestoDocx(bytes).trim(), 'Stacco');
  });

  test('zip senza document.xml o file non zip: FormatException', () {
    final vuoto = Uint8List.fromList(ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('a.txt', [1]))));
    expect(() => estraiTestoDocx(vuoto), throwsFormatException);
    expect(() => estraiTestoDocx(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
}
