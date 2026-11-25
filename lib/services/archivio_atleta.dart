import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/allenamento.dart';
import '../models/scheda.dart';
import 'dolore_data.dart';

/// Quello che il cloud sa dell'atleta (`users/{uid}`).
class StatoCloud {
  const StatoCloud({this.appState, this.updatedAt, this.personalRecords = const {}});

  final Map<String, dynamic>? appState;
  final DateTime? updatedAt;
  final Map<String, double> personalRecords;
}

/// Seam verso il cloud. Adapter: [FirestoreArchivioCloud] in produzione,
/// un fake in memoria nei test.
abstract interface class ArchivioCloud {
  /// `null` se l'utente non è loggato o il cloud non risponde.
  Future<StatoCloud?> leggi();

  /// Sostituisce `app_state` e ne aggiorna `updated_at`. Può lanciare eccezioni.
  Future<void> scriviAppState(Map<String, dynamic> appState);

  /// Sostituisce `personal_records`. Può lanciare eccezioni.
  Future<void> scriviPersonalRecords(Map<String, double> pr);
}

class FirestoreArchivioCloud implements ArchivioCloud {
  FirestoreArchivioCloud({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore,
        _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    if (uid == null) return null;
    return (_firestore ?? FirebaseFirestore.instance).collection('users').doc(uid);
  }

  @override
  Future<StatoCloud?> leggi() async {
    final ref = _doc;
    if (ref == null) return null;
    try {
      final data = (await ref.get()).data();
      if (data == null) return const StatoCloud();
      final rawApp = data['app_state'];
      final appState = rawApp is Map ? Map<String, dynamic>.from(rawApp) : null;
      final rawTs = appState?['updated_at'];
      DateTime? ts;
      if (rawTs is Timestamp) {
        ts = rawTs.toDate();
      } else if (rawTs != null) {
        ts = DateTime.tryParse(rawTs.toString());
      }
      return StatoCloud(
        appState: appState,
        updatedAt: ts,
        personalRecords: ArchivioAtleta.decodificaPr(data['personal_records']),
      );
    } catch (e) {
      debugPrint('ArchivioCloud.leggi fallita: $e');
      return null;
    }
  }

  @override
  Future<void> scriviAppState(Map<String, dynamic> appState) async {
    final ref = _doc;
    if (ref == null) return;
    await ref.set({
      'app_state': {...appState, 'updated_at': FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }

  @override
  Future<void> scriviPersonalRecords(Map<String, double> pr) async {
    final ref = _doc;
    if (ref == null) return;
    await ref.set({
      'personal_records': pr,
      'ultimo_aggiornamento_pr': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }
}

/// Archivio Atleta: l'unico module che possiede lo stato dell'atleta
/// (schede, storico, cartelle, zona e tipo dolore, storico settimane, PR)
/// e la sua sincronizzazione locale/cloud.
///
/// Gli screen leggono e modificano i campi in memoria (gli oggetti sono
/// condivisi fra le schermate) e poi chiamano [salva]. Ogni salvataggio
/// aggiorna il timestamp locale e invia al cloud lo stato **completo**, così
/// il confronto dei timestamp in [carica] resta affidabile.
class ArchivioAtleta extends ChangeNotifier {
  ArchivioAtleta({ArchivioCloud? cloud, DateTime Function()? orologio})
      : _cloud = cloud ?? FirestoreArchivioCloud(),
        _orologio = orologio ?? DateTime.now;

  /// Istanza usata dall'app.
  static final ArchivioAtleta instance = ArchivioAtleta();

  static const String _kSchede = 'schede_salvate';
  static const String _kStorico = 'storico_salvato';
  static const String _kCartelle = 'cartelle_vuote';
  static const String _kWeek = 'week_history_store_v1';
  static const String _kTipoDolore = 'tipo_dolore_selezionato';
  static const String _kUpdatedAt = 'app_state_updated_at_local';
  static const String _kPr = 'personal_records';

  final ArchivioCloud _cloud;
  final DateTime Function() _orologio;

  List<Scheda> schede = [];
  List<Allenamento> storico = [];
  List<String> cartelleVuote = [];
  String zonaStretching = 'Lombare';
  String? tipoDolore;

  /// Snapshot settimanali per scheda: `{schedaId: {"1": schedaJson, ...}}`.
  Map<String, dynamic> weekHistory = {};

  bool _caricato = false;
  Future<void>? _inCaricamento;

  bool get caricato => _caricato;

  /// Carica lo stato una volta sola (le chiamate concorrenti attendono la
  /// stessa lettura). Usa il cloud se non c'è stato locale o se il cloud è
  /// più recente del timestamp locale. Con [forza] rilegge sempre.
  Future<void> carica({bool forza = false}) {
    if (_caricato && !forza) return Future.value();
    return _inCaricamento ??= _carica().whenComplete(() => _inCaricamento = null);
  }

  Future<void> _carica() async {
    final prefs = await SharedPreferences.getInstance();
    schede = _decodificaLista(prefs.getString(_kSchede), Scheda.fromJson);
    storico = _decodificaLista(prefs.getString(_kStorico), Allenamento.fromJson);
    cartelleVuote = _decodificaStringhe(prefs.getString(_kCartelle));
    final zona = prefs.getString(zonaStretchingSharedKey);
    if (zona != null && zoneDolore.contains(zona)) zonaStretching = zona;
    tipoDolore = prefs.getString(_kTipoDolore);
    weekHistory = _decodificaMappa(prefs.getString(_kWeek));
    var aggiornatoIl = DateTime.tryParse(prefs.getString(_kUpdatedAt) ?? '');

    final haStatoLocale = schede.isNotEmpty || storico.isNotEmpty || cartelleVuote.isNotEmpty;
    final remoto = await _cloud.leggi();
    final app = remoto?.appState;
    if (app != null) {
      final cloudTs = remoto!.updatedAt;
      final usaCloud = !haStatoLocale ||
          (cloudTs != null && (aggiornatoIl == null || cloudTs.isAfter(aggiornatoIl)));
      if (usaCloud) {
        if (app['schede_salvate'] is List) {
          schede = _mappaLista(app['schede_salvate'] as List, Scheda.fromJson);
        }
        if (app['storico_salvato'] is List) {
          storico = _mappaLista(app['storico_salvato'] as List, Allenamento.fromJson);
        }
        if (app['cartelle_vuote'] is List) {
          cartelleVuote = (app['cartelle_vuote'] as List).map((e) => e.toString()).toList();
        }
        final z = app['zona_stretching'];
        if (z is String && zoneDolore.contains(z)) zonaStretching = z;
        final t = app['tipo_dolore'];
        if (t is String && t.isNotEmpty) tipoDolore = t;
        if (app['week_history_store'] is Map) {
          weekHistory = Map<String, dynamic>.from(app['week_history_store'] as Map);
        }
        aggiornatoIl = cloudTs ?? aggiornatoIl;
      }
    }

    aggiornaZonaStretchingCondivisa(zonaStretching);
    await _scriviLocale(prefs, aggiornatoIl ?? _orologio());
    _caricato = true;
    notifyListeners();
  }

  /// Salva tutto in locale e, se [cloud], invia lo stato completo.
  /// Gli errori del cloud sono ignorati: il locale resta più recente e
  /// vince al prossimo [carica].
  Future<void> salva({bool cloud = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await _scriviLocale(prefs, _orologio());
    notifyListeners();
    if (cloud) await _inviaAppState();
  }

  /// Salva solo lo storico settimane in locale (scritture frequenti).
  Future<void> salvaWeekHistory({bool cloud = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWeek, jsonEncode(weekHistory));
    await prefs.setString(_kUpdatedAt, _orologio().toIso8601String());
    if (cloud) await _inviaAppState();
  }

  Future<void> impostaZona(String zona) async {
    if (!zoneDolore.contains(zona)) return;
    zonaStretching = zona;
    aggiornaZonaStretchingCondivisa(zona);
    await salva();
  }

  Future<void> impostaTipoDolore(String tipo) async {
    tipoDolore = tipo;
    await salva();
  }

  Future<void> _scriviLocale(SharedPreferences prefs, DateTime ts) async {
    await prefs.setString(_kSchede, jsonEncode(schede.map((e) => e.toJson()).toList()));
    await prefs.setString(_kStorico, jsonEncode(storico.map((e) => e.toJson()).toList()));
    await prefs.setString(_kCartelle, jsonEncode(cartelleVuote));
    await prefs.setString(zonaStretchingSharedKey, zonaStretching);
    if (tipoDolore != null) await prefs.setString(_kTipoDolore, tipoDolore!);
    await prefs.setString(_kWeek, jsonEncode(weekHistory));
    await prefs.setString(_kUpdatedAt, ts.toIso8601String());
  }

  Future<void> _inviaAppState() async {
    try {
      await _cloud.scriviAppState({
        'schede_salvate': schede.map((e) => e.toJson()).toList(),
        'storico_salvato': storico.map((e) => e.toJson()).toList(),
        'cartelle_vuote': cartelleVuote,
        'zona_stretching': zonaStretching,
        if (tipoDolore != null) 'tipo_dolore': tipoDolore,
        'week_history_store': weekHistory,
      });
    } catch (e) {
      debugPrint('Sync app_state fallita: $e');
    }
  }

  /// Sostituisce schede, storico e (se presenti) PR con quelli di un backup
  /// JSON, poi salva e sincronizza.
  Future<void> importaBackup({
    required List schede,
    required List storico,
    dynamic personalRecords,
  }) async {
    await carica();
    this.schede = _mappaLista(schede, Scheda.fromJson);
    this.storico = _mappaLista(storico, Allenamento.fromJson);
    if (personalRecords != null) {
      await salvaPr(decodificaPr(personalRecords), sostituisci: true);
    }
    await salva();
  }

  // ---------------------------------------------------------------- PR

  /// PR salvati sul dispositivo.
  Future<Map<String, double>> prLocali() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return decodificaPr(jsonDecode(prefs.getString(_kPr) ?? '{}'));
    } catch (e) {
      debugPrint('PR locali non validi: $e');
      return {};
    }
  }

  /// PR locali uniti a quelli del cloud (il cloud vince sulle stesse chiavi).
  Future<Map<String, double>> caricaPr() async {
    final out = await prLocali();
    final remoto = await _cloud.leggi();
    if (remoto != null) out.addAll(remoto.personalRecords);
    return out;
  }

  /// Aggiunge (o con [sostituisci] rimpiazza) i PR locali e invia al cloud
  /// la mappa risultante. Con [soloCloud] il locale non viene toccato e al
  /// cloud vanno solo [voci]; con [soloLocale] il cloud non viene toccato.
  Future<void> salvaPr(
    Map<String, double> voci, {
    bool sostituisci = false,
    bool soloCloud = false,
    bool soloLocale = false,
  }) async {
    var daInviare = voci;
    if (!soloCloud) {
      final locali = sostituisci ? <String, double>{} : await prLocali();
      locali.addAll(voci);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPr, jsonEncode(locali));
      daInviare = locali;
    }
    if (soloLocale) return;
    try {
      await _cloud.scriviPersonalRecords(daInviare);
    } catch (e) {
      debugPrint('Sync PR fallita: $e');
    }
  }

  /// Converte una mappa PR grezza (JSON/Firestore) in `{nome: kg}`.
  static Map<String, double> decodificaPr(dynamic raw) {
    final out = <String, double>{};
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      final v = e.value;
      final kg = v is num ? v.toDouble() : double.tryParse(v.toString().replaceAll(',', '.'));
      if (kg != null) out[e.key.toString()] = kg;
    }
    return out;
  }

  // ----------------------------------------------------------- decode

  static List<T> _decodificaLista<T>(String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? _mappaLista(decoded, fromJson) : [];
    } catch (e) {
      debugPrint('Dati locali non validi: $e');
      return [];
    }
  }

  static List<T> _mappaLista<T>(List raw, T Function(Map<String, dynamic>) fromJson) {
    return raw.whereType<Map>().map((e) => fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static List<String> _decodificaStringhe(String? raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.map((e) => e.toString()).toList() : [];
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _decodificaMappa(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }
}
