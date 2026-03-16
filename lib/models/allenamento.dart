import 'scheda.dart';

class Allenamento {
  DateTime data;
  Scheda scheda;
  String? note; // 👈 AGGIUNTO PER IL FEEDBACK

  Allenamento({
    required this.data,
    required this.scheda,
    this.note,
  });

  factory Allenamento.fromJson(Map<String, dynamic> json) {
    return Allenamento(
      data: DateTime.parse(json['data']),
      scheda: Scheda.fromJson(json['scheda']),
      note: json['feedback_atleta'], // 👈 LEGGE LA NOTA DAL CLOUD/MEMORIA
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.toIso8601String(),
      'scheda': scheda.toJson(),
      'feedback_atleta': note, // 👈 INVIA LA NOTA AL CLOUD/MEMORIA
    };
  }
}