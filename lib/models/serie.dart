class Serie {
  String tipo;
  String peso;
  String ripetizioniFatte;
  bool isCompletata;
  String rpe; // IL NUOVO CAMPO RPE!

  Serie({
    required this.tipo,
    this.peso = '',
    this.ripetizioniFatte = '',
    this.isCompletata = false,
    this.rpe = '',
  });

  factory Serie.fromJson(Map<String, dynamic> json) {
    return Serie(
      tipo: json['tipo'] ?? 'Working Set',
      peso: json['peso'] ?? '',
      ripetizioniFatte: json['ripetizioniFatte'] ?? '',
      isCompletata: json['isCompletata'] ?? false,
      rpe: json['rpe'] ?? '', // Retrocompatibilità: se l'allenamento è vecchio, mette vuoto
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tipo': tipo,
      'peso': peso,
      'ripetizioniFatte': ripetizioniFatte,
      'isCompletata': isCompletata,
      'rpe': rpe,
    };
  }
}