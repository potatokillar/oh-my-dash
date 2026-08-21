/// Device list persistence on shared_preferences, including migration from
/// the legacy single-server `baseUrl` setting.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class DeviceStore {
  static const devicesKey = 'devices';
  static const lastDeviceKey = 'lastDeviceId';
  static const legacyBaseUrlKey = 'baseUrl';

  static const defaultDeviceName = 'yo-optiplex-7080';
  static const defaultBaseUrl = 'http://100.103.29.13:3080';

  /// Loads the device list, migrating the legacy single `baseUrl` setting
  /// (or seeding a default device on first run) when no list exists yet.
  static Future<List<Device>> loadDevices(SharedPreferences prefs) async {
    final raw = prefs.getString(devicesKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => Device.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      } catch (_) {
        // Corrupt payload: fall through to re-seeding the default device.
      }
    }
    final migrated = Device(
      id: 'dev-legacy',
      name: defaultDeviceName,
      baseUrl: prefs.getString(legacyBaseUrlKey) ?? defaultBaseUrl,
    );
    await saveDevices(prefs, [migrated]);
    await prefs.remove(legacyBaseUrlKey);
    return [migrated];
  }

  static Future<void> saveDevices(
          SharedPreferences prefs, List<Device> devices) =>
      prefs.setString(
          devicesKey, jsonEncode(devices.map((d) => d.toJson()).toList()));

  static String? loadLastDeviceId(SharedPreferences prefs) =>
      prefs.getString(lastDeviceKey);

  static Future<void> saveLastDeviceId(SharedPreferences prefs, String? id) =>
      id == null
          ? prefs.remove(lastDeviceKey)
          : prefs.setString(lastDeviceKey, id);
}
