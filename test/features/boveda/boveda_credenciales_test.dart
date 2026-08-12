// Etapa 14D (Bóveda de Accesos del Maestro) — misma regla dura que
// Reportes (12D), Dashboard (13), Búsqueda global (14A), Notificaciones
// (14B) y Respaldo (14C): ningún archivo bajo lib/features/boveda/
// puede importar EquipoTelefonicoRepository ni
// RevelarCredencialEquipoTelefonicoUseCase — la Bóveda reutiliza
// CredentialCipher (deliberadamente, es genérico) pero nunca la
// infraestructura específica de Telefonía.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _importsProhibidos = ['equipo_telefonico_repository.dart', 'RevelarCredencialEquipoTelefonicoUseCase'];

void main() {
  test('lib/features/boveda/ nunca importa infraestructura de credenciales de Telefonía', () {
    final directorio = Directory(p.join(Directory.current.path, 'lib', 'features', 'boveda'));
    expect(directorio.existsSync(), isTrue, reason: 'ruta esperada del módulo Bóveda no encontrada');

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
      reason: 'Ningún archivo de la Bóveda debe referenciar infraestructura específica de Telefonía',
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
