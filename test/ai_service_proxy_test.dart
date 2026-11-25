import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/services/ai_service.dart';

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

  test('HttpProxyAi.urlCandidati', () {
    expect(HttpProxyAi(baseUrl: 'https://x.dev/').urlCandidati('a').map((u) => '$u'), ['https://x.dev/a']);
    expect(
      HttpProxyAi(baseUrl: 'https://x.dev/api').urlCandidati('a').map((u) => '$u'),
      ['https://x.dev/api/a', 'https://x.dev/a'],
    );
    expect(HttpProxyAi(baseUrl: 'https://x.dev/a').urlCandidati('a').map((u) => '$u'), ['https://x.dev/a']);
  });
}
