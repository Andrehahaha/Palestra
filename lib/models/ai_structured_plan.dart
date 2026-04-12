class AiSetDelta {
  final int s;
  final String? r;
  final String? kg;
  final String? rest;

  const AiSetDelta({required this.s, this.r, this.kg, this.rest});

  factory AiSetDelta.fromJson(Map<String, dynamic> json) {
    final parsedS = _toIntOrNull(json['s']) ?? 1;
    return AiSetDelta(
      s: parsedS,
      r: _toNullableString(json['r']),
      kg: _toNullableString(json['kg']),
      rest: _toNullableString(json['rest']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      's': s,
      if (r != null && r!.trim().isNotEmpty) 'r': r,
      if (kg != null && kg!.trim().isNotEmpty) 'kg': kg,
      if (rest != null && rest!.trim().isNotEmpty) 'rest': rest,
    };
  }
}

class AiWeekExerciseDelta {
  final String idEs;
  final String status;
  final String? oldIdEs;
  final int? idx;
  final int? pos;
  final List<AiSetDelta> serie;
  final String? note;
  final String? metodo;
  final List<String> tecniche;
  final String? modalitaIntensita;
  final String? rirTarget;
  final double? percentualeMassimale;
  final double? massimaleKg;
  final double? caricoTargetKg;

  const AiWeekExerciseDelta({
    required this.idEs,
    this.status = 'active',
    this.oldIdEs,
    this.idx,
    this.pos,
    this.serie = const [],
    this.note,
    this.metodo,
    this.tecniche = const [],
    this.modalitaIntensita,
    this.rirTarget,
    this.percentualeMassimale,
    this.massimaleKg,
    this.caricoTargetKg,
  });

  factory AiWeekExerciseDelta.fromJson(Map<String, dynamic> json) {
    final serieRaw = json['serie'];
    final serie = (serieRaw is List)
        ? serieRaw
              .whereType<Map>()
              .map((e) => AiSetDelta.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const <AiSetDelta>[];

    final tecnicheRaw = json['tecniche'];
    final tecniche = (tecnicheRaw is List)
        ? tecnicheRaw
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
        : const <String>[];

    return AiWeekExerciseDelta(
      idEs: (json['id_es'] ?? '').toString(),
      status:
          ((json['status'] ?? 'active').toString().trim().toLowerCase() ==
              'removed')
          ? 'removed'
          : 'active',
      oldIdEs: _toNullableString(json['old_id_es']),
      idx: _toIntOrNull(json['idx']),
      pos: _toIntOrNull(json['pos']),
      serie: serie,
      note: _toNullableString(json['note']),
      metodo: _toNullableString(json['metodo']),
      tecniche: tecniche,
      modalitaIntensita: _toNullableString(json['modalitaIntensita']),
      rirTarget: _toNullableString(json['rirTarget']),
      percentualeMassimale: _toDoubleOrNull(json['percentualeMassimale']),
      massimaleKg: _toDoubleOrNull(json['massimaleKg']),
      caricoTargetKg: _toDoubleOrNull(json['caricoTargetKg']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_es': idEs,
      if (status != 'active') 'status': status,
      if (oldIdEs != null && oldIdEs!.trim().isNotEmpty) 'old_id_es': oldIdEs,
      if (idx != null) 'idx': idx,
      if (pos != null) 'pos': pos,
      if (serie.isNotEmpty) 'serie': serie.map((s) => s.toJson()).toList(),
      if (note != null && note!.trim().isNotEmpty) 'note': note,
      if (metodo != null && metodo!.trim().isNotEmpty) 'metodo': metodo,
      if (tecniche.isNotEmpty) 'tecniche': tecniche,
      if (modalitaIntensita != null && modalitaIntensita!.trim().isNotEmpty)
        'modalitaIntensita': modalitaIntensita,
      if (rirTarget != null && rirTarget!.trim().isNotEmpty)
        'rirTarget': rirTarget,
      if (percentualeMassimale != null)
        'percentualeMassimale': percentualeMassimale,
      if (massimaleKg != null) 'massimaleKg': massimaleKg,
      if (caricoTargetKg != null) 'caricoTargetKg': caricoTargetKg,
    };
  }
}

class AiAllenamentoStructured {
  final String idAllenamento;
  final String titolo;
  final Map<String, List<AiWeekExerciseDelta>> weeks;

  const AiAllenamentoStructured({
    required this.idAllenamento,
    required this.titolo,
    required this.weeks,
  });

  factory AiAllenamentoStructured.fromJson(Map<String, dynamic> json) {
    final weeksRaw = json['weeks'];
    final weeks = <String, List<AiWeekExerciseDelta>>{};

    if (weeksRaw is Map) {
      for (final entry in weeksRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is! List) continue;

        final mapped = value
            .whereType<Map>()
            .map(
              (e) => AiWeekExerciseDelta.fromJson(Map<String, dynamic>.from(e)),
            )
            .where((e) => e.idEs.trim().isNotEmpty)
            .toList();

        weeks[key] = mapped;
      }
    }

    return AiAllenamentoStructured(
      idAllenamento: (json['id_allenamento'] ?? '').toString(),
      titolo: (json['titolo'] ?? '').toString(),
      weeks: weeks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_allenamento': idAllenamento,
      'titolo': titolo,
      'weeks': weeks.map(
        (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()),
      ),
    };
  }
}

class AiStructuredPlan {
  final String schedaId;
  final String nomeScheda;
  final List<AiAllenamentoStructured> allenamenti;

  const AiStructuredPlan({
    required this.schedaId,
    required this.nomeScheda,
    required this.allenamenti,
  });

  factory AiStructuredPlan.fromJson(Map<String, dynamic> json) {
    final allenamentiRaw = json['allenamenti'];
    final allenamenti = (allenamentiRaw is List)
        ? allenamentiRaw
              .whereType<Map>()
              .map(
                (e) => AiAllenamentoStructured.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : const <AiAllenamentoStructured>[];

    return AiStructuredPlan(
      schedaId: (json['scheda_id'] ?? '').toString(),
      nomeScheda: (json['nome_scheda'] ?? '').toString(),
      allenamenti: allenamenti,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scheda_id': schedaId,
      'nome_scheda': nomeScheda,
      'allenamenti': allenamenti.map((a) => a.toJson()).toList(),
    };
  }
}

int? _toIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _toDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.'));
}

String? _toNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
