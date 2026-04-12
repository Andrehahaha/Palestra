import 'esercizio.dart';

class Scheda {
  String nome;
  String livello;
  String categoria;
  bool continuativa;
  int settimanaCorrente;
  List<Esercizio> esercizi;
  static int _idCounter = 0;
  String id;

  Scheda({
    required this.nome,
    required this.livello,
    this.categoria = 'Generale',
    String? id,
    this.continuativa = true,
    this.settimanaCorrente = 1,
    required this.esercizi,
  }) : id = (id == null || id.trim().isEmpty)
            ? _newId('$nome|$livello|$categoria')
            : id;

  static String _newId([String seed = '']) {
    _idCounter += 1;
    final ts = DateTime.now().microsecondsSinceEpoch;
    return 'sch_${ts}_${_idCounter}_${seed.hashCode.abs()}';
  }

  static int _stableChecksum(String input) {
    // Deterministic checksum to keep legacy IDs stable across app restarts.
    var hash = 5381;
    for (final c in input.codeUnits) {
      hash = ((hash << 5) + hash) ^ c;
      hash &= 0x7fffffff;
    }
    return hash;
  }

  static String _legacyIdFromJson(Map<String, dynamic> json) {
    final nome = (json['nome'] ?? '').toString();
    final livello = (json['livello'] ?? '').toString();
    final categoria = (json['categoria'] ?? '').toString();

    final eserciziRaw = json['esercizi'];
    final eserciziNames = <String>[];
    if (eserciziRaw is List) {
      for (final e in eserciziRaw) {
        if (e is Map) {
          eserciziNames.add((e['nome'] ?? '').toString());
        }
      }
    }

    final seed = '$nome|$livello|$categoria|${eserciziNames.join(',')}';
    return 'legacy_${_stableChecksum(seed)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'livello': livello,
      'categoria': categoria,
      'continuativa': continuativa,
      'settimanaCorrente': settimanaCorrente,
      'esercizi': esercizi.map((e) => e.toJson()).toList(),
    };
  }

  factory Scheda.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString();

    return Scheda(
      id: (rawId != null && rawId.trim().isNotEmpty)
          ? rawId
          : _legacyIdFromJson(json),
      nome: json['nome'] ?? 'Senza Nome',
      livello: json['livello'] ?? 'Principiante',
      // ECCO IL SALVAVITA: se la categoria non esiste nei vecchi salvataggi, usa 'Generale'
      categoria: json['categoria'] ?? 'Generale', 
      continuativa: json['continuativa'] ?? true,
      settimanaCorrente: json['settimanaCorrente'] ?? 1,
      esercizi: (json['esercizi'] as List?)?.map((e) => Esercizio.fromJson(e)).toList() ?? [],
    );
  }
}