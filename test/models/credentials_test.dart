import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';

void main() {
  group('Credentials', () {
    test('creates valid credentials', () {
      final creds = Credentials(
        baseUrl: 'https://api.example.com',
        projectCode: 'test-project',
        projectToken: 'token123',
        projectName: 'Test Project',
      );

      expect(creds.baseUrl, 'https://api.example.com');
      expect(creds.projectCode, 'test-project');
      expect(creds.projectToken, 'token123');
      expect(creds.projectName, 'Test Project');
    });

    test('projectName is optional', () {
      final creds = Credentials(
        baseUrl: 'http://localhost:3000',
        projectCode: 'test',
        projectToken: 'token',
      );
      expect(creds.projectName, isNull);
    });

    test('throws on empty baseUrl', () {
      expect(
        () => Credentials(baseUrl: '', projectCode: 'p', projectToken: 't'),
        throwsArgumentError,
      );
    });

    test('throws on invalid baseUrl scheme', () {
      expect(
        () => Credentials(baseUrl: 'ftp://x', projectCode: 'p', projectToken: 't'),
        throwsArgumentError,
      );
    });

    test('throws on empty projectCode', () {
      expect(
        () => Credentials(baseUrl: 'https://x', projectCode: '', projectToken: 't'),
        throwsArgumentError,
      );
    });

    test('throws on empty projectToken', () {
      expect(
        () => Credentials(baseUrl: 'https://x', projectCode: 'p', projectToken: ''),
        throwsArgumentError,
      );
    });

    test('projectUrl returns correct path', () {
      final creds = Credentials(
        baseUrl: 'https://api.example.com',
        projectCode: 'myproject',
        projectToken: 'token',
      );
      expect(creds.projectUrl, 'https://api.example.com/projects/myproject');
    });

    test('equality works', () {
      final a = Credentials(baseUrl: 'https://x', projectCode: 'p', projectToken: 't');
      final b = Credentials(baseUrl: 'https://x', projectCode: 'p', projectToken: 't');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality works', () {
      final a = Credentials(baseUrl: 'https://x', projectCode: 'p', projectToken: 't');
      final b = Credentials(baseUrl: 'https://y', projectCode: 'p', projectToken: 't');
      expect(a, isNot(equals(b)));
    });
  });
}
