import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:yt_local_music/services/device_music_service.dart';

void main() {
  group('OnDeviceDeviceMusicService permission selection', () {
    test('API 33+ uses READ_MEDIA_AUDIO (Permission.audio)', () {
      expect(
        OnDeviceDeviceMusicService.permissionForApiLevel(33),
        ph.Permission.audio,
      );
      expect(
        OnDeviceDeviceMusicService.permissionForApiLevel(36),
        ph.Permission.audio,
      );
    });

    test('API <= 32 uses READ_EXTERNAL_STORAGE (Permission.storage)', () {
      expect(
        OnDeviceDeviceMusicService.permissionForApiLevel(32),
        ph.Permission.storage,
      );
      expect(
        OnDeviceDeviceMusicService.permissionForApiLevel(26),
        ph.Permission.storage,
      );
    });

    test('injected sdk drives the permission without a platform channel',
        () async {
      expect(
        await OnDeviceDeviceMusicService(androidSdkInt: 34).permissionForSdk(),
        ph.Permission.audio,
      );
      expect(
        await OnDeviceDeviceMusicService(androidSdkInt: 28).permissionForSdk(),
        ph.Permission.storage,
      );
    });
  });
}