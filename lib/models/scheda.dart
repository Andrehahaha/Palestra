import 'esercizio.dart';
import 'settimana_piano.dart';

class Scheda {
  String nome;
  String livello;
  String categoria;
  bool continuativa;
  int settimanaCorrente;
  List<Esercizio> esercizi;

  /// Settimane scritte nel piano del coach (settimana -> esercizi).
  /// `null` per le schede create a mano.
  Map<int, List<Esercizio>>? programma;

  /// Indicazioni per settimana (RIR relativo, scarico).
  Map<int, SettimanaPiano>? calendario;

  /// Settimane del programma; dopo l'ultima si riparte da [ripartiDaSettimana].
  int? durataProgramma;

  /// Settimana da cui ripartire a programma finito (1 per schede A/B alternate).
  /// `null` = l'ultima settimana continua uguale.
  int? ripartiDaSettimana;
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
    this.programma,
    this.calendario,
    this.durataProgramma,
    this.ripartiDaSettimana,
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
      if (programma != null)
        'programma': programma!.map((k, v) => MapEntry('$k', v.map((e) => e.toJson()).toList())),
      if (calendario != null) 'calendario': calendario!.map((k, v) => MapEntry('$k', v.toJson())),
      if (durataProgramma != null) 'durataProgramma': durataProgramma,
      if (ripartiDaSettimana != null) 'ripartiDaSettimana': ripartiDaSettimana,
    };
  }

  factory Scheda.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString();
    final isLegacyWithoutId = rawId == null || rawId.trim().isEmpty;

    return Scheda(
      id: (rawId != null && rawId.trim().isNotEmpty)
          ? rawId
          : _legacyIdFromJson(json),
      nome: json['nome'] ?? 'Senza Nome',
      livello: json['livello'] ?? 'Principiante',
      // ECCO IL SALVAVITA: se la categoria non esiste nei vecchi salvataggi, usa 'Generale'
      categoria: json['categoria'] ?? 'Generale', 
      continuativa: json['continuativa'] ?? true,
      settimanaCorrente: isLegacyWithoutId ? 1 : (json['settimanaCorrente'] ?? 1),
      esercizi: (json['esercizi'] as List?)?.map((e) => Esercizio.fromJson(e)).toList() ?? [],
      programma: _programmaDaJson(json['programma']),
      calendario: _calendarioDaJson(json['calendario']),
      durataProgramma: (json['durataProgramma'] as num?)?.toInt(),
      ripartiDaSettimana: (json['ripartiDaSettimana'] as num?)?.toInt(),
    );
  }

  static Map<int, SettimanaPiano>? _calendarioDaJson(dynamic raw) {
    if (raw is! Map) return null;
    final out = <int, SettimanaPiano>{};
    for (final e in raw.entries) {
      final settimana = int.tryParse(e.key.toString().trim());
      final info = SettimanaPiano.fromJson(e.value);
      if (settimana != null && settimana >= 1 && info != null) out[settimana] = info;
    }
    return out;
  }

  static Map<int, List<Esercizio>>? _programmaDaJson(dynamic raw) {
    if (raw is! Map) return null;
    final out = <int, List<Esercizio>>{};
    for (final entry in raw.entries) {
      final settimana = int.tryParse(entry.key.toString().trim());
      final lista = entry.value;
      if (settimana == null || settimana < 1 || lista is! List) continue;
      out[settimana] = lista
          .whereType<Map>()
          .map((e) => Esercizio.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return out;
  }
}