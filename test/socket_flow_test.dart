/// Coverage for the two socket defects C13 closes.
///
/// 1. A watch registered before a socket exists was lost completely. `connect`
///    awaits `getToken` BEFORE assigning `_socket`, so the window is real and
///    not merely "before you call connect()". Both halves failed silently:
///    `_socket?.emit(...)` sent no subscribe, and `_socket?.on(...)`
///    registered no listener — so even a later replay would have had nowhere
///    to deliver. The first connect then deliberately skipped the replay, on
///    the assumption socket.io had buffered the subscribe, which is only true
///    once `_socket` is non-null.
///
/// 2. Uploads pushed every chunk into socket.io's send queue in one
///    synchronous burst, buffering the whole file a second time and giving the
///    server no way to slow a client down. The server acks each chunk with
///    `upload:progress`, and that ack was read for a byte count it does not
///    contain — `{name, received: true}` — so progress was reset to 0 by every
///    ack it received.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:socket_io_client/src/manager.dart' show Manager;

import 'package:flexdocs_flutter/src/socket_service.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';
import 'package:flexdocs_flutter/src/models/socket_options.dart';
import 'package:flexdocs_flutter/src/models/upload_progress.dart';
import 'package:flexdocs_flutter/src/models/flexdocs_exception.dart';

class FakeSocket extends Fake implements sio.Socket {
  final List<EmittedEvent> emitted = [];
  final Map<String, List<dynamic Function(dynamic)>> handlers = {};
  final _FakeManager _manager = _FakeManager();

  @override
  Manager get io => _manager;

  @override
  void emit(String event, [dynamic data]) => emitted.add(EmittedEvent(event, data));

  @override
  Function() on(String event, dynamic Function(dynamic) handler) {
    handlers.putIfAbsent(event, () => []).add(handler);
    return () => off(event, handler);
  }

  @override
  void off(String event, [dynamic Function(dynamic)? handler]) {
    if (handler == null) {
      handlers.remove(event);
    } else {
      handlers[event]?.remove(handler);
    }
  }

  @override
  void dispose() => handlers.clear();

  void fire(String event, [dynamic data]) {
    for (final handler
        in List<dynamic Function(dynamic)>.from(handlers[event] ?? const [])) {
      handler(data);
    }
  }

  List<EmittedEvent> ofType(String event) =>
      emitted.where((e) => e.event == event).toList();

  bool hasListener(String event) => (handlers[event] ?? const []).isNotEmpty;

  void clearEmits() => emitted.clear();
}

class _FakeManager extends Fake implements Manager {
  final Map<String, dynamic> _options = <String, dynamic>{'auth': {}};

  @override
  Map<String, dynamic>? get options => _options;

  @override
  Function() on(String event, dynamic Function(dynamic) handler) => () {};
}

class EmittedEvent {
  final String event;
  final dynamic data;
  EmittedEvent(this.event, this.data);
  @override
  String toString() => 'Emitted($event, $data)';
}

Credentials creds() => Credentials(
      baseUrl: 'https://api.example.com',
      projectCode: 'proj',
      projectToken: 'token',
    );

void main() {
  group('watch registered before a socket exists', () {
    late SocketService service;
    late FakeSocket socket;

    setUp(() {
      // No socket: reproduces the window inside connect() between awaiting
      // getToken and assigning _socket.
      service = SocketService(credentials: creds());
      socket = FakeSocket();
    });

    test('its subscribe is sent once the socket arrives and connects', () async {
      service.watchCol('posts').listen((_) {});
      service.attachSocketForTesting(socket);
      socket.fire('connect', null);
      await Future.delayed(Duration.zero);

      expect(
        socket.ofType('watch-col-updates').map((e) => e.data).toList(),
        [
          {'col': 'posts'}
        ],
      );
    });

    test('its listener is attached, so events actually reach the stream', () async {
      final received = <dynamic>[];
      service.watchCol('posts').listen(received.add);
      service.attachSocketForTesting(socket);
      socket.fire('connect', null);
      await Future.delayed(Duration.zero);

      expect(socket.hasListener('update:proj/posts'), isTrue);
      socket.fire('update:proj/posts', {
        'add': [
          {'_id': '1'}
        ],
      });
      await Future.delayed(Duration.zero);
      expect(received, hasLength(1));
    });

    test('a document watch is replayed the same way', () async {
      service.watchDoc('posts/abc').listen((_) {});
      service.attachSocketForTesting(socket);
      socket.fire('connect', null);
      await Future.delayed(Duration.zero);

      expect(socket.ofType('watch-doc').map((e) => e.data).toList(), [
        {'path': 'posts/abc'}
      ]);
      expect(socket.hasListener('abc'), isTrue);
    });

    test('several pending watches all survive', () async {
      service.watchCol('posts').listen((_) {});
      service.watchCol('comments').listen((_) {});
      service.attachSocketForTesting(socket);
      socket.fire('connect', null);
      await Future.delayed(Duration.zero);

      expect(socket.ofType('watch-col-updates'), hasLength(2));
    });

    test('one cancelled before the socket arrives is not subscribed', () async {
      final sub = service.watchCol('posts').listen((_) {});
      await sub.cancel();
      service.attachSocketForTesting(socket);
      socket.fire('connect', null);
      await Future.delayed(Duration.zero);

      expect(socket.ofType('watch-col-updates'), isEmpty);
      expect(socket.hasListener('update:proj/posts'), isFalse);
    });
  });

  group('watch registered after the socket exists', () {
    test('is sent once, not duplicated by the first-connect replay', () async {
      final socket = FakeSocket();
      final service = SocketService(credentials: creds(), socket: socket);

      service.watchCol('posts').listen((_) {});
      socket.fire('connect', null);
      await Future.delayed(Duration.zero);

      // socket.io buffers the emit itself; replaying it would make the server
      // re-send a watch-doc snapshot for no reason.
      expect(socket.ofType('watch-col-updates'), hasLength(1));
    });

    test('is replayed after a reconnect, when the socket id has changed', () async {
      final socket = FakeSocket();
      final service = SocketService(credentials: creds(), socket: socket);

      service.watchCol('posts').listen((_) {});
      socket.fire('connect', null);
      await Future.delayed(Duration.zero);
      socket.fire('disconnect', 'transport close');
      socket.clearEmits();

      socket.fire('connect', null);
      await Future.delayed(Duration.zero);
      expect(socket.ofType('watch-col-updates'), hasLength(1));
    });
  });

  group('upload flow control', () {
    late FakeSocket socket;
    late SocketService service;

    /// 10 chunks of 10 bytes, window of 3.
    void start({int window = 3}) {
      socket = FakeSocket();
      service = SocketService(
        credentials: creds(),
        socket: socket,
        options: SocketServiceOptions(chunkSize: 10, uploadWindow: window),
      );
      socket.fire('connect', null);
    }

    UploadHandle upload() => service.uploadFile(
          UploadFileInfo(
            name: 'f.bin',
            bytes: Uint8List.fromList(List<int>.generate(100, (i) => i % 256)),
          ),
        );

    void ack() => socket.fire('upload:progress:f.bin', {'received': true});

    test('sends only a full window before any acknowledgement', () {
      start();
      upload();
      socket.fire('upload:ready:f.bin', null);

      // Previously this emitted all 10 chunks in one burst.
      expect(socket.ofType('upload:chunk'), hasLength(3));
      expect(socket.ofType('upload:done'), isEmpty);
    });

    test('each acknowledgement admits exactly one more chunk', () {
      start();
      upload();
      socket.fire('upload:ready:f.bin', null);

      ack();
      expect(socket.ofType('upload:chunk'), hasLength(4));
      ack();
      expect(socket.ofType('upload:chunk'), hasLength(5));
    });

    test('sends every chunk exactly once and finishes', () {
      start();
      upload();
      socket.fire('upload:ready:f.bin', null);
      for (var i = 0; i < 10; i++) {
        ack();
      }

      expect(socket.ofType('upload:chunk'), hasLength(10));
      expect(socket.ofType('upload:done'), hasLength(1));
    });

    test('withholds upload:done until every chunk is acknowledged', () {
      start();
      upload();
      socket.fire('upload:ready:f.bin', null);
      // All chunks sent, but three still unacknowledged.
      for (var i = 0; i < 7; i++) {
        ack();
      }
      expect(socket.ofType('upload:chunk'), hasLength(10));
      expect(socket.ofType('upload:done'), isEmpty,
          reason: 'the server would be told the file is complete while writes '
              'were still queued behind it');

      for (var i = 0; i < 3; i++) {
        ack();
      }
      expect(socket.ofType('upload:done'), hasLength(1));
    });

    test('never emits upload:done twice on a late extra acknowledgement', () {
      start();
      upload();
      socket.fire('upload:ready:f.bin', null);
      for (var i = 0; i < 14; i++) {
        ack();
      }
      expect(socket.ofType('upload:done'), hasLength(1));
    });

    // The server ack is {name, received: true} with no byte count. Reading a
    // 'uploaded' field off it produced 0 and drove progress backwards.
    test('progress advances with acknowledgements rather than resetting to 0', () async {
      start();
      final handle = upload();
      final seen = <double>[];
      handle.progress.listen((p) => seen.add(p.progress));

      socket.fire('upload:ready:f.bin', null);
      ack();
      ack();
      await Future.delayed(Duration.zero);

      expect(seen, isNotEmpty);
      expect(seen, everyElement(greaterThanOrEqualTo(0.0)));
      expect(seen.last, closeTo(20.0, 0.001));
    });

    test('stops sending when the socket disconnects mid-file', () {
      start();
      final handle = upload();
      handle.result.catchError((_) => null); // failure is asserted elsewhere
      socket.fire('upload:ready:f.bin', null);
      final sentBeforeDrop = socket.ofType('upload:chunk').length;

      socket.fire('disconnect', 'transport close');
      ack();

      expect(socket.ofType('upload:chunk'), hasLength(sentBeforeDrop));
      expect(socket.ofType('upload:done'), isEmpty);
    });

    test('stops sending once cancelled', () {
      start();
      final handle = upload();
      handle.result.catchError((_) => null);
      socket.fire('upload:ready:f.bin', null);
      final sentBeforeCancel = socket.ofType('upload:chunk').length;

      handle.cancel();
      ack();

      expect(socket.ofType('upload:chunk'), hasLength(sentBeforeCancel));
    });

    test('a cancelled upload fails with a typed exception', () async {
      start();
      final handle = upload();
      socket.fire('upload:ready:f.bin', null);
      handle.cancel();

      await expectLater(
        handle.result,
        throwsA(isA<FlexDocsUploadException>()
            .having((e) => e.code, 'code', 'UPLOAD_CANCELLED')),
      );
    });

    test('a server-reported failure is a typed exception too', () async {
      start();
      final handle = upload();
      socket.fire('upload:ready:f.bin', null);
      socket.fire('upload:error:f.bin', {'error': 'File exceeds maximum size'});

      await expectLater(
        handle.result,
        throwsA(isA<FlexDocsUploadException>()
            .having((e) => e.message, 'message', 'File exceeds maximum size')),
      );
    });

    test('a window of 1 is strict lockstep', () {
      start(window: 1);
      upload();
      socket.fire('upload:ready:f.bin', null);
      expect(socket.ofType('upload:chunk'), hasLength(1));
      ack();
      expect(socket.ofType('upload:chunk'), hasLength(2));
    });

    test('a window wider than the file still sends each chunk once', () {
      start(window: 50);
      upload();
      socket.fire('upload:ready:f.bin', null);
      expect(socket.ofType('upload:chunk'), hasLength(10));
      for (var i = 0; i < 10; i++) {
        ack();
      }
      expect(socket.ofType('upload:done'), hasLength(1));
    });
  });
}
