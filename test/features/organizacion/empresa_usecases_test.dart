import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_empresa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_empresa_activa_usecase.dart';

void main() {
  late AppDatabase db;
  late ObtenerEmpresaActivaUseCase obtenerActiva;
  late ActualizarEmpresaUseCase actualizar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final repo = EmpresaRepositoryImpl(db);
    obtenerActiva = ObtenerEmpresaActivaUseCase(repo);
    actualizar = ActualizarEmpresaUseCase(repo);
  });

  tearDown(() => db.close());

  test('ObtenerEmpresaActivaUseCase devuelve Ok con RSG-01', () async {
    final result = await obtenerActiva.ejecutar();
    expect(result.isOk, isTrue);
    result.when(ok: (e) => expect(e.codigo, 'RSG-01'), failure: (_) => fail('no debería fallar'));
  });

  test('ActualizarEmpresaUseCase rechaza un RFC con formato inválido', () async {
    final result = await actualizar.ejecutar(rfc: 'CORTO');
    expect(result.isFailure, isTrue);
  });

  test('ActualizarEmpresaUseCase acepta un RFC genérico válido y lo normaliza', () async {
    final result = await actualizar.ejecutar(rfc: ' xaxx010101000 ');
    expect(result.isOk, isTrue);
    result.when(ok: (e) => expect(e.rfc, 'XAXX010101000'), failure: (_) => fail('no debería fallar'));
  });

  test('ActualizarEmpresaUseCase aplica razonSocial sin tocar los demás campos', () async {
    final result = await actualizar.ejecutar(razonSocial: 'Seguridad Privada RISEG S.A. de C.V.');
    result.when(
      ok: (e) {
        expect(e.razonSocial, 'Seguridad Privada RISEG S.A. de C.V.');
        expect(e.nombreComercial, 'Seguridad Privada RISEG');
      },
      failure: (_) => fail('no debería fallar'),
    );
  });
}
