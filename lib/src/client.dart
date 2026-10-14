part of '../vatio.dart';

/// A connection to one Vatio workspace, from a Flutter app.
///
///     final vatio = Vatio(workspace: 'acme', token: 'vatpub_...');
///     final chat = VatioChat(vatio);
///     await chat.send('hola');
///
/// [token] is a publishable token (`vatpub_…`), meant to ship inside your
/// app. It only works from the origins the token allows: `ios-app://` plus
/// the bundle id on iOS and macOS, `android-app://` plus the package name on
/// Android. A `vat_` token is a developer secret and must never ship in an
/// app.
class Vatio {
  Vatio({
    required this.workspace,
    required this.token,
    this.baseUrl = 'https://vatio.ai',
    this.appId,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const version = '0.1.0';

  final String workspace;
  final String token;
  final String baseUrl;

  /// The bundle id (iOS, macOS) or package name (Android) sent as the
  /// `Origin`. Read from the app itself when null.
  final String? appId;

  final http.Client _http;
  late final _prefs = SharedPreferencesAsync();
  Future<String>? _origin;

  static const _timeout = Duration(seconds: 60);

  /// The agent's name, avatar, accent color and widget copy, without
  /// starting a conversation. Throws `no_agent_deployed` when nothing is
  /// published to the token's environment.
  Future<VatioConfig> config() async {
    _validateToken();
    final json = await _request('GET', 'config', bearer: token);
    return _decode(() => _configFrom(json));
  }

  /// Every conversation this visitor has had on this workspace from this
  /// device, newest first. Empty for a visitor who never talked here. Pass
  /// the same [visitorToken] you give [VatioChat].
  Future<List<VatioConversation>> conversations({String? visitorToken}) async {
    _validateToken();
    final visitorRef = await _storage(visitorToken).visitorRef();
    if (visitorRef == null) return const [];

    // A conversation this person had signed in is listed only alongside
    // their token.
    final json = await _request(
      'GET',
      'chats?visitor_ref=${Uri.encodeComponent(visitorRef)}',
      bearer: token,
      visitorToken: visitorToken,
    );
    return _decode(() => _list(json).map(_conversationFrom).toList());
  }

  // Internals

  _VisitorStorage _storage(String? visitorToken) => _VisitorStorage(_prefs, 'vatio:$baseUrl:$workspace', visitorToken);

  void _validateToken() {
    if (!token.startsWith('vatpub_')) {
      throw const VatioException(
        'wrong_token_kind',
        'token must be a publishable token (vatpub_...). A vat_ token is a developer secret and must never ship in an app.',
      );
    }
  }

  Future<String> _originFor() => _origin ??= _resolveOrigin();

  Future<String> _resolveOrigin() async {
    final scheme = Platform.isAndroid
        ? 'android-app'
        : Platform.isIOS || Platform.isMacOS
            ? 'ios-app'
            : throw const VatioException(
                'unsupported_platform',
                'Vatio for Flutter runs on iOS, Android and macOS. On the web, use the widget or @vatio-ai/sdk.',
              );
    final id = appId ?? (await PackageInfo.fromPlatform()).packageName;
    return '$scheme://${id.toLowerCase()}';
  }

  Uri get _cableUrl {
    final url = Uri.parse(baseUrl).resolve('cable');
    return url.replace(scheme: url.scheme == 'http' ? 'ws' : 'wss');
  }

  Uri _url(String path) => Uri.parse(baseUrl).resolve('api/visitor/v1/${Uri.encodeComponent(workspace)}/$path');

  Future<Map<String, String>> _headers(String bearer) async => {
        'Authorization': 'Bearer $bearer',
        'Origin': await _originFor(),
        'Accept': 'application/json',
      };

  Future<_Json> _request(
    String method,
    String path, {
    required String bearer,
    Map<String, Object?>? body,
    String? visitorToken,
  }) async {
    final request = http.Request(method, _url(path))..headers.addAll(await _headers(bearer));
    if (visitorToken != null && visitorToken.isNotEmpty) request.headers['Vatio-Visitor-Token'] = visitorToken;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _send(request);
  }

  /// multipart/form-data: `content` and one `files[]` part per upload.
  Future<_Json> _upload(String path,
      {required String bearer, required String content, required List<VatioUpload> files}) async {
    final request = http.MultipartRequest('POST', _url(path))..headers.addAll(await _headers(bearer));
    if (content.isNotEmpty) request.fields['content'] = content;
    for (final file in files) {
      MediaType? type;
      try {
        type = MediaType.parse(file.contentType);
      } on FormatException {
        type = MediaType('application', 'octet-stream');
      }
      request.files
          .add(http.MultipartFile.fromBytes('files[]', file.bytes, filename: file.filename, contentType: type));
    }
    return _send(request);
  }

  Future<_Json> _send(http.BaseRequest request) async {
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(_timeout)).timeout(_timeout);
    } on Exception catch (error) {
      throw VatioException('network_error', '$error');
    }

    _Json? json;
    try {
      final decoded = response.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is _Json) json = decoded;
    } on FormatException {
      // Not JSON: a proxy's error page, say. The status still says enough.
    }

    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final code = json?['error'] is String ? json!['error'] as String : null;
      final description = json?['error_description'] is String ? json!['error_description'] as String : null;
      throw VatioException(code ?? 'request_failed', description ?? code ?? 'request failed with $status',
          status: status);
    }
    return json ?? <String, dynamic>{};
  }
}
