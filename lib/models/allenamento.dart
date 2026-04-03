import 'scheda.dart';
import 'esercizio.dart';
import 'serie.dart';

DateTime _parseDate(dynamic raw) {
  if (raw == null) return DateTime.now();
  if (raw is DateTime) return raw;

  // Gestisce Firestore Timestamp senza dipendere dal package cloud_firestore nel model.
  final dyn = raw as dynamic;
  try {
    final dt = dyn.toDate();
    if (dt is DateTime) return dt;
  } catch (_) {}

  return DateTime.tryParse(raw.toString()) ?? DateTime.now();
}

List<Serie> _parseSerieLegacy(dynamic rawSerie) {
  if (rawSerie is! List) return [];
  return rawSerie
      .whereType<Map>()
      .map((row) {
        final m = Map<String, dynamic>.from(row);
        return Serie(
          tipo: (m['tipo'] ?? 'Working Set').toString(),
          peso: (m['peso'] ?? '').toString(),
          ripetizioniFatte: (m['ripetizioniFatte'] ?? '').toString(),
          isCompletata: m['isCompletata'] == true,
          rpe: (m['rpe'] ?? '').toString(),
        );
      })
      .toList();
}

Scheda _parseScheda(dynamic rawJson) {
  if (rawJson is Map<String, dynamic>) {
    return Scheda.fromJson(rawJson);
  }

  if (rawJson is Map) {
    return Scheda.fromJson(Map<String, dynamic>.from(rawJson));
  }

  return Scheda(nome: 'Allenamento', livello: 'Principiante', esercizi: []);
}

Scheda _parseSchedaFromLegacyRoot(Map<String, dynamic> json) {
  final nomeScheda = (json['nomeScheda'] ?? json['nome'] ?? 'Allenamento').toString();
  final eserciziLegacy = json['esercizi'];

  if (eserciziLegacy is! List) {
    return Scheda(nome: nomeScheda, livello: 'Principiante', esercizi: []);
  }

  final esercizi = eserciziLegacy
      .whereType<Map>()
      .map((row) {
        final m = Map<String, dynamic>.from(row);
        final serie = _parseSerieLegacy(m['serie']);
        final working = serie.where((s) => s.tipo != 'Avvicinamento').length;

        return Esercizio(
          nome: (m['nome'] ?? 'Esercizio').toString(),
          avvicinamento: serie.where((s) => s.tipo == 'Avvicinamento').length,
          workingSet: working == 0 ? 3 : working,
          ripetizioni: (m['target_ripetizioni'] ?? m['ripetizioni'] ?? '').toString(),
          recupero: (m['recupero'] ?? '').toString(),
          serieAttive: serie,
        );
      })
      .toList();

  return Scheda(
    nome: nomeScheda,
    livello: (json['livello'] ?? 'Principiante').toString(),
    categoria: (json['categoria'] ?? 'Legacy').toString(),
    esercizi: esercizi,
  );
}

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
    final rawScheda = json['scheda'];
    final scheda = (rawScheda != null)
        ? _parseScheda(rawScheda)
        : _parseSchedaFromLegacyRoot(json);

    return Allenamento(
      data: _parseDate(json['data'] ?? json['sessionAt']),
      scheda: scheda,
      note: (json['feedback_atleta'] ?? json['note'])?.toString(), // 👈 LEGGE LA NOTA DAL CLOUD/MEMORIA
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