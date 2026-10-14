import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vatio/vatio.dart';

import 'main.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onAsk});

  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inicio')),
      body: ListView(
        children: [
          const ListTile(leading: Icon(Icons.local_shipping_outlined), title: Text('Pedidos')),
          const ListTile(leading: Icon(Icons.credit_card), title: Text('Pagos')),
          const ListTile(leading: Icon(Icons.person_outline), title: Text('Perfil')),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Escribe una pregunta abajo: la app pasa a la pestaña Asistente y el agente responde ahí.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      bottomNavigationBar: AskBar(onSubmit: onAsk),
    );
  }
}

class AskBar extends StatefulWidget {
  const AskBar({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<AskBar> createState() => _AskBarState();
}

class _AskBarState extends State<AskBar> {
  final _text = TextEditingController();

  void _submit() {
    final question = _text.text.trim();
    if (question.isEmpty) return;
    _text.clear();
    widget.onSubmit(question);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(hintText: 'Pregúntale al asistente', border: OutlineInputBorder()),
              ),
            ),
            IconButton(onPressed: _submit, icon: const Icon(Icons.arrow_upward)),
          ],
        ),
      ),
    );
  }
}

class ConversationTab extends StatelessWidget {
  const ConversationTab({super.key, required this.store});

  final ChatStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final chat = store.chat;
        return ListenableBuilder(
          listenable: chat,
          builder: (context, _) {
            final feedback = chat.feedback;
            final error = store.sendError ?? chat.lastError?.message;
            final rows = <Widget>[
              if (chat.messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    store.isConfigured ? 'Todavía no hay conversación.' : 'Configura workspace y token en Ajustes.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final message in chat.messages)
                Bubble(
                  key: ValueKey(message.id),
                  message: message,
                  paints: message.role == VatioRole.assistant && !store.settled.contains(message.id),
                  onFinish: () => store.settle([message]),
                ),
              if (feedback != null && (feedback.isOpen || feedback.rating != null))
                FeedbackCard(chat: chat, feedback: feedback),
              if (chat.isTyping)
                const Row(children: [
                  SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Escribiendo…')
                ]),
              if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ];
            return Scaffold(
              appBar: AppBar(
                title: const Text('Asistente'),
                leading: Center(child: StatusDot(status: chat.status)),
                leadingWidth: 120,
                actions: [
                  TextButton(onPressed: chat.messages.isEmpty ? null : chat.startOver, child: const Text('Nueva')),
                ],
              ),
              // Reversed, so the list stays pinned to the newest message as
              // replies arrive and grow.
              body: ListView(
                reverse: true,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final row in rows.reversed)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: row),
                ],
              ),
              bottomNavigationBar: Composer(
                onSend: (text, files) => store.send(text, attachments: files),
              ),
            );
          },
        );
      },
    );
  }
}

class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.message, this.paints = false, this.onFinish});

  final VatioMessage message;
  final bool paints;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mine = message.isFromVisitor;
    final foreground = mine ? colors.onPrimary : colors.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Opacity(
          opacity: message.isPending ? 0.6 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: mine ? colors.primary : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final attachment in message.attachments)
                    AttachmentView(attachment: attachment, color: foreground),
                  // A file-only message carries a stand-in ("Image"); the
                  // file above already says it.
                  if (!message.isMediaLabel && message.content.isNotEmpty)
                    TypewriterText(
                      text: message.content,
                      paints: paints,
                      onFinish: onFinish,
                      style: TextStyle(color: foreground),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status});

  final VatioStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      VatioStatus.connected => (Colors.green, 'en vivo'),
      VatioStatus.connecting => (Colors.orange, 'conectando'),
      VatioStatus.reconnecting => (Colors.orange, 'reconectando'),
      VatioStatus.idle => (Colors.grey, 'sin conversación'),
      VatioStatus.closed => (Colors.grey, 'cerrado'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.store});

  final ChatStore store;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final _workspace = TextEditingController(text: widget.store.workspace);
  late final _token = TextEditingController(text: widget.store.token);
  late final _baseUrl = TextEditingController(text: widget.store.baseUrl);
  String? _agent;

  Future<void> _apply() async {
    setState(() => _agent = 'Verificando…');
    await widget.store.save(
      workspace: _workspace.text.trim(),
      token: _token.text.trim(),
      baseUrl: _baseUrl.text.trim(),
    );
    String result;
    try {
      final config = await widget.store.chat.vatio.config();
      result = 'Conectado a ${config.agentName} (${config.environment})';
    } on VatioException catch (error) {
      result = '${error.code}: ${error.message}';
    }
    if (mounted) setState(() => _agent = result);
  }

  @override
  void dispose() {
    _workspace.dispose();
    _token.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _workspace,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Workspace (slug)'),
          ),
          TextField(controller: _token, autocorrect: false, decoration: const InputDecoration(labelText: 'vatpub_…')),
          TextField(
            controller: _baseUrl,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'https://vatio.ai'),
          ),
          const SizedBox(height: 8),
          Text(
            'Agrega ios-app://ai.vatio.example y android-app://ai.vatio.example a los orígenes del token.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _apply, child: const Text('Guardar y conectar')),
          if (_agent case final agent?) Padding(padding: const EdgeInsets.only(top: 8), child: Text(agent)),
        ],
      ),
    );
  }
}

/// Shows a reply that arrived whole as if it were being written, the way the
/// web widget does: the SDK delivers the complete message, and the effect is
/// purely on screen. Faster the more text is left, so a long answer never
/// keeps the reader waiting. Tap to show it all at once.
class TypewriterText extends StatefulWidget {
  const TypewriterText({super.key, required this.text, required this.paints, this.onFinish, this.style});

  final String text;
  final bool paints;
  final VoidCallback? onFinish;
  final TextStyle? style;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  late int _shown = widget.paints ? 0 : _length;
  Timer? _timer;
  final _clock = Stopwatch();

  int get _length => widget.text.characters.length;

  @override
  void initState() {
    super.initState();
    if (_shown < _length) _paint();
  }

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (!widget.paints) {
      _timer?.cancel();
      _shown = _length;
    } else if (_shown < _length && _timer == null) {
      _paint();
    }
  }

  void _paint() {
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final elapsed = _clock.elapsedMicroseconds / 1e6;
      _clock.reset();
      // Characters per second, as in the widget: behind / 0.4s, 170...900.
      final rate = ((_length - _shown) / 0.4).clamp(170, 900);
      setState(() => _shown = math.min(_length, _shown + math.max(1, (rate * elapsed).round())));
      if (_shown >= _length) _finish();
    });
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    if (_shown < _length) setState(() => _shown = _length);
    widget.onFinish?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _shown < _length ? _finish : null,
      child: Text(widget.text.characters.take(_shown).toString(), style: widget.style),
    );
  }
}

/// What Vatio's feedback moment looks like in this app. The SDK only says when
/// to ask (`chat.feedback`) and takes the answer (`rate`, `dismissFeedback`);
/// the card is yours to design.
class FeedbackCard extends StatefulWidget {
  const FeedbackCard({super.key, required this.chat, required this.feedback});

  final VatioChat chat;
  final VatioFeedback feedback;

  @override
  State<FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<FeedbackCard> {
  VatioRating? _picked;
  final _comment = TextEditingController();
  bool _sending = false;
  String? _error;

  static const _labels = {VatioRating.good: 'Bien', VatioRating.neutral: 'Más o menos', VatioRating.bad: 'Mal'};

  // "Bien" needs no explanation, so it goes straight out.
  void _choose(VatioRating rating) {
    setState(() => _picked = rating);
    if (rating == VatioRating.good) _answer(() => widget.chat.rate(VatioRating.good));
  }

  Future<void> _answer(Future<void> Function() call) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await call();
    } on VatioException catch (error) {
      _error = error.message;
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedback = widget.feedback;
    final picked = _picked;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (feedback.rating != null)
              const Row(children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('¡Gracias por tu opinión!')
              ])
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      feedback.question ?? '¿Cómo lo hizo ${feedback.agentName}?',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _sending ? null : () => _answer(widget.chat.dismissFeedback),
                    child: const Text('Omitir'),
                  ),
                ],
              ),
              SegmentedButton<VatioRating>(
                segments: [
                  for (final rating in VatioRating.values) ButtonSegment(value: rating, label: Text(_labels[rating]!)),
                ],
                selected: picked == null ? {} : {picked},
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                onSelectionChanged: _sending ? null : (selection) => _choose(selection.first),
              ),
              if (picked != null && picked != VatioRating.good) ...[
                TextField(
                  controller: _comment,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: '¿Qué pudo salir mejor? (opcional)'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _sending
                      ? null
                      : () => _answer(
                            () => widget.chat.rate(picked, comment: _comment.text.isEmpty ? null : _comment.text),
                          ),
                  child: const Text('Enviar'),
                ),
              ],
            ],
            if (_error case final error?) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
    );
  }
}

/// The conversation's input: text, or a photo from the library.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.onSend});

  final void Function(String text, List<VatioUpload> files) onSend;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();

  void _sendText() {
    final message = _text.text.trim();
    if (message.isEmpty) return;
    _text.clear();
    widget.onSend(message, const []);
  }

  Future<void> _pickPhoto() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (photo == null) return;
    widget.onSend('', [await VatioUpload.fromPath(photo.path, contentType: photo.mimeType)]);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          children: [
            IconButton(onPressed: _pickPhoto, icon: const Icon(Icons.attach_file)),
            Expanded(
              child: TextField(
                controller: _text,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: const InputDecoration(hintText: 'Escribe un mensaje', border: OutlineInputBorder()),
              ),
            ),
            IconButton(onPressed: _sendText, icon: const Icon(Icons.arrow_upward)),
          ],
        ),
      ),
    );
  }
}

/// How this app draws a file on a message: the image, or a link for anything
/// else. While pending there is no URL yet.
class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.attachment, required this.color});

  final VatioAttachment attachment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final url = attachment.url;
    if (attachment.kind == VatioAttachmentKind.image) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: url == null
              ? const SizedBox(width: 160, height: 120, child: Center(child: CircularProgressIndicator()))
              : Image.network(url.toString(), width: 220, fit: BoxFit.contain),
        ),
      );
    }
    final label = attachment.kind == VatioAttachmentKind.audio ? 'Nota de voz' : attachment.filename;
    final icon = attachment.kind == VatioAttachmentKind.audio ? Icons.play_circle : Icons.description_outlined;
    return TextButton.icon(
      onPressed: url == null ? null : () => launchUrl(url),
      icon: Icon(icon, color: color),
      label: Text(label, style: TextStyle(color: color)),
    );
  }
}
