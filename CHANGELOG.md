## 0.2.0

- `VatioMessage.buttons`: the links the agent's reply sends as buttons, each
  with its `title` and `url`, and `textWithoutButtons`, the message's content
  without those links, to draw above them. See https://vatio.ai/docs/links#buttons.

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
