import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/ubicacion_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';

const _direccionDemo = DireccionInput(
  calle: 'Av. Insurgentes',
  numeroExterior: '123',
  colonia: 'Roma Norte',
  municipioAlcaldia: 'Cuauhtémoc',
  estado: 'Ciudad de México',
  codigoPostal: '06700',
);

void main() {
  late AppDatabase db;
  late CrearServicioUseCase crearServicio;
  late CrearClienteUseCase crearCliente;
  late CrearSucursalUseCase crearSucursal;
  late ClienteRepositoryImpl clienteRepo;
  late UbicacionRepositoryImpl ubicacionRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    ubicacionRepo = UbicacionRepositoryImpl(db);
    crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
    crearSucursal = CrearSucursalUseCase(SucursalRepositoryImpl(db), generarCodigo);
    crearServicio = CrearServicioUseCase(
      ServicioRepositoryImpl(db),
      clienteRepo,
      generarCodigo,
    );
  });

  tearDown(() => db.close());

  Future<String> crearClienteDePrueba() async {
    final r = await crearCliente.ejecutar(razonSocial: 'Sportium');
    late String id;
    r.when(ok: (c) => id = c.id, failure: (_) => fail('no debería fallar'));
    return id;
  }

  Future<String> crearSucursalDePrueba() async {
    final r = await crearSucursal.ejecutar(
      nombre: 'Sucursal Centro',
      tipoSucursalId: SeedIds.tipoSucursalBaseOperativa,
    );
    late String id;
    r.when(ok: (s) => id = s.id, failure: (_) => fail('no debería fallar'));
    return id;
  }

  test('crea Servicio con su Dirección operativa y Ubicación raíz en una sola transacción', () async {
    final clienteId = await crearClienteDePrueba();
    final sucursalId = await crearSucursalDePrueba();

    final result = await crearServicio.ejecutar(
      clienteId: clienteId,
      nombre: 'Vigilancia Sportium Centro',
      tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
      sucursalAdministrativaId: sucursalId,
      fechaInicio: DateTime(2026, 1, 1),
      direccionOperativa: _direccionDemo,
    );

    expect(result.isOk, isTrue);
    late String servicioId;
    result.when(ok: (s) => servicioId = s.id, failure: (_) => fail('no debería fallar'));

    final raiz = await ubicacionRepo.obtenerRaizDeServicio(servicioId);
    expect(raiz, isNotNull);
    expect(raiz!.tipoUbicacion, TipoUbicacion.servicio.name);
  });

  test('rechaza elementosAutorizados negativo', () async {
    final clienteId = await crearClienteDePrueba();
    final sucursalId = await crearSucursalDePrueba();

    final result = await crearServicio.ejecutar(
      clienteId: clienteId,
      nombre: 'Servicio inválido',
      tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
      sucursalAdministrativaId: sucursalId,
      fechaInicio: DateTime(2026, 1, 1),
      elementosAutorizados: -1,
      direccionOperativa: _direccionDemo,
    );
    expect(result.isFailure, isTrue);
  });

  test('rechaza fechaTermino anterior a fechaInicio', () async {
    final clienteId = await crearClienteDePrueba();
    final sucursalId = await crearSucursalDePrueba();

    final result = await crearServicio.ejecutar(
      clienteId: clienteId,
      nombre: 'Servicio inválido',
      tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
      sucursalAdministrativaId: sucursalId,
      fechaInicio: DateTime(2026, 6, 1),
      fechaTermino: DateTime(2026, 1, 1),
      direccionOperativa: _direccionDemo,
    );
    expect(result.isFailure, isTrue);
  });

  test('rechaza un contacto responsable que no pertenece al Cliente', () async {
    final clienteId = await crearClienteDePrueba();
    final otroClienteId = await crearClienteDePrueba();
    final sucursalId = await crearSucursalDePrueba();

    final contactoDeOtroCliente = await clienteRepo.agregarContacto(
      ContactoCompanion.insert(clienteId: otroClienteId, nombre: 'Contacto ajeno'),
    );

    final result = await crearServicio.ejecutar(
      clienteId: clienteId,
      nombre: 'Servicio con contacto ajeno',
      tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
      sucursalAdministrativaId: sucursalId,
      fechaInicio: DateTime(2026, 1, 1),
      responsableClienteContactoId: contactoDeOtroCliente.id,
      direccionOperativa: _direccionDemo,
    );
    expect(result.isFailure, isTrue);
  });

  test('acepta un contacto responsable que sí pertenece al Cliente', () async {
    final clienteId = await crearClienteDePrueba();
    final sucursalId = await crearSucursalDePrueba();

    final contacto = await clienteRepo.agregarContacto(
      ContactoCompanion.insert(clienteId: clienteId, nombre: 'Contacto correcto'),
    );

    final result = await crearServicio.ejecutar(
      clienteId: clienteId,
      nombre: 'Servicio con contacto correcto',
      tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
      sucursalAdministrativaId: sucursalId,
      fechaInicio: DateTime(2026, 1, 1),
      responsableClienteContactoId: contacto.id,
      direccionOperativa: _direccionDemo,
    );
    expect(result.isOk, isTrue);
  });
}
