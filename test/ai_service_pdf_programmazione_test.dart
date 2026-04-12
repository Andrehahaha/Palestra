import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/scheda.dart';
import 'package:palestra/services/ai_service.dart';

void main() {
  group('AiService AI import normalization', () {
    test('keeps generated fields unchanged', () {
      final raw = [
        {
          'id': 'ai_week2_day1',
          'nome': 'Week 2 - Seduta A',
          'livello': 'Intermedio',
          'categoria': 'Week 2',
          'continuativa': true,
          'settimanaCorrente': 2,
          'esercizi': [
            {
              'nome': 'Squat',
              'avvicinamento': 1,
              'workingSet': 1,
              'ripetizioni': '1',
              'recupero': '180',
              'tecniche': ['Classico'],
              'modalitaIntensita': 'percentuale',
              'percentualeMassimale': 90,
              'serieAttive': [
                {'tipo': 'Avvicinamento'},
                {'tipo': 'Working Set'},
              ],
            },
          ],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      final scheda = parsed.first;
      final esercizio =
          (scheda['esercizi'] as List).first as Map<String, dynamic>;

      expect(scheda['settimanaCorrente'], 2);
      expect(esercizio['workingSet'], 1);
      expect(esercizio['ripetizioni'], '1');
      expect((esercizio['serieAttive'] as List).length, 2);
    });

    test('without id still keeps provided week', () {
      final raw = [
        {
          'nome': 'Week 3 - Seduta B',
          'livello': 'Intermedio',
          'categoria': 'Week 3',
          'continuativa': true,
          'settimanaCorrente': 3,
          'esercizi': [],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      expect(parsed.first['settimanaCorrente'], 3);
    });

    test('defaults to week 1 only when missing from generated json', () {
      final raw = [
        {
          'nome': 'Giorno 2',
          'livello': 'Intermedio',
          'categoria': 'Importata AI',
          'continuativa': true,
          'esercizi': [],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      expect(parsed.first['settimanaCorrente'], 1);
    });

    test('expands to multiple weeks when only W1 is present but week signal exists', () {
      final raw = [
        {
          'id': 'w1_only_a',
          'nome': 'Week 1 - Seduta A',
          'livello': 'Intermedio',
          'categoria': 'Week 1',
          'continuativa': true,
          'settimanaCorrente': 1,
          'esercizi': [
            {
              'nome': 'Squat',
              'workingSet': 4,
              'ripetizioni': '8-10',
            },
          ],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      final weeks = parsed
          .map((s) => (s['settimanaCorrente'] as num?)?.toInt() ?? 1)
          .toSet();

      expect(weeks.contains(1), isTrue);
      expect(
        weeks.contains(2),
        isTrue,
        reason:
            'weeks=$weeks len=${parsed.length} names=${parsed.map((s) => s['nome']).toList()}',
      );
      expect(parsed.length, greaterThan(1));

      final week1 = parsed.firstWhere(
        (s) => ((s['settimanaCorrente'] as num?)?.toInt() ?? 1) == 1,
      );
      final week2 = parsed.firstWhere(
        (s) => ((s['settimanaCorrente'] as num?)?.toInt() ?? 1) == 2,
      );

      final repsW1 = ((week1['esercizi'] as List).first as Map<String, dynamic>?)?['ripetizioni']
          .toString();
      final repsW2 = ((week2['esercizi'] as List).first as Map<String, dynamic>?)?['ripetizioni']
          .toString();

      expect(repsW1, '8-10');
      expect(repsW2, '9-11');
    });

    test(
      'progresses working-set loads when only W1 exists and weeks are generated',
      () {
        final raw = [
          {
            'id': 'bench_w1',
            'nome': 'Week 1 - Seduta A',
            'livello': 'Intermedio',
            'categoria': 'Week 1',
            'continuativa': true,
            'settimanaCorrente': 1,
            'esercizi': [
              {
                'nome': 'Panca piana',
                'workingSet': 3,
                'ripetizioni': '6',
                'rirTarget': '3',
                'serieAttive': [
                  {
                    'tipo': 'Working Set',
                    'peso': '100',
                    'ripetizioniFatte': '',
                    'isCompletata': false,
                    'rpe': '',
                    'percentualeTarget': '',
                  },
                  {
                    'tipo': 'Working Set',
                    'peso': '100',
                    'ripetizioniFatte': '',
                    'isCompletata': false,
                    'rpe': '',
                    'percentualeTarget': '',
                  },
                  {
                    'tipo': 'Working Set',
                    'peso': '100',
                    'ripetizioniFatte': '',
                    'isCompletata': false,
                    'rpe': '',
                    'percentualeTarget': '',
                  },
                ],
              },
            ],
          },
        ];

        final parsed = AiService.normalizeImportedSchedeForTest(raw);
        final week1 = parsed.firstWhere(
          (s) => ((s['settimanaCorrente'] as num?)?.toInt() ?? 1) == 1,
        );
        final week2 = parsed.firstWhere(
          (s) => ((s['settimanaCorrente'] as num?)?.toInt() ?? 1) == 2,
        );

        final pesoW1 = ((((week1['esercizi'] as List).first as Map<String, dynamic>)['serieAttive'] as List)
                .first as Map<String, dynamic>)['peso']
            .toString();
        final pesoW2 = ((((week2['esercizi'] as List).first as Map<String, dynamic>)['serieAttive'] as List)
                .first as Map<String, dynamic>)['peso']
            .toString();
        final repsW2 = (((week2['esercizi'] as List).first as Map<String, dynamic>)['ripetizioni']
            .toString());
        final rpeW2 = ((((week2['esercizi'] as List).first as Map<String, dynamic>)['serieAttive'] as List)
                .first as Map<String, dynamic>)['rpe']
            .toString();

        expect(pesoW1, '100');
        expect(pesoW2, '102.5');
        expect(repsW2, '7');
        expect(rpeW2, '7.5');
      },
    );

    test(
      'fills and progresses per-series % tag when intensity evolves in percentuale mode',
      () {
        final raw = [
          {
            'id': 'percent_w1',
            'nome': 'Week 1 - Seduta A',
            'livello': 'Intermedio',
            'categoria': 'Week 1',
            'continuativa': true,
            'settimanaCorrente': 1,
            'esercizi': [
              {
                'nome': 'Squat',
                'modalitaIntensita': 'percentuale',
                'percentualeMassimale': 75,
                'massimaleKg': 100,
                'workingSet': 2,
                'ripetizioni': '5',
                'serieAttive': [
                  {
                    'tipo': 'Working Set',
                    'peso': '75',
                    'ripetizioniFatte': '',
                    'isCompletata': false,
                    'rpe': '',
                    'percentualeTarget': '',
                  },
                ],
              },
            ],
          },
        ];

        final parsed = AiService.normalizeImportedSchedeForTest(raw);
        final week2 = parsed.firstWhere(
          (s) => ((s['settimanaCorrente'] as num?)?.toInt() ?? 1) == 2,
        );

        final percentTagW2 = ((((week2['esercizi'] as List).first as Map<String, dynamic>)['serieAttive'] as List)
                .first as Map<String, dynamic>)['percentualeTarget']
            .toString();

        expect(percentTagW2, '77.5');
      },
    );

    test('coalesces week categories into a single folder', () {
      final raw = [
        {
          'id': 'w1_a',
          'nome': 'Forza Base - W1',
          'livello': 'Intermedio',
          'categoria': 'Week 1',
          'continuativa': true,
          'settimanaCorrente': 1,
          'esercizi': [],
        },
        {
          'id': 'w2_a',
          'nome': 'Forza Base - W2',
          'livello': 'Intermedio',
          'categoria': 'Week 2',
          'continuativa': true,
          'settimanaCorrente': 2,
          'esercizi': [],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      final categories = parsed
          .map((s) => (s['categoria'] ?? '').toString())
          .toSet();

      expect(categories.length, 1);
      expect(categories.first, 'Forza Base');
    });

    test('extracts workingSet and reps when present only in tecniche tags', () {
      final raw = [
        {
          'id': 'tag_only_sets',
          'nome': 'Blocco Ipertrofia',
          'livello': 'Intermedio',
          'categoria': 'Week 1',
          'continuativa': true,
          'settimanaCorrente': 1,
          'esercizi': [
            {
              'nome': 'Chest Press',
              'recupero': '120',
              'tecniche': ['4x10', 'Classico'],
            },
          ],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      final scheda = parsed.first;
      final esercizio =
          (scheda['esercizi'] as List).first as Map<String, dynamic>;

      expect(esercizio['workingSet'], 4);
      expect(esercizio['ripetizioni'], '10');
      final tecniche = List<String>.from(esercizio['tecniche'] as List);
      expect(tecniche.contains('4x10'), isFalse);
      expect(tecniche, contains('Classico'));
    });

    test('extracts workingSet from textual set tag', () {
      final raw = [
        {
          'id': 'tag_series_count',
          'nome': 'Forza Tecnica',
          'livello': 'Intermedio',
          'categoria': 'Week 1',
          'continuativa': true,
          'settimanaCorrente': 1,
          'esercizi': [
            {
              'nome': 'Row Machine',
              'ripetizioni': '8',
              'recupero': '90',
              'tecniche': ['4 serie', 'tempo controllato'],
            },
          ],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      final scheda = parsed.first;
      final esercizio =
          (scheda['esercizi'] as List).first as Map<String, dynamic>;

      expect(esercizio['workingSet'], 4);
      expect(esercizio['ripetizioni'], '8');
      final tecniche = List<String>.from(esercizio['tecniche'] as List);
      expect(tecniche.contains('4 serie'), isFalse);
      expect(tecniche, contains('tempo controllato'));
    });

    test('migrates legacy saved schede set/rep tokens from tecniche', () {
      final stored = <Scheda>[
        Scheda.fromJson({
          'id': 'legacy_saved',
          'nome': 'Archivio Storico',
          'livello': 'Intermedio',
          'categoria': 'Generale',
          'continuativa': true,
          'settimanaCorrente': 1,
          'esercizi': [
            {
              'nome': 'Chest Press',
              'avvicinamento': 0,
              'workingSet': 1,
              'ripetizioni': '1',
              'recupero': '120',
              'tecniche': ['4x10', 'tempo controllato'],
            },
          ],
        }),
      ];

      final migrated = AiService.migrateLegacySetRepInSavedSchede(stored);
      final esercizio = migrated.first.esercizi.first;

      expect(esercizio.workingSet, 4);
      expect(esercizio.ripetizioni, '10');
      expect(esercizio.tecniche.contains('4x10'), isFalse);
      expect(esercizio.tecniche, contains('tempo controllato'));
    });

    test(
      'uses progression table hint, propagates set count, and keeps explicit reps',
      () {
        final raw = [
          {
            'id': 'wk1',
            'nome': 'Forza Base - W1',
            'livello': 'Intermedio',
            'categoria': 'Week 1',
            'continuativa': true,
            'settimanaCorrente': 1,
            'esercizi': [
              {
                'nome': 'Leg Press',
                'workingSet': 1,
                'ripetizioni': '1',
                'tecniche': ['4x8', 'controllato'],
              },
            ],
          },
          {
            'id': 'wk2',
            'nome': 'Forza Base - W2',
            'livello': 'Intermedio',
            'categoria': 'Week 2',
            'continuativa': true,
            'settimanaCorrente': 2,
            'esercizi': [
              {
                'nome': 'Leg Press',
                'workingSet': 1,
                'ripetizioni': '8',
                'note': 'Guarda la tabella progressione',
                'tecniche': ['Classico'],
              },
            ],
          },
        ];

        final parsed = AiService.normalizeImportedSchedeForTest(raw);
        final wk2 = parsed.last;
        final esercizioWk2 =
            (wk2['esercizi'] as List).first as Map<String, dynamic>;

        expect(esercizioWk2['workingSet'], 4);
        expect(esercizioWk2['ripetizioni'], '8');
      },
    );

    test(
      'collapses multi-week imports into one scheda per seduta and stores later weeks',
      () {
        final raw = [
          {
            'id': 'a_w1',
            'nome': 'Power Block - Seduta A - W1',
            'livello': 'Intermedio',
            'categoria': 'Power Block',
            'settimanaCorrente': 1,
            'esercizi': [
              {'nome': 'Squat', 'workingSet': 4, 'ripetizioni': '6'},
            ],
          },
          {
            'id': 'a_w2',
            'nome': 'Power Block - Seduta A - W2',
            'livello': 'Intermedio',
            'categoria': 'Power Block',
            'settimanaCorrente': 2,
            'esercizi': [
              {'nome': 'Squat', 'workingSet': 4, 'ripetizioni': '5'},
            ],
          },
          {
            'id': 'b_w1',
            'nome': 'Power Block - Seduta B - W1',
            'livello': 'Intermedio',
            'categoria': 'Power Block',
            'settimanaCorrente': 1,
            'esercizi': [
              {'nome': 'Panca piana', 'workingSet': 4, 'ripetizioni': '6'},
            ],
          },
          {
            'id': 'b_w2',
            'nome': 'Power Block - Seduta B - W2',
            'livello': 'Intermedio',
            'categoria': 'Power Block',
            'settimanaCorrente': 2,
            'esercizi': [
              {'nome': 'Panca piana', 'workingSet': 4, 'ripetizioni': '5'},
            ],
          },
        ];

        final parsedMaps = AiService.normalizeImportedSchedeForTest(raw);
        final parsedSchede = parsedMaps.map(Scheda.fromJson).toList();
        final resolved = AiService.collapseImportedSchedeForWeeklyProgression(
          parsedSchede,
        );

        expect(resolved.schedeVisibili.length, 2);
        expect(resolved.weekHistoryStoreEntries.length, 2);

        final sedutaA = resolved.schedeVisibili.firstWhere(
          (s) => s.nome.contains('Seduta A'),
        );
        expect(sedutaA.nome.contains('W1'), isFalse);
        expect(sedutaA.settimanaCorrente, 1);

        final sedutaAHistory = resolved.weekHistoryStoreEntries[sedutaA.id];
        expect(sedutaAHistory, isNotNull);
        expect(sedutaAHistory!.containsKey('2'), isTrue);
      },
    );

    test('keeps single-week imports unchanged', () {
      final raw = [
        {
          'id': 'single_day',
          'nome': 'Upper Day',
          'livello': 'Intermedio',
          'categoria': 'Upper Lower',
          'settimanaCorrente': 1,
          'esercizi': [
            {'nome': 'Chest Press', 'workingSet': 3, 'ripetizioni': '10'},
          ],
        },
      ];

      final parsedMaps = AiService.normalizeImportedSchedeForTest(raw);
      final parsedSchede = parsedMaps.map(Scheda.fromJson).toList();
      final resolved = AiService.collapseImportedSchedeForWeeklyProgression(
        parsedSchede,
      );

      expect(resolved.schedeVisibili.length, 1);
      expect(resolved.weekHistoryStoreEntries.isEmpty, isTrue);
      expect(resolved.schedeVisibili.first.nome, 'Upper Day');
    });

    test(
      'single-week collapse resets visible week to 1 and refreshes import id',
      () {
        final raw = [
          {
            'id': 'single_week2',
            'nome': 'Week 2 - Upper Day',
            'livello': 'Intermedio',
            'categoria': 'Upper Lower',
            'settimanaCorrente': 2,
            'esercizi': [
              {'nome': 'Chest Press', 'workingSet': 3, 'ripetizioni': '10'},
            ],
          },
        ];

        final parsedMaps = AiService.normalizeImportedSchedeForTest(raw);
        final parsedSchede = parsedMaps.map(Scheda.fromJson).toList();
        final resolved = AiService.collapseImportedSchedeForWeeklyProgression(
          parsedSchede,
        );

        expect(resolved.schedeVisibili.length, 1);
        expect(resolved.schedeVisibili.first.settimanaCorrente, 1);
        expect(resolved.schedeVisibili.first.id, isNot('single_week2'));
      },
    );
  });
}
