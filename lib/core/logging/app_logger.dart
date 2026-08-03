import 'package:logger/logger.dart';

/// Envoltorio sobre `logger` para desacoplar el resto del código del paquete
/// concreto.
///
/// En esta etapa solo escribe a consola. La arquitectura queda lista para
/// agregar salida a archivo, rotación y retención cuando exista una
/// necesidad real de diagnóstico en producción — deliberadamente no
/// implementado todavía.
class AppLogger {
  AppLogger._(this._logger);

  final Logger _logger;

  factory AppLogger.console() {
    return AppLogger._(
      Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 5,
          lineLength: 100,
          colors: true,
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        ),
      ),
    );
  }

  void debug(String message) => _logger.d(message);

  void info(String message) => _logger.i(message);

  void warning(String message) => _logger.w(message);

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
}
