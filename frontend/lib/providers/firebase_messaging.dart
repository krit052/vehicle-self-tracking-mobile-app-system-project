import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class FirebaseMessagingProvider extends ChangeNotifier {
  final _messaging = FirebaseMessaging.instance;

  String? _token;
  final List<RemoteMessage> _messages = [];

  String? get token => _token;
  List<RemoteMessage> get messages => List.unmodifiable(_messages);

  Future<void> init() async {
    await _requestPermission();
    _token = await _messaging.getToken();
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _messaging.onTokenRefresh.listen((t) {
      _token = t;
      notifyListeners();
    });
    debugPrint("FCM token: $_token");
    notifyListeners();
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  void _onForegroundMessage(RemoteMessage message) {
    _messages.insert(0, message);
    notifyListeners();
  }
}
