part of '../vatio.dart';

sealed class _CableEvent {
  const _CableEvent();
}

final class _Subscribed extends _CableEvent {
  const _Subscribed();
}

final class _Rejected extends _CableEvent {
  const _Rejected();
}

final class _Typing extends _CableEvent {
  const _Typing(this.typing);
  final bool typing;
}

final class _Message extends _CableEvent {
  const _Message(this.message);
  final VatioMessage message;
}

final class _Feedback extends _CableEvent {
  const _Feedback(this.feedback);
  final VatioFeedback? feedback;
}

final class _Updated extends _CableEvent {
  const _Updated(this.id, this.content, this.isMediaLabel);
  final int id;
  final String content;
  final bool isMediaLabel;
}

final class _Closed extends _CableEvent {
  const _Closed();
}

/// The realtime half: one Action Cable subscription to the visitor's own
/// conversation. Not public -- the wire format is free to change, VatioChat is
/// the contract.
class _Cable {
  _Cable({required this.url, required this.origin, required String chatToken, required this.onEvent})
      // Keys in sorted order, so the identifier the server echoes back is
      // always the same string this sent.
      : _identifier = jsonEncode({'channel': 'VisitorChatChannel', 'chat_token': chatToken});

  final Uri url;
  final String origin;
  final void Function(_CableEvent event) onEvent;
  final String _identifier;

  WebSocket? _socket;
  // Closed by close(), rejected, or already reported as closed: no more
  // events from this cable.
  bool _done = false;

  void connect() {
    WebSocket.connect(
      url.toString(),
      protocols: const ['actioncable-v1-json', 'actioncable-unsupported'],
      headers: {'Origin': origin},
    ).then((socket) {
      if (_done) {
        socket.close(WebSocketStatus.goingAway);
        return;
      }
      _socket = socket..pingInterval = const Duration(seconds: 15);
      socket.listen(_receive, onDone: _ended, onError: (Object _) => _ended(), cancelOnError: true);
    }, onError: (Object _) => _ended());
  }

  void close() {
    if (_done) return;
    _done = true;
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    _send({'command': 'unsubscribe', 'identifier': _identifier}, socket);
    socket.close(WebSocketStatus.goingAway);
  }

  // Closed by the network rather than by close(): report it once.
  void _ended() {
    if (_done) return;
    _done = true;
    _socket = null;
    onEvent(const _Closed());
  }

  void _receive(Object? frame) {
    if (_done) return;
    final text = switch (frame) {
      String string => string,
      List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    _Json json;
    try {
      final decoded = text == null ? null : jsonDecode(text);
      if (decoded is! _Json) return;
      json = decoded;
    } on FormatException {
      return;
    }

    switch (json['type']) {
      case 'welcome':
        final socket = _socket;
        if (socket != null) _send({'command': 'subscribe', 'identifier': _identifier}, socket);
      case 'confirm_subscription':
        onEvent(const _Subscribed());
      case 'reject_subscription':
        _done = true;
        _socket?.close(WebSocketStatus.normalClosure);
        _socket = null;
        onEvent(const _Rejected());
      case 'ping' || 'disconnect':
        // A disconnect is followed by the socket closing, which is where
        // reconnecting happens.
        return;
      default:
        final event = json['message'];
        if (event is _Json) _dispatch(event);
    }
  }

  void _dispatch(_Json event) {
    try {
      switch (event['type']) {
        case 'typing_start':
          onEvent(const _Typing(true));
        case 'typing_stop':
          onEvent(const _Typing(false));
        case 'message':
          onEvent(_Message(_messageFrom(event['message'] as _Json)));
        case 'message_updated':
          final update = event['message'] as _Json;
          onEvent(_Updated(
            update['id'] as int,
            update['content'] as String? ?? '',
            update['content_is_media_label'] as bool? ?? false,
          ));
        case 'feedback':
          onEvent(_Feedback(_feedbackFrom(event['feedback'])));
      }
    } on TypeError {
      // An event of a shape this version does not know: skip it.
    }
  }

  void _send(Map<String, String> command, WebSocket socket) {
    try {
      socket.add(jsonEncode(command));
    } on StateError {
      // Already closing.
    }
  }
}
