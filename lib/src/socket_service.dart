import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'models/credentials.dart';
import 'models/socket_options.dart';
import 'models/collection_event.dart';
import 'models/document_event.dart';
import 'models/upload_progress.dart';
import 'models/flexdocs_exception.dart';
import 'logger.dart';

/// Socket.IO service for real-time subscriptions and file uploads.
class SocketService {
  final Credentials _credentials;
  final SocketServiceOptions _options;
  io.Socket? _socket;
  bool _connected = false;
  bool _hasConnected = false;
  Completer<bool>? _connectionCompleter;

  /// Active upload trackers keyed by upload key.
  final Map<String, _UploadTracker> _activeUploads = {};

  /// Active watch subscriptions keyed by the event name the server emits on.
  /// Carries the subscribe payload as well as the reference count, because the
  /// server rooms are keyed by socket id and a reconnect has to replay them.
  final Map<String, _WatchSubscription> _watchSubscriptions = {};

  /// Every open watch controller, so [close] can hand watchers a done event.
  final Set<StreamController<Object>> _watchControllers = {};

  /// Handlers registered while `_socket` was still null, waiting to be
  /// attached once it exists.
  ///
  /// [connect] awaits `getToken` before it assigns `_socket`, so there is a
  /// real window — not just "before you call connect()" — in which `watchCol`
  /// and `watchDoc` run with no socket to register on. Every `_socket?.on(...)`
  /// in that window silently did nothing, which meant such a watch received no
  /// events ever: not only was its subscribe never sent, its listener was
  /// never attached either, so even a replayed subscribe would have gone
  /// nowhere.
  final Map<String, List<Function(dynamic)>> _pendingListeners = {};

  SocketService({
    required Credentials credentials,
    SocketServiceOptions options = const SocketServiceOptions(),
    io.Socket? socket,
  })  : _credentials = credentials,
        _options = options {
    if (socket != null) {
      _socket = socket;
      _setupListeners();
    }
  }

  /// Initialize the socket connection.
  Future<void> connect() async {
    if (_socket != null) return;

    String? userToken;
    if (_options.getToken != null) {
      userToken = await _options.getToken!();
    }

    _socket = io.io(
      _credentials.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({
            'projectToken': _credentials.projectToken,
            'projectCode': _credentials.projectCode,
            // Server's socketAuth reads `userToken` (not `token`) from the
            // handshake to set socket.sender.
            'userToken': ?userToken,
          })
          .enableReconnection()
          .setReconnectionDelay(_options.reconnectionDelay)
          .setReconnectionDelayMax(_options.reconnectionDelayMax)
          .setReconnectionAttempts(_options.reconnectionAttempts)
          .setTimeout(_options.timeout)
          .build(),
    );

    _setupListeners();
  }

  /// Attaches an already-built socket, exactly as [connect] does with the one
  /// it constructs.
  ///
  /// Exists so tests can exercise the window between a watch being registered
  /// and a socket existing. [connect] cannot stand in for that: it always
  /// builds a real `io.Socket` that would try to open a network connection.
  @visibleForTesting
  void attachSocketForTesting(io.Socket socket) {
    _socket = socket;
    _setupListeners();
  }

  /// Registers [handler] for [event], buffering it if there is no socket yet.
  void _on(String event, Function(dynamic) handler) {
    final socket = _socket;
    if (socket != null) {
      socket.on(event, handler);
      return;
    }
    _pendingListeners.putIfAbsent(event, () => []).add(handler);
  }

  /// Removes [handler], whether it was attached to a socket or still pending.
  void _off(String event, Function(dynamic) handler) {
    _socket?.off(event, handler);
    final pending = _pendingListeners[event];
    if (pending == null) return;
    pending.remove(handler);
    if (pending.isEmpty) _pendingListeners.remove(event);
  }

  /// Attaches everything registered before the socket existed. Called from
  /// [_setupListeners], which runs immediately after `_socket` is assigned in
  /// both the constructor and [connect].
  void _flushPendingListeners() {
    if (_pendingListeners.isEmpty) return;
    for (final entry in _pendingListeners.entries) {
      for (final handler in entry.value) {
        _socket!.on(entry.key, handler);
      }
    }
    _pendingListeners.clear();
  }

  void _setupListeners() {
    _flushPendingListeners();

    _socket!.onConnect((_) {
      final reconnected = _hasConnected;
      _connected = true;
      _hasConnected = true;
      logger.info('Socket connected');

      _connectionCompleter?.complete(true);
      _connectionCompleter = null;

      _afterConnect(reconnected);
    });

    _socket!.onDisconnect((reason) {
      _connected = false;
      logger.info('Socket disconnected: $reason');
      // The next connect gets a new socket id, so the server's rooms no longer
      // hold any of these — every one is unsent again from its point of view.
      for (final sub in _watchSubscriptions.values) {
        sub.sent = false;
      }
      _options.onDisconnect?.call(reason.toString());

      // Mark active uploads as failed
      for (final tracker in _activeUploads.values) {
        if (tracker.status == UploadStatus.uploading ||
            tracker.status == UploadStatus.preparing) {
          tracker.completeWithError('Disconnected during upload');
        }
      }
    });

    _socket!.onConnectError((error) {
      logger.error('Socket connection error: $error');
      _connectionCompleter?.complete(false);
      _connectionCompleter = null;
      _options.onError?.call(error);
    });

    _socket!.onError((error) {
      logger.error('Socket error: $error');
      _options.onError?.call(error);
    });
  }

  /// Whether the socket is currently connected.
  bool get isConnected => _connected;

  /// Wait for the socket to connect, with a timeout.
  Future<bool> waitForConnection({int timeout = 5000}) async {
    if (_connected) return true;

    _connectionCompleter ??= Completer<bool>();

    return _connectionCompleter!.future.timeout(
      Duration(milliseconds: timeout),
      onTimeout: () {
        _connectionCompleter = null;
        return false;
      },
    );
  }

  /// Update the user authentication token.
  Future<void> setUserToken(String? token) async {
    if (_socket == null) return;
    _socket!.io.options?['auth'] = {
      'projectToken': _credentials.projectToken,
      'projectCode': _credentials.projectCode,
      'userToken': ?token,
    };
    // Also push the identity over the live socket so the change applies
    // without waiting for a reconnect.
    _socket!.emit('set-user-token', token);
  }

  // ---------------------------------------------------------------------------
  // Watch subscriptions
  // ---------------------------------------------------------------------------

  /// Register a watcher of [eventName], subscribing on the first one only.
  void _subscribe(String eventName, String subscribeEvent, dynamic payload) {
    final existing = _watchSubscriptions[eventName];
    if (existing != null) {
      existing.count++;
      return;
    }
    final subscription = _WatchSubscription(
      event: subscribeEvent,
      payload: payload,
    );
    _watchSubscriptions[eventName] = subscription;
    if (_socket != null) {
      // socket.io buffers this until the connection opens, so it counts as
      // sent even before onConnect fires.
      _socket!.emit(subscribeEvent, payload);
      subscription.sent = true;
    }
  }

  /// Drop a watcher of [eventName], unsubscribing once the last one is gone.
  void _unsubscribe(String eventName, String unsubscribeEvent, dynamic payload) {
    final existing = _watchSubscriptions[eventName];
    if (existing != null) {
      existing.count--;
      if (existing.count > 0) return;
      _watchSubscriptions.remove(eventName);
    }
    _socket?.emit(unsubscribeEvent, payload);
  }

  /// Re-assert identity, replay subscriptions, then notify the caller.
  ///
  /// The order is load-bearing and must not be interleaved:
  ///
  ///  1. `set-user-token` first, because the server's socketColGuard checks
  ///     read rules against `socket.sender`, which only exists once the token
  ///     lands. A replayed subscribe that overtakes it is silently denied.
  ///  2. the replay next, while the registry still holds the old watches.
  ///  3. `onConnect` last. It used to run synchronously here while the replay
  ///     waited on a microtask, so a consumer that tears down and re-creates
  ///     its watches in that callback — which is exactly what apps wrote to
  ///     work around the missing replay — drained the registry before the
  ///     replay read it, leaving the replay a no-op.
  Future<void> _afterConnect(bool reconnected) async {
    if (_options.getToken != null) {
      try {
        _socket?.emit('set-user-token', await _options.getToken!());
      } catch (error) {
        // An unauthenticated replay still beats no replay: public collections
        // keep working, and rule-protected ones were already going to fail.
        logger.warn('Could not refresh token on reconnect: $error');
      }
    }

    // A reconnect needs every subscription re-sent; a FIRST connect needs only
    // the ones registered before the socket existed, whose emit went nowhere.
    // This used to skip the first connect entirely on the assumption that
    // socket.io had buffered every subscribe — true only once `_socket` is
    // non-null, which is exactly the case `sent` now distinguishes.
    _resubscribeAll(all: reconnected);

    _options.onConnect?.call();
  }

  /// Re-emit tracked subscriptions the current socket has not received.
  ///
  /// The server keys its rooms by socket id, so a reconnect arrives with a new
  /// id and belongs to nothing. It cannot restore the rooms itself — without
  /// this replay realtime just stops after the first network blip.
  ///
  /// Re-sending a subscribe the server already has is harmless: its watch
  /// registry is keyed by collection plus filter, so a duplicate is dropped.
  void _resubscribeAll({required bool all}) {
    final due = _watchSubscriptions.values
        .where((sub) => all || !sub.sent)
        .toList();
    if (due.isEmpty) return;
    for (final sub in due) {
      _socket?.emit(sub.event, sub.payload);
      sub.sent = true;
    }
    logger.info('Re-subscribed ${due.length} watch(es)');
  }

  /// Watch a collection for real-time changes.
  ///
  /// Returns a [Stream] of [CollectionChangeEvent]. The stream emits the
  /// initial data snapshot followed by change events. Cancel the subscription
  /// to stop watching.
  Stream<CollectionChangeEvent> watchCol(String colPath) {
    final controller = StreamController<CollectionChangeEvent>.broadcast();
    // Server emits `update:<projectCode>/<col>` (see db.sockets.js
    // sendUpdateCollectionStreamEvent). colPath here is the bare collection
    // name (e.g. "expenses").
    final eventName = 'update:${_credentials.projectCode}/$colPath';

    void onData(dynamic data) {
      if (data is Map<String, dynamic>) {
        controller.add(CollectionChangeEvent.fromMap(data));
      } else if (data is Map) {
        controller.add(CollectionChangeEvent.fromMap(
          Map<String, dynamic>.from(data),
        ));
      }
    }

    void onError(dynamic error) {
      controller.add(CollectionChangeEvent.error(error.toString()));
    }

    _watchControllers.add(controller);
    _subscribe(eventName, 'watch-col-updates', {'col': colPath});

    _on(eventName, onData);
    _on('$eventName:error', onError);

    controller.onCancel = () {
      _off(eventName, onData);
      _off('$eventName:error', onError);
      _watchControllers.remove(controller);
      _unsubscribe(eventName, 'unwatch-col-updates', {'col': colPath});
    };

    return controller.stream;
  }

  /// Watch a document for real-time changes.
  ///
  /// Returns a [Stream] of [DocumentChangeEvent]. Cancel the subscription
  /// to stop watching.
  Stream<DocumentChangeEvent> watchDoc(String docPath) {
    final controller = StreamController<DocumentChangeEvent>.broadcast();
    // Server joins the room named by the document's _id and emits an event of
    // that same name (see db.sockets.js watch-doc handler). The id is the last
    // path segment.
    final eventName = docPath.split('/').last;

    void onData(dynamic data) {
      if (data is Map<String, dynamic>) {
        controller.add(DocumentChangeEvent.fromMap(data));
      } else if (data is Map) {
        controller.add(DocumentChangeEvent.fromMap(
          Map<String, dynamic>.from(data),
        ));
      }
    }

    void onError(dynamic error) {
      controller.add(DocumentChangeEvent.error(error.toString()));
    }

    _watchControllers.add(controller);
    _subscribe(eventName, 'watch-doc', {'path': docPath});

    _on(eventName, onData);
    _on('$eventName:error', onError);

    controller.onCancel = () {
      _off(eventName, onData);
      _off('$eventName:error', onError);
      _watchControllers.remove(controller);
      _unsubscribe(eventName, 'unwatch-doc-updates', docPath);
    };

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // File upload
  // ---------------------------------------------------------------------------

  /// Upload a file via Socket.IO chunked protocol.
  ///
  /// Returns an [UploadHandle] for tracking progress, awaiting result, or cancelling.
  UploadHandle uploadFile(UploadFileInfo file, {String? bucketId}) {
    final key = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final tracker = _UploadTracker(
      key: key,
      file: file,
      bucketId: bucketId,
      chunkSize: _options.chunkSize,
    );

    _activeUploads[key] = tracker;

    _startUpload(tracker);

    return UploadHandle._(tracker);
  }

  Future<void> _startUpload(_UploadTracker tracker) async {
    if (_socket == null || !_connected) {
      tracker.completeWithError('Socket not connected');
      return;
    }

    tracker.status = UploadStatus.preparing;
    tracker.emitProgress();

    // Listen for upload events for this file
    final readyEvent = 'upload:ready:${tracker.file.name}';
    final progressEvent = 'upload:progress:${tracker.file.name}';
    final completeEvent = 'upload:complete:${tracker.file.name}';
    final errorEvent = 'upload:error:${tracker.file.name}';

    void onReady(dynamic data) {
      _sendChunks(tracker);
    }

    // One ack per chunk the server accepted. It carries no byte count — the
    // payload is `{name, received: true}` — which is why progress is computed
    // from the chunk sizes this client queued rather than read off the event.
    // Reading a `uploaded` field that the server never sends is what used to
    // reset progress to 0 on every single ack.
    void onProgress(dynamic data) {
      tracker.status = UploadStatus.uploading;
      tracker.acknowledgeChunk();
      tracker.emitProgress();
      _sendChunks(tracker);
    }

    void onComplete(dynamic data) {
      String? url;
      if (data is Map) {
        url = data['url'] as String?;
      }
      tracker.status = UploadStatus.complete;
      tracker.url = url;
      tracker.progress = 100.0;
      tracker.emitProgress();
      tracker.complete(url);
      _cleanupUploadListeners(tracker);
      _activeUploads.remove(tracker.key);
    }

    void onError(dynamic data) {
      final message = data is Map ? data['error']?.toString() : data?.toString();
      tracker.completeWithError(message ?? 'Upload failed');
      _cleanupUploadListeners(tracker);
      _activeUploads.remove(tracker.key);
    }

    tracker.listeners = {
      readyEvent: onReady,
      progressEvent: onProgress,
      completeEvent: onComplete,
      errorEvent: onError,
    };

    for (final entry in tracker.listeners.entries) {
      _socket!.on(entry.key, entry.value);
    }

    // Emit upload:start
    _socket!.emit('upload:start', {
      'name': tracker.file.name,
      'size': tracker.file.size,
      'type': tracker.file.mimeType ?? 'application/octet-stream',
      'bucket': tracker.bucketId,
    });
  }

  /// Pushes chunks until the in-flight window is full, then stops.
  ///
  /// Called once when the server says it is ready, and again on every
  /// `upload:progress` ack — so the window refills as the server drains it.
  /// This is real flow control, and replaces a loop that emitted the entire
  /// file into socket.io's send queue in one synchronous burst. That burst
  /// buffered the whole file a second time in memory, ignored `_connected`
  /// after the first chunk, and gave the server no way to slow a client down
  /// no matter how far behind its write chain fell.
  ///
  /// A window rather than one-chunk-at-a-time because strict lockstep would
  /// cap throughput at one chunk per round trip.
  void _sendChunks(_UploadTracker tracker) {
    if (tracker.cancelled) return;

    tracker.status = UploadStatus.uploading;
    final bytes = tracker.file.bytes;

    while (tracker.inFlight < _options.uploadWindow &&
        tracker.sentBytes < bytes.length) {
      // Re-checked every iteration: a disconnect mid-file must stop the send,
      // which the old unconditional loop did not do.
      if (tracker.cancelled || _socket == null || !_connected) return;

      final start = tracker.sentBytes;
      final end = (start + tracker.chunkSize).clamp(0, bytes.length);
      _socket!.emit('upload:chunk', {
        'name': tracker.file.name,
        'chunk': bytes.sublist(start, end),
      });
      tracker.recordSentChunk(end - start);
    }

    // Only once every chunk has been sent AND acknowledged, so the server is
    // never told the file is complete while writes are still queued behind it.
    if (tracker.sentBytes >= bytes.length &&
        tracker.inFlight == 0 &&
        !tracker.doneSent &&
        !tracker.cancelled &&
        _socket != null &&
        _connected) {
      tracker.doneSent = true;
      _socket!.emit('upload:done', {'name': tracker.file.name});
    }
  }

  void _cleanupUploadListeners(_UploadTracker tracker) {
    for (final entry in tracker.listeners.entries) {
      _socket?.off(entry.key, entry.value);
    }
  }

  /// Cancel an active upload.
  void cancelUpload(String key) {
    final tracker = _activeUploads[key];
    if (tracker != null) {
      tracker.cancel();
      _cleanupUploadListeners(tracker);
      _activeUploads.remove(key);
    }
  }

  /// Get all active uploads.
  List<UploadProgress> getAllUploads() {
    return _activeUploads.values.map((t) => t.toProgress()).toList();
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Close the socket connection and clean up all resources.
  void close() {
    for (final tracker in _activeUploads.values) {
      tracker.cancel();
      _cleanupUploadListeners(tracker);
    }
    _activeUploads.clear();
    _watchSubscriptions.clear();
    _pendingListeners.clear();

    _socket?.dispose();
    _socket = null;
    _connected = false;
    _hasConnected = false;
    _connectionCompleter?.complete(false);
    _connectionCompleter = null;

    // Closed last so watchers get a done event instead of a stream that just
    // goes quiet. close() fires onCancel, which mutates the set — hence a copy.
    for (final controller in _watchControllers.toList()) {
      controller.close();
    }
    _watchControllers.clear();

    logger.info('Socket service closed');
  }
}

// ---------------------------------------------------------------------------
// Internal watch subscription
// ---------------------------------------------------------------------------

class _WatchSubscription {
  final String event;
  final dynamic payload;

  int count = 1;

  /// Whether this subscribe has been handed to a socket yet.
  ///
  /// False for a watch registered while `_socket` was null — that emit went
  /// nowhere, so the first connect has to send it. Reset on disconnect,
  /// because a reconnect arrives with a new socket id and the server's rooms
  /// are keyed by it, so every subscription is unsent again from its point of
  /// view.
  bool sent = false;

  _WatchSubscription({
    required this.event,
    required this.payload,
  });
}

// ---------------------------------------------------------------------------
// Internal upload tracker
// ---------------------------------------------------------------------------

class _UploadTracker {
  final String key;
  final UploadFileInfo file;
  final String? bucketId;
  final int chunkSize;

  UploadStatus status = UploadStatus.pending;
  double progress = 0.0;

  /// Bytes the server has acknowledged. What progress is reported from.
  int uploaded = 0;

  /// Bytes handed to socket.io, acknowledged or not. Always >= [uploaded].
  int sentBytes = 0;

  /// Sizes of chunks sent but not yet acknowledged, oldest first. The server's
  /// ack carries no byte count, so this is how an ack is converted back into
  /// progress: one ack retires one chunk, in send order.
  final Queue<int> _unackedChunks = Queue<int>();

  /// Whether `upload:done` has gone out. Guards against sending it twice when
  /// a late ack arrives after the file is already fully acknowledged.
  bool doneSent = false;

  String? url;
  String? error;
  bool cancelled = false;

  /// Chunks sent and awaiting an ack — the depth of the flow-control window.
  int get inFlight => _unackedChunks.length;

  void recordSentChunk(int size) {
    _unackedChunks.add(size);
    sentBytes += size;
  }

  void acknowledgeChunk() {
    if (_unackedChunks.isEmpty) return;
    uploaded += _unackedChunks.removeFirst();
    final total = file.size;
    progress = total <= 0 ? 100.0 : (uploaded / total) * 100;
  }

  Map<String, Function(dynamic)> listeners = {};

  final _progressController = StreamController<UploadProgress>.broadcast();
  final _resultCompleter = Completer<String?>();

  _UploadTracker({
    required this.key,
    required this.file,
    this.bucketId,
    this.chunkSize = 65536,
  });

  UploadProgress toProgress() {
    return UploadProgress(
      key: key,
      name: file.name,
      size: file.size,
      status: status,
      progress: progress,
      error: error,
      url: url,
    );
  }

  void emitProgress() {
    if (!_progressController.isClosed) {
      _progressController.add(toProgress());
    }
  }

  void complete(String? fileUrl) {
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.complete(fileUrl);
    }
    _progressController.close();
  }

  void completeWithError(String message) {
    error = message;
    status = UploadStatus.error;
    emitProgress();
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.completeError(FlexDocsUploadException(message));
    }
    _progressController.close();
  }

  void cancel() {
    cancelled = true;
    status = UploadStatus.error;
    error = 'Cancelled';
    emitProgress();
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.completeError(
        const FlexDocsUploadException('Upload cancelled', code: 'UPLOAD_CANCELLED'),
      );
    }
    _progressController.close();
  }

  Stream<UploadProgress> get progressStream => _progressController.stream;
  Future<String?> get result => _resultCompleter.future;
}

// ---------------------------------------------------------------------------
// Public upload handle
// ---------------------------------------------------------------------------

/// Handle for tracking and controlling a file upload.
class UploadHandle {
  final _UploadTracker _tracker;

  UploadHandle._(this._tracker);

  /// Stream of progress updates for this upload.
  Stream<UploadProgress> get progress => _tracker.progressStream;

  /// Future that completes with the file URL on success.
  Future<String?> get result => _tracker.result;

  /// The unique key for this upload.
  String get key => _tracker.key;

  /// Cancel this upload.
  void cancel() => _tracker.cancel();
}
