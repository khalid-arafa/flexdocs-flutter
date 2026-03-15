import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/models/api_client_options.dart';
import 'package:flexdocs_flutter/src/models/socket_options.dart';
import 'package:flexdocs_flutter/src/models/service_options.dart';
import 'package:flexdocs_flutter/src/models/collection_event.dart';
import 'package:flexdocs_flutter/src/models/document_event.dart';
import 'package:flexdocs_flutter/src/models/upload_progress.dart';
import 'package:flexdocs_flutter/src/models/auth_models.dart';
import 'package:flexdocs_flutter/src/models/storage_models.dart';

void main() {
  // -------------------------------------------------------------------------
  // ApiClientOptions
  // -------------------------------------------------------------------------
  group('ApiClientOptions', () {
    test('has correct defaults', () {
      const opts = ApiClientOptions();
      expect(opts.timeout, 30000);
      expect(opts.retryAttempts, 3);
      expect(opts.retryDelay, 1000);
      expect(opts.getToken, isNull);
      expect(opts.onError, isNull);
    });

    test('accepts custom values', () {
      final opts = ApiClientOptions(
        timeout: 5000,
        retryAttempts: 1,
        retryDelay: 500,
        getToken: () async => 'tok',
        onError: (_) {},
      );
      expect(opts.timeout, 5000);
      expect(opts.retryAttempts, 1);
      expect(opts.retryDelay, 500);
      expect(opts.getToken, isNotNull);
      expect(opts.onError, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // SocketServiceOptions
  // -------------------------------------------------------------------------
  group('SocketServiceOptions', () {
    test('has correct defaults', () {
      const opts = SocketServiceOptions();
      expect(opts.timeout, 30000);
      expect(opts.reconnection, isTrue);
      expect(opts.reconnectionDelay, 1000);
      expect(opts.reconnectionDelayMax, 5000);
      expect(opts.reconnectionAttempts, 999999);
      expect(opts.chunkSize, 65536);
      expect(opts.getToken, isNull);
      expect(opts.onConnect, isNull);
      expect(opts.onDisconnect, isNull);
      expect(opts.onError, isNull);
    });

    test('accepts custom values', () {
      const opts = SocketServiceOptions(
        timeout: 10000,
        reconnection: false,
        chunkSize: 32768,
      );
      expect(opts.timeout, 10000);
      expect(opts.reconnection, isFalse);
      expect(opts.chunkSize, 32768);
    });
  });

  // -------------------------------------------------------------------------
  // ServiceOptions
  // -------------------------------------------------------------------------
  group('ServiceOptions', () {
    test('defaults are null', () {
      const opts = ServiceOptions();
      expect(opts.apiOptions, isNull);
      expect(opts.socketOptions, isNull);
    });

    test('accepts both options', () {
      const opts = ServiceOptions(
        apiOptions: ApiClientOptions(timeout: 5000),
        socketOptions: SocketServiceOptions(chunkSize: 1024),
      );
      expect(opts.apiOptions!.timeout, 5000);
      expect(opts.socketOptions!.chunkSize, 1024);
    });
  });

  // -------------------------------------------------------------------------
  // CollectionChangeEvent
  // -------------------------------------------------------------------------
  group('CollectionChangeEvent', () {
    test('fromMap with full data', () {
      final event = CollectionChangeEvent.fromMap({
        'data': [
          {'_id': '1', 'name': 'Alice'},
          {'_id': '2', 'name': 'Bob'},
        ],
        'added': [
          {'_id': '3', 'name': 'Charlie'},
        ],
        'updated': [
          {'_id': '1', 'name': 'Alice Updated'},
        ],
        'removed': [
          {'_id': '2', 'name': 'Bob'},
        ],
      });
      expect(event.data, hasLength(2));
      expect(event.added, hasLength(1));
      expect(event.updated, hasLength(1));
      expect(event.removed, hasLength(1));
      expect(event.error, isNull);
    });

    test('fromMap with null fields', () {
      final event = CollectionChangeEvent.fromMap({});
      expect(event.data, isNull);
      expect(event.added, isNull);
      expect(event.updated, isNull);
      expect(event.removed, isNull);
    });

    test('fromMap with error', () {
      final event = CollectionChangeEvent.fromMap({'error': 'fail'});
      expect(event.error, 'fail');
    });

    test('error factory', () {
      final event = CollectionChangeEvent.error('something broke');
      expect(event.error, 'something broke');
      expect(event.data, isNull);
    });

    test('toString includes counts', () {
      final event = CollectionChangeEvent(data: [
        {'_id': '1'}
      ]);
      expect(event.toString(), contains('data: 1'));
    });
  });

  // -------------------------------------------------------------------------
  // DocumentChangeEvent
  // -------------------------------------------------------------------------
  group('DocumentChangeEvent', () {
    test('fromMap with update action', () {
      final event = DocumentChangeEvent.fromMap({
        'action': 'update',
        'doc': {'_id': '1', 'name': 'Alice'},
      });
      expect(event.action, DocumentAction.update);
      expect(event.doc, isNotNull);
      expect(event.doc!['name'], 'Alice');
    });

    test('fromMap with delete action', () {
      final event = DocumentChangeEvent.fromMap({
        'action': 'delete',
        'doc': {'_id': '1'},
      });
      expect(event.action, DocumentAction.delete);
    });

    test('fromMap with unknown action', () {
      final event = DocumentChangeEvent.fromMap({
        'action': 'unknown',
        'doc': {'_id': '1'},
      });
      expect(event.action, isNull);
    });

    test('fromMap with no action', () {
      final event = DocumentChangeEvent.fromMap({
        'doc': {'_id': '1'},
      });
      expect(event.action, isNull);
    });

    test('fromMap with error', () {
      final event = DocumentChangeEvent.fromMap({'error': 'oops'});
      expect(event.error, 'oops');
    });

    test('error factory', () {
      final event = DocumentChangeEvent.error('broken');
      expect(event.error, 'broken');
      expect(event.action, isNull);
      expect(event.doc, isNull);
    });

    test('toString includes action', () {
      final event = DocumentChangeEvent(action: DocumentAction.update);
      expect(event.toString(), contains('update'));
    });
  });

  // -------------------------------------------------------------------------
  // UploadProgress & UploadFileInfo
  // -------------------------------------------------------------------------
  group('UploadProgress', () {
    test('default values', () {
      final p = UploadProgress(key: 'k', name: 'f.txt', size: 100);
      expect(p.status, UploadStatus.pending);
      expect(p.progress, 0.0);
      expect(p.error, isNull);
      expect(p.url, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      final p = UploadProgress(key: 'k', name: 'f.txt', size: 100);
      final updated = p.copyWith(status: UploadStatus.uploading, progress: 50);
      expect(updated.key, 'k');
      expect(updated.name, 'f.txt');
      expect(updated.size, 100);
      expect(updated.status, UploadStatus.uploading);
      expect(updated.progress, 50);
    });

    test('copyWith with url', () {
      final p = UploadProgress(key: 'k', name: 'f.txt', size: 100);
      final done = p.copyWith(
        status: UploadStatus.complete,
        progress: 100,
        url: 'https://cdn.example.com/f.txt',
      );
      expect(done.url, 'https://cdn.example.com/f.txt');
      expect(done.status, UploadStatus.complete);
    });

    test('copyWith with error', () {
      final p = UploadProgress(key: 'k', name: 'f.txt', size: 100);
      final err = p.copyWith(
        status: UploadStatus.error,
        error: 'network fail',
      );
      expect(err.error, 'network fail');
      expect(err.status, UploadStatus.error);
    });

    test('toString includes percentage', () {
      final p = UploadProgress(
        key: 'k',
        name: 'f.txt',
        size: 100,
        progress: 42.567,
      );
      expect(p.toString(), contains('42.6%'));
    });
  });

  group('UploadFileInfo', () {
    test('computes size from bytes', () {
      final f = UploadFileInfo(name: 'test.bin', bytes: Uint8List(512));
      expect(f.size, 512);
      expect(f.name, 'test.bin');
      expect(f.mimeType, isNull);
    });

    test('accepts mimeType', () {
      final f = UploadFileInfo(
        name: 'image.png',
        bytes: Uint8List(1024),
        mimeType: 'image/png',
      );
      expect(f.mimeType, 'image/png');
    });

    test('toString', () {
      final f = UploadFileInfo(name: 'x.txt', bytes: Uint8List(10));
      expect(f.toString(), contains('x.txt'));
      expect(f.toString(), contains('10'));
    });
  });

  group('UploadStatus', () {
    test('has all expected values', () {
      expect(UploadStatus.values, hasLength(5));
      expect(UploadStatus.values, containsAll([
        UploadStatus.pending,
        UploadStatus.preparing,
        UploadStatus.uploading,
        UploadStatus.complete,
        UploadStatus.error,
      ]));
    });
  });

  // -------------------------------------------------------------------------
  // AuthUser
  // -------------------------------------------------------------------------
  group('AuthUser', () {
    test('fromJson parses all fields', () {
      final user = AuthUser.fromJson({
        '_id': 'u1',
        'email': 'alice@example.com',
        'name': 'Alice',
        'avatar': 'https://example.com/avatar.png',
        'roles': ['admin', 'user'],
        'token': 'jwt-123',
      });
      expect(user.id, 'u1');
      expect(user.email, 'alice@example.com');
      expect(user.name, 'Alice');
      expect(user.avatar, 'https://example.com/avatar.png');
      expect(user.roles, ['admin', 'user']);
      expect(user.token, 'jwt-123');
      expect(user.raw['_id'], 'u1');
    });

    test('fromJson with "id" instead of "_id"', () {
      final user = AuthUser.fromJson({'id': 'u2', 'email': 'bob@example.com'});
      expect(user.id, 'u2');
    });

    test('fromJson with empty map', () {
      final user = AuthUser.fromJson({});
      expect(user.id, isNull);
      expect(user.email, isNull);
      expect(user.name, isNull);
      expect(user.roles, isNull);
    });

    test('toString', () {
      final user = AuthUser.fromJson({'_id': 'u1', 'email': 'a@b.com'});
      expect(user.toString(), contains('u1'));
      expect(user.toString(), contains('a@b.com'));
    });
  });

  // -------------------------------------------------------------------------
  // BucketInfo
  // -------------------------------------------------------------------------
  group('BucketInfo', () {
    test('fromJson parses all fields', () {
      final bucket = BucketInfo.fromJson({
        '_id': 'b1',
        'name': 'Photos',
        'description': 'My photos',
        'parentId': 'root',
      });
      expect(bucket.id, 'b1');
      expect(bucket.name, 'Photos');
      expect(bucket.description, 'My photos');
      expect(bucket.parentId, 'root');
      expect(bucket.raw['_id'], 'b1');
    });

    test('fromJson with "id" key', () {
      final bucket = BucketInfo.fromJson({'id': 'b2', 'name': 'Docs'});
      expect(bucket.id, 'b2');
    });

    test('fromJson with empty map', () {
      final bucket = BucketInfo.fromJson({});
      expect(bucket.id, isNull);
      expect(bucket.name, isNull);
    });

    test('toString', () {
      final bucket = BucketInfo.fromJson({'_id': 'b1', 'name': 'Photos'});
      expect(bucket.toString(), contains('b1'));
      expect(bucket.toString(), contains('Photos'));
    });
  });

  // -------------------------------------------------------------------------
  // FileInfo
  // -------------------------------------------------------------------------
  group('FileInfo', () {
    test('fromJson parses all fields', () {
      final file = FileInfo.fromJson({
        '_id': 'f1',
        'name': 'photo.jpg',
        'url': 'https://cdn.example.com/photo.jpg',
        'size': 2048,
        'mimeType': 'image/jpeg',
        'bucketId': 'b1',
      });
      expect(file.id, 'f1');
      expect(file.name, 'photo.jpg');
      expect(file.url, 'https://cdn.example.com/photo.jpg');
      expect(file.size, 2048);
      expect(file.mimeType, 'image/jpeg');
      expect(file.bucketId, 'b1');
    });

    test('fromJson uses "filename" fallback', () {
      final file = FileInfo.fromJson({'filename': 'doc.pdf'});
      expect(file.name, 'doc.pdf');
    });

    test('fromJson uses "type" fallback for mimeType', () {
      final file = FileInfo.fromJson({'type': 'application/pdf'});
      expect(file.mimeType, 'application/pdf');
    });

    test('fromJson with "id" key', () {
      final file = FileInfo.fromJson({'id': 'f2'});
      expect(file.id, 'f2');
    });

    test('fromJson with empty map', () {
      final file = FileInfo.fromJson({});
      expect(file.id, isNull);
      expect(file.name, isNull);
      expect(file.url, isNull);
      expect(file.size, isNull);
    });

    test('toString', () {
      final file = FileInfo.fromJson({'_id': 'f1', 'name': 'photo.jpg'});
      expect(file.toString(), contains('f1'));
      expect(file.toString(), contains('photo.jpg'));
    });
  });
}
