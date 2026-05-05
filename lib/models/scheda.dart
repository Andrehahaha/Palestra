import 'esercizio.dart';

class Scheda {
  String nome;
  String livello;
  String categoria;
  bool continuativa;
  int settimanaCorrente;
  Map<int, List<Esercizio>> eserciziPerSettimana;
  static int _idCounter = 0;
  String id;

  Scheda({
    required this.nome,
    required this.livello,
    this.categoria = 'Generale',
    String? id,
    this.continuativa = true,
    this.settimanaCorrente = 1,
    List<Esercizio>? esercizi,
    Map<int, List<Esercizio>>? eserciziPerSettimana,
  }) : eserciziPerSettimana = eserciziPerSettimana ??
            (esercizi != null
                ? {settimanaCorrente: esercizi}
                : <int, List<Esercizio>>{}),
       id = (id == null || id.trim().isEmpty)
            ? _newId('$nome|$livello|$categoria')
            : id;

  // esercizi is a transparent getter/setter for the current week's list.
  // putIfAbsent ensures the list reference is stable for in-place mutations (.add, etc.).
  List<Esercizio> get esercizi =>
      eserciziPerSettimana.putIfAbsent(settimanaCorrente, () => <Esercizio>[]);

  set esercizi(List<Esercizio> list) =>
      eserciziPerSettimana[settimanaCorrente] = list;

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
      // Keep flat 'esercizi' for backwards compat with older clients / cloud reads.
      'esercizi': esercizi.map((e) => e.toJson()).toList(),
      'eserciziPerSettimana': eserciziPerSettimana.map(
        (k, v) => MapEntry(k.toString(), v.map((e) => e.toJson()).toList()),
      ),
    };
  }

  factory Scheda.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString();
    final week = (json['settimanaCorrente'] as num?)?.toInt() ?? 1;

    Map<int, List<Esercizio>> eperSett = {};

    final rawPerSett = json['eserciziPerSettimana'];
    if (rawPerSett is Map && rawPerSett.isNotEmpty) {
      for (final entry in rawPerSett.entries) {
        final k = int.tryParse(entry.key.toString());
        if (k == null) continue;
        final v = entry.value;
        if (v is List) {
          eperSett[k] = v
              .map((e) => Esercizio.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    }

    // Backwards compat: wrap legacy flat esercizi into the current week slot.
    if (eperSett.isEmpty) {
      final legacyList = (json['esercizi'] as List?)
              ?.map((e) => Esercizio.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <Esercizio>[];
      eperSett = {week: legacyList};
    }

    return Scheda(
      id: (rawId != null && rawId.trim().isNotEmpty)
          ? rawId
          : _legacyIdFromJson(json),
      nome: json['nome'] ?? 'Senza Nome',
      livello: json['livello'] ?? 'Principiante',
      categoria: json['categoria'] ?? 'Generale',
      continuativa: json['continuativa'] ?? true,
      settimanaCorrente: week,
      eserciziPerSettimana: eperSett,
    );
  }
}
