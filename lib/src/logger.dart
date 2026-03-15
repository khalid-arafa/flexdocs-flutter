import 'dart:developer' as developer;

/// Log severity levels.
enum LogLevel {
  debug(0),
  info(1),
  warn(2),
  error(3),
  none(4);

  final int value;
  const LogLevel(this.value);
}

/// A simple leveled logger for FlexDocs.
class Logger {
  LogLevel level;
  final String prefix;

  /// Optional output sink for testing. If null, uses `developer.log`.
  void Function(String message, {String name, int level})? _sink;

  Logger({
    this.level = LogLevel.info,
    this.prefix = '[FlexDocs]',
  });

  /// Creates a logger with a custom output sink (useful for testing).
  Logger.withSink({
    required void Function(String message, {String name, int level}) sink,
    this.level = LogLevel.info,
    this.prefix = '[FlexDocs]',
  }) : _sink = sink;

  void setLevel(LogLevel newLevel) {
    level = newLevel;
  }

  void debug(String message) => _log(LogLevel.debug, message);
  void info(String message) => _log(LogLevel.info, message);
  void warn(String message) => _log(LogLevel.warn, message);
  void error(String message) => _log(LogLevel.error, message);

  void _log(LogLevel msgLevel, String message) {
    if (msgLevel.value < level.value) return;

    final label = msgLevel.name.toUpperCase();
    final formatted = '$prefix [$label] $message';

    if (_sink != null) {
      _sink!(formatted, name: prefix, level: msgLevel.value);
    } else {
      developer.log(formatted, name: prefix, level: msgLevel.value * 300);
    }
  }
}

/// Package-level default logger instance.
final logger = Logger();
