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

  test('un Prospecto puede crearse sin RFC', () async {
    final result = await crearCliente.ejecutar(razonSocial: 'Prospecto S.A.');
    expect(result.isOk, isTrue);
    result.when(
      ok: (c) {
        expect(c.codigo, 'CLI-000001');
        expect(c.rfc, isNull);
      },
      failure: (_) => fail('no debería fallar'),
    );
  });

  test('normaliza el RFC a mayúsculas y sin espacios', () async {
    final result = await crearCliente.ejecutar(razonSocial: 'Sportium', rfc: '  spo010101aa1  ');
    result.when(
      ok: (c) => expect(c.rfc, 'SPO010101AA1'),
      failure: (_) => fail('no debería fallar'),
    );
  });

  test('acepta RFC genéricos válidos (XAXX010101000 / XEXX010101000)', () async {
    final r1 = await crearCliente.ejecutar(razonSocial: 'Cliente genérico 1', rfc: 'XAXX010101000');
    final r2 = await crearCliente.ejecutar(razonSocial: 'Cliente genérico 2', rfc: 'XEXX010101000');
    expect(r1.isOk, isTrue);
    expect(r2.isOk, isTrue);
  });

  test('rechaza un RFC con longitud incorrecta', () async {
    final result = await crearCliente.ejecutar(razonSocial: 'Cliente inválido', rfc: 'CORTO123');
    expect(result.isFailure, isTrue);
  });

  test('rechaza un RFC con caracteres fuera del conjunto permitido', () async {
    final result = await crearCliente.ejecutar(razonSocial: 'Cliente inválido', rfc: 'SPO010101#A1');
    expect(result.isFailure, isTrue);
  });

  test('acepta Ñ y & dentro del RFC', () async {
    final result = await crearCliente.ejecutar(razonSocial: 'Peña & Asociados', rfc: 'PEÑ010101A&1');
    expect(result.isOk, isTrue);
  });

  test('rechaza un segundo cliente con el mismo RFC', () async {
    final primero = await crearCliente.ejecutar(razonSocial: 'Cliente uno', rfc: 'CUN010101AA1');
    expect(primero.isOk, isTrue);

    final segundo = await crearCliente.ejecutar(razonSocial: 'Cliente dos', rfc: 'cun010101aa1');
    expect(segundo.isFailure, isTrue);
  });

  test('dos prospectos sin RFC no chocan entre sí', () async {
    final r1 = await crearCliente.ejecutar(razonSocial: 'Prospecto A');
    final r2 = await crearCliente.ejecutar(razonSocial: 'Prospecto B');
    expect(r1.isOk, isTrue);
    expect(r2.isOk, isTrue);
  });
}
