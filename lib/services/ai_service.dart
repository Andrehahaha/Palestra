import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/scheda.dart';
import '../models/settimana_piano.dart';
import '../services/api_esercizi.dart'; 
import '../services/dizionario_esercizi.dart';
import '../services/archivio_atleta.dart';
import '../services/carichi.dart';
import '../services/riepilogo_import.dart';
import '../services/testo_docx.dart';
import '../services/workload_calculator.dart';

class AiProxyException implements Exception {
  final String message;
  final int? statusCode;
  final String? details;

  const AiProxyException(this.message, {this.statusCode, this.details});

  @override
  String toString() => 'AiProxyException(status: $statusCode, message: $message, details: $details)';
}

/// Esito di una chiamata AI: [valore] se riuscita, altrimenti [errore]
/// (messaggio già pronto per l'utente).
class EsitoAi<T> {
  const EsitoAi.ok(T this.valore) : errore = null;
  const EsitoAi.errore(String this.errore) : valore = null;

  final T? valore;
  final String? errore;

  bool get ok => errore == null;
}

/// Seam verso il proxy AI. Adapter: [HttpProxyAi] in produzione, un fake nei test.
abstract interface class ProxyAi {
  /// Dove punta il proxy, per i messaggi d'errore.
  String get descrizione;

  /// POST JSON a [endpoint]. Lancia [AiProxyException] in caso di errore.
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> payload);
}

class HttpProxyAi implements ProxyAi {
  HttpProxyAi({
    String? baseUrl,
    http.Client? client,
    FirebaseAuth? auth,
    Future<String?> Function()? idToken,
    this.timeout = const Duration(seconds: 120),
  })  : _baseUrl = baseUrl ?? const String.fromEnvironment('AI_PROXY_BASE_URL', defaultValue: ''),
        _client = client,
        _auth = auth,
        _idToken = idToken;

  final String _baseUrl;
  final http.Client? _client;
  final FirebaseAuth? _auth;
  final Future<String?> Function()? _idToken;

  /// Attesa massima per una risposta: leggere un PDF di più settimane può
  /// richiedere più di un minuto.
  final Duration timeout;

  /// Token Firebase dell'utente; `null` se non è loggato.
  Future<String?> _token() async {
    if (_idToken != null) return _idToken();
    return (_auth ?? FirebaseAuth.instance).currentUser?.getIdToken();
  }

  @override
  String get descrizione => _baseUrl.isEmpty ? '(vuoto)' : _baseUrl;

  /// URL da provare per [endpoint]: `base/endpoint` e, se la base contiene
  /// già un path, `host/endpoint`. Un 404 fa passare al successivo.
  List<Uri> urlCandidati(String endpoint) {
    final base = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    final out = <Uri>[base.endsWith('/$endpoint') ? Uri.parse(base) : Uri.parse('$base/$endpoint')];
    final parsed = Uri.tryParse(base);
    if (parsed != null && parsed.hasAuthority) {
      final root = parsed.replace(path: '/$endpoint', query: null, fragment: null);
      if (!out.contains(root)) out.add(root);
    }
    return out;
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> payload) async {
    if (_baseUrl.isEmpty) {
      throw const AiProxyException('AI proxy non configurato. Imposta AI_PROXY_BASE_URL.');
    }
    try {
      // Il token in cache viene rinnovato da Firebase quando sta per scadere.
      final idToken = await _token();
      if (idToken == null) {
        throw const AiProxyException('Utente non autenticato.', statusCode: 401);
      }
      final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'};
      final body = jsonEncode(payload);
      final client = _client;
      final tried = <String>[];

      for (final uri in urlCandidati(endpoint)) {
        final response = await (client == null
                ? http.post(uri, headers: headers, body: body)
                : client.post(uri, headers: headers, body: body))
            .timeout(timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) return decoded;
          throw const AiProxyException('Risposta proxy non valida (JSON atteso).');
        }

        tried.add('$uri -> ${response.statusCode}');
        if (response.statusCode == 404) continue;

        var backendError = response.body;
        try {
          final b = jsonDecode(response.body);
          if (b is Map && b['error'] != null) {
            // Il proxy mette in `details` il motivo restituito da Gemini.
            backendError = [b['error'], b['details']].where((x) => x != null && '$x'.isNotEmpty).join(': ');
          }
        } catch (_) {}
        throw AiProxyException(
          'Proxy AI errore ${response.statusCode}',
          statusCode: response.statusCode,
          details: backendError,
        );
      }

      throw AiProxyException(
        'Endpoint AI non trovato',
        statusCode: 404,
        details: 'URL provati: ${tried.join(' | ')}',
      );
    } on TimeoutException {
      throw const AiProxyException('Timeout durante la connessione al proxy AI.', statusCode: 408);
    } on SocketException {
      throw const AiProxyException('Nessuna connessione di rete verso il proxy AI.');
    }
  }
}

/// Import AI: foto di una scheda -> [Scheda] normalizzate (nomi esercizi del
/// database, schema dell'app, carichi %1RM dai PR) e recensione di una
/// cartella. Gli errori arrivano come [EsitoAi.errore], già leggibili.
class AiService {
  AiService({
    ProxyAi? proxy,
    Future<Map<String, double>> Function()? caricaPr,
    Future<List<String>> Function()? nomiUfficiali,
  })  : _proxy = proxy ?? HttpProxyAi(),
        _caricaPr = caricaPr ?? (() => ArchivioAtleta.instance.caricaPr()),
        _nomiUfficiali = nomiUfficiali ?? _nomiDalDatabase;

  static final AiService instance = AiService();

  final ProxyAi _proxy;
  final Future<Map<String, double>> Function() _caricaPr;
  final Future<List<String>> Function() _nomiUfficiali;

  static Future<List<String>> _nomiDalDatabase() async {
    final database = await ApiEsercizi.ottieniEserciziTradotti();
    return database.map((e) => e['nome'].toString()).toSet().toList();
  }

  static final RegExp _separatori = RegExp(r'[^a-z0-9àèéìòù]');
  static const Set<String> _stopWords = {
    'con', 'al', 'allo', 'alla', 'ai', 'agli', 'alle', 'a', 'da', 'di', 'del', 'della', 'dello',
    'dei', 'degli', 'delle', 'in', 'su', 'per', 'ed', 'e', 'the', 'of',
  };

  static String _normalizza(String input) {
    final lower = input.toLowerCase().trim();
    final replaced = lower
        .replaceAll('à', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');
    return replaced.replaceAll(_separatori, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Set<String> _tokenizza(String input) {
    return _normalizza(input)
        .split(' ')
        .where((token) => token.isNotEmpty && !_stopWords.contains(token))
        .toSet();
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.generate(b.length + 1, (j) => j);
    final current = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      current[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      for (int j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }

  static double _similaritaToken(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }

  static String _risolviNomeEsercizio(String rawName, List<String> ufficiali) {
    final input = rawName.trim();
    if (input.isEmpty) return rawName;

    final normalizedInput = _normalizza(input);

    for (final nome in ufficiali) {
      if (_normalizza(nome) == normalizedInput) return nome;
    }

    final daDizionario = DizionarioEsercizi.daIngleseAItaliano[input] ??
        DizionarioEsercizi.daIngleseAItaliano.entries
            .where((e) => _normalizza(e.key) == normalizedInput || _normalizza(e.value) == normalizedInput)
            .map((e) => e.value)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);

    if (daDizionario != null) {
      final normalizedDict = _normalizza(daDizionario);
      for (final nome in ufficiali) {
        if (_normalizza(nome) == normalizedDict) return nome;
      }
    }

    final inputTokens = _tokenizza(input);
    String best = input;
    double bestScore = -1;

    for (final candidato in ufficiali) {
      final normCand = _normalizza(candidato);
      final candTokens = _tokenizza(candidato);

      double score = 0;

      if (normCand.contains(normalizedInput) || normalizedInput.contains(normCand)) {
        score += 0.25;
      }

      final tokenScore = _similaritaToken(inputTokens, candTokens);
      score += tokenScore * 0.45;

      final lev = _levenshtein(normalizedInput, normCand);
      final maxLen = normalizedInput.length > normCand.length ? normalizedInput.length : normCand.length;
      final levScore = maxLen == 0 ? 0 : (1 - (lev / maxLen));
      score += levScore * 0.30;

      if (score > bestScore) {
        bestScore = score;
        best = candidato;
      }
    }

    return bestScore >= 0.55 ? best : input;
  }

  static void _normalizzaEserciziJson(List<dynamic> jsonDecodificato, List<String> ufficiali) {
    for (final scheda in jsonDecodificato) {
      if (scheda is! Map<String, dynamic>) continue;
      final programma = scheda['programma'];
      final liste = [
        scheda['esercizi'],
        if (programma is Map) ...programma.values,
      ];
      for (final esercizi in liste) {
        if (esercizi is! List) continue;
        for (final esercizio in esercizi) {
          if (esercizio is! Map) continue;
          final nomeRaw = esercizio['nome']?.toString() ?? '';
          esercizio['nome'] = _risolviNomeEsercizio(nomeRaw, ufficiali);
        }
      }
    }
  }

  static double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final normalized = value.toString().replaceAll(',', '.').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  static int _toIntOrDefault(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }



  static double? _findOneRmFromPersonalRecords(Map<String, dynamic> personalRecords, String exerciseName) {
    final prs = <String, double>{};
    for (final entry in personalRecords.entries) {
      final value = _toDoubleOrNull(entry.value);
      if (value != null) prs[entry.key] = value;
    }
    return Carichi.trovaPr(prs, exerciseName);
  }

  static List<Map<String, dynamic>> applicaPrFallback(
    List<Map<String, dynamic>> normalizedSchede,
    Map<String, dynamic> personalRecords,
  ) {
    return normalizedSchede.map((scheda) {
      final eserciziRaw = scheda['esercizi'];
      if (eserciziRaw is! List) return scheda;

      final esercizi = eserciziRaw.whereType<Map>().map((eRaw) {
        final e = Map<String, dynamic>.from(eRaw.cast<String, dynamic>());
        final modalita = (e['modalitaIntensita'] ?? '').toString().toLowerCase();
        if (modalita != 'percentuale') return e;

        final percentuale = _toDoubleOrNull(e['percentualeMassimale']);
        var massimale = _toDoubleOrNull(e['massimaleKg']);

        if ((massimale == null || massimale <= 0) && Carichi.riconosciBig3((e['nome'] ?? '').toString()) != null) {
          massimale = _findOneRmFromPersonalRecords(personalRecords, (e['nome'] ?? '').toString());
          if (massimale != null) {
            e['massimaleKg'] = massimale;
          }
        }

        if (percentuale != null && massimale != null && massimale > 0) {
          e['caricoTargetKg'] = WorkloadCalculator.calculateFromMaxAndPercentage(
            oneRepMax: massimale,
            percentage: percentuale,
          );
        }

        return e;
      }).toList();

      return {
        ...scheda,
        'esercizi': esercizi,
      };
    }).toList();
  }



  static double? _extractOneRmFromText(String text) {
    final rmMatch = RegExp(
      r'(?:1\s*rm|1rm|massimale|max)\D{0,10}(\d{1,4}(?:[\.,]\d+)?)\s*kg?',
      caseSensitive: false,
    ).firstMatch(text);
    if (rmMatch != null) {
      return _toDoubleOrNull(rmMatch.group(1));
    }
    return null;
  }

  static List<Map<String, dynamic>> _normalizzaSchemaSchede(List<dynamic> rawItems) {
    return rawItems
        .whereType<Map>()
        .map((rawScheda) {
          final scheda = Map<String, dynamic>.from(rawScheda.cast<String, dynamic>());
          final rawId = scheda['id']?.toString();
          final hasStableId = rawId != null && rawId.trim().isNotEmpty;

          final piano = _pianoSettimane(_normalizzaListaEsercizi(scheda['esercizi']), scheda);
          final esercizi = piano.esercizi;
          final programma = {for (final e in piano.settimane.entries) '${e.key}': e.value};

          return {
            'id': hasStableId ? rawId : null,
            'nome': scheda['nome']?.toString().trim().isNotEmpty == true ? scheda['nome'] : 'Scheda Importata',
            'livello': scheda['livello']?.toString().trim().isNotEmpty == true ? scheda['livello'] : 'Intermedio',
            'categoria': scheda['categoria']?.toString().trim().isNotEmpty == true ? scheda['categoria'] : 'Importata AI',
            'continuativa': scheda['continuativa'] ?? true,
            'settimanaCorrente': hasStableId ? _toIntOrDefault(scheda['settimanaCorrente'], 1) : 1,
            'esercizi': esercizi,
            'programma': programma,
            'calendario': {for (final e in piano.calendario.entries) '${e.key}': e.value.toJson()},
            'durataProgramma': piano.durata,
            'ripartiDaSettimana': piano.ripartiDa,
          };
        })
        .toList();
  }

  /// Settimane indicate da una chiave: "Sett. 2" -> [2], "7-9" -> [7, 8, 9].
  static List<int> _settimaneDaChiave(Object? chiave) {
    final testo = '$chiave';
    final intervallo = RegExp(r'(\d+)\s*[-–]\s*(\d+)').firstMatch(testo);
    if (intervallo != null) {
      final da = int.parse(intervallo.group(1)!);
      final a = int.parse(intervallo.group(2)!);
      if (da >= 1 && a >= da && a - da < 60) return [for (var w = da; w <= a; w++) w];
    }
    final n = int.tryParse(RegExp(r'\d+').firstMatch(testo)?.group(0) ?? '');
    return n != null && n >= 1 ? [n] : const [];
  }

  static int? _intero(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());

  /// Controllo delle settimane lette dall'AI:
  /// - chiavi ridotte al numero ("Settimana 2", "W2" -> 2; nel calendario
  ///   anche intervalli "7-9");
  /// - W1 garantita: se manca, la prima settimana presente diventa la W1 e le
  ///   altre scalano (calendario compreso); la W1 è salvata anche nel piano;
  /// - durata ricavata dal piano se manca; ripartenza tenuta solo se coerente.
  static ({
    List<Map<String, dynamic>> esercizi,
    Map<int, List<Map<String, dynamic>>> settimane,
    Map<int, SettimanaPiano> calendario,
    int? durata,
    int? ripartiDa,
  }) _pianoSettimane(List<Map<String, dynamic>> base, Map<String, dynamic> scheda) {
    var settimane = <int, List<Map<String, dynamic>>>{};
    final programmaRaw = scheda['programma'];
    if (programmaRaw is Map) {
      for (final e in programmaRaw.entries) {
        final numeri = _settimaneDaChiave(e.key);
        final lista = _normalizzaListaEsercizi(e.value);
        if (numeri.length == 1 && lista.isNotEmpty) settimane[numeri.single] = lista;
      }
    }

    var calendario = <int, SettimanaPiano>{};
    final calendarioRaw = scheda['calendario'];
    if (calendarioRaw is Map) {
      for (final e in calendarioRaw.entries) {
        final info = SettimanaPiano.fromJson(e.value);
        if (info == null) continue;
        for (final w in _settimaneDaChiave(e.key)) {
          calendario[w] = info;
        }
      }
    }

    var esercizi = base;
    if (esercizi.isEmpty && settimane.isNotEmpty) {
      final spostamento = settimane.keys.reduce((a, b) => a < b ? a : b) - 1;
      settimane = {for (final e in settimane.entries) e.key - spostamento: e.value};
      calendario = {
        for (final e in calendario.entries)
          if (e.key - spostamento >= 1) e.key - spostamento: e.value,
      };
      esercizi = settimane[1]!;
    }
    if (esercizi.isNotEmpty) settimane[1] = esercizi;

    final ultimaScritta = [...settimane.keys, ...calendario.keys, 1].reduce((a, b) => a > b ? a : b);
    var durata = _intero(scheda['durataSettimane'] ?? scheda['durataProgramma']);
    var ripartiDa = _intero(scheda['ripartiDaSettimana']);
    final cicloVecchio = _intero(scheda['cicloSettimane']);
    if (durata == null && ripartiDa == null && cicloVecchio != null && cicloVecchio >= 2) {
      // Formato precedente: un ciclo di N settimane che riparte dalla prima.
      durata = cicloVecchio;
      ripartiDa = 1;
    }
    if (durata == null || durata < ultimaScritta) durata = ultimaScritta;
    if (ripartiDa != null && (ripartiDa < 1 || ripartiDa > durata)) ripartiDa = null;

    return (esercizi: esercizi, settimane: settimane, calendario: calendario, durata: durata, ripartiDa: ripartiDa);
  }

  static List<Map<String, dynamic>> _normalizzaListaEsercizi(dynamic raw) {
    return (raw is List ? raw : <dynamic>[])
              .whereType<Map>()
              .map((rawEs) {
                final es = Map<String, dynamic>.from(rawEs.cast<String, dynamic>());

                final percentuale = _toDoubleOrNull(es['percentualeMassimale'] ?? es['percentuale']);
                final massimale = _toDoubleOrNull(es['massimaleKg'] ?? es['massimale']);
                final infoTestuale = [
                  es['ripetizioni'],
                  es['note'],
                  es['descrizione'],
                ].where((v) => v != null).map((v) => v.toString()).join(' ');

                final bigThree = Carichi.riconosciBig3((es['nome'] ?? '').toString()) != null;
                final percentualeDaTesto = Carichi.estraiPercentualeDaTesto(infoTestuale);
                final massimaleDaTesto = _extractOneRmFromText(infoTestuale);
                final percentualeFinale = percentuale ?? (bigThree ? percentualeDaTesto : null);
                final massimaleFinale = massimale ?? (bigThree ? massimaleDaTesto : null);

                String modalita = (es['modalitaIntensita'] ?? '').toString().trim().toLowerCase();
                if (modalita != 'rir' && modalita != 'percentuale') {
                  modalita = (percentualeFinale != null || massimaleFinale != null) ? 'percentuale' : 'rir';
                }

                final tecnicheValue = es['tecniche'];
                final metodo = es['metodo']?.toString().trim();
                final tecniche = tecnicheValue is List
                    ? tecnicheValue.map((t) => t.toString()).where((t) => t.trim().isNotEmpty).toList()
                    : (metodo != null && metodo.isNotEmpty)
                        ? <String>[metodo]
                        : <String>['Classico'];

                final rirDaInput = es['rirTarget'] ?? es['rir'] ?? es['rpe'];

                return {
                  'nome': es['nome']?.toString().trim().isNotEmpty == true ? es['nome'] : 'Esercizio',
                  'avvicinamento': _toIntOrDefault(es['avvicinamento'], 0),
                  'workingSet': _toIntOrDefault(es['workingSet'], 3),
                  'ripetizioni': (es['ripetizioni'] ?? '').toString(),
                  'recupero': (es['recupero'] ?? '').toString(),
                  'note': es['note']?.toString(),
                  'tecniche': tecniche,
                  'modalitaIntensita': modalita,
                  'rirTarget': modalita == 'rir' && rirDaInput != null
                      ? rirDaInput.toString().trim()
                      : null,
                  'percentualeMassimale': modalita == 'percentuale' ? percentualeFinale : null,
                  'massimaleKg': modalita == 'percentuale' ? massimaleFinale : null,
                  'caricoTargetKg': _toDoubleOrNull(es['caricoTargetKg']),
                  'serieAttive': es['serieAttive'] is List ? es['serieAttive'] : <dynamic>[],
                  'progressione': es['progressione'],
                };
              })
              .toList();
  }

  /// Normalizza le schede grezze restituite dall'AI (nomi esercizi e schema).
  static List<Map<String, dynamic>> normalizzaSchedeImportate(
    List<dynamic> rawItems, {
    List<String> nomiUfficiali = const [],
  }) {
    final cloned = rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();

    if (nomiUfficiali.isNotEmpty) {
      _normalizzaEserciziJson(cloned, nomiUfficiali);
    }

    return _normalizzaSchemaSchede(cloned);
  }

  String _messaggioErrore(AiProxyException e) {
    final code = e.statusCode;
    final details = e.details?.trim();
    final hasDetails = details != null && details.isNotEmpty;

    if (code == 401 || code == 403) {
      return 'Sessione scaduta o non autorizzata. Esci e rientra nell\'app, poi riprova.';
    }
    if (code == 404) {
      return 'Endpoint AI non trovato. Base URL attuale: ${_proxy.descrizione}. '
          '${hasDetails ? details : 'Verifica AI_PROXY_BASE_URL e deploy del proxy.'}';
    }
    if (code == 408) return 'Il servizio AI non risponde in tempo. Controlla la rete e riprova.';
    if (code == 429) return 'Limite richieste Gemini raggiunto. Attendi qualche minuto e riprova.';
    if (code != null && code >= 500) {
      return hasDetails ? 'Errore server AI: $details' : 'Errore interno del servizio AI. Riprova tra poco.';
    }
    return hasDetails ? 'Errore AI: $details' : e.message;
  }

  static const int maxBytesFile = 15 * 1024 * 1024;

  static const Map<String, String> _mimePerEstensione = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'heic': 'image/heic',
    'pdf': 'application/pdf',
  };

  /// Estensioni accettate da "Importa da file".
  static const List<String> estensioniSupportate = ['jpg', 'jpeg', 'png', 'heic', 'pdf', 'docx'];

  /// Legge la foto di una scheda (galleria). Usa il formato di richiesta
  /// storico, compatibile anche con un proxy non aggiornato.
  Future<EsitoAi<List<Scheda>>> analizzaFotoScheda(XFile foto) async {
    try {
      final imageBytes = await foto.readAsBytes();
      return _analizza({'imageBase64': base64Encode(imageBytes)});
    } catch (e) {
      debugPrint('Errore AI Foto: $e');
      return const EsitoAi.errore('Errore imprevisto durante la connessione all\'IA.');
    }
  }

  /// Legge una scheda da file: immagine, PDF o Word (.docx).
  Future<EsitoAi<List<Scheda>>> analizzaFile({required String nomeFile, required Uint8List bytes}) async {
    final estensione = nomeFile.contains('.') ? nomeFile.split('.').last.toLowerCase() : '';
    if (!estensioniSupportate.contains(estensione)) {
      return const EsitoAi.errore('Formato non supportato. Usa PDF, foto (jpg, png, heic) o Word (.docx).');
    }
    if (bytes.length > maxBytesFile) {
      return const EsitoAi.errore('Il file supera i 15 MB. Prova a ridurlo o a esportarlo di nuovo.');
    }

    if (estensione == 'docx') {
      final String testo;
      try {
        testo = estraiTestoDocx(bytes);
      } on FormatException {
        return const EsitoAi.errore('Non riesco ad aprire il file Word. Prova a salvarlo di nuovo come .docx.');
      }
      if (testo.trim().isEmpty) {
        return const EsitoAi.errore('Il file Word non contiene testo leggibile.');
      }
      return _analizza({'testo': testo});
    }
    return _analizza({'fileBase64': base64Encode(bytes), 'mimeType': _mimePerEstensione[estensione]});
  }

  Future<EsitoAi<List<Scheda>>> _analizza(Map<String, dynamic> documento) async {
    try {
      final nomi = await _nomiUfficiali();
      final risultato = await _proxy.post('analyzeWorkoutPhoto', {...documento, 'nomiUfficiali': nomi});

      final items = risultato['items'];
      if (items is! List || items.isEmpty) {
        return const EsitoAi.errore('Nessuna scheda riconosciuta. Prova con un file più leggibile.');
      }

      _normalizzaEserciziJson(items, nomi);
      final prs = await _caricaPr();
      final compatibili = applicaPrFallback(_normalizzaSchemaSchede(items), prs);
      final schede = compatibili.map((e) => Scheda.fromJson(e)).toList();
      debugPrint(RiepilogoImport.testo(schede));
      return EsitoAi.ok(schede);
    } on AiProxyException catch (e) {
      debugPrint('Errore AI import: $e');
      return EsitoAi.errore(_messaggioErrore(e));
    } catch (e) {
      debugPrint('Errore AI import: $e');
      return const EsitoAi.errore('Errore imprevisto durante la connessione all\'IA.');
    }
  }

  /// Recensione testuale delle schede di una cartella.
  Future<EsitoAi<String>> valutaCartella(String nomeCartella, List<Scheda> schede) async {
    try {
      final risultato = await _proxy.post('reviewWorkoutFolder', {
        'nomeCartella': nomeCartella,
        'schede': schede.map((s) => s.toJson()).toList(),
      });
      final text = risultato['text']?.toString();
      if (text == null || text.trim().isEmpty) {
        return const EsitoAi.errore('Errore: risposta AI non valida.');
      }
      return EsitoAi.ok(text);
    } on AiProxyException catch (e) {
      debugPrint('Errore AI Valutazione: $e');
      return EsitoAi.errore(_messaggioErrore(e));
    } catch (e) {
      debugPrint('Errore AI Valutazione: $e');
      return const EsitoAi.errore("Errore di connessione all'IA. Controlla la rete e riprova.");
    }
  }
}
