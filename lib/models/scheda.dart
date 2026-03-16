import 'esercizio.dart';

class Scheda {
  String nome;
  String livello;
  String categoria;
  List<Esercizio> esercizi;

  Scheda({
    required this.nome,
    required this.livello,
    this.categoria = 'Generale',
    required this.esercizi,
  });

  Map<String, dynamic> toJson() {
    return {
      'nome': nome,
      'livello': livello,
      'categoria': categoria,
      'esercizi': esercizi.map((e) => e.toJson()).toList(),
    };
  }

  factory Scheda.fromJson(Map<String, dynamic> json) {
    return Scheda(
      nome: json['nome'] ?? 'Senza Nome',
      livello: json['livello'] ?? 'Principiante',
      // ECCO IL SALVAVITA: se la categoria non esiste nei vecchi salvataggi, usa 'Generale'
      categoria: json['categoria'] ?? 'Generale', 
      esercizi: (json['esercizi'] as List?)?.map((e) => Esercizio.fromJson(e)).toList() ?? [],
    );
  }
}