import 'dart:async';

import 'models/upload_progress.dart';
import 'socket_service.dart';

/// Orchestrates uploading multiple files and provides aggregate progress.
class CustomUpload {
  final SocketService _socketService;
  final List<UploadFileInfo> _files;
  final String? _bucketId;
  final bool autoDispose;

  final List<UploadHandle> _handles = [];
  final _progressController = StreamController<List<UploadProgress>>.broadcast();
  final _resultCompleter = Completer<List<String?>>();
  bool _started = false;

  CustomUpload({
    required SocketService socketService,
    required List<UploadFileInfo> files,
    String? bucketId,
    this.autoDispose = true,
  })  : _socketService = socketService,
        _files = files,
        _bucketId = bucketId {
    _start();
  }

  /// Broadcast stream of progress updates for all files.
  Stream<List<UploadProgress>> get progress => _progressController.stream;

  /// Future that completes with the list of file URLs when all uploads finish.
  Future<List<String?>> get result => _resultCompleter.future;

  /// Cancel all in-progress uploads.
  void cancel() {
    for (final handle in _handles) {
      handle.cancel();
    }
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.completeError(Exception('All uploads cancelled'));
    }
    if (autoDispose) _dispose();
  }

  void _start() {
    if (_started) return;
    _started = true;

    if (_files.isEmpty) {
      _resultCompleter.complete([]);
      _dispose();
      return;
    }

    final results = List<String?>.filled(_files.length, null);
    var completedCount = 0;
    var hasError = false;

    for (var i = 0; i < _files.length; i++) {
      final index = i;
      final handle = _socketService.uploadFile(
        _files[index],
        bucketId: _bucketId,
      );
      _handles.add(handle);

      // Listen to individual progress
      handle.progress.listen(
        (_) => _emitAggregateProgress(),
        onError: (_) {},
      );

      // Track result
      handle.result.then((url) {
        results[index] = url;
        completedCount++;
        _emitAggregateProgress();

        if (completedCount == _files.length && !_resultCompleter.isCompleted) {
          _resultCompleter.complete(results);
          if (autoDispose) _dispose();
        }
      }).catchError((Object error) {
        if (!hasError) {
          hasError = true;
          if (!_resultCompleter.isCompleted) {
            _resultCompleter.completeError(error);
          }
          if (autoDispose) _dispose();
        }
      });
    }
  }

  void _emitAggregateProgress() {
    if (_progressController.isClosed) return;
    final allProgress = _socketService.getAllUploads();
    _progressController.add(allProgress);
  }

  void _dispose() {
    if (!_progressController.isClosed) {
      _progressController.close();
    }
  }
}
