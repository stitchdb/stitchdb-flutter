import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitchdb/stitchdb.dart';

/// An [OfflineStore] that keeps the offline copy in SharedPreferences, so
/// queued writes and synced rows survive an app restart.
///
/// Every key is prefixed with [name]; use one name per signed-in user.
///
/// ```dart
/// final offline = Stitch.instance.client.offline(
///   store: SharedPreferencesOfflineStore(name: 'offline-$userId'),
/// );
/// ```
class SharedPreferencesOfflineStore implements OfflineStore {
  /// Prefix of every key this store writes.
  final String name;

  Future<SharedPreferences>? _prefs;

  SharedPreferencesOfflineStore({this.name = 'stitchdb-offline'});

  Future<SharedPreferences> get _p => _prefs ??= () {
    WidgetsFlutterBinding.ensureInitialized();
    return SharedPreferences.getInstance();
  }();

  String get _prefix => '$name/';

  @override
  Future<dynamic> get(String key) async {
    final v = (await _p).getString(_prefix + key);
    return v == null ? null : jsonDecode(v);
  }

  @override
  Future<void> set(String key, dynamic value) async {
    await (await _p).setString(_prefix + key, jsonEncode(value));
  }

  @override
  Future<void> delete(String key) async {
    await (await _p).remove(_prefix + key);
  }

  @override
  Future<List<MapEntry<String, dynamic>>> entries(String prefix) async {
    final p = await _p;
    final full = _prefix + prefix;
    final out = <MapEntry<String, dynamic>>[];
    for (final k in p.getKeys()) {
      if (!k.startsWith(full)) continue;
      final v = p.getString(k);
      if (v != null)
        out.add(MapEntry(k.substring(_prefix.length), jsonDecode(v)));
    }
    return out;
  }

  @override
  Future<void> clear() async {
    final p = await _p;
    for (final k in p.getKeys().toList()) {
      if (k.startsWith(_prefix)) await p.remove(k);
    }
  }
}
