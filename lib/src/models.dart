part of '../vatio.dart';

/// Who wrote a message.
enum VatioRole {
  user,
  assistant,

  /// A role this SDK version does not know yet.
  other,
}

/// One message in a conversation, as the visitor sees it.
@immutable
class VatioMessage {
  const VatioMessage({
    required this.id,
    required this.role,
    required this.content,
    this.createdAt,
    this.isPending = false,
    this.attachments = const [],
    this.isMediaLabel = false,
  });

  /// Server id. Negative while [isPending], because the server has not
  /// assigned one yet.
  final int id;
  final VatioRole role;

  /// Markdown, as the agent wrote it. Render it as untrusted text.
  final String content;
  final DateTime? createdAt;

  /// True for a message the visitor just sent that the server has not
  /// acknowledged yet. It is shown straight away so the question is on
  /// screen before the network answers.
  final bool isPending;

  /// The visitor's own files. While [isPending] their `url` is null.
  final List<VatioAttachment> attachments;

  /// [content] is only a stand-in ("Image", "Audio") for a message that was
  /// just a file: draw the attachment, not the word.
  final bool isMediaLabel;

  bool get isFromVisitor => role == VatioRole.user;

  @override
  bool operator ==(Object other) =>
      other is VatioMessage &&
      other.id == id &&
      other.role == role &&
      other.content == content &&
      other.createdAt == createdAt &&
      other.isPending == isPending &&
      listEquals(other.attachments, attachments) &&
      other.isMediaLabel == isMediaLabel;

  @override
  int get hashCode => Object.hash(id, role, content, createdAt, isPending, Object.hashAll(attachments), isMediaLabel);

  @override
  String toString() => 'VatioMessage($id, ${role.name}${isPending ? ', pending' : ''}: $content)';
}

/// What a [VatioAttachment] is, for choosing how to draw it.
enum VatioAttachmentKind { image, audio, video, file }

/// A file on a message.
@immutable
class VatioAttachment {
  const VatioAttachment({
    required this.id,
    required this.filename,
    required this.contentType,
    required this.byteSize,
    required this.kind,
    this.url,
  });

  final int id;
  final String filename;
  final String contentType;
  final int byteSize;
  final VatioAttachmentKind kind;

  /// Absolute and signed; loads without the chat credential. Null while the
  /// message is pending.
  final Uri? url;

  @override
  bool operator ==(Object other) =>
      other is VatioAttachment &&
      other.id == id &&
      other.filename == filename &&
      other.contentType == contentType &&
      other.byteSize == byteSize &&
      other.kind == kind &&
      other.url == url;

  @override
  int get hashCode => Object.hash(id, filename, contentType, byteSize, kind, url);
}

/// A file to attach to [VatioChat.send]: an image (JPEG, PNG, WebP, GIF,
/// HEIC), a PDF, a text file, or audio (M4A, MP3, OGG, WAV, AAC, FLAC), up to
/// 8 MB. A voice note is transcribed, and the transcript becomes the
/// message's content.
@immutable
class VatioUpload {
  const VatioUpload({required this.bytes, required this.filename, required this.contentType});

  static const maxBytes = 8 * 1024 * 1024;

  final Uint8List bytes;
  final String filename;
  final String contentType;

  /// Reads a local file, taking its type from the extension -- a recorder's
  /// .m4a, a picked photo's path, a PDF from a file picker.
  static Future<VatioUpload> fromPath(String path, {String? contentType}) async {
    final filename = path.substring(path.lastIndexOf('/') + 1);
    return VatioUpload(
      bytes: await File(path).readAsBytes(),
      filename: filename,
      contentType: contentType ?? _contentTypeFor(filename),
    );
  }

  VatioAttachmentKind get kind => _kindOf(contentType);
}

/// How a reply is delivered. Fixed when a conversation starts.
enum VatioReplyStyle {
  /// One complete reply, sent the moment it is ready. The default.
  stream,

  /// Two or three short messages, each preceded by a typing indicator.
  paced,

  /// One complete reply and no typing events.
  instant,
}

/// The agent's public branding and the widget copy configured in `vatio.yml`.
@immutable
class VatioConfig {
  const VatioConfig._({
    required this.workspace,
    required this.environment,
    required this.agentName,
    required this.avatarUrl,
    required this.about,
    required this.accentColor,
    required this.title,
    required this.greeting,
    required this.suggestions,
    required this.locale,
  });

  final String workspace;
  final String environment;
  final String agentName;
  final Uri? avatarUrl;
  final String? about;

  /// `#RRGGBB`.
  final String? accentColor;
  final String? title;
  final String? greeting;
  final List<String> suggestions;

  /// `en`, `es` or `pt`: the language for your UI's own labels. The agent
  /// answers in whatever language the visitor writes.
  final String? locale;
}

/// A past conversation of this visitor, as returned by [Vatio.conversations].
@immutable
class VatioConversation {
  const VatioConversation._({
    required this.id,
    required this.title,
    required this.preview,
    required this.startedAt,
    required this.updatedAt,
    required String chatToken,
    required DateTime? expiresAt,
  })  : _chatToken = chatToken,
        _expiresAt = expiresAt;

  final int id;

  /// What the visitor opened with.
  final String title;

  /// The last thing said.
  final String preview;
  final DateTime? startedAt;
  final DateTime? updatedAt;

  final String _chatToken;
  final DateTime? _expiresAt;

  @override
  bool operator ==(Object other) => other is VatioConversation && other.id == id && other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, updatedAt);
}

/// How the visitor rated a conversation.
enum VatioRating { good, neutral, bad }

/// A moment to ask the visitor how it went, offered by Vatio once per
/// conversation when a request looks resolved.
@immutable
class VatioFeedback {
  const VatioFeedback._({
    required this.agentName,
    required this.messageId,
    required this.question,
    required this.rating,
    required this.submittedAt,
    required this.dismissed,
  });

  /// The agent that answered, for "How did `name` do?".
  final String agentName;

  /// The reply the moment is attached to.
  final int messageId;

  /// The agent's own words to ask with, written for this conversation.
  /// Null when there are none; ask in your own words then.
  final String? question;

  /// Set once the visitor answered.
  final VatioRating? rating;
  final DateTime? submittedAt;
  final bool dismissed;

  /// Still waiting for the visitor: neither rated nor dismissed.
  bool get isOpen => rating == null && !dismissed;

  @override
  bool operator ==(Object other) =>
      other is VatioFeedback &&
      other.agentName == agentName &&
      other.messageId == messageId &&
      other.question == question &&
      other.rating == rating &&
      other.submittedAt == submittedAt &&
      other.dismissed == dismissed;

  @override
  int get hashCode => Object.hash(agentName, messageId, question, rating, submittedAt, dismissed);
}

/// Every failure: a machine-readable [code], a [message] and the HTTP
/// [status] when there was a response.
class VatioException implements Exception {
  const VatioException(this.code, this.message, {this.status});

  /// `origin_not_allowed`, `rate_limited`, `no_agent_deployed`,
  /// `blank_content`, `content_too_long`, … or `network_error` when the
  /// request never got an answer.
  final String code;
  final String message;
  final int? status;

  @override
  String toString() => 'VatioException($code): $message';
}

// Wire shapes. Not public -- the server's JSON is free to grow.

typedef _Json = Map<String, dynamic>;

/// Runs a parse, turning a payload of the wrong shape into a VatioException.
T _decode<T>(T Function() parse) {
  try {
    return parse();
  } on TypeError catch (error) {
    throw VatioException('invalid_response', 'unexpected response from Vatio: $error');
  }
}

List<_Json> _list(_Json json) => (json['data'] as List? ?? const []).cast<_Json>();

VatioMessage _messageFrom(_Json json) => VatioMessage(
      id: json['id'] as int,
      role: switch (json['role']) {
        'user' => VatioRole.user,
        'assistant' => VatioRole.assistant,
        _ => VatioRole.other,
      },
      content: json['content'] as String? ?? '',
      createdAt: _parseDate(json['occurred_at'] ?? json['created_at']),
      attachments: (json['attachments'] as List? ?? const []).cast<_Json>().map(_attachmentFrom).toList(),
      isMediaLabel: json['content_is_media_label'] as bool? ?? false,
    );

VatioAttachment _attachmentFrom(_Json json) => VatioAttachment(
      id: json['id'] as int,
      filename: json['filename'] as String,
      contentType: json['content_type'] as String? ?? 'application/octet-stream',
      byteSize: json['byte_size'] as int? ?? 0,
      kind: VatioAttachmentKind.values.asNameMap()[json['kind']] ?? VatioAttachmentKind.file,
      url: json['url'] is String ? Uri.tryParse(json['url'] as String) : null,
    );

VatioFeedback? _feedbackFrom(Object? raw) {
  if (raw is! _Json) return null;
  return VatioFeedback._(
    agentName: raw['agent_name'] as String,
    messageId: raw['message_id'] as int,
    question: raw['question'] as String?,
    rating: VatioRating.values.asNameMap()[raw['rating']],
    submittedAt: _parseDate(raw['submitted_at']),
    dismissed: raw['dismissed'] as bool? ?? false,
  );
}

VatioConversation _conversationFrom(_Json json) => VatioConversation._(
      id: json['chat_id'] as int,
      title: json['title'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
      startedAt: _parseDate(json['started_at']),
      updatedAt: _parseDate(json['updated_at']),
      chatToken: json['chat_token'] as String,
      expiresAt: _parseDate(json['chat_token_expires_at']),
    );

VatioConfig _configFrom(_Json json) {
  final workspace = json['workspace'] as String;
  final agent = json['agent'] as _Json? ?? const {};
  final theme = json['theme'] as _Json? ?? const {};
  final ui = json['ui'] as _Json? ?? const {};
  final avatar = agent['avatar_url'];
  return VatioConfig._(
    workspace: workspace,
    environment: json['environment'] as String,
    agentName: agent['name'] as String? ?? workspace,
    avatarUrl: avatar is String ? Uri.tryParse(avatar) : null,
    about: agent['about'] as String?,
    accentColor: theme['accent'] as String?,
    title: ui['title'] as String?,
    greeting: ui['greeting'] as String?,
    suggestions: (ui['suggestions'] as List? ?? const []).cast<String>(),
    locale: json['locale'] as String?,
  );
}

DateTime? _parseDate(Object? value) => value is String ? DateTime.tryParse(value) : null;

VatioAttachmentKind _kindOf(String contentType) {
  if (contentType.startsWith('image/')) return VatioAttachmentKind.image;
  if (contentType.startsWith('audio/')) return VatioAttachmentKind.audio;
  if (contentType.startsWith('video/')) return VatioAttachmentKind.video;
  return VatioAttachmentKind.file;
}

// The server reads the type from the bytes; this only has to be close.
String _contentTypeFor(String filename) {
  final dot = filename.lastIndexOf('.');
  final extension = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'md' => 'text/markdown',
    'm4a' || 'mp4' => 'audio/mp4',
    'mp3' => 'audio/mpeg',
    'ogg' || 'oga' || 'opus' => 'audio/ogg',
    'wav' => 'audio/wav',
    'aac' => 'audio/aac',
    'flac' => 'audio/flac',
    _ => 'application/octet-stream',
  };
}
