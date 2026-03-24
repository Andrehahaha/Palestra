import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProgressPage {
  final List<Map<String, dynamic>> items;
  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;

  const ProgressPage({required this.items, required this.nextCursor});
}

class AthleteProgressService {
  AthleteProgressService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static String buildDateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  CollectionReference<Map<String, dynamic>> _progressCollection({
    required String coachId,
    required String athleteId,
  }) {
    return _firestore
        .collection('coaches')
        .doc(coachId)
        .collection('athletes')
        .doc(athleteId)
        .collection('progress');
  }

  DocumentReference<Map<String, dynamic>> _statsDoc({
    required String coachId,
    required String athleteId,
  }) {
    return _firestore
        .collection('coaches')
        .doc(coachId)
        .collection('athletes')
        .doc(athleteId)
        .collection('stats')
        .doc('current');
  }

  Future<void> saveProgressEntry({
    required String coachId,
    required String athleteId,
    required Map<String, dynamic> payload,
    DateTime? sessionAt,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Utente non autenticato');
    }

    final when = sessionAt ?? DateTime.now();
    final docId = buildDateKey(when);
    final cleanPayload = Map<String, dynamic>.from(payload)
      ..removeWhere((key, value) => value == null);

    await _progressCollection(coachId: coachId, athleteId: athleteId)
        .doc(docId)
        .set(
      {
        ...cleanPayload,
        'athleteId': athleteId,
        'coachId': coachId,
        'sessionAt': Timestamp.fromDate(when),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await _statsDoc(coachId: coachId, athleteId: athleteId).set(
      {
        'athleteId': athleteId,
        'coachId': coachId,
        'lastSessionAt': Timestamp.fromDate(when),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<ProgressPage> getRecentProgress({
    required String coachId,
    required String athleteId,
    int limit = 30,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _progressCollection(
      coachId: coachId,
      athleteId: athleteId,
    ).orderBy('sessionAt', descending: true).limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final items = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();

    return ProgressPage(
      items: items,
      nextCursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
    );
  }

  Stream<List<Map<String, dynamic>>> watchRecentProgress({
    required String coachId,
    required String athleteId,
    int limit = 30,
  }) {
    return _progressCollection(coachId: coachId, athleteId: athleteId)
        .orderBy('sessionAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }
}
