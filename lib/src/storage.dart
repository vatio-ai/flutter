part of '../vatio.dart';

class _StoredChat {
  const _StoredChat(this.chatId, this.chatToken, this.expiresAt);

  final int chatId;
  final String chatToken;
  final DateTime? expiresAt;

  bool get isExpired => !(expiresAt?.isAfter(DateTime.now()) ?? false);

  String encode() =>
      jsonEncode({'chat_id': chatId, 'chat_token': chatToken, 'expires_at': expiresAt?.toIso8601String()});

  static _StoredChat? decode(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as _Json;
      return _StoredChat(json['chat_id'] as int, json['chat_token'] as String, _parseDate(json['expires_at']));
    } catch (_) {
      return null;
    }
  }
}

/// The stored conversation and visitor id, kept per person: a different
/// `visitorToken` subject is a different visitor, with its own conversation
/// and its own id, so signing out of the app really does sign out.
class _VisitorStorage {
  _VisitorStorage(this._prefs, this._prefix, String? visitorToken) : _subject = _subjectOf(visitorToken);

  final SharedPreferencesAsync _prefs;
  final String _prefix;
  final String? _subject;

  bool get isIdentified => _subject != null;

  Future<String?> visitorRef() => _prefs.getString(_key('visitor', identified: isIdentified));

  Future<void> setVisitorRef(String ref) => _prefs.setString(_key('visitor', identified: isIdentified), ref);

  Future<_StoredChat?> chat() => _read(_key('chat', identified: isIdentified));

  Future<void> setChat(_StoredChat? chat) => _write(_key('chat', identified: isIdentified), chat);

  /// The conversation filed before the visitor signed in, which an
  /// identified visitor adopts instead of losing.
  Future<_StoredChat?> anonymousChat() => _read(_key('chat', identified: false));

  Future<void> setAnonymousChat(_StoredChat? chat) => _write(_key('chat', identified: false), chat);

  String _key(String name, {required bool identified}) {
    final scope = identified ? 'default#$_subject' : 'default';
    return '$_prefix:$scope:$name';
  }

  Future<_StoredChat?> _read(String key) async {
    final chat = _StoredChat.decode(await _prefs.getString(key));
    return chat == null || chat.isExpired ? null : chat;
  }

  Future<void> _write(String key, _StoredChat? chat) =>
      chat == null ? _prefs.remove(key) : _prefs.setString(key, chat.encode());

  // Read without verifying, which is safe because it is only a cache key:
  // the server checks the signature before trusting anything in it.
  static String? _subjectOf(String? visitorToken) {
    final parts = visitorToken?.split('.') ?? const [];
    if (parts.length < 2) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final sub = payload is _Json ? payload['sub'] : null;
      return sub == null ? null : '$sub';
    } catch (_) {
      return null;
    }
  }
}
