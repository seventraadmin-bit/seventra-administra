// Etapa 14A (Búsqueda global) — misma regla dura que Reportes (12D),
// Dashboard (13) y Bóveda de Accesos (14D): ningún archivo bajo
// lib/features/busqueda/ puede importar EquipoTelefonicoRepository,
// RevelarCredencialEquipoTelefonicoUseCase, BovedaCredencialRepository,
// RevelarSecretoCredencialBovedaUseCase ni CredentialCipher —
// estructural, no basado en permiso, porque `hasCode` de Maestro
// siempre regresa true.

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
  test('lib/features/busqueda/ nunca importa infraestructura de credenciales de Telefonía', () {
    final directorio = Directory(p.join(Directory.current.path, 'lib', 'features', 'busqueda'));
    expect(directorio.existsSync(), isTrue, reason: 'ruta esperada del módulo Búsqueda no encontrada');

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
      reason: 'Ningún archivo de Búsqueda global debe referenciar credenciales de Telefonía, ni siquiera para Maestro',
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
