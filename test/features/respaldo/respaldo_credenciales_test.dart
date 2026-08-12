// Etapa 14C (Respaldo y restauración) — misma regla dura que
// Reportes (12D), Dashboard (13), Búsqueda global (14A) y
// Notificaciones (14B): ningún archivo bajo lib/features/respaldo/
// puede importar EquipoTelefonicoRepository,
// RevelarCredencialEquipoTelefonicoUseCase ni CredentialCipher. La
// clave de cifrado vive en el Almacén de Credenciales de Windows y
// nunca se exporta — este test confirma que el módulo ni siquiera
// referencia esa infraestructura.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _importsProhibidos = [
  'equipo_telefonico_repository.dart',
  'RevelarCredencialEquipoTelefonicoUseCase',
  'CredentialCipher',
];

void main() {
  test('lib/features/respaldo/ nunca importa infraestructura de credenciales de Telefonía', () {
    final directorio = Directory(p.join(Directory.current.path, 'lib', 'features', 'respaldo'));
    expect(directorio.existsSync(), isTrue, reason: 'ruta esperada del módulo Respaldo no encontrada');

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
      reason: 'Ningún archivo de Respaldo debe referenciar credenciales de Telefonía, ni siquiera para Maestro',
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
