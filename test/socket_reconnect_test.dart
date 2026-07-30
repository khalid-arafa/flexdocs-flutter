/// Coverage for reconnect resubscription.
///
/// The existing socket_service_test.dart builds a SocketService with no socket
/// at all, so none of the reconnect behaviour was exercised: disabling
/// `_resubscribeAll()` entirely left all 200 tests passing. These drive a real
/// injected `io.Socket` through the constructor's `socket:` seam.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:socket_io_client/src/manager.dart' show Manager;

import 'package:flexdocs_flutter/src/socket_service.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';
import 'package:flexdocs_flutter/src/models/socket_options.dart';

/// Records emits and lets a test fire server-side events by hand.
///
/// `onConnect`/`onDisconnect`/`onError` are extension methods on io.Socket, so
/// they route through `on`/`io.on` and need no override here.
class FakeSocket extends Fake implements sio.Socket {
  final List<EmittedEvent> emitted = [];
  final Map<String, List<dynamic Function(dynamic)>> handlers = {};
  final _FakeManager _manager = _FakeManager();
  bool disposed = false;

  @override
  Manager get io => _manager;

  @override
  void emit(String event, [dynamic data]) {
    emitted.add(EmittedEvent(event, data));
  }

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
  void dispose() {
    disposed = true;
    handlers.clear();
  }

  void fire(String event, [dynamic data]) {
    for (final handler in List<dynamic Function(dynamic)>.from(handlers[event] ?? const [])) {
      handler(data);
    }
  }

  List<EmittedEvent> get subscribeEmits =>
      emitted.where((e) => e.event.startsWith('watch-')).toList();

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

Credentials _creds() => Credentials(
      baseUrl: 'https://api.example.com',
      projectCode: 'proj',
      projectToken: 'token',
    );

void main() {
  late FakeSocket socket;

  setUp(() => socket = FakeSocket());

  SocketService serviceWith({SocketServiceOptions? options}) => SocketService(
        credentials: _creds(),
        options: options ?? const SocketServiceOptions(),
        socket: socket,
      );

  group('reconnect resubscription', () {
    test('does not double-subscribe on the first connect', () async {
      final service = serviceWith();
      service.watchCol('users').listen((_) {});
      socket.clearEmits();

      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      expect(socket.subscribeEmits, isEmpty,
          reason: 'watchCol already emitted; the first connect must not repeat it');
      service.close();
    });

    test('replays every subscription after a reconnect', () async {
      final service = serviceWith();
      service.watchCol('users').listen((_) {});
      service.watchCol('posts').listen((_) {});
      service.watchDoc('users/u1').listen((_) {});

      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);
      socket.clearEmits();

      socket.fire('disconnect', 'transport close');
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      final replayed = socket.subscribeEmits.map((e) => e.event).toList();
      expect(replayed.where((e) => e == 'watch-col-updates').length, 2);
      expect(replayed.where((e) => e == 'watch-doc').length, 1);
      service.close();
    });

    test('replays on every reconnect, not only the first', () async {
      final service = serviceWith();
      service.watchCol('users').listen((_) {});
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < 3; i++) {
        socket.clearEmits();
        socket.fire('disconnect', 'transport close');
        socket.fire('connect');
        await Future<void>.delayed(Duration.zero);
        expect(socket.subscribeEmits, hasLength(1), reason: 'reconnect #${i + 1}');
      }
      service.close();
    });

    test('does not replay a subscription that was cancelled', () async {
      final service = serviceWith();
      final sub = service.watchCol('users').listen((_) {});
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      socket.clearEmits();

      socket.fire('disconnect', 'transport close');
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      expect(socket.subscribeEmits, isEmpty);
      service.close();
    });

    test('re-asserts identity before replaying, so the rule guard sees it', () async {
      final service = serviceWith(
        options: SocketServiceOptions(getToken: () async => 'jwt-abc'),
      );
      service.watchCol('users').listen((_) {});
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);
      socket.clearEmits();

      socket.fire('disconnect', 'transport close');
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      final order = socket.emitted.map((e) => e.event).toList();
      final tokenAt = order.indexOf('set-user-token');
      final watchAt = order.indexOf('watch-col-updates');
      expect(tokenAt, isNonNegative, reason: 'token must be re-sent on reconnect');
      expect(watchAt, isNonNegative);
      expect(tokenAt, lessThan(watchAt),
          reason: 'socketColGuard checks rules against socket.sender, which the '
              'token sets — a subscribe that overtakes it is denied');
      service.close();
    });

    // The reason the replay was inert for the one shipping consumer: onConnect
    // ran synchronously while the replay waited on a microtask, so a consumer
    // that tears down and re-creates its watches in that callback — exactly the
    // workaround apps wrote for the missing replay — drained the registry
    // before the replay read it.
    //
    // Asserting "both happened" is not enough to catch that; the ordering has
    // to be observed at the moment onConnect runs.
    test('replays before invoking the caller onConnect callback', () async {
      int? replayedWhenOnConnectRan;
      final service = serviceWith(
        options: SocketServiceOptions(
          getToken: () async => 'jwt-abc',
          onConnect: () =>
              replayedWhenOnConnectRan = socket.subscribeEmits.length,
        ),
      );
      service.watchCol('users').listen((_) {});
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      socket.clearEmits();
      replayedWhenOnConnectRan = null;

      socket.fire('disconnect', 'transport close');
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      expect(replayedWhenOnConnectRan, 1,
          reason: 'the replay must already have run by the time onConnect '
              'fires, or a consumer that re-subscribes there wipes it');
      service.close();
    });

    // The concrete shape of the bug: a consumer whose onConnect cancels its
    // watches and re-creates them. If onConnect runs first the registry is
    // empty when the replay reads it, and the replay emits nothing.
    test('survives a consumer that re-creates its watches in onConnect', () async {
      late SocketService service;
      StreamSubscription<dynamic>? sub;
      var replayedEmits = 0;

      service = serviceWith(
        options: SocketServiceOptions(
          onConnect: () {
            replayedEmits = socket.subscribeEmits.length;
            sub?.cancel();
            sub = service.watchCol('users').listen((_) {});
          },
        ),
      );
      sub = service.watchCol('users').listen((_) {});
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      socket.clearEmits();
      socket.fire('disconnect', 'transport close');
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      expect(replayedEmits, 1,
          reason: 'the SDK replay must land before the consumer workaround runs');
      service.close();
    });

    test('a failing getToken still replays rather than skipping it', () async {
      final service = serviceWith(
        options: SocketServiceOptions(
          getToken: () async => throw StateError('no token'),
        ),
      );
      service.watchCol('users').listen((_) {});
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);
      socket.clearEmits();

      socket.fire('disconnect', 'transport close');
      socket.fire('connect');
      await Future<void>.delayed(Duration.zero);

      expect(socket.subscribeEmits, hasLength(1));
      service.close();
    });
  });
}
