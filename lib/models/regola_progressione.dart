/// Regola di progressione letta dalla scheda del coach per un esercizio
/// (es. "+2,5 kg a settimana dalla 2 alla 6"). I conti li fa l'app.
class RegolaProgressione {
  const RegolaProgressione({
    required this.daSettimana,
    this.aSettimana,
    this.incrementoKg,
    this.incrementoPercentuale,
    this.rirTarget,
    this.nota,
  });

  final int daSettimana;

  /// `null` = fino alla fine del programma.
  final int? aSettimana;
  final double? incrementoKg;
  final double? incrementoPercentuale;
  final String? rirTarget;

  /// Testo originale della regola, come scritto nel foglio.
  final String? nota;

  /// C'è qualcosa da calcolare e l'intervallo ha senso.
  bool get haCalcolo {
    final numeri = incrementoKg != null ||
        incrementoPercentuale != null ||
        (rirTarget != null && rirTarget!.trim().isNotEmpty);
    return numeri && (aSettimana == null || aSettimana! >= daSettimana);
  }

  bool valePer(int settimana) =>
      haCalcolo && settimana >= daSettimana && (aSettimana == null || settimana <= aSettimana!);

  Map<String, dynamic> toJson() => {
        'daSettimana': daSettimana,
        'aSettimana': aSettimana,
        'incrementoKg': incrementoKg,
        'incrementoPercentuale': incrementoPercentuale,
        'rirTarget': rirTarget,
        'nota': nota,
      };

  static RegolaProgressione? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final da = _intero(raw['daSettimana']);
    if (da == null || da < 1) return null;
    final rir = raw['rirTarget']?.toString().trim();
    final nota = raw['nota']?.toString().trim();
    return RegolaProgressione(
      daSettimana: da,
      aSettimana: _intero(raw['aSettimana']),
      incrementoKg: _numero(raw['incrementoKg']),
      incrementoPercentuale: _numero(raw['incrementoPercentuale']),
      rirTarget: (rir == null || rir.isEmpty) ? null : rir,
      nota: (nota == null || nota.isEmpty) ? null : nota,
    );
  }

  static double? _numero(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.').trim());
  }

  static int? _intero(dynamic v) => _numero(v)?.toInt();
}
