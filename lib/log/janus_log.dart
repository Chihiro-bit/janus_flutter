import 'package:logger/logger.dart';

class JanusLogger {
  static bool _debugEnabled = false;
  static List<String> _enabledLevels = [];
 static Logger logger = Logger();
  static void init({List<String> debug = const []}) {
    _debugEnabled = debug.isNotEmpty;
    _enabledLevels = debug;

  }
  static void log(String message) {
    if (_debugEnabled && _enabledLevels.contains('log')) {
      logger.log(Level.trace,'[JANUS LOG] $message');
    }
  }

  static void debug(String message) {
    if (_debugEnabled && _enabledLevels.contains('debug')) {
      logger.d('[JANUS DEBUG] $message');
    }
  }

  static void error(String message) {
    if (_debugEnabled && _enabledLevels.contains('error')) {
      logger.e('[JANUS ERROR] $message');
    }
  }

  static void warn(String message) {
    if (_debugEnabled && _enabledLevels.contains('warn')) {
      logger.w('[JANUS WARN] $message');
    }
  }
}