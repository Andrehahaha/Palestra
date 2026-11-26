import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/services/ai_service.dart';

import 'testo_docx_test.dart' show docxDi;

class FakeProxy implements ProxyAi {
  FakeProxy({this.risposta, this.errore});

  Map<String, dynamic>? risposta;
  AiProxyException? errore;
  final List<(String, Map<String, dynamic>)> chiamate = [];

  @override
  String get descrizione => 'https://proxy.test';

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> payload) async {
    chiamate.add((endpoint, payload));
    if (errore != null) throw errore!;
    return risposta!;
  }
}

final _foto = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'scheda.jpg');

AiService _service(FakeProxy proxy, {Map<String, double> pr = const {}}) => AiService(
      proxy: proxy,
      caricaPr: () async => pr,
      nomiUfficiali: () async => ['Panca Piana', 'Squat'],
    );

void main() {
  group('analizzaFotoScheda', () {
    test('invia immagine e nomi, restituisce schede con carichi dai PR', () async {
      final proxy = FakeProxy(risposta: {
        'items': [
          {
            'nome': 'Giorno A',
            'esercizi': [
              {
                'nome': 'Bench Press',
                'workingSet': 3,
                'ripetizioni': '5',
                'modalitaIntensita': 'percentuale',
                'percentualeMassimale': 80,
              },
            ],
          },
        ],
      });
      final esito = await _service(proxy, pr: {'Panca Piana': 100}).analizzaFotoScheda(_foto);

      expect(esito.ok, isTrue);
      final scheda = esito.valore!.single;
      expect(scheda, isA<Scheda>());
      expect(scheda.esercizi.single.massimaleKg, 100);
      expect(scheda.esercizi.single.caricoTargetKg, 80);

      final (endpoint, payload) = proxy.chiamate.single;
      expect(endpoint, 'analyzeWorkoutPhoto');
      expect(payload['imageBase64'], base64Encode([1, 2, 3]));
      expect(payload['nomiUfficiali'], ['Panca Piana', 'Squat']);
    });

    test('nessuna scheda riconosciuta è un errore', () async {
      final esito = await _service(FakeProxy(risposta: {'items': []})).analizzaFotoScheda(_foto);
      expect(esito.ok, isFalse);
      expect(esito.errore, contains('Nessuna scheda'));
    });

    test('401 diventa messaggio di sessione scaduta', () async {
      final proxy = FakeProxy(errore: const AiProxyException('x', statusCode: 401));
      final esito = await _service(proxy).analizzaFotoScheda(_foto);
      expect(esito.errore, contains('Sessione scaduta'));
    });

    test('404 riporta la base URL', () async {
      final proxy = FakeProxy(errore: const AiProxyException('x', statusCode: 404));
      final esito = await _service(proxy).analizzaFotoScheda(_foto);
      expect(esito.errore, contains('https://proxy.test'));
    });
  });

  group('valutaCartella', () {
    test('restituisce il testo', () async {
      final proxy = FakeProxy(risposta: {'text': 'Bilanciata'});
      final esito = await _service(proxy).valutaCartella('Forza', []);
      expect(esito.valore, 'Bilanciata');
      expect(proxy.chiamate.single.$1, 'reviewWorkoutFolder');
    });

    test('429 e testo vuoto sono errori, non testo normale', () async {
      final quota = await _service(FakeProxy(errore: const AiProxyException('x', statusCode: 429)))
          .valutaCartella('Forza', []);
      expect(quota.valore, isNull);
      expect(quota.errore, contains('Limite richieste'));

      final vuoto = await _service(FakeProxy(risposta: {'text': ' '})).valutaCartella('Forza', []);
      expect(vuoto.ok, isFalse);
    });
  });

  group('analizzaFile', () {
    final risposta = {
      'items': [
        {
          'nome': 'GG1',
          'esercizi': [
            {
              'nome': 'Bench Press',
              'workingSet': 3,
              'progressione': {'daSettimana': 2, 'aSettimana': 3, 'incrementoKg': 2.5, 'nota': '+2,5 kg a settimana'},
            },
          ],
          'programma': {
            '4': [
              {'nome': 'panca PIANA', 'workingSet': 6},
            ],
          },
        },
      ],
    };

    test('PDF: inviato come file con il suo tipo', () async {
      final proxy = FakeProxy(risposta: risposta);
      final esito = await _service(proxy).analizzaFile(nomeFile: 'scheda.PDF', bytes: Uint8List.fromList([1, 2]));
      expect(esito.ok, isTrue);
      final payload = proxy.chiamate.single.$2;
      expect(payload['mimeType'], 'application/pdf');
      expect(payload['fileBase64'], base64Encode([1, 2]));
      expect(payload.containsKey('imageBase64'), isFalse);
    });

    test('Word: inviato il testo estratto', () async {
      final proxy = FakeProxy(risposta: risposta);
      final docx = docxDi('<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Panca</w:t></w:r></w:p></w:tc>'
          '<w:tc><w:p><w:r><w:t>3x8</w:t></w:r></w:p></w:tc></w:tr></w:tbl>');
      await _service(proxy).analizzaFile(nomeFile: 'programma.docx', bytes: docx);
      expect(proxy.chiamate.single.$2['testo'], contains('Panca\t3x8'));
      expect(proxy.chiamate.single.$2.containsKey('fileBase64'), isFalse);
    });

    test('programma e regola normalizzati come gli esercizi', () async {
      final esito = await _service(FakeProxy(risposta: risposta))
          .analizzaFile(nomeFile: 'a.jpg', bytes: Uint8List.fromList([1]));
      final scheda = esito.valore!.single;
      expect(scheda.programma!.keys.toSet(), {1, 4});
      expect(scheda.programma![4]!.single.nome, 'Panca Piana');
      expect(scheda.programma![4]!.single.workingSet, 6);
      final regola = scheda.esercizi.single.progressione!;
      expect(regola.incrementoKg, 2.5);
      expect(regola.nota, '+2,5 kg a settimana');
    });

    test('proxy vecchio senza programma: piano con la sola W1', () async {
      final esito = await _service(FakeProxy(risposta: {
        'items': [
          {'nome': 'GG1', 'esercizi': [{'nome': 'Squat'}]},
        ],
      })).analizzaFile(nomeFile: 'a.png', bytes: Uint8List.fromList([1]));
      expect(esito.valore!.single.programma!.keys, [1]);
      expect(esito.valore!.single.ripartiDaSettimana, isNull);
    });

    test('file oltre 15 MB: errore, nessuna chiamata', () async {
      final proxy = FakeProxy(risposta: risposta);
      final esito = await _service(proxy)
          .analizzaFile(nomeFile: 'grande.pdf', bytes: Uint8List(15 * 1024 * 1024 + 1));
      expect(esito.errore, contains('15 MB'));
      expect(proxy.chiamate, isEmpty);
    });

    test('Word senza testo o rotto: errore, nessuna chiamata', () async {
      final proxy = FakeProxy(risposta: risposta);
      final vuoto = await _service(proxy).analizzaFile(nomeFile: 'v.docx', bytes: docxDi(''));
      final rotto = await _service(proxy).analizzaFile(nomeFile: 'r.docx', bytes: Uint8List.fromList([1, 2, 3]));
      expect(vuoto.ok, isFalse);
      expect(rotto.ok, isFalse);
      expect(proxy.chiamate, isEmpty);
    });

    test('formato non supportato', () async {
      final proxy = FakeProxy(risposta: risposta);
      final esito = await _service(proxy).analizzaFile(nomeFile: 'piano.xlsx', bytes: Uint8List.fromList([1]));
      expect(esito.errore, contains('Formato non supportato'));
      expect(proxy.chiamate, isEmpty);
    });
  });

  group('controllo settimane all\'import', () {
    Future<Scheda> importa(Map<String, dynamic> giorno) async {
      final esito = await _service(FakeProxy(risposta: {'items': [giorno]}))
          .analizzaFile(nomeFile: 'a.pdf', bytes: Uint8List.fromList([1]));
      return esito.valore!.single;
    }

    Map<String, dynamic> es(String nome) => {'nome': nome, 'workingSet': 3};

    test('etichette testuali diventano numeri', () async {
      final s = await importa({
        'nome': 'GG1',
        'esercizi': [es('Squat')],
        'programma': {'Settimana 2': [es('Panca Piana')], 'W3': [es('Squat')], 'boh': [es('Squat')]},
      });
      expect(s.programma!.keys.toSet(), {1, 2, 3});
    });

    test('la W1 viene salvata anche nel piano', () async {
      final s = await importa({'nome': 'GG1', 'esercizi': [es('Squat')], 'programma': {'2': [es('Panca Piana')]}});
      expect(s.programma![1]!.single.nome, 'Squat');
    });

    test('senza W1 la prima settimana presente diventa la W1 e le altre scalano', () async {
      final s = await importa({
        'nome': 'GG1',
        'esercizi': [],
        'programma': {'3': [es('Squat')], '4': [es('Panca Piana')]},
      });
      expect(s.esercizi.single.nome, 'Squat');
      expect(s.programma!.keys.toSet(), {1, 2});
      expect(s.programma![2]!.single.nome, 'Panca Piana');
    });

    test('schede A/B: durata 2, si riparte dalla 1', () async {
      final ab = await importa({
        'nome': 'GG1',
        'esercizi': [es('Squat')],
        'programma': {'2': [es('Panca Piana')]},
        'durataSettimane': 2,
        'ripartiDaSettimana': 1,
      });
      expect(ab.durataProgramma, 2);
      expect(ab.ripartiDaSettimana, 1);
    });

    test('vecchio campo cicloSettimane letto come durata con ripartenza dalla 1', () async {
      final ab = await importa({
        'nome': 'GG1',
        'esercizi': [es('Squat')],
        'programma': {'2': [es('Panca Piana')]},
        'cicloSettimane': 2,
      });
      expect(ab.durataProgramma, 2);
      expect(ab.ripartiDaSettimana, 1);
    });

    test('ripartenza oltre la durata scartata; durata mancante ricavata dal piano', () async {
      final oltre = await importa({'nome': 'GG1', 'esercizi': [es('Squat')], 'durataSettimane': 5, 'ripartiDaSettimana': 9});
      expect(oltre.ripartiDaSettimana, isNull);
      final senzaDurata = await importa({
        'nome': 'GG1',
        'esercizi': [es('Squat')],
        'calendario': {'15': {'scarico': true}},
        'ripartiDaSettimana': 6,
      });
      expect(senzaDurata.durataProgramma, 15);
      expect(senzaDurata.ripartiDaSettimana, 6);
    });

    test('settimana parziale completata dalla precedente, RIR mancante ereditato', () async {
      final s = await importa({
        'nome': 'Upper',
        'esercizi': [
          {'nome': 'Squat', 'workingSet': 4, 'rirTarget': '1-2'},
          {'nome': 'Panca Piana', 'workingSet': 3, 'rirTarget': '1'},
          {'nome': 'Trazioni', 'workingSet': 3, 'rirTarget': '1'},
        ],
        'programma': {
          '6': [
            {'nome': 'Squat', 'workingSet': 5},
            {'nome': 'Trazioni', 'workingSet': 4},
          ],
        },
      });
      final w6 = s.programma![6]!;
      expect(w6.map((e) => e.nome), ['Squat', 'Panca Piana', 'Trazioni']);
      expect(w6.map((e) => e.workingSet), [5, 3, 4]);
      expect(w6.map((e) => e.rirTarget), ['1-2', '1', '1']);
    });

    test('nomi cambiati rispetto al documento: elenco per il log', () async {
      final proxy = FakeProxy(risposta: {
        'items': [
          {
            'nome': 'Lower',
            'esercizi': [
              {'nome': 'Chest Press alla Macchina', 'nomeOriginale': 'Pressa 45°'},
              {'nome': 'Squat', 'nomeOriginale': 'Squat'},
            ],
          },
        ],
      });
      final service = _service(proxy);
      await service.analizzaFile(nomeFile: 'a.pdf', bytes: Uint8List.fromList([1]));
      expect(service.ultimiNomiCambiati, [('Pressa 45°', 'Chest Press alla Macchina')]);
    });

    test('calendario: chiavi testuali e intervalli espansi, valori non validi scartati', () async {
      final s = await importa({
        'nome': 'Upper',
        'esercizi': [es('Squat')],
        'calendario': {
          'Sett. 1': {'rirDelta': '+2'},
          '5': {'scarico': true},
          '7-9': {'rirDelta': 0},
          '3': {'rirDelta': 'boh'},
        },
      });
      expect(s.calendario!.keys.toSet(), {1, 5, 7, 8, 9});
      expect(s.calendario![1]!.rirDelta, 2);
      expect(s.calendario![5]!.scarico, isTrue);
      expect(s.calendario![8]!.rirDelta, 0);
    });
  });

  test('HttpProxyAi: un errore del proxy porta anche il motivo di Gemini', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({'error': 'Gemini error 400', 'details': '{"error":{"message":"Unsupported MIME type"}}'}),
          400,
        ));
    final proxy = HttpProxyAi(baseUrl: 'https://x.dev', client: client, idToken: () async => 't');
    await expectLater(
      proxy.post('analyzeWorkoutPhoto', {}),
      throwsA(isA<AiProxyException>()
          .having((e) => e.statusCode, 'status', 400)
          .having((e) => e.details, 'details', allOf(contains('Gemini error 400'), contains('Unsupported MIME type')))),
    );
  });

  test('HttpProxyAi: attesa di default 120 secondi, oltre diventa 408', () async {
    expect(HttpProxyAi(baseUrl: 'https://x.dev').timeout, const Duration(seconds: 120));
    final lento = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return http.Response('{}', 200);
    });
    final proxy = HttpProxyAi(
      baseUrl: 'https://x.dev',
      client: lento,
      idToken: () async => 't',
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      proxy.post('analyzeWorkoutPhoto', {}),
      throwsA(isA<AiProxyException>().having((e) => e.statusCode, 'status', 408)),
    );
  });

  test('HttpProxyAi.urlCandidati', () {
    expect(HttpProxyAi(baseUrl: 'https://x.dev/').urlCandidati('a').map((u) => '$u'), ['https://x.dev/a']);
    expect(
      HttpProxyAi(baseUrl: 'https://x.dev/api').urlCandidati('a').map((u) => '$u'),
      ['https://x.dev/api/a', 'https://x.dev/a'],
    );
    expect(HttpProxyAi(baseUrl: 'https://x.dev/a').urlCandidati('a').map((u) => '$u'), ['https://x.dev/a']);
  });
}
