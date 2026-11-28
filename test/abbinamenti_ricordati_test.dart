import 'package:flutter_test/flutter_test.dart';
import 'package:palestra/services/abbinamenti_ricordati.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ricorda e ricarica, chiave senza maiuscole e spazi in più', () async {
    SharedPreferences.setMockInitialValues({});
    await AbbinamentiRicordati.ricorda({'Hip  thrust ': 'Hip Thrust con Bilanciere'});
    await AbbinamentiRicordati.ricorda({'Pressa 45°': 'Pressa 45°'});
    final tutti = await AbbinamentiRicordati.carica();
    expect(tutti['hip thrust'], 'Hip Thrust con Bilanciere');
    expect(tutti['pressa 45°'], 'Pressa 45°');
  });
}
