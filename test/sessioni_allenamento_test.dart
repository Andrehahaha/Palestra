import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/allenamento.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/models/serie.dart';
import 'package:palestra/services/archivio_atleta.dart';
import 'package:palestra/services/sessioni_allenamento.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CloudVuoto implements ArchivioCloud {
  @override
  Future<StatoCloud?> leggi() async => null;
  @override
  Future<void> scriviAppState(Map<String, dynamic> appState) async {}
  @override
  Future<void> scriviPersonalRecords(Map<String, double> pr) async {}
}

class FakeRegistro implements RegistroSessioniCloud {
  final Map<String, Map<String, dynamic>> docs = {};
  final List<String> eliminati = [];
  bool offline = false;

  @override
  Future<void> scrivi(Allenamento sessione, Map<String, dynamic> documento) async {
    if (offline) throw Exception('offline');
    docs[sessione.id] = documento;
  }

  @override
  Future<void> elimina(Allenamento sessione) async {
    if (offline) throw Exception('offline');
    eliminati.add(sessione.id);
    docs.remove(sessione.id);
  }
}

Scheda _scheda() => Scheda(
      nome: 'Push',
      livello: 'Base',
      id: 'sch_push',
      esercizi: [
        Esercizio(
          nome: 'Panca Piana',
          avvicinamento: 1,
          workingSet: 2,
          ripetizioni: '5',
          recupero: '2m',
          serieAttive: [
            Serie(tipo: 'Avvicinamento', peso: '40', isCompletata: true),
            Serie(tipo: 'Working Set', peso: '80', ripetizioniFatte: '5', isCompletata: true),
            Serie(tipo: 'Working Set', peso: '80'),
          ],
        ),
      ],
    );

void main() {
  late ArchivioAtleta archivio;
  late FakeRegistro registro;
  late SessioniAllenamento sessioni;
  final t = DateTime(2026, 3, 1, 18, 30);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    archivio = ArchivioAtleta(cloud: _CloudVuoto(), orologio: () => t);
    registro = FakeRegistro();
    sessioni = SessioniAllenamento(archivio: archivio, registro: registro, orologio: () => t);
  });

  test('completa registra una sola sessione, in locale e nel cloud', () async {
    final scheda = _scheda();
    final sessione = await sessioni.completa(scheda, note: 'Ottimo');

    expect(archivio.storico, hasLength(1));
    expect(archivio.storico.single.id, sessione.id);
    expect(archivio.storico.single.note, 'Ottimo');
    expect(registro.docs.keys, [sessione.id]);
  });

  test('la sessione è una copia: la scheda viene azzerata, lo storico no', () async {
    final scheda = _scheda();
    await sessioni.completa(scheda);

    expect(scheda.esercizi.single.serieAttive.every((s) => !s.isCompletata), isTrue);
    final salvata = archivio.storico.single.scheda.esercizi.single.serieAttive;
    expect(salvata.where((s) => s.isCompletata), hasLength(2));
  });

  test('il documento cloud ha schema completo e riepilogo per il coach', () async {
    final sessione = await sessioni.completa(_scheda(), note: 'Ok');
    final doc = registro.docs[sessione.id]!;

    expect(doc['id'], sessione.id);
    expect(doc['scheda'], isA<Map>());
    expect(doc['feedback_atleta'], 'Ok');
    expect(doc['nomeScheda'], 'Push');
    final es = (doc['esercizi'] as List).single as Map;
    expect(es['nome'], 'Panca Piana');
    expect(es['target_ripetizioni'], '5');
    expect((es['serie'] as List).map((s) => s['peso']), ['40', '80']);

    final riletta = Allenamento.fromJson(Map<String, dynamic>.from(doc));
    expect(riletta.id, sessione.id);
    expect(riletta.scheda.esercizi.single.serieAttive, hasLength(3));
  });

  test('due sessioni nello stesso giorno restano distinte', () async {
    var ora = t;
    sessioni = SessioniAllenamento(archivio: archivio, registro: registro, orologio: () => ora);
    await sessioni.completa(_scheda());
    ora = t.add(const Duration(hours: 2));
    await sessioni.completa(_scheda());
    expect(registro.docs, hasLength(2));
    expect(archivio.storico.map((a) => a.id).toSet(), hasLength(2));
  });

  test('offline la sessione resta salvata in locale', () async {
    registro.offline = true;
    await sessioni.completa(_scheda());
    expect(archivio.storico, hasLength(1));
  });

  test('elimina toglie la sessione da locale e cloud', () async {
    final sessione = await sessioni.completa(_scheda());
    await sessioni.elimina(sessione);
    expect(archivio.storico, isEmpty);
    expect(registro.docs, isEmpty);
    expect(registro.eliminati, [sessione.id]);
  });

  test('registra salva una sessione già costruita (es. test PR)', () async {
    final test = Allenamento(data: t, scheda: _scheda(), note: 'PR panca');
    await sessioni.registra(test);
    expect(archivio.storico.single.note, 'PR panca');
    expect(registro.docs[test.id]!['feedback_atleta'], 'PR panca');
  });

  test('id stabile per dati legacy senza id', () {
    final json = {'data': t.toIso8601String(), 'scheda': _scheda().toJson()};
    expect(Allenamento.fromJson(json).id, Allenamento.fromJson(json).id);
    expect(Allenamento.fromJson(json).id, Allenamento.idDaData(t));
  });
}
