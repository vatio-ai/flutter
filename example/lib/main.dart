import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vatio/vatio.dart';

import 'views.dart';

// A dummy app for trying the SDK: a home screen with an ask bar at the
// bottom, a conversation tab where the agent answers, and a settings tab for
// the workspace and token. Allow `ios-app://ai.vatio.example` or
// `android-app://ai.vatio.example` on the token first.
//
// Settings can also come from the command line, VATIO_ASK asks a question the
// way the bar does, and VATIO_ASK_FILE sends a file:
//   flutter run --dart-define=VATIO_WORKSPACE=acme --dart-define=VATIO_TOKEN=vatpub_... \
//     --dart-define=VATIO_BASE_URL=http://localhost:3000 --dart-define=VATIO_ASK=hola
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final Future<ChatStore> _store = ChatStore.load();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vatio',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5), brightness: Brightness.dark, useMaterial3: true),
      home: FutureBuilder(
        future: _store,
        builder: (context, snapshot) => switch (snapshot.data) {
          final store? => Home(store: store),
          null => const Scaffold(body: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key, required this.store});

  final ChatStore store;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _tab = 0;

  ChatStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    unawaited(store.resume());
    const question = String.fromEnvironment('VATIO_ASK');
    if (question.isNotEmpty) _ask(question);
    const file = String.fromEnvironment('VATIO_ASK_FILE');
    if (file.isNotEmpty) _askFile(file);
  }

  Future<void> _askFile(String path) async {
    setState(() => _tab = 1);
    await store.send('', attachments: [await VatioUpload.fromPath(path)]);
  }

  void _ask(String question) {
    setState(() => _tab = 1);
    store.send(question);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeTab(onAsk: _ask),
          ConversationTab(store: store),
          SettingsTab(store: store),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'Asistente'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ajustes'),
        ],
      ),
    );
  }
}

/// Holds the current VatioChat and rebuilds it when the settings change.
class ChatStore extends ChangeNotifier {
  ChatStore._(this._prefs) {
    chat = _build();
  }

  static Future<ChatStore> load() async => ChatStore._(
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {'workspace', 'token', 'baseUrl'}),
        ),
      );

  final SharedPreferencesWithCache _prefs;
  late VatioChat chat;
  String? sendError;

  /// Replies already shown in full: history from `resume()`, and every reply
  /// once its typewriter finishes. Only the rest are painted.
  final Set<int> settled = {};

  // A --dart-define wins over what was saved, for that run only.
  String get workspace => _setting('workspace', const String.fromEnvironment('VATIO_WORKSPACE'));
  String get token => _setting('token', const String.fromEnvironment('VATIO_TOKEN'));
  String get baseUrl => _setting('baseUrl', const String.fromEnvironment('VATIO_BASE_URL'), 'https://vatio.ai');

  bool get isConfigured => workspace.isNotEmpty && token.startsWith('vatpub_');

  String _setting(String key, String defined, [String fallback = '']) =>
      defined.isNotEmpty ? defined : _prefs.getString(key) ?? fallback;

  VatioChat _build() => VatioChat(Vatio(workspace: workspace, token: token, baseUrl: baseUrl));

  Future<void> save({required String workspace, required String token, required String baseUrl}) async {
    await _prefs.setString('workspace', workspace);
    await _prefs.setString('token', token);
    await _prefs.setString('baseUrl', baseUrl.isEmpty ? 'https://vatio.ai' : baseUrl);
    chat.dispose();
    chat = _build();
    settled.clear();
    sendError = null;
    notifyListeners();
    await resume();
  }

  Future<void> resume() async {
    if (!isConfigured) return;
    await chat.resume();
    settle(chat.messages);
  }

  void settle(Iterable<VatioMessage> messages) {
    settled.addAll(messages.map((message) => message.id));
    notifyListeners();
  }

  Future<void> send(String text, {List<VatioUpload> attachments = const []}) async {
    sendError = null;
    notifyListeners();
    try {
      await chat.send(text, attachments: attachments);
    } on VatioException catch (error) {
      sendError = '${error.code}: ${error.message}';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    chat.dispose();
    super.dispose();
  }
}
