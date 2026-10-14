# Vatio example

A dummy app for trying the Vatio Flutter SDK: a home screen with an ask bar, a
conversation tab where the agent answers, and a settings tab for the workspace
and token.

Allow `ios-app://ai.vatio.example` and `android-app://ai.vatio.example` on the
publishable token you use, then make the platform folders this example leaves
out and run it:

```bash
flutter create . --org ai.vatio --platforms ios,android
flutter run --dart-define=VATIO_WORKSPACE=acme --dart-define=VATIO_TOKEN=vatpub_...
```

`--dart-define=VATIO_BASE_URL=http://localhost:3000` points it at another
server, `--dart-define=VATIO_ASK=hola` asks a question on launch, and
`--dart-define=VATIO_ASK_FILE=/path/to/note.m4a` sends a file. Without them,
fill in the settings tab.
