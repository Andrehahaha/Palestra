import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/allenamento.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/services/archivio_atleta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adapter in memoria che si comporta come Firestore per `users/{uid}`.
class FakeCloud implements ArchivioCloud {
  FakeCloud({this.appState, this.updatedAt, Map<String, double>? pr, this.orologio})
      : pr = pr ?? {};

  Map<String, dynamic>? appState;
  DateTime? updatedAt;
  Map<String, double> pr;
  DateTime Function()? orologio;
  int scrittureAppState = 0;
  bool offline = false;

  @override
  Future<StatoCloud?> leggi() async {
    if (offline) return null;
    return StatoCloud(
      appState: appState == null ? null : jsonDecode(jsonEncode(appState)) as Map<String, dynamic>,
      updatedAt: updatedAt,
      personalRecords: Map.of(pr),
    );
  }

  @override
  Future<void> scriviAppState(Map<String, dynamic> nuovo) async {
    if (offline) throw Exception('offline');
    scrittureAppState++;
    appState = jsonDecode(jsonEncode(nuovo)) as Map<String, dynamic>;
    updatedAt = (orologio ?? DateTime.now)();
  }

  @override
  Future<void> scriviPersonalRecords(Map<String, double> nuovi) async {
    if (offline) throw Exception('offline');
    pr = Map.of(nuovi);
  }
}

Scheda _scheda(String nome) => Scheda(nome: nome, livello: 'Base', id: 'id_$nome', esercizi: []);

Map<String, Object> _localeConSchede(List<String> nomi, DateTime ts) => {
      'schede_salvate': jsonEncode(nomi.map((n) => _scheda(n).toJson()).toList()),
      'storico_salvato': '[]',
      'app_state_updated_at_local': ts.toIso8601String(),
    };

void main() {
  final t1 = DateTime(2026, 1, 1, 10);
  final t2 = DateTime(2026, 1, 2, 10);
  final t3 = DateTime(2026, 1, 3, 10);

  group('carica', () {
    test('senza stato locale usa il cloud', () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = FakeCloud(
        appState: {
          'schede_salvate': [_scheda('Cloud').toJson()],
          'storico_salvato': [],
          'zona_stretching': 'Collo',
          'tipo_dolore': 'muscolare',
        },
        updatedAt: t1,
      );
      final a = ArchivioAtleta(cloud: cloud, orologio: () => t2);
      await a.carica();
      expect(a.schede.map((s) => s.nome), ['Cloud']);
      expect(a.zonaStretching, 'Collo');
      expect(a.tipoDolore, 'muscolare');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('schede_salvate'), contains('Cloud'));
    });

    test('stato locale più recente vince sul cloud', () async {
      SharedPreferences.setMockInitialValues(_localeConSchede(['Locale'], t2));
      final cloud = FakeCloud(appState: {'schede_salvate': [_scheda('Cloud').toJson()]}, updatedAt: t1);
      final a = ArchivioAtleta(cloud: cloud, orologio: () => t3);
      await a.carica();
      expect(a.schede.map((s) => s.nome), ['Locale']);
    });

    test('cloud più recente vince sul locale', () async {
      SharedPreferences.setMockInitialValues(_localeConSchede(['Locale'], t1));
      final cloud = FakeCloud(appState: {'schede_salvate': [_scheda('Cloud').toJson()]}, updatedAt: t2);
      final a = ArchivioAtleta(cloud: cloud, orologio: () => t3);
      await a.carica();
      expect(a.schede.map((s) => s.nome), ['Cloud']);
    });

    test('offline usa solo il locale', () async {
      SharedPreferences.setMockInitialValues(_localeConSchede(['Locale'], t1));
      final a = ArchivioAtleta(cloud: FakeCloud()..offline = true, orologio: () => t3);
      await a.carica();
      expect(a.schede.map((s) => s.nome), ['Locale']);
    });

    test('chiamate concorrenti leggono il cloud una volta sola', () async {
      SharedPreferences.setMockInitialValues({});
      var letture = 0;
      final cloud = _CountingCloud(() => letture++);
      final a = ArchivioAtleta(cloud: cloud, orologio: () => t1);
      await Future.wait([a.carica(), a.carica(), a.carica()]);
      expect(letture, 1);
    });
  });

  group('salva', () {
    test('invia sempre lo stato completo e aggiorna il timestamp locale', () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = FakeCloud(orologio: () => t2);
      final a = ArchivioAtleta(cloud: cloud, orologio: () => t2);
      await a.carica();
      a.schede.add(_scheda('A'));
      a.storico.add(Allenamento(data: t1, scheda: _scheda('A')));
      a.cartelleVuote.add('Forza');
      await a.salva();

      expect((cloud.appState!['schede_salvate'] as List).length, 1);
      expect((cloud.appState!['storico_salvato'] as List).length, 1);
      expect(cloud.appState!['cartelle_vuote'], ['Forza']);
      expect(cloud.appState!['zona_stretching'], 'Lombare');
      expect(cloud.appState!.containsKey('week_history_store'), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_state_updated_at_local'), t2.toIso8601String());
    });

    test('cambiare la zona dopo una modifica offline non perde le schede', () async {
      // Regressione: prima la zona veniva scritta da sola nel cloud con un
      // nuovo updated_at, e al caricamento successivo il cloud (vecchio)
      // sovrascriveva schede e storico locali.
      SharedPreferences.setMockInitialValues(_localeConSchede(['A'], t1));
      final cloud = FakeCloud(appState: {'schede_salvate': [_scheda('A').toJson()]}, updatedAt: t1, orologio: () => t3);
      final a = ArchivioAtleta(cloud: cloud, orologio: () => t2);
      await a.carica();

      cloud.offline = true;
      a.schede.add(_scheda('B'));
      await a.salva();

      cloud.offline = false;
      await a.impostaZona('Collo');

      final riavvio = ArchivioAtleta(cloud: cloud, orologio: () => t3);
      await riavvio.carica();
      expect(riavvio.schede.map((s) => s.nome), ['A', 'B']);
      expect(riavvio.zonaStretching, 'Collo');
    });

    test('salvaWeekHistory resta locale finché non richiesto', () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = FakeCloud();
      final a = ArchivioAtleta(cloud: cloud, orologio: () => t1);
      await a.carica();
      a.weekHistory['id_A'] = {'1': {'nome': 'A'}};
      await a.salvaWeekHistory();
      expect(cloud.scrittureAppState, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('week_history_store_v1'), contains('id_A'));

      await a.salvaWeekHistory(cloud: true);
      expect(cloud.scrittureAppState, 1);
      expect(cloud.appState!['week_history_store'], contains('id_A'));
    });

    test('notifica i listener', () async {
      SharedPreferences.setMockInitialValues({});
      final a = ArchivioAtleta(cloud: FakeCloud(), orologio: () => t1);
      await a.carica();
      var notifiche = 0;
      a.addListener(() => notifiche++);
      await a.salva();
      expect(notifiche, 1);
    });
  });

  group('personal records', () {
    test('caricaPr unisce locale e cloud, il cloud vince', () async {
      SharedPreferences.setMockInitialValues({
        'personal_records': jsonEncode({'Squat': 100, 'Panca Piana': 80}),
      });
      final a = ArchivioAtleta(cloud: FakeCloud(pr: {'Squat': 120}), orologio: () => t1);
      final pr = await a.caricaPr();
      expect(pr, {'Squat': 120.0, 'Panca Piana': 80.0});
    });

    test('salvaPr aggiunge voci in locale e nel cloud', () async {
      SharedPreferences.setMockInitialValues({
        'personal_records': jsonEncode({'Squat': 100}),
      });
      final cloud = FakeCloud();
      final a = ArchivioAtleta(cloud: cloud, orologio: () => t1);
      await a.salvaPr({'Panca Piana': 90});
      expect(cloud.pr, {'Squat': 100.0, 'Panca Piana': 90.0});
      expect(await a.prLocali(), {'Squat': 100.0, 'Panca Piana': 90.0});
    });

    test('salvaPr con sostituisci rimpiazza il locale', () async {
      SharedPreferences.setMockInitialValues({
        'personal_records': jsonEncode({'Squat': 100}),
      });
      final a = ArchivioAtleta(cloud: FakeCloud(), orologio: () => t1);
      await a.salvaPr({'Stacco da Terra': 150}, sostituisci: true);
      expect(await a.prLocali(), {'Stacco da Terra': 150.0});
    });
  });
}

class _CountingCloud extends FakeCloud {
  _CountingCloud(this.onRead);
  final void Function() onRead;

  @override
  Future<StatoCloud?> leggi() async {
    onRead();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return super.leggi();
  }
}
