import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Testo di un file Word (.docx): un paragrafo per riga, le celle di una
/// riga di tabella separate da tab. Lancia [FormatException] se il file
/// non è un .docx leggibile.
String estraiTestoDocx(Uint8List bytes) {
  final Archive archivio;
  try {
    archivio = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('File Word non valido');
  }
  final documento = archivio.findFile('word/document.xml');
  if (documento == null) throw const FormatException('File Word non valido');

  final XmlDocument xml;
  try {
    xml = XmlDocument.parse(utf8.decode(documento.content));
  } catch (_) {
    throw const FormatException('File Word non valido');
  }

  final body = xml.findAllElements('w:body').firstOrNull;
  if (body == null) return '';
  final righe = <String>[];
  for (final nodo in body.childElements) {
    if (nodo.name.qualified == 'w:p') {
      righe.add(_testoParagrafo(nodo));
    } else if (nodo.name.qualified == 'w:tbl') {
      for (final riga in nodo.findAllElements('w:tr')) {
        final celle = riga
            .findElements('w:tc')
            .map((c) => c.findAllElements('w:p').map(_testoParagrafo).where((t) => t.isNotEmpty).join(' '));
        righe.add(celle.join('\t'));
      }
    }
  }
  return righe.join('\n');
}

String _testoParagrafo(XmlElement p) =>
    p.findAllElements('w:t').map((t) => t.innerText).join().trim();
