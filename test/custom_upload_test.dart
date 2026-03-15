import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/custom_upload.dart';
import 'package:flexdocs_flutter/src/socket_service.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';
import 'package:flexdocs_flutter/src/models/upload_progress.dart';

void main() {
  late Credentials creds;
  late SocketService socketService;

  setUp(() {
    creds = Credentials(
      baseUrl: 'https://api.example.com',
      projectCode: 'test',
      projectToken: 'token',
    );
    socketService = SocketService(credentials: creds);
  });

  group('CustomUpload', () {
    test('completes immediately with empty file list', () async {
      final upload = CustomUpload(
        socketService: socketService,
        files: [],
      );

      final result = await upload.result;
      expect(result, isEmpty);
    });

    test('cancel completes result with error', () async {
      final file = UploadFileInfo(
        name: 'test.txt',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      final upload = CustomUpload(
        socketService: socketService,
        files: [file],
      );

      upload.cancel();

      expect(() => upload.result, throwsA(anything));
    });

    test('progress stream is broadcast', () {
      final upload = CustomUpload(
        socketService: socketService,
        files: [],
      );

      // Should be able to listen multiple times on a broadcast stream
      upload.progress.listen((_) {});
      upload.progress.listen((_) {});
    });

    test('upload with socket not connected fails gracefully', () async {
      final file = UploadFileInfo(
        name: 'test.txt',
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      final upload = CustomUpload(
        socketService: socketService,
        files: [file],
        autoDispose: true,
      );

      // Socket is not connected, so upload should fail
      try {
        await upload.result;
        fail('Should have thrown');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    test('multiple files with no connection all fail', () async {
      final files = [
        UploadFileInfo(name: 'a.txt', bytes: Uint8List(10)),
        UploadFileInfo(name: 'b.txt', bytes: Uint8List(20)),
        UploadFileInfo(name: 'c.txt', bytes: Uint8List(30)),
      ];

      final upload = CustomUpload(
        socketService: socketService,
        files: files,
      );

      try {
        await upload.result;
        fail('Should have thrown');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    test('autoDispose false keeps streams open after completion', () async {
      final upload = CustomUpload(
        socketService: socketService,
        files: [],
        autoDispose: false,
      );

      await upload.result;
      // Should not throw when listening after completion
      upload.progress.listen((_) {});
    });
  });
}
