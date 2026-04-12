import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/scheda.dart';

void main() {
  group('Scheda legacy defaults', () {
    test('without id keeps provided week', () {
      final scheda = Scheda.fromJson({
        'nome': 'Forza A',
        'livello': 'Intermedio',
        'categoria': 'Test',
        'settimanaCorrente': 4,
        'esercizi': [],
      });

      expect(scheda.id.isNotEmpty, true);
      expect(scheda.settimanaCorrente, 4);
    });

    test('with id keeps saved week', () {
      final scheda = Scheda.fromJson({
        'id': 'sch_fixed_1',
        'nome': 'Forza B',
        'livello': 'Intermedio',
        'categoria': 'Test',
        'settimanaCorrente': 3,
        'esercizi': [],
      });

      expect(scheda.id, 'sch_fixed_1');
      expect(scheda.settimanaCorrente, 3);
    });
  });
}
