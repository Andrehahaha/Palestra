import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/models/esercizio.dart';
import 'package:palestra/models/serie.dart';
import 'package:palestra/screens/training/settimana_successiva_screen.dart';

void main() {
  group('Settimana progression logic', () {
    test('does not erase existing max/percent when inputs are null', () {
      final ex = Esercizio(
        nome: 'Squat',
        avvicinamento: 0,
        workingSet: 2,
        ripetizioni: '5',
        recupero: '120',
        modalitaIntensita: 'percentuale',
        massimaleKg: 200,
        percentualeMassimale: 75,
        serieAttive: [
          Serie(tipo: 'Working Set', percentualeTarget: '75'),
          Serie(tipo: 'Working Set', percentualeTarget: '77.5'),
        ],
      );

      applyProgressioneToExerciseForTest(
        exercise: ex,
        massimaleInput: null,
        percentualeBaseInput: null,
        incrementoPercentuale: 0,
        incrementoKg: null,
      );

      expect(ex.massimaleKg, 200);
      expect(ex.percentualeMassimale, 75);
    });

    test('when percent delta is set, kg increment is not applied on top', () {
      final ex = Esercizio(
        nome: 'Stacco da Terra',
        avvicinamento: 0,
        workingSet: 1,
        ripetizioni: '3',
        recupero: '180',
        modalitaIntensita: 'percentuale',
        massimaleKg: 200,
        percentualeMassimale: 75,
        serieAttive: [
          Serie(tipo: 'Working Set', percentualeTarget: '75'),
        ],
      );

      applyProgressioneToExerciseForTest(
        exercise: ex,
        massimaleInput: 200,
        percentualeBaseInput: 75,
        incrementoPercentuale: 5,
        incrementoKg: 10,
      );

      // 200 * 80% = 160.0 -> rounded to 160.0
      expect(ex.percentualeMassimale, 80);
      expect(ex.caricoTargetKg, 160);
      expect(ex.serieAttive.first.peso, '160.0');
    });
    
      test('override percentuali serie modifica solo le serie indicate', () {
        final esercizio = Esercizio(
          nome: 'Stacco da Terra',
          avvicinamento: 0,
          workingSet: 2,
          ripetizioni: '5',
          recupero: '120',
          modalitaIntensita: 'percentuale',
          percentualeMassimale: 75,
          massimaleKg: 150,
          serieAttive: [
            Serie(tipo: 'Working Set', percentualeTarget: '75'),
            Serie(tipo: 'Working Set', percentualeTarget: '75'),
          ],
        );
    
        applyProgressioneToExerciseForTest(
          exercise: esercizio,
          massimaleInput: 150,
          percentualeBaseInput: 75,
          incrementoPercentuale: 0,
          percentualiSerieOverride: [75, 80],
        );
    
        expect(esercizio.serieAttive[0].percentualeTarget, '75');
        expect(esercizio.serieAttive[1].percentualeTarget, '80');
      });

      test('senza delta o override non sovrascrive carichi custom esistenti', () {
        final esercizio = Esercizio(
          nome: 'Panca Piana',
          avvicinamento: 0,
          workingSet: 2,
          ripetizioni: '5',
          recupero: '120',
          modalitaIntensita: 'percentuale',
          percentualeMassimale: 75,
          massimaleKg: 100,
          serieAttive: [
            Serie(tipo: 'Working Set', percentualeTarget: '75', peso: '70'),
            Serie(tipo: 'Working Set', percentualeTarget: '75', peso: '67.5'),
          ],
        );

        applyProgressioneToExerciseForTest(
          exercise: esercizio,
          massimaleInput: 100,
          percentualeBaseInput: 75,
          incrementoPercentuale: 0,
        );

        expect(esercizio.serieAttive[0].peso, '70');
        expect(esercizio.serieAttive[1].peso, '67.5');
      });

      test('forceRecalculateWeights sovrascrive carichi custom con valori calcolati', () {
        final esercizio = Esercizio(
          nome: 'Panca Piana',
          avvicinamento: 0,
          workingSet: 2,
          ripetizioni: '5',
          recupero: '120',
          modalitaIntensita: 'percentuale',
          percentualeMassimale: 75,
          massimaleKg: 100,
          serieAttive: [
            Serie(tipo: 'Working Set', percentualeTarget: '75', peso: '70'),
            Serie(tipo: 'Working Set', percentualeTarget: '75', peso: '67.5'),
          ],
        );

        applyProgressioneToExerciseForTest(
          exercise: esercizio,
          massimaleInput: 100,
          percentualeBaseInput: 75,
          incrementoPercentuale: 0,
          forceRecalculateWeights: true,
        );

        expect(esercizio.serieAttive[0].peso, '75.0');
        expect(esercizio.serieAttive[1].peso, '75.0');
      });
  });
}
