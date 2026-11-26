/// Indicazioni del piano per una settimana, uguali per tutti gli esercizi
/// (es. "RIR tabella +2" in settimana 1, "scarico" in settimana 5).
class SettimanaPiano {
  const SettimanaPiano({this.rirDelta, this.scarico = false});

  /// Ripetizioni di margine da aggiungere al RIR della tabella.
  final int? rirDelta;

  /// Settimana di scarico: metà delle serie, RIR 4, niente tecniche.
  final bool scarico;

  Map<String, dynamic> toJson() => {
        if (rirDelta != null) 'rirDelta': rirDelta,
        if (scarico) 'scarico': true,
      };

  static SettimanaPiano? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final delta = raw['rirDelta'];
    final rirDelta = delta is num ? delta.toInt() : int.tryParse('${delta ?? ''}'.replaceAll('+', '').trim());
    final scarico = raw['scarico'] == true || '${raw['scarico']}'.toLowerCase() == 'true';
    if (rirDelta == null && !scarico) return null;
    return SettimanaPiano(rirDelta: rirDelta, scarico: scarico);
  }
}
