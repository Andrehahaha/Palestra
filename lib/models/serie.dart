class Serie {
  String tipo;
  String peso;
  String ripetizioniFatte;
  bool isCompletata;
  String rpe; // IL NUOVO CAMPO RPE
  String percentualeTarget;

  Serie({
    required this.tipo,
    this.peso = '',
    this.ripetizioniFatte = '',
    this.isCompletata = false,
    this.rpe = '',
    this.percentualeTarget = '',
  });

  factory Serie.fromJson(Map<String, dynamic> json) {
    return Serie(
      tipo: json['tipo'] ?? 'Working Set',
      peso: json['peso'] ?? '',
      ripetizioniFatte: json['ripetizioniFatte'] ?? '',
      isCompletata: json['isCompletata'] ?? false,
      rpe: json['rpe'] ?? '', // Retrocompatibilità: se l'allenamento è vecchio, mette vuoto
      percentualeTarget: json['percentualeTarget'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tipo': tipo,
      'peso': peso,
      'ripetizioniFatte': ripetizioniFatte,
      'isCompletata': isCompletata,
      'rpe': rpe,
      'percentualeTarget': percentualeTarget,
    };
  }
}