// Etapa 1B — pruebas del auditor estático de providers crudos
// (`tool/auditor_providers_crudos.dart`). Corre sobre un árbol `lib/`
// SINTÉTICO en un directorio temporal (nunca el `lib/` real del
// proyecto) para que las 5 aserciones sean deterministas e
// independientes de cómo evolucione el código real.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/auditor_providers_crudos.dart';

void _escribir(Directory base, String rutaRelativa, String contenido) {
  final archivo = File('${base.path}/$rutaRelativa');
  archivo.parent.createSync(recursive: true);
  archivo.writeAsStringSync(contenido);
}

void main() {
  late Directory tempDir;
  late Directory libFalso;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('auditor_providers_crudos_test_');
    libFalso = Directory('${tempDir.path}/lib')..createSync();

    // Módulo X: provider crudo con wrapper autorizado — dueño legítimo
    // es `x_providers.dart`.
    _escribir(libFalso, 'features/x/x_providers.dart', '''
final registrarXUseCaseProvider = Provider<RegistrarXUseCase>((ref) {
  return RegistrarXUseCase(ref.watch(xRepositoryProvider));
});

final registrarXAutorizadoProvider = Provider<RegistrarXAutorizado>((ref) {
  return ({required String nombre}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'x.crear',
      () => ref.read(registrarXUseCaseProvider).ejecutar(nombre: nombre),
      RegistrarXErrorInesperado.new,
    );
  };
});
''');

    // 1) VIOLACIÓN REAL: un diálogo lee el provider crudo directo,
    // saltándose `registrarXAutorizadoProvider`.
    _escribir(libFalso, 'features/x/presentation/widgets/x_dialog_violacion.dart', '''
void ejemplo(WidgetRef ref) {
  final resultado = ref.read(registrarXUseCaseProvider).ejecutar(nombre: 'prueba');
}
''');

    // 2) USO CORRECTO del autorizado — nunca menciona el provider
    // crudo, no debe aparecer en ninguna violación.
    _escribir(libFalso, 'features/x/presentation/widgets/x_dialog_correcto.dart', '''
void ejemplo(WidgetRef ref) {
  final resultado = ref.read(registrarXAutorizadoProvider)(nombre: 'prueba');
}
''');

    // 3) CONSULTA LEGÍTIMA: provider de solo lectura, nunca envuelto en
    // autorizarUseCase/exigirMaestro en ningún archivo — no protegido.
    _escribir(libFalso, 'features/y/y_providers.dart', '''
final obtenerYUseCaseProvider = Provider<ObtenerYUseCase>((ref) {
  return ObtenerYUseCase(ref.watch(yRepositoryProvider));
});
''');
    _escribir(libFalso, 'features/y/presentation/y_screen.dart', '''
void ejemplo(WidgetRef ref) {
  final datos = ref.read(obtenerYUseCaseProvider).ejecutar();
}
''');

    // 4) PDF/EXPORTACIÓN LEGÍTIMA: mismo criterio — nunca envuelto en
    // autorización en ningún lugar.
    _escribir(libFalso, 'features/z/z_providers.dart', '''
final generarZPdfUseCaseProvider = Provider<GenerarZPdfUseCase>((ref) {
  return GenerarZPdfUseCase(ref.watch(zRepositoryProvider));
});
''');
    _escribir(libFalso, 'features/z/presentation/z_dialog.dart', '''
void ejemplo(WidgetRef ref) {
  final bytes = ref.read(generarZPdfUseCaseProvider).ejecutar();
}
''');

    // 5) USO DESDE CONTROLLER PERMITIDO: la envoltura autorizada vive
    // DENTRO de un método de Controller (no un `xxxAutorizadoProvider`
    // aparte) — el mismo archivo que gatea también lee el provider
    // crudo; no debe marcarse como violación.
    _escribir(libFalso, 'features/w/presentation/w_controller.dart', '''
class WController {
  Future<CorregirWResultado> corregir({required String id}) async {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'w.corregir',
      () => ref.read(corregirWUseCaseProvider).ejecutar(id: id),
      CorregirWErrorInesperado.new,
    );
  }
}
''');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('descubre el registro de providers protegidos a partir de autorizarUseCase/exigirMaestro reales', () {
    final registro = descubrirProvidersProtegidos(libFalso);

    expect(registro.containsKey('registrarXUseCaseProvider'), isTrue);
    expect(registro.containsKey('corregirWUseCaseProvider'), isTrue);
    // Nunca protegidos: no hay ninguna envoltura de autorización para ellos.
    expect(registro.containsKey('obtenerYUseCaseProvider'), isFalse);
    expect(registro.containsKey('generarZPdfUseCaseProvider'), isFalse);
  });

  test('1) violación real: diálogo lee el provider crudo saltándose el autorizado', () {
    final registro = descubrirProvidersProtegidos(libFalso);
    final violaciones = buscarViolaciones(libFalso, registro);

    final violacionX = violaciones.where((v) => v.provider == 'registrarXUseCaseProvider');
    expect(violacionX, hasLength(1));
    expect(violacionX.single.archivo, contains('x_dialog_violacion.dart'));
    expect(violacionX.single.wrapperEsperado, contains('registrarXAutorizadoProvider'));
  });

  test('2) uso correcto del autorizado nunca genera una violación', () {
    final registro = descubrirProvidersProtegidos(libFalso);
    final violaciones = buscarViolaciones(libFalso, registro);

    expect(violaciones.any((v) => v.archivo.contains('x_dialog_correcto.dart')), isFalse);
  });

  test('3) consulta legítima (provider de solo lectura, nunca envuelto) nunca genera una violación', () {
    final registro = descubrirProvidersProtegidos(libFalso);
    final violaciones = buscarViolaciones(libFalso, registro);

    expect(violaciones.any((v) => v.provider == 'obtenerYUseCaseProvider'), isFalse);
  });

  test('4) generación de PDF/exportación legítima nunca genera una violación', () {
    final registro = descubrirProvidersProtegidos(libFalso);
    final violaciones = buscarViolaciones(libFalso, registro);

    expect(violaciones.any((v) => v.provider == 'generarZPdfUseCaseProvider'), isFalse);
  });

  test('5) uso desde dentro del propio Controller que gatea (sin AutorizadoProvider aparte) es permitido', () {
    final registro = descubrirProvidersProtegidos(libFalso);
    final violaciones = buscarViolaciones(libFalso, registro);

    expect(violaciones.any((v) => v.provider == 'corregirWUseCaseProvider'), isFalse);
  });

  test('el total de violaciones detectadas es exactamente 1 (solo la del escenario 1)', () {
    final registro = descubrirProvidersProtegidos(libFalso);
    final violaciones = buscarViolaciones(libFalso, registro);

    expect(violaciones, hasLength(1));
  });
}
