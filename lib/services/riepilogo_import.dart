import '../models/esercizio.dart';
import '../models/regola_progressione.dart';
import '../models/scheda.dart';

/// Riepilogo testuale delle schede importate, da stampare nel terminale per
/// controllare cosa ha letto l'AI.
abstract final class RiepilogoImport {
  static String testo(List<Scheda> schede) {
    final out = StringBuffer('=== IMPORT: ${schede.length} schede ===\n');
    for (final s in schede) {
      out.writeln('--- ${s.nome} (${s.categoria}) ---');
      final ripartenza = s.ripartiDaSettimana != null ? ', riparte dalla W${s.ripartiDaSettimana}' : '';
      if (s.durataProgramma != null) out.writeln('durata ${s.durataProgramma} settimane$ripartenza');

      final calendario = s.calendario;
      if (calendario != null && calendario.isNotEmpty) {
        final voci = (calendario.keys.toList()..sort()).map((w) {
          final info = calendario[w]!;
          if (info.scarico) return 'W$w scarico';
          final d = info.rirDelta!;
          return 'W$w RIR ${d >= 0 ? '+' : ''}$d';
        });
        out.writeln('calendario: ${voci.join(', ')}');
      }

      out.writeln('W1:');
      for (final e in s.esercizi) {
        out.writeln('  ${_esercizio(e)}');
      }
      final altre = (s.programma?.keys.where((w) => w != 1).toList() ?? [])..sort();
      for (final w in altre) {
        out.writeln('W$w:');
        for (final e in s.programma![w]!) {
          out.writeln('  ${_esercizio(e)}');
        }
      }
    }
    return out.toString();
  }

  /// Esercizi il cui nome è stato cambiato rispetto al documento: da
  /// controllare a mano. Vuoto se non ce ne sono.
  static String nomiCambiati(List<(String, String)> coppie) {
    if (coppie.isEmpty) return '';
    final out = StringBuffer()..writeln('=== NOMI CAMBIATI (controlla) ===');
    for (final (originale, scelto) in coppie) {
      out.writeln('  $originale -> $scelto');
    }
    return out.toString();
  }

  static String _esercizio(Esercizio e) {
    final riga = StringBuffer('${e.nome} ${e.workingSet}x${e.ripetizioni}');
    if (e.rirTarget != null && e.rirTarget!.isNotEmpty) riga.write(' RIR ${e.rirTarget}');
    if (e.modalitaIntensita == 'percentuale' && e.percentualeMassimale != null) {
      riga.write(' @${e.percentualeMassimale}%');
    }
    final tecniche = e.tecniche.where((t) => t != 'Classico').toList();
    if (tecniche.isNotEmpty) riga.write(' [${tecniche.join(', ')}]');
    final p = e.progressione;
    if (p != null) riga.write(' | progressione da W${p.daSettimana}: ${_regola(p)}');
    return riga.toString();
  }

  static String _regola(RegolaProgressione p) {
    final parti = [
      if (p.incrementoKg != null) '+${p.incrementoKg} kg',
      if (p.incrementoPercentuale != null) '+${p.incrementoPercentuale}%',
      if (p.rirTarget != null) 'RIR ${p.rirTarget}',
      if (p.nota != null) '"${p.nota}"',
    ];
    return parti.join(' ');
  }
}
