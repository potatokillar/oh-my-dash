import 'package:dsh_mobile/device_store.dart';
import 'package:dsh_mobile/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Device JSON', () {
    test('roundtrip', () {
      const d = Device(id: 'dev-1', name: 'optiplex', baseUrl: 'http://x:3080');
      final back = Device.fromJson(d.toJson());
      expect(back.id, d.id);
      expect(back.name, d.name);
      expect(back.baseUrl, d.baseUrl);
    });

    test('fromJson tolerates missing fields', () {
      final d = Device.fromJson(const {});
      expect(d.id, '');
      expect(d.name, '');
      expect(d.baseUrl, '');
    });
  });

  group('isValidBaseUrl', () {
    test('accepts http/https with host', () {
      expect(isValidBaseUrl('http://100.103.29.13:3080'), isTrue);
      expect(isValidBaseUrl('https://dsh.example.com'), isTrue);
      expect(isValidBaseUrl(' http://192.168.1.2:8080 '), isTrue);
    });

    test('rejects bad input', () {
      expect(isValidBaseUrl(''), isFalse);
      expect(isValidBaseUrl('100.103.29.13:3080'), isFalse);
      expect(isValidBaseUrl('ftp://x'), isFalse);
      expect(isValidBaseUrl('http://'), isFalse);
      expect(isValidBaseUrl('not a url'), isFalse);
    });
  });

  group('DeviceStore.loadDevices', () {
    test('first run seeds the default device and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final devices = await DeviceStore.loadDevices(prefs);
      expect(devices.length, 1);
      expect(devices[0].name, DeviceStore.defaultDeviceName);
      expect(devices[0].baseUrl, DeviceStore.defaultBaseUrl);
      // Persisted: a second load reads the stored list.
      final again = await DeviceStore.loadDevices(prefs);
      expect(again.single.id, devices[0].id);
    });

    test('migrates the legacy single baseUrl setting', () async {
      SharedPreferences.setMockInitialValues({'baseUrl': 'http://10.0.0.2:3080'});
      final prefs = await SharedPreferences.getInstance();
      final devices = await DeviceStore.loadDevices(prefs);
      expect(devices.single.name, DeviceStore.defaultDeviceName);
      expect(devices.single.baseUrl, 'http://10.0.0.2:3080');
      // Legacy key removed after migration.
      expect(prefs.getString('baseUrl'), isNull);
    });

    test('loads an existing list untouched', () async {
      SharedPreferences.setMockInitialValues({
        'devices':
            '[{"id":"a","name":"n1","baseUrl":"http://h1"},{"id":"b","name":"n2","baseUrl":"http://h2"}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final devices = await DeviceStore.loadDevices(prefs);
      expect(devices.map((d) => d.id), ['a', 'b']);
      expect(devices[1].baseUrl, 'http://h2');
    });

    test('corrupt payload falls back to the default device', () async {
      SharedPreferences.setMockInitialValues({'devices': '{not json'});
      final prefs = await SharedPreferences.getInstance();
      final devices = await DeviceStore.loadDevices(prefs);
      expect(devices.single.baseUrl, DeviceStore.defaultBaseUrl);
    });
  });

  group('DeviceStore last-device', () {
    test('save/load/clear lastDeviceId', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(DeviceStore.loadLastDeviceId(prefs), isNull);
      await DeviceStore.saveLastDeviceId(prefs, 'dev-1');
      expect(DeviceStore.loadLastDeviceId(prefs), 'dev-1');
      await DeviceStore.saveLastDeviceId(prefs, null);
      expect(DeviceStore.loadLastDeviceId(prefs), isNull);
    });
  });
}
