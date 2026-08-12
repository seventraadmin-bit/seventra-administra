// Etapa 14B (Centro de notificaciones) — misma regla dura que
// Reportes (12D), Dashboard (13), Búsqueda global (14A) y Bóveda de
// Accesos (14D): ningún archivo bajo lib/features/notificaciones/
// puede importar EquipoTelefonicoRepository,
// RevelarCredencialEquipoTelefonicoUseCase, BovedaCredencialRepository,
// RevelarSecretoCredencialBovedaUseCase ni CredentialCipher. Este
// módulo nunca toca Telefonía ni la Bóveda, pero se mantiene el mismo
// test estructural por consistencia.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _importsProhibidos = [
  'equipo_telefonico_repository.dart',
  'RevelarCredencialEquipoTelefonicoUseCase',
  'boveda_credencial_repository.dart',
  'RevelarSecretoCredencialBovedaUseCase',
  'CredentialCipher',
];

void main() {
  test('lib/features/notificaciones/ nunca importa infraestructura de credenciales de Telefonía', () {
    final directorio = Directory(p.join(Directory.current.path, 'lib', 'features', 'notificaciones'));
    expect(directorio.existsSync(), isTrue, reason: 'ruta esperada del módulo Notificaciones no encontrada');

    final archivosConImportProhibido = <String>[];
    for (final entidad in directorio.listSync(recursive: true)) {
      if (entidad is! File || !entidad.path.endsWith('.dart')) continue;
      final contenido = entidad.readAsStringSync();
      for (final prohibido in _importsProhibidos) {
        if (_esImportReal(contenido, prohibido)) {
          archivosConImportProhibido.add('${entidad.path} ($prohibido)');
        }
      }
    }

    expect(
      archivosConImportProhibido,
      isEmpty,
      reason: 'Ningún archivo de Notificaciones debe referenciar credenciales de Telefonía, ni siquiera para Maestro',
    );
  });
}

bool _esImportReal(String contenido, String prohibido) {
  for (final linea in contenido.split('\n')) {
    final recortada = linea.trim();
    if (recortada.startsWith('import') && recortada.contains(prohibido)) return true;
  }
  return false;
}
