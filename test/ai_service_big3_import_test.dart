import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/services/ai_service.dart';

void main() {
  group('AiService big 3 pass-through', () {
    test('keeps explicit percent fields from generated json', () {
      final raw = [
        {
          'id': 'sch_big3_1',
          'nome': 'Forza A',
          'livello': 'Intermedio',
          'categoria': 'Week 1',
          'continuativa': true,
          'settimanaCorrente': 1,
          'esercizi': [
            {
              'nome': 'Panca piana',
              'avvicinamento': 0,
              'workingSet': 5,
              'ripetizioni': '5',
              'recupero': '180',
              'tecniche': ['Classico'],
              'modalitaIntensita': 'percentuale',
              'percentualeMassimale': 75.0,
              'massimaleKg': 120.0,
            },
          ],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      final es = (parsed.first['esercizi'] as List).first as Map<String, dynamic>;

      expect(es['modalitaIntensita'], 'percentuale');
      expect(es['percentualeMassimale'], 75.0);
      expect(es['massimaleKg'], 120.0);
    });

    test('does not infer percentage from free text when field is absent', () {
      final raw = [
        {
          'id': 'sch_big3_2',
          'nome': 'Forza B',
          'livello': 'Intermedio',
          'categoria': 'Week 1',
          'continuativa': true,
          'settimanaCorrente': 1,
          'esercizi': [
            {
              'nome': 'Squat',
              'avvicinamento': 0,
              'workingSet': 4,
              'ripetizioni': '4x4 82.5%',
              'recupero': '180',
              'tecniche': ['Classico'],
              'modalitaIntensita': 'percentuale',
              'percentualeMassimale': null,
            },
          ],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      final es = (parsed.first['esercizi'] as List).first as Map<String, dynamic>;

      expect(es['percentualeMassimale'], null);
      expect(es['ripetizioni'], '4x4 82.5%');
    });

    test('keeps english names as generated', () {
      final raw = [
        {
          'id': 'sch_big3_3',
          'nome': 'Strength Block',
          'livello': 'Intermedio',
          'categoria': 'Week 2',
          'continuativa': true,
          'settimanaCorrente': 2,
          'esercizi': [
            {
              'nome': 'Deadlift',
              'avvicinamento': 0,
              'workingSet': 3,
              'ripetizioni': '3',
              'recupero': '210',
              'tecniche': ['Classico'],
              'modalitaIntensita': 'rir',
            },
          ],
        },
      ];

      final parsed = AiService.normalizeImportedSchedeForTest(raw);
      final es = (parsed.first['esercizi'] as List).first as Map<String, dynamic>;

      expect(es['nome'], 'Deadlift');
      expect(es['workingSet'], 3);
    });
  });
}
