import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/services/ai_service.dart';

void main() {
  group('AiService big 3 percent import', () {
    test('imports percentage for panca piana', () {
      final raw = [
        {
          'nome': 'Forza A',
          'esercizi': [
            {
              'nome': 'Panca piana',
              'workingSet': 5,
              'ripetizioni': '5x5 @ 75%',
              'note': '1RM 120kg',
            },
          ],
        },
      ];

      final normalized = AiService.normalizeImportedSchedeForTest(raw);
      final es = normalized.first['esercizi'][0] as Map<String, dynamic>;

      expect(es['modalitaIntensita'], 'percentuale');
      expect(es['percentualeMassimale'], 75.0);
      expect(es['massimaleKg'], 120.0);
    });

    test('imports percentage for squat', () {
      final raw = [
        {
          'nome': 'Forza B',
          'esercizi': [
            {
              'nome': 'Squat',
              'workingSet': 4,
              'ripetizioni': '4x4 82.5%',
            },
          ],
        },
      ];

      final normalized = AiService.normalizeImportedSchedeForTest(raw);
      final es = normalized.first['esercizi'][0] as Map<String, dynamic>;

      expect(es['modalitaIntensita'], 'percentuale');
      expect(es['percentualeMassimale'], 82.5);
    });

    test('imports percentage for deadlift/stacco', () {
      final raw = [
        {
          'nome': 'Forza C',
          'esercizi': [
            {
              'nome': 'Stacco da terra',
              'workingSet': 3,
              'ripetizioni': '3x3 al 70%',
              'note': 'massimale 190kg',
            },
          ],
        },
      ];

      final normalized = AiService.normalizeImportedSchedeForTest(raw);
      final es = normalized.first['esercizi'][0] as Map<String, dynamic>;

      expect(es['modalitaIntensita'], 'percentuale');
      expect(es['percentualeMassimale'], 70.0);
      expect(es['massimaleKg'], 190.0);
    });

    test('imports percentage for english big 3 names', () {
      final raw = [
        {
          'nome': 'Strength Block',
          'esercizi': [
            {
              'nome': 'Bench Press',
              'workingSet': 5,
              'ripetizioni': '5x3 @ 80%',
            },
            {
              'nome': 'Back Squat',
              'workingSet': 4,
              'ripetizioni': '4x4 77.5%',
            },
            {
              'nome': 'Deadlift',
              'workingSet': 3,
              'ripetizioni': '3x2 at 85%',
              'note': '1RM 210kg',
            },
          ],
        },
      ];

      final normalized = AiService.normalizeImportedSchedeForTest(raw);
      final exercises = normalized.first['esercizi'] as List<dynamic>;

      final bench = exercises[0] as Map<String, dynamic>;
      final squat = exercises[1] as Map<String, dynamic>;
      final deadlift = exercises[2] as Map<String, dynamic>;

      expect(bench['modalitaIntensita'], 'percentuale');
      expect(bench['percentualeMassimale'], 80.0);

      expect(squat['modalitaIntensita'], 'percentuale');
      expect(squat['percentualeMassimale'], 77.5);

      expect(deadlift['modalitaIntensita'], 'percentuale');
      expect(deadlift['percentualeMassimale'], 85.0);
      expect(deadlift['massimaleKg'], 210.0);
    });

    test('imports percentage from text variants without % symbol', () {
      final raw = [
        {
          'nome': 'Forza D',
          'esercizi': [
            {
              'nome': 'Panca piana',
              'workingSet': 4,
              'ripetizioni': '4x6 all\'80 percento',
            },
            {
              'nome': 'Squat',
              'workingSet': 5,
              'note': 'lavoro per cento: 72.5 per cento',
            },
            {
              'nome': 'Deadlift',
              'workingSet': 3,
              'ripetizioni': '3x3 al 78',
            },
          ],
        },
      ];

      final normalized = AiService.normalizeImportedSchedeForTest(raw);
      final exercises = normalized.first['esercizi'] as List<dynamic>;

      final bench = exercises[0] as Map<String, dynamic>;
      final squat = exercises[1] as Map<String, dynamic>;
      final deadlift = exercises[2] as Map<String, dynamic>;

      expect(bench['modalitaIntensita'], 'percentuale');
      expect(bench['percentualeMassimale'], 80.0);

      expect(squat['modalitaIntensita'], 'percentuale');
      expect(squat['percentualeMassimale'], 72.5);

      expect(deadlift['modalitaIntensita'], 'percentuale');
      expect(deadlift['percentualeMassimale'], 78.0);
    });

    test('db fallback fills missing massimale from personal_records', () {
      final raw = [
        {
          'nome': 'Forza E',
          'esercizi': [
            {
              'nome': 'Panca piana',
              'modalitaIntensita': 'percentuale',
              'percentualeMassimale': 80,
              'massimaleKg': null,
            },
          ],
        },
      ];

      final normalized = AiService.normalizeImportedSchedeForTest(raw);
      final withFallback = AiService.applyPersonalRecordsFallbackForTest(
        normalized,
        {
          'Panca Piana': 125.0,
          'Squat': 180.0,
        },
      );

      final es = withFallback.first['esercizi'][0] as Map<String, dynamic>;
      expect(es['massimaleKg'], 125.0);
      expect(es['caricoTargetKg'], 100.0);
    });

    test('db alias with noisy symbols maps to panca piana', () {
      final raw = [
        {
          'nome': 'Forza F',
          'esercizi': [
            {
              'nome': 'panca piana con bilanciere)presa media=)',
              'modalitaIntensita': 'percentuale',
              'percentualeMassimale': 70,
              'massimaleKg': null,
            },
          ],
        },
      ];

      final normalized = AiService.normalizeImportedSchedeForTest(raw);
      final withFallback = AiService.applyPersonalRecordsFallbackForTest(
        normalized,
        {
          'Panca Piana': 120.0,
        },
      );

      final es = withFallback.first['esercizi'][0] as Map<String, dynamic>;
      expect(es['massimaleKg'], 120.0);
      expect(es['caricoTargetKg'], 84.0);
    });

    test('db fallback maps stacco alias and computes target load', () {
      final raw = [
        {
          'nome': 'Forza G',
          'esercizi': [
            {
              'nome': 'Stacco da terra con bilanciere',
              'modalitaIntensita': 'percentuale',
              'percentualeMassimale': 75,
              'massimaleKg': null,
            },
          ],
        },
      ];

      final normalized = AiService.normalizeImportedSchedeForTest(raw);
      final withFallback = AiService.applyPersonalRecordsFallbackForTest(
        normalized,
        {
          'Stacco da Terra': 200.0,
        },
      );

      final es = withFallback.first['esercizi'][0] as Map<String, dynamic>;
      expect(es['massimaleKg'], 200.0);
      expect(es['caricoTargetKg'], 150.0);
    });
  });
}
