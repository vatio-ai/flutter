/// Talk to a Vatio agent from your own Flutter app.
///
///     final chat = VatioChat(Vatio(workspace: 'acme', token: 'vatpub_...'));
///     await chat.send('hola');
///
/// [VatioChat] is a [ChangeNotifier] with no UI: listen to it and draw
/// [VatioChat.messages] however your app looks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'src/cable.dart';
part 'src/chat.dart';
part 'src/client.dart';
part 'src/models.dart';
part 'src/storage.dart';
