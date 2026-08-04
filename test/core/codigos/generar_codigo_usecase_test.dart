import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late GenerarCodigoUseCase useCase;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    useCase = GenerarCodigoUseCase(CodigoSecuenciaService(db));
  });

  tearDown(() => db.close());

  test('devuelve Ok con el código para un tipo registrado', () async {
    final result = await useCase.ejecutar('puesto');
    expect(result.isOk, isTrue);
    result.when(
      ok: (codigo) => expect(codigo, 'PUE-0001'),
      failure: (_) => fail('no debería fallar'),
    );
  });

  test('devuelve Failure para un tipo no registrado', () async {
    final result = await useCase.ejecutar('inexistente');
    expect(result.isFailure, isTrue);
  });
}
