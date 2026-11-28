/// Indicazioni del piano per una settimana, uguali per tutti gli esercizi
/// (es. "RIR tabella +2" in settimana 1, "scarico" in settimana 5).
class SettimanaPiano {
  const SettimanaPiano({this.rirDelta, this.scarico = false, this.tecniche});

  /// Ripetizioni di margine da aggiungere al RIR della tabella.
  final int? rirDelta;

  /// Settimana di scarico: metà delle serie, RIR 4, niente tecniche.
  final bool scarico;

  /// Tecniche ammesse questa settimana fra quelle scritte negli esercizi:
  /// `null` = tutte, `[]` = nessuna, `["LP"]` = solo LP.
  final List<String>? tecniche;

  /// Le tecniche di un esercizio che valgono questa settimana.
  List<String> filtra(List<String> tecnicheEsercizio) {
    final ammesse = tecniche;
    if (ammesse == null) return tecnicheEsercizio;
    final chiavi = ammesse.map(_chiave).toSet();
    final tenute = tecnicheEsercizio.where((t) => chiavi.contains(_chiave(t))).toList();
    return tenute.isEmpty ? const ['Classico'] : tenute;
  }

  static String _chiave(String t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Map<String, dynamic> toJson() => {
        if (rirDelta != null) 'rirDelta': rirDelta,
        if (scarico) 'scarico': true,
        if (tecniche != null) 'tecniche': tecniche,
      };

  static SettimanaPiano? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final delta = raw['rirDelta'];
    final rirDelta = delta is num ? delta.toInt() : int.tryParse('${delta ?? ''}'.replaceAll('+', '').trim());
    final scarico = raw['scarico'] == true || '${raw['scarico']}'.toLowerCase() == 'true';
    final tecniche = _tecnicheDaJson(raw['tecniche']);
    if (rirDelta == null && !scarico && tecniche == null) return null;
    return SettimanaPiano(rirDelta: rirDelta, scarico: scarico, tecniche: tecniche);
  }

  static List<String>? _tecnicheDaJson(dynamic raw) {
    if (raw is List) return raw.map((t) => '$t'.trim()).where((t) => t.isNotEmpty).toList();
    if (raw is String && raw.trim().toLowerCase() == 'nessuna') return const [];
    return null;
  }
}
