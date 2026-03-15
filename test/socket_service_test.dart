import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/socket_service.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';
import 'package:flexdocs_flutter/src/models/socket_options.dart';
import 'package:flexdocs_flutter/src/models/collection_event.dart';
import 'package:flexdocs_flutter/src/models/document_event.dart';
import 'package:flexdocs_flutter/src/models/upload_progress.dart';

/// A minimal mock Socket that records emitted events and allows
/// triggering incoming events for testing.
class MockSocket {
  final Map<String, List<Function>> _listeners = {};
  final List<EmittedEvent> emitted = [];
  bool disposed = false;

  void on(String event, Function callback) {
    _listeners.putIfAbsent(event, () => []).add(callback);
  }

  void off(String event, [Function? callback]) {
    if (callback != null) {
      _listeners[event]?.remove(callback);
    } else {
      _listeners.remove(event);
    }
  }

  void emit(String event, [dynamic data]) {
    emitted.add(EmittedEvent(event, data));
  }

  void onConnect(Function callback) => on('connect', callback);
  void onDisconnect(Function callback) => on('disconnect', callback);
  void onConnectError(Function callback) => on('connect_error', callback);
  void onError(Function callback) => on('error', callback);

  void dispose() {
    disposed = true;
    _listeners.clear();
  }

  /// Simulate an incoming event from the server.
  void simulateEvent(String event, [dynamic data]) {
    final callbacks = List<Function>.from(_listeners[event] ?? []);
    for (final cb in callbacks) {
      cb(data);
    }
  }

  /// Simulate a connection.
  void simulateConnect() => simulateEvent('connect', null);

  /// Simulate a disconnection.
  void simulateDisconnect(String reason) => simulateEvent('disconnect', reason);

  Map<String, dynamic>? io;
}

class EmittedEvent {
  final String event;
  final dynamic data;
  EmittedEvent(this.event, this.data);

  @override
  String toString() => 'Emitted($event, $data)';
}

/// Creates a SocketService with a mock socket injected.
SocketService createTestService(MockSocket mock) {
  final creds = Credentials(
    baseUrl: 'https://api.example.com',
    projectCode: 'test',
    projectToken: 'token',
  );

  // We pass the mock as the socket parameter.
  // Since MockSocket isn't a real io.Socket, we use a wrapper approach.
  // For testing, we'll directly test the SocketService methods that don't
  // need a real socket, and test the watch/upload logic via event simulation.
  return SocketService(
    credentials: creds,
    options: const SocketServiceOptions(chunkSize: 10),
  );
}

void main() {
  group('SocketService connection state', () {
    test('starts disconnected', () {
      final creds = Credentials(
        baseUrl: 'https://api.example.com',
        projectCode: 'test',
        projectToken: 'token',
      );
      final service = SocketService(credentials: creds);
      expect(service.isConnected, isFalse);
    });

    test('waitForConnection times out when not connected', () async {
      final creds = Credentials(
        baseUrl: 'https://api.example.com',
        projectCode: 'test',
        projectToken: 'token',
      );
      final service = SocketService(credentials: creds);
      final result = await service.waitForConnection(timeout: 100);
      expect(result, isFalse);
    });

    test('close cleans up resources', () {
      final creds = Credentials(
        baseUrl: 'https://api.example.com',
        projectCode: 'test',
        projectToken: 'token',
      );
      final service = SocketService(credentials: creds);
      // Should not throw even without a socket
      service.close();
      expect(service.isConnected, isFalse);
    });
  });

  group('CollectionChangeEvent', () {
    test('fromMap parses data', () {
      final event = CollectionChangeEvent.fromMap({
        'data': [
          {'_id': '1', 'name': 'Alice'}
        ],
      });
      expect(event.data, hasLength(1));
      expect(event.data![0]['name'], 'Alice');
    });

    test('fromMap parses added/updated/removed', () {
      final event = CollectionChangeEvent.fromMap({
        'added': [
          {'_id': '2', 'name': 'Bob'}
        ],
        'updated': [
          {'_id': '1', 'name': 'Alice Updated'}
        ],
        'removed': [
          {'_id': '3', 'name': 'Charlie'}
        ],
      });
      expect(event.added, hasLength(1));
      expect(event.updated, hasLength(1));
      expect(event.removed, hasLength(1));
    });

    test('error factory creates error event', () {
      final event = CollectionChangeEvent.error('Something went wrong');
      expect(event.error, 'Something went wrong');
      expect(event.data, isNull);
    });
  });

  group('DocumentChangeEvent', () {
    test('fromMap parses update action', () {
      final event = DocumentChangeEvent.fromMap({
        'action': 'update',
        'doc': {'_id': '1', 'name': 'Alice'},
      });
      expect(event.action, DocumentAction.update);
      expect(event.doc!['name'], 'Alice');
    });

    test('fromMap parses delete action', () {
      final event = DocumentChangeEvent.fromMap({
        'action': 'delete',
        'doc': {'_id': '1'},
      });
      expect(event.action, DocumentAction.delete);
    });

    test('error factory creates error event', () {
      final event = DocumentChangeEvent.error('Oops');
      expect(event.error, 'Oops');
      expect(event.action, isNull);
    });
  });

  group('UploadHandle and UploadProgress', () {
    test('UploadProgress copyWith works', () {
      final progress = UploadProgress(
        key: 'k1',
        name: 'file.txt',
        size: 100,
        status: UploadStatus.pending,
      );

      final updated = progress.copyWith(
        status: UploadStatus.uploading,
        progress: 50.0,
      );

      expect(updated.key, 'k1');
      expect(updated.name, 'file.txt');
      expect(updated.status, UploadStatus.uploading);
      expect(updated.progress, 50.0);
    });

    test('UploadFileInfo computes size from bytes', () {
      final file = UploadFileInfo(
        name: 'test.bin',
        bytes: Uint8List(256),
      );
      expect(file.size, 256);
      expect(file.name, 'test.bin');
    });
  });

  group('SocketService upload tracking', () {
    test('getAllUploads returns empty list initially', () {
      final creds = Credentials(
        baseUrl: 'https://api.example.com',
        projectCode: 'test',
        projectToken: 'token',
      );
      final service = SocketService(credentials: creds);
      expect(service.getAllUploads(), isEmpty);
    });
  });
}
