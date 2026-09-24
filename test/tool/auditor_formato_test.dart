// Etapa 4B (cierre) — el auditor no puede depender del formato.
//
// Complementa a `auditor_providers_crudos_test.dart` (Etapa 1B), que
// fija QUÉ cuenta como provider protegido y qué es una violación. Aquí
// se fija algo distinto: que esa detección sobreviva a cómo quede
// escrito el código.
//
// El auditor leía el código **línea por línea**, así que `dart format`
// podía partir una llamada en tres líneas y volverla invisible: el
// provider desaparecía del registro y —lo grave— una llamada cruda
// dejaba de contar como violación. Nada fallaba; el número de cobertura
// simplemente bajaba en silencio. Así se perdieron 10 providers, entre
// ellos `cancelarEgresoUseCaseProvider` y `desactivarUsuarioUseCaseProvider`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/auditor_providers_crudos.dart';

void main() {
  late Directory lib;

  setUp(() => lib = Directory.systemTemp.createTempSync('riseg_auditor_formato_'));
  tearDown(() => lib.deleteSync(recursive: true));

  void escribir(String nombre, String contenido) {
    final archivo = File(p.join(lib.path, nombre));
    archivo.parent.createSync(recursive: true);
    archivo.writeAsStringSync(contenido);
  }

  /// Un archivo de providers que envuelve una operación con
  /// autorización, escrito con el [cuerpo] exacto que se pone a prueba.
  String providersCon(String cuerpo) => '''
final borrarTodoAutorizadoProvider = Provider<void Function()>((ref) {
  return () {
    return autorizarUseCase(
      ref.read(permissionServiceProvider),
      'algo.eliminar',
$cuerpo
      ErrorInesperado.new,
    );
  };
});
''';

  Map<String, List<ProviderProtegido>> registro() => descubrirProvidersProtegidos(lib);

  group('Formas que dart format produce', () {
    test('una línea', () {
      escribir('providers.dart', providersCon('      () => ref.read(borrarTodoUseCaseProvider).ejecutar(id: id),'));

      expect(registro().keys, contains('borrarTodoUseCaseProvider'));
    });

    test('multilínea: salto antes de .read y antes de .ejecutar', () {
      escribir(
        'providers.dart',
        providersCon('''      () => ref
          .read(borrarTodoUseCaseProvider)
          .ejecutar(id: id),'''),
      );

      expect(
        registro().keys,
        contains('borrarTodoUseCaseProvider'),
        reason: 'es exactamente lo que dart format escribe cuando la línea se pasa de 120',
      );
    });

    test('salto DENTRO de ref.read(, con la coma final que agrega el formateador', () {
      escribir(
        'providers.dart',
        providersCon('''      () => ref.read(
        borrarTodoUseCaseProvider,
      ).ejecutar(id: id),'''),
      );

      expect(registro().keys, contains('borrarTodoUseCaseProvider'));
    });

    test('espacios de sobra en cada junta', () {
      escribir('providers.dart', providersCon('      () => ref . read ( borrarTodoUseCaseProvider ) . ejecutar (id),'));

      expect(registro().keys, contains('borrarTodoUseCaseProvider'));
    });

    test('un comentario entre medias no lo despista', () {
      escribir(
        'providers.dart',
        providersCon('''      () => ref
          .read(borrarTodoUseCaseProvider)
          // Ojo: esto borra de verdad.
          .ejecutar(id: id),'''),
      );

      expect(registro().keys, contains('borrarTodoUseCaseProvider'));
    });

    test('la línea reportada es la de la envoltura', () {
      escribir(
        'providers.dart',
        providersCon('''      () => ref
          .read(borrarTodoUseCaseProvider)
          .ejecutar(id: id),'''),
      );

      expect(registro()['borrarTodoUseCaseProvider']!.single.lineaDueno, 3);
    });
  });

  group('Lo que NO debe contar', () {
    test('un ejemplo escrito en un comentario no registra nada', () {
      escribir('providers.dart', '''
/// Así NO se hace:
/// autorizarUseCase(x, () => ref.read(inventadoUseCaseProvider).ejecutar(), E.new);
// autorizarUseCase(y, () => ref.read(otroInventadoUseCaseProvider).ejecutar(), E.new);
final algo = 1;
''');

      expect(
        registro(),
        isEmpty,
        reason: 'un comentario describe código, no lo es: contarlo inventa cobertura que no existe',
      );
    });

    test('un método que no es .ejecutar( sigue sin contar', () {
      escribir('providers.dart', providersCon('      () => ref.read(borrarTodoUseCaseProvider).obtenerResumen(id),'));

      expect(registro(), isEmpty);
    });
  });

  group('Violaciones', () {
    test('una llamada cruda desde otro archivo se detecta aunque esté partida en varias líneas', () {
      escribir('providers.dart', providersCon('      () => ref.read(borrarTodoUseCaseProvider).ejecutar(id: id),'));
      escribir('pantalla.dart', '''
void alPulsar(WidgetRef ref, String id) {
  ref
      .read(borrarTodoUseCaseProvider)
      .ejecutar(id: id);
}
''');

      final violaciones = buscarViolaciones(lib, registro());

      expect(violaciones, hasLength(1), reason: 'es el caso que el auditor existe para atrapar');
      expect(violaciones.single.provider, 'borrarTodoUseCaseProvider');
      expect(violaciones.single.linea, 2, reason: 'la línea donde empieza la llamada, no donde termina');
    });

    test('una llamada cruda en una sola línea sigue detectándose', () {
      escribir('providers.dart', providersCon('      () => ref.read(borrarTodoUseCaseProvider).ejecutar(id: id),'));
      escribir('pantalla.dart', 'void f(ref) => ref.read(borrarTodoUseCaseProvider).ejecutar(id: 1);');

      expect(buscarViolaciones(lib, registro()), hasLength(1));
    });

    test('una llamada cruda comentada no es una violación', () {
      escribir('providers.dart', providersCon('      () => ref.read(borrarTodoUseCaseProvider).ejecutar(id: id),'));
      escribir('pantalla.dart', '// ref.read(borrarTodoUseCaseProvider).ejecutar(id: 1); // pendiente');

      expect(buscarViolaciones(lib, registro()), isEmpty);
    });
  });
}
