import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/logger.dart';

void main() {
  group('Logger', () {
    late List<String> logs;
    late Logger logger;

    setUp(() {
      logs = [];
      logger = Logger.withSink(
        sink: (message, {String name = '', int level = 0}) {
          logs.add(message);
        },
        level: LogLevel.debug,
      );
    });

    test('logs messages at or above current level', () {
      logger.setLevel(LogLevel.info);
      logger.debug('should not appear');
      logger.info('should appear');
      logger.warn('should also appear');

      expect(logs, hasLength(2));
      expect(logs[0], contains('[INFO]'));
      expect(logs[1], contains('[WARN]'));
    });

    test('debug level logs everything', () {
      logger.setLevel(LogLevel.debug);
      logger.debug('d');
      logger.info('i');
      logger.warn('w');
      logger.error('e');

      expect(logs, hasLength(4));
    });

    test('none level suppresses all logs', () {
      logger.setLevel(LogLevel.none);
      logger.debug('d');
      logger.info('i');
      logger.warn('w');
      logger.error('e');

      expect(logs, isEmpty);
    });

    test('error level only logs errors', () {
      logger.setLevel(LogLevel.error);
      logger.debug('d');
      logger.info('i');
      logger.warn('w');
      logger.error('e');

      expect(logs, hasLength(1));
      expect(logs[0], contains('[ERROR]'));
    });

    test('includes prefix in output', () {
      logger.info('test message');
      expect(logs[0], startsWith('[FlexDocs]'));
    });

    test('custom prefix works', () {
      final custom = Logger.withSink(
        sink: (message, {String name = '', int level = 0}) {
          logs.add(message);
        },
        prefix: '[MyApp]',
        level: LogLevel.debug,
      );
      custom.info('hello');
      expect(logs.last, startsWith('[MyApp]'));
    });

    test('setLevel changes threshold', () {
      logger.setLevel(LogLevel.warn);
      logger.info('should not appear');
      expect(logs, isEmpty);

      logger.setLevel(LogLevel.info);
      logger.info('should appear');
      expect(logs, hasLength(1));
    });
  });

  group('LogLevel', () {
    test('values are ordered', () {
      expect(LogLevel.debug.value, lessThan(LogLevel.info.value));
      expect(LogLevel.info.value, lessThan(LogLevel.warn.value));
      expect(LogLevel.warn.value, lessThan(LogLevel.error.value));
      expect(LogLevel.error.value, lessThan(LogLevel.none.value));
    });
  });
}
