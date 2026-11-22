# Keep TierTask FlutterActivity entry point and platform channel lifecycle methods.
-keep class de.akjir.tiertask.MainActivity {
    public <init>();
    public void configureFlutterEngine(io.flutter.embedding.engine.FlutterEngine);
    public void cleanUpFlutterEngine(io.flutter.embedding.engine.FlutterEngine);
    public void onRequestPermissionsResult(int, java.lang.String[], int[]);
}

# Keep Flutter plugin registration entry points discovered by GeneratedPluginRegistrant.
-keep class io.flutter.plugins.GeneratedPluginRegistrant {
    public static void registerWith(io.flutter.embedding.engine.FlutterEngine);
}
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    public <init>();
}

# Keep flutter_secure_storage plugin entry point and cipher algorithm enums resolved by name.
-keep class com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin {
    public <init>();
}
-keep enum com.it_nomads.fluttersecurestorage.ciphers.KeyCipherAlgorithm { *; }
-keep enum com.it_nomads.fluttersecurestorage.ciphers.StorageCipherAlgorithm { *; }
