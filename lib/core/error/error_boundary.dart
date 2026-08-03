import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

/// Conecta los manejadores globales de errores de Flutter y de Dart al
/// [AppLogger], para que ningún error no capturado se pierda en silencio.
///
/// No implementa todavía reporte externo (crash reporting) ni escritura a
/// archivo — solo asegura que todo error inesperado quede registrado.
void installErrorBoundary(AppLogger logger) {
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      'Error de Flutter no capturado',
      details.exception,
      details.stack,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.error('Error de plataforma no capturado', error, stack);
    return true;
  };
}

/// Ejecuta [body] dentro de una zona que también captura errores
/// asíncronos no manejados por ninguna otra vía.
void runGuardedApp(AppLogger logger, void Function() body) {
  runZonedGuarded(
    body,
    (error, stack) => logger.error('Error no manejado en la zona raíz', error, stack),
  );
}
