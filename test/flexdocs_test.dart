import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/flexdocs_flutter.dart';

void main() {
  final creds = Credentials(
    baseUrl: 'https://api.example.com',
    projectCode: 'test-project',
    projectToken: 'test-token',
  );

  tearDown(() {
    FlexDocs.dispose();
  });

  group('FlexDocs singleton', () {
    test('getDatabase returns same instance on repeated calls', () {
      final db1 = FlexDocs.getDatabase(creds);
      final db2 = FlexDocs.getDatabase(creds);
      expect(identical(db1, db2), isTrue);
    });

    test('getAuth returns same instance on repeated calls', () {
      final auth1 = FlexDocs.getAuth(creds);
      final auth2 = FlexDocs.getAuth(creds);
      expect(identical(auth1, auth2), isTrue);
    });

    test('getStorage returns same instance on repeated calls', () {
      final storage1 = FlexDocs.getStorage(creds);
      final storage2 = FlexDocs.getStorage(creds);
      expect(identical(storage1, storage2), isTrue);
    });

    test('dispose clears all singletons', () {
      final db1 = FlexDocs.getDatabase(creds);
      FlexDocs.dispose();
      final db2 = FlexDocs.getDatabase(creds);
      expect(identical(db1, db2), isFalse);
    });

    test('isConnected returns false initially', () {
      expect(FlexDocs.isConnected, isFalse);
    });

    test('getDatabase returns DbService', () {
      final db = FlexDocs.getDatabase(creds);
      expect(db, isA<DbService>());
    });

    test('getAuth returns AuthService', () {
      final auth = FlexDocs.getAuth(creds);
      expect(auth, isA<AuthService>());
    });

    test('getStorage returns StorageService', () {
      final storage = FlexDocs.getStorage(creds);
      expect(storage, isA<StorageService>());
    });

    test('db.doc() works through singleton', () {
      final db = FlexDocs.getDatabase(creds);
      final docRef = db.doc('users/user_1');
      expect(docRef.url, '/projects/test-project/db/users/user_1');
    });

    test('db.col() works through singleton', () {
      final db = FlexDocs.getDatabase(creds);
      final colRef = db.col('users');
      expect(colRef.url, '/projects/test-project/db/users');
    });

    test('new credentials create new instances', () {
      final db1 = FlexDocs.getDatabase(creds);

      final creds2 = Credentials(
        baseUrl: 'https://other.example.com',
        projectCode: 'other-project',
        projectToken: 'other-token',
      );
      final db2 = FlexDocs.getDatabase(creds2);

      expect(identical(db1, db2), isFalse);
    });
  });

  group('FlexDocs with options', () {
    test('accepts ServiceOptions', () {
      final db = FlexDocs.getDatabase(
        creds,
        options: ServiceOptions(
          apiOptions: ApiClientOptions(timeout: 5000, retryAttempts: 1),
          socketOptions: SocketServiceOptions(chunkSize: 32768),
        ),
      );
      expect(db, isA<DbService>());
    });
  });
}
