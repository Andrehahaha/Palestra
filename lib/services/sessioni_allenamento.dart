import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/allenamento.dart';
import '../models/scheda.dart';
import 'archivio_atleta.dart';
import 'athlete_progress_service.dart';
import 'carichi.dart';

/// Seam verso il registro cloud delle sessioni (`storico_atleti` e
/// `coaches/{coachId}/athletes/{uid}/progress`). Adapter:
/// [FirestoreRegistroSessioni] in produzione, un fake nei test.
abstract interface class RegistroSessioniCloud {
  /// Scrive (o riscrive) il documento della sessione, con chiave [Allenamento.id].
  Future<void> scrivi(Allenamento sessione, Map<String, dynamic> documento);

  /// Elimina i documenti della sessione.
  Future<void> elimina(Allenamento sessione);
}

class FirestoreRegistroSessioni implements RegistroSessioniCloud {
  FirestoreRegistroSessioni({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore,
        _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  User? get _user => (_auth ?? FirebaseAuth.instance).currentUser;

  Future<String?> _coachId(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final id = doc.data()?['coachId']?.toString().trim() ?? '';
      return id.isEmpty ? null : id;
    } catch (e) {
      debugPrint('Impossibile leggere coachId atleta: $e');
      return null;
    }
  }

  @override
  Future<void> scrivi(Allenamento sessione, Map<String, dynamic> documento) async {
    final user = _user;
    if (user == null) return;
    final coachId = await _coachId(user.uid);
    final payload = {
      ...documento,
      'atletaId': user.uid,
      'atletaEmail': user.email,
      'coachId': ?coachId,
    };
    await _db.collection('storico_atleti').doc(sessione.id).set(payload);
    if (coachId != null) {
      await AthleteProgressService(firestore: _db, auth: _auth).saveProgressEntry(
        coachId: coachId,
        athleteId: user.uid,
        payload: payload,
        sessionAt: sessione.data,
        entryId: sessione.id,
      );
    }
  }

  @override
  Future<void> elimina(Allenamento sessione) async {
    final user = _user;
    if (user == null) return;
    final dataIso = sessione.data.toIso8601String();

    await _db.collection('storico_atleti').doc(sessione.id).delete();
    // Documenti legacy creati con id casuale: si riconoscono dalla data.
    final legacy = await _db
        .collection('storico_atleti')
        .where('atletaId', isEqualTo: user.uid)
        .where('data', isEqualTo: dataIso)
        .get();
    for (final doc in legacy.docs) {
      await doc.reference.delete();
    }

    final coachId = await _coachId(user.uid);
    if (coachId == null) return;
    final progress = _db
        .collection('coaches')
        .doc(coachId)
        .collection('athletes')
        .doc(user.uid)
        .collection('progress');
    await progress.doc(sessione.id).delete();
    // Schema precedente: un documento per giorno (yyyyMMdd).
    final perGiorno = progress.doc(AthleteProgressService.buildDateKey(sessione.data));
    final snap = await perGiorno.get();
    if (snap.exists && snap.data()?['data'] == dataIso) {
      await perGiorno.delete();
    }
  }
}

/// Sessioni di allenamento: l'unico punto che registra o elimina una
/// sessione completata, in locale ([ArchivioAtleta.storico]) e nel cloud
/// (un solo documento per sessione, con chiave stabile).
class SessioniAllenamento {
  SessioniAllenamento({
    ArchivioAtleta? archivio,
    RegistroSessioniCloud? registro,
    DateTime Function()? orologio,
  })  : _archivio = archivio ?? ArchivioAtleta.instance,
        _registro = registro ?? FirestoreRegistroSessioni(),
        _orologio = orologio ?? DateTime.now;

  static final SessioniAllenamento instance = SessioniAllenamento();

  final ArchivioAtleta _archivio;
  final RegistroSessioniCloud _registro;
  final DateTime Function() _orologio;

  /// Registra una copia di [scheda] come sessione completata e azzera le
  /// serie della scheda per il prossimo allenamento.
  Future<Allenamento> completa(Scheda scheda, {String? note}) async {
    final sessione = Allenamento(
      data: _orologio(),
      scheda: Scheda.fromJson(scheda.toJson()),
      note: (note == null || note.trim().isEmpty) ? null : note,
    );
    for (final es in scheda.esercizi) {
      for (final s in es.serieAttive) {
        s.isCompletata = false;
      }
    }
    await registra(sessione);
    return sessione;
  }

  /// Aggiunge allo storico una sessione già costruita (es. un test PR).
  /// Se il cloud non risponde la sessione resta comunque salvata in locale.
  Future<void> registra(Allenamento sessione) async {
    await _archivio.carica();
    _archivio.storico.add(sessione);
    await _archivio.salva();
    try {
      await _registro.scrivi(sessione, documentoCloud(sessione));
    } catch (e) {
      debugPrint('Invio sessione al cloud fallito: $e');
    }
  }

  Future<void> elimina(Allenamento sessione) async {
    await _archivio.carica();
    _archivio.storico.removeWhere((a) => a.id == sessione.id);
    await _archivio.salva();
    try {
      await _registro.elimina(sessione);
    } catch (e) {
      debugPrint('Eliminazione sessione dal cloud fallita: $e');
    }
  }

  /// Schema completo ([Allenamento.toJson]) più il riepilogo piatto letto
  /// dalla dashboard coach (`nomeScheda`, `esercizi[].serie`).
  static Map<String, dynamic> documentoCloud(Allenamento sessione) {
    return {
      ...sessione.toJson(),
      'nomeScheda': sessione.scheda.nome,
      'esercizi': sessione.scheda.esercizi
          .map((e) => {
                'nome': Carichi.traduci(e.nome),
                'target_ripetizioni': e.ripetizioni,
                'tecniche': e.tecniche,
                'serie': e.serieAttive
                    .where((s) => s.isCompletata)
                    .map((s) => {
                          'peso': s.peso,
                          'tipo': s.tipo,
                          'ripetizioniFatte': s.ripetizioniFatte,
                          'rpe': s.rpe,
                        })
                    .toList(),
              })
          .toList(),
    };
  }
}
