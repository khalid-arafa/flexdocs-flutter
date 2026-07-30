import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'models/credentials.dart';
import 'models/socket_options.dart';
import 'models/collection_event.dart';
import 'models/document_event.dart';
import 'models/upload_progress.dart';
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

  void _setupListeners() {
    _socket!.onConnect((_) {
      // A first connect needs no replay: watchCol/watchDoc already emitted
      // (or buffered) their subscribe for this socket.
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
    _watchSubscriptions[eventName] = _WatchSubscription(
      event: subscribeEvent,
      payload: payload,
    );
    _socket?.emit(subscribeEvent, payload);
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

    if (reconnected) _resubscribeAll();

    _options.onConnect?.call();
  }

  /// Re-emit every tracked subscription.
  ///
  /// The server keys its rooms by socket id, so a reconnect arrives with a new
  /// id and belongs to nothing. It cannot restore the rooms itself — without
  /// this replay realtime just stops after the first network blip.
  void _resubscribeAll() {
    if (_watchSubscriptions.isEmpty) return;
    for (final sub in _watchSubscriptions.values) {
      _socket?.emit(sub.event, sub.payload);
    }
    logger.info('Re-subscribed ${_watchSubscriptions.length} watch(es)');
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

    _socket?.on(eventName, onData);
    _socket?.on('$eventName:error', onError);

    controller.onCancel = () {
      _socket?.off(eventName, onData);
      _socket?.off('$eventName:error', onError);
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

    _socket?.on(eventName, onData);
    _socket?.on('$eventName:error', onError);

    controller.onCancel = () {
      _socket?.off(eventName, onData);
      _socket?.off('$eventName:error', onError);
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

    void onProgress(dynamic data) {
      if (data is Map) {
        final uploaded = data['uploaded'] as int? ?? 0;
        tracker.uploaded = uploaded;
        tracker.status = UploadStatus.uploading;
        tracker.emitProgress();
      }
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

  void _sendChunks(_UploadTracker tracker) {
    if (tracker.cancelled) return;

    tracker.status = UploadStatus.uploading;
    final bytes = tracker.file.bytes;
    var offset = tracker.uploaded;

    void sendNext() {
      if (tracker.cancelled || _socket == null || !_connected) return;
      if (offset >= bytes.length) {
        _socket!.emit('upload:done', {'name': tracker.file.name});
        return;
      }

      final end = (offset + tracker.chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);

      _socket!.emit('upload:chunk', {
        'name': tracker.file.name,
        'chunk': chunk,
      });

      offset = end;
      tracker.uploaded = offset;
      tracker.progress = (offset / bytes.length) * 100;
      tracker.emitProgress();
    }

    sendNext();

    // The server will acknowledge each chunk via upload:progress,
    // but we send all chunks sequentially based on the ready event.
    // For simplicity, send remaining chunks after a microtask.
    Future.microtask(() {
      while (offset < bytes.length && !tracker.cancelled) {
        final end = (offset + tracker.chunkSize).clamp(0, bytes.length);
        final chunk = bytes.sublist(offset, end);

        _socket!.emit('upload:chunk', {
          'name': tracker.file.name,
          'chunk': chunk,
        });

        offset = end;
        tracker.uploaded = offset;
        tracker.progress = (offset / bytes.length) * 100;
        tracker.emitProgress();
      }

      if (!tracker.cancelled) {
        _socket!.emit('upload:done', {'name': tracker.file.name});
      }
    });
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
  int uploaded = 0;
  String? url;
  String? error;
  bool cancelled = false;

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
      _resultCompleter.completeError(Exception(message));
    }
    _progressController.close();
  }

  void cancel() {
    cancelled = true;
    status = UploadStatus.error;
    error = 'Cancelled';
    emitProgress();
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.completeError(Exception('Upload cancelled'));
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
