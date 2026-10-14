part of '../vatio.dart';

/// Where a [VatioChat]'s connection stands.
enum VatioStatus {
  /// No conversation yet, or it was closed with [VatioChat.startOver].
  idle,
  connecting,

  /// Live: replies arrive the moment they are sent.
  connected,

  /// The socket dropped. Replies are fetched by polling until it is back.
  reconnecting,
  closed,
}

/// One visitor's conversation with the agent, as a [ChangeNotifier]. It draws
/// nothing: listen to it, draw [messages], [isTyping] and [status] in your
/// own widgets, and call [send].
///
///     final chat = VatioChat(vatio);
///
///     ListenableBuilder(
///       listenable: chat,
///       builder: (context, _) => ListView(
///         children: [for (final m in chat.messages) Bubble(m)],
///       ),
///     );
///     await chat.send(text);
///
/// Creating one costs nothing and opens no connection. The conversation starts
/// on the first [send], so a visitor who never writes never becomes a contact.
/// Call [resume] when the screen appears to pick up where they left off, and
/// [dispose] when the chat is gone for good.
class VatioChat extends ChangeNotifier {
  /// [visitorToken] says who the visitor is when your app already knows: a
  /// token your backend signed for the signed-in user (see
  /// vatio.ai/docs/authentication/sessions). A different token subject is a
  /// different person, with a conversation of their own.
  ///
  /// [replyStyle] is fixed when the conversation starts.
  VatioChat(this.vatio, {this.visitorToken, this.replyStyle = VatioReplyStyle.stream});

  final Vatio vatio;
  final String? visitorToken;
  final VatioReplyStyle replyStyle;

  List<VatioMessage> _messages = const [];
  bool _isTyping = false;
  VatioStatus _status = VatioStatus.idle;
  VatioException? _lastError;
  VatioFeedback? _feedback;

  /// The conversation so far, oldest first, deduplicated by id. A new list
  /// each time it changes.
  List<VatioMessage> get messages => _messages;

  /// The agent is writing.
  bool get isTyping => _isTyping;

  VatioStatus get status => _status;

  /// The last failure that happened outside a [send] call — a reply that
  /// could not be fetched, a credential that expired. [send] throws instead.
  VatioException? get lastError => _lastError;

  /// A moment to ask the visitor how it went, when Vatio offers one -- at
  /// most once per conversation, after a request looks resolved. Show it
  /// while [VatioFeedback.isOpen], and answer with [rate] or
  /// [dismissFeedback]. It goes back to null when the visitor writes again
  /// without answering.
  VatioFeedback? get feedback => _feedback;

  /// The conversation id, once there is one.
  int? get conversationId => _current?.chatId;

  _StoredChat? _current;
  Future<_StoredChat>? _starting;
  _Cable? _cable;
  bool _subscribed = false;
  bool _closed = false;
  bool _disposed = false;
  int _attempt = 0;
  int _lastMessageId = 0;
  int _nextPendingId = -1;
  final List<Completer<void>> _readyWaiters = [];
  bool _polling = false;
  int _pollRun = 0;
  DateTime _pollUntil = DateTime.fromMillisecondsSinceEpoch(0);
  // Storage writes run in order, and a start reads after the last one.
  Future<void> _stored = Future.value();

  static const _reconnectDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];
  static const _pollInterval = Duration(milliseconds: 1500);
  static const _pollWindow = Duration(seconds: 45);
  static const _subscribeTimeout = Duration(seconds: 10);

  // Public surface

  /// Whether there is a stored, unexpired conversation [resume] would open.
  Future<bool> canResume() async {
    await _stored;
    final storage = vatio._storage(visitorToken);
    return await storage.chat() != null || (storage.isIdentified && await storage.anonymousChat() != null);
  }

  /// Reopens the visitor's stored conversation and loads its history. Does
  /// nothing when there is none — it never starts a new one.
  Future<void> resume() async {
    if (_current != null || _starting != null || !await canResume()) return;
    try {
      await _ensureStarted(createIfMissing: false);
    } on VatioException catch (error) {
      if (error.code == 'no_conversation') return;
      _lastError = error;
      _notify();
    }
  }

  /// Sends the visitor's message. It appears in [messages] at once, marked
  /// [VatioMessage.isPending], and the reply follows through [messages] and
  /// [isTyping].
  ///
  /// [attachments] adds up to four files (see [VatioUpload]); with them,
  /// [text] may be empty. Once the server answers, the pending message is
  /// replaced by the stored one, file URLs included. A voice note is
  /// transcribed in the background: the message shows "Audio"
  /// ([VatioMessage.isMediaLabel]) at first, and its content becomes the
  /// transcript a few seconds later, in place.
  ///
  /// The first call starts the conversation. Throws a [VatioException] —
  /// `blank_content`, `content_too_long` (4,000 characters),
  /// `too_many_files`, `file_too_large`, `unsupported_file_type`,
  /// `rate_limited`, `origin_not_allowed`, …; on failure the pending message
  /// is removed, so put the text and files back.
  Future<void> send(String text, {List<VatioUpload> attachments = const []}) async {
    final content = text.trim();
    if (content.isEmpty && attachments.isEmpty) {
      throw const VatioException('blank_content', 'content or attachments are required');
    }
    if (attachments.length > 4) {
      throw const VatioException('too_many_files', 'at most 4 files per message');
    }
    for (final file in attachments) {
      if (file.bytes.length > VatioUpload.maxBytes) {
        throw VatioException('file_too_large', '${file.filename} is over 8 MB');
      }
    }

    final pending = VatioMessage(
      id: _nextPendingId--,
      role: VatioRole.user,
      content: content,
      createdAt: DateTime.now(),
      isPending: true,
      attachments: [
        for (final (index, file) in attachments.indexed)
          VatioAttachment(
            id: -(index + 1),
            filename: file.filename,
            contentType: file.contentType,
            byteSize: file.bytes.length,
            kind: file.kind,
          ),
      ],
      isMediaLabel: content.isEmpty,
    );
    _messages = List.unmodifiable([..._messages, pending]);
    _lastError = null;
    _notify();

    try {
      final chat = await _ensureStarted(createIfMissing: true);
      await _ready();

      final path = 'chats/${chat.chatId}/messages';
      final json = attachments.isEmpty
          ? await vatio._request('POST', path, bearer: chat.chatToken, body: {'content': content})
          : await vatio._upload(path, bearer: chat.chatToken, content: content, files: attachments);

      VatioMessage? stored;
      int? id;
      try {
        final message = json['message'];
        stored = message is _Json ? _messageFrom(message) : null;
        id = json['user_message_id'] as int?;
      } on TypeError {
        // Stays pending under its own id; the socket or a resync brings the
        // stored copy.
      }
      _confirm(pending, stored, id);
      // Writing again moves the conversation on, and the moment with it.
      if (_feedback?.rating == null) _feedback = null;
      if (!_subscribed) _pollFor(_pollWindow);
      _notify();
    } catch (_) {
      _messages = List.unmodifiable(_messages.where((message) => message.id != pending.id));
      _notify();
      rethrow;
    }
  }

  /// Answers the feedback moment. [comment] (up to 2,000 characters) is
  /// meant for [VatioRating.neutral] and [VatioRating.bad]. Throws
  /// `feedback_unavailable` once the moment has passed.
  Future<void> rate(VatioRating rating, {String? comment}) => _answerFeedback(rating: rating, comment: comment);

  /// Declines the feedback moment; it is not offered again.
  Future<void> dismissFeedback() => _answerFeedback(dismiss: true);

  /// Switches to one of the visitor's past conversations, from
  /// [Vatio.conversations]. It becomes the stored one, so [resume] returns to
  /// it from then on.
  Future<void> open(VatioConversation conversation) async {
    _disconnect();
    _messages = const [];
    _lastMessageId = 0;
    _notify();
    final chat = _StoredChat(conversation.id, conversation._chatToken, conversation._expiresAt);
    _store((storage) => storage.setChat(chat));
    await _stored;
    await _connect(chat, loadHistory: true);
  }

  /// Forgets the stored conversation and clears [messages]. The next [send]
  /// starts a new one. Server history is kept.
  void startOver() {
    _disconnect();
    _store((storage) => storage.setChat(null));
    _messages = const [];
    _lastMessageId = 0;
    _lastError = null;
    _status = VatioStatus.idle;
    _notify();
  }

  /// Disconnects. Call it when the conversation leaves the screen for a
  /// while; [resume] or [send] reconnects.
  void close() {
    _disconnect();
    _status = VatioStatus.closed;
    _notify();
  }

  /// Disconnects for good. The chat cannot be used afterwards.
  @override
  void dispose() {
    _disposed = true;
    _disconnect();
    super.dispose();
  }

  // Starting

  Future<_StoredChat> _ensureStarted({required bool createIfMissing}) {
    final current = _current;
    if (current != null) return Future.value(current);
    return _starting ??= _start(createIfMissing: createIfMissing).whenComplete(() => _starting = null);
  }

  Future<_StoredChat> _start({required bool createIfMissing}) async {
    vatio._validateToken();
    _setStatus(VatioStatus.connecting);
    try {
      await _stored;
      final storage = vatio._storage(visitorToken);
      final own = await storage.chat();
      final stored = own ?? (storage.isIdentified ? await storage.anonymousChat() : null);

      if (stored != null) {
        final token = visitorToken;
        if (token != null && !await _identify(stored, token)) {
          // The stored conversation belongs to someone else.
          _store((storage) => storage.setAnonymousChat(null));
        } else {
          // Signing in keeps the conversation the visitor was having.
          if (own == null) {
            _store((storage) async {
              await storage.setChat(stored);
              await storage.setAnonymousChat(null);
            });
          }
          await _connect(stored, loadHistory: true);
          return stored;
        }
      }

      if (!createIfMissing) {
        throw const VatioException('no_conversation', 'there is no conversation to resume');
      }

      final ref = await storage.visitorRef();
      final json = await vatio._request('POST', 'chats', bearer: vatio.token, body: {
        'reply_style': replyStyle.name,
        if (ref != null) 'visitor_ref': ref,
        if (visitorToken != null) 'visitor_token': visitorToken,
      });
      final chat = _decode(() => _StoredChat(
            json['chat_id'] as int,
            json['chat_token'] as String,
            _parseDate(json['chat_token_expires_at']),
          ));
      final newRef = json['visitor_ref'];
      _store((storage) async {
        if (newRef is String) await storage.setVisitorRef(newRef);
        await storage.setChat(chat);
      });

      await _connect(chat, loadHistory: false);
      return chat;
    } catch (_) {
      if (_current == null) _setStatus(VatioStatus.idle);
      rethrow;
    }
  }

  /// False only when the server says this conversation belongs to a
  /// different person. A network failure carries on with it.
  Future<bool> _identify(_StoredChat chat, String visitorToken) async {
    try {
      final json = await vatio._request(
        'POST',
        'chats/${chat.chatId}/identify',
        bearer: chat.chatToken,
        body: {'visitor_token': visitorToken},
      );
      return json['reason'] != 'identity_changed';
    } on VatioException catch (error) {
      return error.status != 401;
    }
  }

  Future<void> _connect(_StoredChat chat, {required bool loadHistory}) async {
    _closed = false;
    _setStatus(VatioStatus.connecting);
    try {
      if (loadHistory) {
        final json = await vatio._request('GET', 'chats/${chat.chatId}/messages', bearer: chat.chatToken);
        _merge(_decode(() => _list(json).map(_messageFrom).toList()));
      }
      _current = chat;
      await _openSocket();
    } catch (_) {
      if (_current == null) _setStatus(VatioStatus.idle);
      rethrow;
    }
    await _ready();
  }

  // Transport

  Future<void> _openSocket() async {
    final chat = _current;
    if (chat == null || _closed || _disposed) return;
    final origin = await vatio._originFor();
    if (_current != chat || _closed || _disposed || _cable != null) return;

    late final _Cable cable;
    cable = _Cable(
      url: vatio._cableUrl,
      origin: origin,
      chatToken: chat.chatToken,
      onEvent: (event) {
        if (_cable == cable) _handle(event);
      },
    );
    _cable = cable;
    cable.connect();

    Timer(_subscribeTimeout, () {
      if (_cable != cable || _subscribed) return;
      // No socket in time (a network that eats upgrades): poll instead.
      _pollFor(_pollWindow);
      _releaseWaiters();
    });
  }

  void _handle(_CableEvent event) {
    switch (event) {
      case _Subscribed():
        _subscribed = true;
        _attempt = 0;
        _status = VatioStatus.connected;
        _stopPolling();
        _releaseWaiters();
        // Whatever was said while there was no subscription: the gap after
        // loading history, or a reconnect.
        if (_lastMessageId > 0) unawaited(_resync());
        // A moment offered while nobody was listening arrives this way.
        unawaited(_refreshFeedback());

      case _Rejected():
        // The credential expired or was revoked. The next send starts a new
        // conversation.
        _cable = null;
        _subscribed = false;
        _current = null;
        _store((storage) => storage.setChat(null));
        _status = VatioStatus.idle;
        _lastError = const VatioException('subscription_rejected', 'the chat credential is no longer valid');
        _releaseWaiters();

      case _Typing(:final typing):
        _isTyping = typing;

      case _Message(:final message):
        if (message.role != VatioRole.user) _isTyping = false;
        _merge([message]);

      case _Feedback(:final feedback):
        _feedback = feedback;

      case _Updated(:final id, :final content, :final isMediaLabel):
        // A voice note's transcript, in where the "Audio" label stood.
        final index = _messages.indexWhere((message) => message.id == id);
        if (index < 0) return;
        final old = _messages[index];
        _messages = List.unmodifiable([
          ..._messages.take(index),
          VatioMessage(
            id: old.id,
            role: old.role,
            content: content,
            createdAt: old.createdAt,
            attachments: old.attachments,
            isMediaLabel: isMediaLabel,
          ),
          ..._messages.skip(index + 1),
        ]);

      case _Closed():
        _cable = null;
        _subscribed = false;
        if (_closed) return;
        _status = VatioStatus.reconnecting;
        _releaseWaiters();
        _pollFor(_pollWindow);

        final delay = _reconnectDelays[math.min(_attempt, _reconnectDelays.length - 1)];
        _attempt += 1;
        Timer(delay, () {
          if (!_closed && _cable == null) unawaited(_openSocket());
        });
    }
    _notify();
  }

  /// Returns once the socket is subscribed, or once it is clear it will not
  /// be soon, so a send never races the reply it is about to cause.
  Future<void> _ready() {
    if (_cable == null || _subscribed || _polling) return Future.value();
    final waiter = Completer<void>();
    _readyWaiters.add(waiter);
    return waiter.future;
  }

  void _releaseWaiters() {
    final waiters = List.of(_readyWaiters);
    _readyWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
    }
  }

  void _disconnect() {
    _closed = true;
    _cable?.close();
    _cable = null;
    _subscribed = false;
    _current = null;
    _isTyping = false;
    _feedback = null;
    _stopPolling();
    _releaseWaiters();
  }

  // Feedback

  Future<void> _answerFeedback({VatioRating? rating, String? comment, bool dismiss = false}) async {
    final chat = _current;
    if (chat == null) {
      throw const VatioException('feedback_unavailable', 'there is no conversation');
    }
    final json = await vatio._request('POST', 'chats/${chat.chatId}/feedback', bearer: chat.chatToken, body: {
      if (rating != null) 'rating': rating.name,
      if (comment != null) 'comment': comment,
      if (dismiss) 'dismiss': true,
    });
    _feedback = _decode(() => _feedbackFrom(json['feedback']));
    _notify();
  }

  Future<void> _refreshFeedback() async {
    final chat = _current;
    if (chat == null) return;
    try {
      final json = await vatio._request('GET', 'chats/${chat.chatId}/feedback', bearer: chat.chatToken);
      final offered = _decode(() => _feedbackFrom(json['feedback']));
      if (_current?.chatId != chat.chatId || offered == _feedback) return;
      _feedback = offered;
      _notify();
    } on VatioException {
      // Next time, then.
    }
  }

  // Fallbacks

  Future<void> _resync() async {
    final chat = _current;
    if (chat == null) return;
    try {
      final json = await vatio._request(
        'GET',
        'chats/${chat.chatId}/messages?after=$_lastMessageId',
        bearer: chat.chatToken,
      );
      if (_current?.chatId != chat.chatId) return;
      final fetched = _decode(() => _list(json).map(_messageFrom).toList());
      if (fetched.any((message) => message.role != VatioRole.user)) _isTyping = false;
      _merge(fetched);
      _notify();
    } on VatioException catch (error) {
      if (error.code != 'network_error') {
        _lastError = error;
        _notify();
      }
    }
  }

  void _pollFor(Duration duration) {
    final until = DateTime.now().add(duration);
    if (until.isAfter(_pollUntil)) _pollUntil = until;
    if (_polling || _closed || _disposed) return;

    _polling = true;
    final run = ++_pollRun;
    () async {
      while (true) {
        await Future<void>.delayed(_pollInterval);
        if (run != _pollRun) return;
        if (_closed || _subscribed || DateTime.now().isAfter(_pollUntil)) break;
        await _resync();
      }
      if (run == _pollRun) _polling = false;
    }();
  }

  void _stopPolling() {
    _pollRun += 1;
    _polling = false;
  }

  // State

  // The stored message when the server returned it (its transcript, its file
  // URLs); otherwise the pending one under the server's id.
  void _confirm(VatioMessage pending, VatioMessage? stored, int? id) {
    final index = _messages.indexWhere((message) => message.id == pending.id);
    if (index < 0) return;
    final confirmedId = stored?.id ?? id;
    final rest = [..._messages]..removeAt(index);
    if (confirmedId == null || rest.any((message) => message.id == confirmedId)) {
      _messages = List.unmodifiable(rest);
      return;
    }
    rest.add(stored ??
        VatioMessage(
          id: confirmedId,
          role: VatioRole.user,
          content: pending.content,
          createdAt: pending.createdAt,
          attachments: pending.attachments,
          isMediaLabel: pending.isMediaLabel,
        ));
    _lastMessageId = math.max(_lastMessageId, confirmedId);
    _messages = List.unmodifiable(rest..sort(_order));
  }

  void _merge(List<VatioMessage> incoming) {
    if (incoming.isEmpty) return;
    final messages = [..._messages];
    final known = {for (final message in messages) message.id};
    for (final message in incoming) {
      if (known.contains(message.id)) continue;
      // A resync can return the visitor's message before `send` hears back:
      // it replaces the pending copy instead of doubling it.
      if (message.role == VatioRole.user) {
        final index = messages.indexWhere((other) => other.isPending && other.content == message.content);
        if (index >= 0) messages.removeAt(index);
      }
      messages.add(message);
      known.add(message.id);
      _lastMessageId = math.max(_lastMessageId, message.id);
    }
    _messages = List.unmodifiable(messages..sort(_order));
  }

  // Pending messages last, in the order they were sent (their ids count down
  // from -1).
  static int _order(VatioMessage a, VatioMessage b) {
    if (a.isPending != b.isPending) return a.isPending ? 1 : -1;
    return a.isPending ? b.id.compareTo(a.id) : a.id.compareTo(b.id);
  }

  void _store(Future<void> Function(_VisitorStorage storage) write) {
    final storage = vatio._storage(visitorToken);
    _stored = _stored.then((_) => write(storage)).catchError((Object _) {});
  }

  void _setStatus(VatioStatus status) {
    if (_status == status) return;
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
