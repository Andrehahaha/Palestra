import 'serie.dart';

class Esercizio {
  final String nome;
  final int avvicinamento;
  final int workingSet;
  final String ripetizioni;
  final String recupero;
  final String? note;
  final List<String> tecniche; 
  List<Serie> serieAttive;

  Esercizio({
    required this.nome,
    required this.avvicinamento,
    required this.workingSet,
    required this.ripetizioni,
    required this.recupero,
    this.note,
    this.tecniche = const ['Classico'], 
    List<Serie>? serieAttive,
  }) : serieAttive = serieAttive ?? [];

  Map<String, dynamic> toJson() {
    return {
      'nome': nome,
      'avvicinamento': avvicinamento,
      'workingSet': workingSet,
      'ripetizioni': ripetizioni,
      'recupero': recupero,
      'note': note,
      'tecniche': tecniche,
      'serieAttive': serieAttive.map((s) => s.toJson()).toList(),
    };
  }

  factory Esercizio.fromJson(Map<String, dynamic> json) {
    int avv = json['avvicinamento'] ?? 0;
    int work = json['workingSet'] ?? 3;
    
    // LOGICA PUNTO 3: Creazione automatica delle righe
    List<Serie> serieGenerate = [];
    
    // Se nel JSON non ci sono serie salvate, le creiamo noi basandoci sui numeri
    if (json['serieAttive'] == null || (json['serieAttive'] as List).isEmpty) {
      for (int i = 0; i < avv; i++) {
        serieGenerate.add(Serie(tipo: 'Avvicinamento'));
      }
      for (int i = 0; i < work; i++) {
        serieGenerate.add(Serie(tipo: 'Working Set'));
      }
    }

    return Esercizio(
      nome: json['nome'] ?? 'Esercizio',
      avvicinamento: avv,
      workingSet: work,
      ripetizioni: json['ripetizioni'] ?? '',
      recupero: json['recupero'] ?? '',
      note: json['note'],
      tecniche: json['tecniche'] != null ? List<String>.from(json['tecniche']) : ['Classico'],
      serieAttive: json['serieAttive'] != null && (json['serieAttive'] as List).isNotEmpty
          ? (json['serieAttive'] as List).map((e) => Serie.fromJson(e)).toList()
          : serieGenerate, 
    );
  }
}