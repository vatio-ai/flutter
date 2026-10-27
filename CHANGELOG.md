## 0.1.1

- `conversations(visitorToken:)` lists a signed-in visitor's conversations by
  their token, with no visitor id stored on the device, so they come back after
  a reinstall or on another device. It returned an empty list for a visitor
  who signed in after starting the conversation.

## 0.1.0

- First release: `Vatio` and `VatioChat`, the conversation the iOS and Android
  SDKs give, as a `ChangeNotifier` — messages, typing and connection status,
  files and voice notes, the feedback moment, signed-in visitors and past
  conversations.
