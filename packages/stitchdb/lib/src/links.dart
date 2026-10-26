import 'dart:convert';

import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:stitchdb_common/stitchdb_common.dart';

import 'analytics.dart' show AnalyticsStore;

// Deep links and short links (`stitchdb.links`, Studio › Links):
// `https://<project host or your domain>/l/<code>` opens your app on the
// right screen when it is installed (iOS Universal Links, Android App Links),
// and otherwise sends people to the App Store, Google Play or a web page.
// The app resolves the link it was opened with to its path and data, and on
// its first launch after an install can ask which link led to the install
// (deferred deep link, best effort).

final _codeRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final _pathRe = RegExp(r'^/l/([A-Za-z0-9_-]{1,64})/?$');
const _checkedKey = 'deferred_link_checked';

/// Thrown when the links API refuses a request: [status] 404 for an unknown
/// link, 410 for an expired or turned-off one, 403 without the right key,
/// 402 at the plan limit, 409 when a code is taken, 0 when the request could
/// not be sent.
class LinksException implements Exception {
  final String message;
  final int status;

  const LinksException(this.message, this.status);

  @override
  String toString() => 'LinksException($status): $message';
}

/// What the app gets for a link.
class AppLink {
  final String code;

  /// The short link.
  final String url;

  /// The screen to show, as you stored it (for example `/product/42`), or
  /// `null` for the start screen.
  final String? path;

  /// The data stored with the link.
  final Map<String, dynamic> data;

  /// [LinksClient.deferred] only: how the install was matched to the click,
  /// `referrer` or `network`.
  final String? matchedBy;

  const AppLink({
    required this.code,
    required this.url,
    this.path,
    this.data = const {},
    this.matchedBy,
  });

  factory AppLink.fromJson(Map<String, dynamic> json) => AppLink(
    code: '${json['code']}',
    url: '${json['url']}',
    path: json['path'] as String?,
    data: _map(json['data']),
    matchedBy: json['matched_by'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'url': url,
    'path': path,
    'data': data,
    if (matchedBy != null) 'matched_by': matchedBy,
  };

  @override
  String toString() => 'AppLink(${jsonEncode(toJson())})';
}

/// The fields of a link to create or change. Only the fields you set are
/// sent; set a field to `null` with [clear] (for example `clear: {'title'}`).
class LinkInput {
  /// The screen the app shows (a path your router knows).
  final String? path;

  /// Up to 4 KB of JSON for the app.
  final Map<String, dynamic>? data;

  /// Service key only: choose the code (letters, digits, `_` and `-`);
  /// default a random 7-letter code.
  final String? code;

  /// Where people on a computer go (default: the project's web page).
  final String? webUrl;

  /// Instead of the App Store when the app is not installed.
  final String? iosUrl;

  /// Instead of Google Play when the app is not installed.
  final String? androidUrl;

  /// Shown when the link is shared in chats and social posts.
  final String? title;
  final String? description;
  final String? imageUrl;

  /// When the link stops working.
  final DateTime? expiresAt;
  final bool? disabled;

  /// Fields sent as `null` (wire names such as `expires_at` or `title`).
  final Set<String> clear;

  const LinkInput({
    this.path,
    this.data,
    this.code,
    this.webUrl,
    this.iosUrl,
    this.androidUrl,
    this.title,
    this.description,
    this.imageUrl,
    this.expiresAt,
    this.disabled,
    this.clear = const {},
  });

  Map<String, dynamic> toJson() => {
    for (final k in clear) k: null,
    'path': ?path,
    'data': ?data,
    'code': ?code,
    'web_url': ?webUrl,
    'ios_url': ?iosUrl,
    'android_url': ?androidUrl,
    'title': ?title,
    'description': ?description,
    'image_url': ?imageUrl,
    'expires_at': ?expiresAt?.toUtc().toIso8601String(),
    'disabled': ?disabled,
  };
}

/// A short link with its counts, as the service key sees it.
class Link {
  final String code;
  final String url;
  final String? path;
  final Map<String, dynamic> data;
  final String? webUrl;
  final String? iosUrl;
  final String? androidUrl;
  final String? title;
  final String? description;
  final String? imageUrl;
  final DateTime? expiresAt;
  final bool disabled;

  /// `studio`, `api` or `user`.
  final String source;
  final String? createdBy;
  final int clicks;
  final int opens;
  final int installs;
  final DateTime? lastClickAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Link({
    required this.code,
    required this.url,
    this.path,
    this.data = const {},
    this.webUrl,
    this.iosUrl,
    this.androidUrl,
    this.title,
    this.description,
    this.imageUrl,
    this.expiresAt,
    this.disabled = false,
    this.source = 'api',
    this.createdBy,
    this.clicks = 0,
    this.opens = 0,
    this.installs = 0,
    this.lastClickAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Link.fromJson(Map<String, dynamic> json) => Link(
    code: '${json['code']}',
    url: '${json['url']}',
    path: json['path'] as String?,
    data: _map(json['data']),
    webUrl: json['web_url'] as String?,
    iosUrl: json['ios_url'] as String?,
    androidUrl: json['android_url'] as String?,
    title: json['title'] as String?,
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    expiresAt: _date(json['expires_at']),
    disabled: json['disabled'] == true,
    source: json['source'] is String ? json['source'] as String : 'api',
    createdBy: json['created_by'] as String?,
    clicks: _int(json['clicks']),
    opens: _int(json['opens']),
    installs: _int(json['installs']),
    lastClickAt: _date(json['last_click_at']),
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
  );
}

/// One day of a link's numbers.
class LinkDay {
  /// `YYYY-MM-DD`.
  final String day;
  final int clicks;
  final int opens;
  final int installs;

  const LinkDay({
    required this.day,
    this.clicks = 0,
    this.opens = 0,
    this.installs = 0,
  });
}

/// A link with its clicks per day, platform, country, where people went
/// (outcome) and referrers, for the last [days] days. The breakdowns map
/// each value to its count.
class LinkStats {
  final Link link;
  final int days;
  final List<LinkDay> daily;
  final Map<String, int> platforms;
  final Map<String, int> countries;
  final Map<String, int> outcomes;
  final Map<String, int> referrers;

  const LinkStats({
    required this.link,
    required this.days,
    this.daily = const [],
    this.platforms = const {},
    this.countries = const {},
    this.outcomes = const {},
    this.referrers = const {},
  });

  factory LinkStats.fromJson(Map<String, dynamic> json) {
    Map<String, int> by(Object? v) => {
      if (v is List)
        for (final e in v.whereType<Map<dynamic, dynamic>>())
          '${e['k']}': _int(e['n']),
    };
    final daily = json['daily'];
    return LinkStats(
      link: Link.fromJson(_map(json['link'])),
      days: _int(json['days']),
      daily: [
        if (daily is List)
          for (final d in daily.whereType<Map<dynamic, dynamic>>())
            LinkDay(
              day: '${d['day']}',
              clicks: _int(d['clicks']),
              opens: _int(d['opens']),
              installs: _int(d['installs']),
            ),
      ],
      platforms: by(json['platforms']),
      countries: by(json['countries']),
      outcomes: by(json['outcomes']),
      referrers: by(json['referrers']),
    );
  }
}

/// A page of [Link]s and the number of links that match.
class LinkList {
  final List<Link> links;
  final int total;

  const LinkList(this.links, this.total);
}

/// Deep links and short links for one [StitchClient] (`stitchdb.links`).
///
/// ```dart
/// // the app was opened by a link (for example from the app_links package)
/// final link = await stitchdb.links.resolve(uri.toString());
/// if (link != null) router.go(link.path ?? '/', extra: link.data);
///
/// // first launch after an install (asked once per install)
/// final first = await stitchdb.links.deferred();
///
/// // make a link: signed-in users when the project allows it, any link
/// // with the service key
/// final made = await stitchdb.links.create(
///   const LinkInput(path: '/invite/7', data: {'from': 'ana'}),
/// );
/// share(made.url);
/// ```
class LinksClient {
  final String _url;
  final Client _http;
  final Map<String, String> Function() _headers;
  final AnalyticsStore Function() _store;
  String? Function() _platform = _dartPlatform;

  @internal
  LinksClient(this._url, this._http, this._headers, this._store);

  /// For platform integrations and tests: the platform sent by default
  /// (`ios`, `android` or `null`; default: the OS the app runs on).
  void configure({String? Function()? platform}) {
    if (platform != null) _platform = platform;
  }

  /// The code of a short link (`https://…/l/<code>`, a trailing slash and
  /// the query are ignored), or `null` for any other URL. A bare code is
  /// returned as is.
  static String? codeFrom(String urlOrCode) {
    final s = urlOrCode.trim();
    if (_codeRe.hasMatch(s)) return s;
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.hasScheme) return null;
    return _pathRe.firstMatch(uri.path)?.group(1);
  }

  /// The link the app was opened with: its path and data (counted as an
  /// open in Studio). `null`, without a request, for a URL that is not a
  /// short link. An unknown link throws a [LinksException] with status 404,
  /// an expired or turned-off one with status 410.
  ///
  /// [platform] is `ios`, `android` or `web` (default: the OS the app runs
  /// on, when it is iOS or Android).
  Future<AppLink?> resolve(String urlOrCode, {String? platform}) async {
    final code = codeFrom(urlOrCode);
    if (code == null) return null;
    final p = platform ?? _safePlatform();
    final json = await _req('GET', '/resolve/$code', query: {'platform': ?p});
    return AppLink.fromJson(_map(json));
  }

  /// First launch after an install: the link that led to it, or `null`.
  ///
  /// Asked once per install: after an answer from StitchDB this is
  /// remembered in the analytics store (SharedPreferences in Flutter apps)
  /// and later calls return `null` without a request; [force] asks again.
  ///
  /// Android apps pass the Play install referrer as [referrer] (an exact
  /// match; read `ReferrerDetails.installReferrer` with the Play Install
  /// Referrer API in your app). Otherwise the click is matched by network
  /// and platform within 2 hours, best effort, and each click is handed out
  /// once. [platform] is `ios` or `android` (default: the OS the app runs
  /// on).
  Future<AppLink?> deferred({
    String? platform,
    String? referrer,
    bool force = false,
  }) async {
    final p = platform ?? _safePlatform();
    if (p != 'ios' && p != 'android') {
      throw ArgumentError.value(p, 'platform', 'ios or android');
    }
    final store = _store();
    if (!force) {
      try {
        if (await store.get(_checkedKey) == 'true') return null;
      } catch (_) {}
    }
    final json = await _req(
      'POST',
      '/deferred',
      body: {'platform': p, 'referrer': ?referrer},
    );
    try {
      await store.set(_checkedKey, 'true');
    } catch (_) {}
    final match = json is Map ? json['match'] : null;
    return match is Map
        ? AppLink.fromJson(match.cast<String, dynamic>())
        : null;
  }

  /// Make a short link (signed-in users when the project allows it in
  /// Studio › Links, any link with the service key).
  Future<Link> create(LinkInput link) async =>
      Link.fromJson(_map(await _req('POST', '/links', body: link.toJson())));

  /// Links, newest first, whose code, path or title contains [search]
  /// (service key).
  Future<LinkList> list({String? search, int? limit, int? offset}) async {
    final json = _map(
      await _req(
        'GET',
        '/links',
        query: {
          if (search != null && search.isNotEmpty) 'q': search,
          'limit': ?limit?.toString(),
          'offset': ?offset?.toString(),
        },
      ),
    );
    final links = json['links'];
    return LinkList([
      if (links is List)
        for (final l in links.whereType<Map<dynamic, dynamic>>())
          Link.fromJson(l.cast<String, dynamic>()),
    ], _int(json['total']));
  }

  /// One link with its numbers for the last [days] days (service key).
  Future<LinkStats> get(String code, {int? days}) async => LinkStats.fromJson(
    _map(
      await _req(
        'GET',
        '/links/${Uri.encodeComponent(code)}',
        query: {'days': ?days?.toString()},
      ),
    ),
  );

  /// Change a link (service key); only the fields set in [patch] change.
  Future<Link> update(String code, LinkInput patch) async => Link.fromJson(
    _map(
      await _req(
        'PATCH',
        '/links/${Uri.encodeComponent(code)}',
        body: patch.toJson(),
      ),
    ),
  );

  /// Delete a link (service key). Returns the deleted code.
  Future<String> remove(String code) async {
    final json = _map(
      await _req('DELETE', '/links/${Uri.encodeComponent(code)}'),
    );
    return '${json['deleted'] ?? code}';
  }

  String? _safePlatform() {
    try {
      return _platform();
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _req(
    String method,
    String path, {
    Map<String, String> query = const {},
    Object? body,
  }) async {
    var uri = Uri.parse(_url + path);
    if (query.isNotEmpty) uri = uri.replace(queryParameters: query);
    final headers = {..._headers()};
    final Response res;
    try {
      final req = Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      res = await Response.fromStream(await _http.send(req));
    } catch (e) {
      throw LinksException('$e', 0);
    }
    dynamic json;
    try {
      json = jsonDecode(res.body);
    } catch (_) {
      json = <String, dynamic>{};
    }
    if (res.statusCode < 200 || res.statusCode > 299) {
      final message = json is Map ? json['message'] : null;
      throw LinksException(
        message is String ? message : 'Request failed (${res.statusCode})',
        res.statusCode,
      );
    }
    return json;
  }
}

String? _dartPlatform() {
  final p = conditionalPlatform;
  return p == 'ios' || p == 'android' ? p : null;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
