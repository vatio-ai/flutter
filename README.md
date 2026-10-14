# Vatio for Flutter

Talk to a [Vatio](https://vatio.ai) agent from your own Flutter app. A Dart
package with no UI: it gives you the conversation as a `ChangeNotifier`, and
you draw it however your app looks.

- Android, iOS and macOS, Flutter 3.22+
- `http`, `shared_preferences` and `package_info_plus` only

## Setup

**1. Allow your app.** A publishable token only works from its own allowed
origins. A Flutter app has one per platform: `ios-app://` plus its bundle id
(iOS and macOS) and `android-app://` plus its package name (its
`applicationId`):

```bash
vatio tokens create --env live --label app \
  --origin ios-app://com.acme.app --origin android-app://com.acme.app
```

To add them to a token you already have, use `vatio tokens origins PREFIX URL...`
or the tokens section of **Channels → Web widget** in the inbox.

**2. Add the package:**

```bash
flutter pub add vatio
```

Android release builds need `<uses-permission android:name="android.permission.INTERNET"/>`
in `android/app/src/main/AndroidManifest.xml` (Flutter's template only adds it
to debug builds), and macOS needs `com.apple.security.network.client` in both
`.entitlements` files.

**3. Create a client** with the `vatpub_` token. It is meant to ship inside
the app. A `vat_` token is a developer secret: never put one in an app.

```dart
import 'package:vatio/vatio.dart';

final vatio = Vatio(workspace: 'acme', token: 'vatpub_...');
```

## The whole API

```dart
final chat = VatioChat(vatio);       // no network yet

chat.messages                        // List<VatioMessage>, oldest first
chat.isTyping                        // the agent is writing
chat.status                          // idle connecting connected reconnecting closed
chat.lastError                       // background failures; send() throws instead
chat.feedback                        // a feedback moment on offer, or null

await chat.send('hola');             // starts the conversation on first call
await chat.send('', attachments: [upload]);   // images, PDFs, text, audio (8 MB)
await chat.resume();                 // reopen the stored conversation, if any
chat.startOver();                    // forget it; next send starts a new one
chat.close();                        // disconnect; resume() or send() reconnects
chat.dispose();                      // for good

await chat.rate(VatioRating.good);   // answer it: good neutral bad (+ comment:)
await chat.dismissFeedback();        // or decline it

await vatio.config();                // agent name, avatar, accent, greeting, suggestions
await vatio.conversations();         // this visitor's past conversations
await chat.open(conversation);       // switch to one of them
```

`VatioChat` notifies its listeners whenever any of that changes, so a
`ListenableBuilder` redraws as the reply arrives, and it drops into Provider's
or Riverpod's `ChangeNotifierProvider` as it is. `messages` is a new,
unmodifiable list each time.

A `VatioMessage` has `id`, `role` (`VatioRole.user`, `VatioRole.assistant`),
`content` (markdown, untrusted), `createdAt` and `isPending`. The visitor's
message appears in `messages` the moment `send` is called, with
`isPending == true` until the server acknowledges it; the reply follows on its
own.

## Example: a text bar that opens the conversation

A bar at the bottom of the app. When the user asks something, the app moves to
an Assistant tab where the agent is answering.

```dart
import 'package:flutter/material.dart';
import 'package:vatio/vatio.dart';

void main() => runApp(const MaterialApp(home: AcmeApp()));

class AcmeApp extends StatefulWidget {
  const AcmeApp({super.key});

  @override
  State<AcmeApp> createState() => _AcmeAppState();
}

class _AcmeAppState extends State<AcmeApp> {
  final chat = VatioChat(Vatio(workspace: 'acme', token: 'vatpub_...'));
  int tab = 0;

  @override
  void initState() {
    super.initState();
    chat.resume();
  }

  @override
  void dispose() {
    chat.dispose();
    super.dispose();
  }

  Future<void> ask(String question) async {
    setState(() => tab = 1);
    try {
      await chat.send(question);
    } on VatioException {
      // Put the text back in the field.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: tab == 0 ? const Center(child: Text('Home')) : Conversation(chat: chat)),
          AskBar(onSubmit: ask),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) => setState(() => tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.forum), label: 'Assistant'),
        ],
      ),
    );
  }
}

class Conversation extends StatelessWidget {
  const Conversation({super.key, required this.chat});

  final VatioChat chat;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => ListView(
        reverse: true, // stays on the newest message
        padding: const EdgeInsets.all(16),
        children: [
          if (chat.isTyping) const Text('…'),
          for (final message in chat.messages.reversed)
            Align(
              alignment: message.isFromVisitor ? Alignment.centerRight : Alignment.centerLeft,
              child: Opacity(
                opacity: message.isPending ? 0.6 : 1,
                child: Card(child: Padding(padding: const EdgeInsets.all(10), child: Text(message.content))),
              ),
            ),
        ],
      ),
    );
  }
}

class AskBar extends StatelessWidget {
  AskBar({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;
  final text = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: text,
          textInputAction: TextInputAction.send,
          decoration: const InputDecoration(hintText: 'Ask anything'),
          onSubmitted: (question) {
            if (question.trim().isEmpty) return;
            text.clear();
            onSubmit(question);
          },
        ),
      ),
    );
  }
}
```

Handle the exception from `send` to put the text back in the field: on failure
the pending message is removed from `messages`. `content` is markdown; render
it with a markdown package if you want links and lists, as untrusted text.

### Try it: the example app

`example/` is a runnable version of this, with a settings tab for the
workspace, token and base URL. It also paints each new reply progressively, as
the web widget does (`TypewriterText` in `views.dart`): the SDK delivers the
reply whole, and the effect is purely on screen, so copy it if you want it.
Allow `ios-app://ai.vatio.example` and `android-app://ai.vatio.example` on the
token you use (`--origin` above), then:

```bash
cd example
flutter create . --org ai.vatio --platforms ios,android
flutter run --dart-define=VATIO_WORKSPACE=acme --dart-define=VATIO_TOKEN=vatpub_...
```

`flutter create` only adds the platform folders the example leaves out.
`--dart-define=VATIO_BASE_URL=http://localhost:3000` points it at another
server, and `--dart-define=VATIO_ASK=hola` asks a question on launch.

## Files and voice notes

`send(text, attachments: ...)` takes up to four `VatioUpload`s — an image
(JPEG, PNG, WebP, GIF, HEIC), a PDF, a text file, or audio (M4A, MP3, OGG,
WAV, AAC, FLAC), up to 8 MB each. With files, the text may be empty:

```dart
// From image_picker, file_picker or a recorder: the type comes from the extension.
final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
await chat.send('Is this the right part?', attachments: [await VatioUpload.fromPath(photo!.path)]);

// A voice note recorded to .m4a (AAC), with the record package, say.
await chat.send('', attachments: [await VatioUpload.fromPath(recordingPath)]);

// Or bytes you already have.
VatioUpload(bytes: jpegBytes, filename: 'photo.jpg', contentType: 'image/jpeg');
```

The pending message shows the files at once, with `url == null`; when the
server answers it is replaced by the stored message, whose `VatioAttachment`s
each have a signed, absolute `url`. A voice note is transcribed in the
background: the message reads "Audio" at first and its `content` becomes the
transcript a few seconds later, in place. The agent waits for it. When
`isMediaLabel` is true, `content` is only a stand-in ("Image", "Audio") for a
file-only message: draw the attachment instead.

The server reads a file's type from its bytes and refuses one the agent cannot
read (`unsupported_file_type`). `example/` has a composer with a photo picker
(`Composer` and `AttachmentView` in `views.dart`).

## Visitor feedback

Vatio offers a feedback moment at most once per conversation, when a request
looks resolved and the visitor closed the topic. `chat.feedback` holds it —
pushed the moment it exists, and fetched on connect for a conversation that
was resumed. Show your own prompt while `feedback.isOpen` and answer with
`rate(rating, comment: ...)` (a comment of up to 2,000 characters, meant for
`neutral` and `bad`) or `dismissFeedback()`. It goes back to null when the
visitor writes again without answering. `example/` has a card for it
(`FeedbackCard`).

## Signed-in users

When your app knows who the user is, have your backend sign a visitor token
and pass it, so the agent can use protected tools and the conversation lands on
the right contact:

```dart
final chat = VatioChat(vatio, visitorToken: tokenFromYourBackend);
```

Pass the same token to `vatio.conversations(visitorToken: ...)`. A different
token subject is a different person, with its own conversation and history, so
signing out of your app signs out of the chat too: dispose the chat and create
a new one with the new token. An anonymous conversation is kept when the user
signs in. See
[Sessions and channels](https://vatio.ai/docs/authentication/sessions).

## Options

```dart
Vatio(
  workspace: 'acme',
  token: 'vatpub_...',
  baseUrl: 'https://vatio.ai',   // default
  appId: null,                   // defaults to the app's bundle id or package name
  httpClient: null,              // an http.Client of your own
);

VatioChat(vatio, visitorToken: null, replyStyle: VatioReplyStyle.stream);   // stream, paced, instant
```

`replyStyle` is fixed when a conversation starts. `stream` sends one complete
reply as soon as it is ready; `paced` sends two or three short messages with a
typing indicator before each, like a person texting.

## Delivery and storage

Replies arrive over a WebSocket. When it drops (the app went to the
background, the network changed), the SDK reconnects with backoff, polls in the
meantime, and fetches whatever was said while it was away. Messages are
deduplicated by id.

The current conversation and the visitor id are stored with
`shared_preferences`, per workspace and per signed-in user. Chat credentials
last 12 hours; after that, `resume()` finds nothing and the next `send` starts
a new conversation.

Limits are the same as on the web: 4,000 characters per message, and per IP
and workspace, per minute, 10 conversations started, 30 messages and 60
configuration reads or conversation lists.

## Errors

Every failure is a `VatioException` with a `code`, a `message` and the HTTP
`status` when there was one:

| `code` | Meaning |
|---|---|
| `origin_not_allowed` | `ios-app://<bundle id>` or `android-app://<package name>` is not among the token's allowed origins |
| `wrong_token_kind` | The token is not a `vatpub_` publishable token |
| `no_agent_deployed` | Nothing is published to the token's environment |
| `blank_content`, `content_too_long` | The message is empty or over 4,000 characters |
| `too_many_files`, `file_too_large`, `unsupported_file_type` | More than four files, one over 8 MB, or a type the agent cannot read |
| `rate_limited` | Too many requests; back off |
| `subscription_rejected` | The chat credential expired; the next `send` starts a new conversation |
| `network_error` | The request never got an answer |
| `unsupported_platform` | Not Android, iOS or macOS; on the web, use the widget or `@vatio-ai/sdk` |

## Versions

Versions follow semver, and `Vatio.version` matches the one on pub.dev. A
breaking change to the public API is a new major version.

## Issues

Bugs and questions go to [issues](https://github.com/vatio-ai/flutter/issues).
This repository is a read-only mirror of the SDK as it ships inside Vatio, so
a pull request cannot be merged here: open an issue describing the change
instead.
