import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';

void main() {
  late AppDatabase db;
  late CrearClienteUseCase crearCliente;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    crearCliente = CrearClienteUseCase(
      ClienteRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
    );
  });

  tearDown(() => db.close());

  test('crea un Cliente comercial con solo nombre comercial', () async {
    final result = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    expect(result.isOk, isTrue);
    result.when(
      ok: (c) {
        expect(c.codigo, 'CLI-000001');
        expect(c.nombreComercial, 'Sportium');
        expect(c.estatus, 'prospecto');
        expect(c.observaciones, isNull);
      },
      failure: (_) => fail('no debería fallar'),
    );
  });

  test('acepta observaciones opcionales', () async {
    final result = await crearCliente.ejecutar(nombreComercial: 'Miluyole', observaciones: '  Cliente referido  ');
    result.when(
      ok: (c) => expect(c.observaciones, 'Cliente referido'),
      failure: (_) => fail('no debería fallar'),
    );
  });

  test('rechaza un nombre comercial vacío', () async {
    final result = await crearCliente.ejecutar(nombreComercial: '   ');
    expect(result.isFailure, isTrue);
  });

  test('dos Clientes con el mismo nombre comercial no chocan entre sí', () async {
    final r1 = await crearCliente.ejecutar(nombreComercial: 'Cliente repetido');
    final r2 = await crearCliente.ejecutar(nombreComercial: 'Cliente repetido');
    expect(r1.isOk, isTrue);
    expect(r2.isOk, isTrue);
  });
}
