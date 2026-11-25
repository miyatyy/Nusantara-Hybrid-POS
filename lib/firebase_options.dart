import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
/// Provides real Firebase project configuration for Nusantara Hybrid POS.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCLAlFEFGC4iOJ1JfxBDSFLF-YwEJ8FbcY',
    appId: '1:278951292221:web:7da93ffa549ee53b392954',
    messagingSenderId: '278951292221',
    projectId: 'nusantara-hybrid-pos',
    authDomain: 'nusantara-hybrid-pos.firebaseapp.com',
    storageBucket: 'nusantara-hybrid-pos.firebasestorage.app',
    measurementId: 'G-JV9R27MJGR',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDuyLsbr1n87DfNAn-S0x8BIG-PGfy-CNg',
    appId: '1:278951292221:android:3a3714e22baf5a37392954',
    messagingSenderId: '278951292221',
    projectId: 'nusantara-hybrid-pos',
    storageBucket: 'nusantara-hybrid-pos.firebasestorage.app',
  );
}
