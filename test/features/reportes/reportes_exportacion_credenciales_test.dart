// Etapa 12D — regla dura, sin excepción para Maestro: ningún archivo
// bajo lib/features/reportes/ (incluidas las carpetas nuevas
// data/pdf, data/xlsx y domain/export de esta etapa) puede importar
// EquipoTelefonicoRepository, RevelarCredencialEquipoTelefonicoUseCase,
// BovedaCredencialRepository (Etapa 14D) ni
// RevelarSecretoCredencialBovedaUseCase, ni CredentialCipher — el
// límite es estructural, no basado en permiso, porque `hasCode` de
// Maestro siempre regresa true. Falla si alguno de esos imports
// aparece alguna vez bajo este directorio.

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
  test('lib/features/reportes/ nunca importa infraestructura de credenciales de Telefonía', () {
    final directorio = Directory(p.join(Directory.current.path, 'lib', 'features', 'reportes'));
    expect(directorio.existsSync(), isTrue, reason: 'ruta esperada del módulo Reportes no encontrada');

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
      reason: 'Ningún archivo de Reportes debe referenciar credenciales de Telefonía, ni siquiera para Maestro',
    );
  });
}

/// Distingue una referencia real de código (import/uso del símbolo) de
/// una simple mención en un comentario de documentación — solo las
/// líneas de `import` cuentan como violación real de la regla; los
/// doc comments que citan estos nombres por contexto no lo son.
bool _esImportReal(String contenido, String prohibido) {
  for (final linea in contenido.split('\n')) {
    final recortada = linea.trim();
    if (recortada.startsWith('import') && recortada.contains(prohibido)) return true;
  }
  return false;
}
