import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_entidad_fiscal_a_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_responsable_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_sucursal_administrativa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_responsable_interno_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_expediente_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

const _direccionCompleta = DireccionBorrador(
  calle: 'Av. Toluca',
  numeroExterior: '50',
  colonia: 'Centro',
  municipioAlcaldia: 'Toluca',
  estado: 'Estado de México',
  codigoPostal: '50000',
);

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;
  late SucursalRepositoryImpl sucursalRepo;
  late CrearServicioUseCase crearServicio;
  late CrearEntidadFiscalUseCase crearEntidadFiscal;
  late CrearSucursalUseCase crearSucursal;
  late CambiarCicloVidaEntidadFiscalUseCase cambiarCicloVidaEntidadFiscal;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;
  late AsignarEntidadFiscalAServicioUseCase asignarEntidadFiscal;
  late AsignarResponsableClienteUseCase asignarResponsableCliente;
  late AsignarSucursalAdministrativaUseCase asignarSucursalAdministrativa;
  late GuardarDireccionOperativaServicioUseCase guardarDireccionOperativa;
  late GuardarResponsableInternoUseCase guardarResponsableInterno;
  late ObtenerExpedienteServicioUseCase obtenerExpediente;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    sucursalRepo = SucursalRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final entidadFiscalValidator = EntidadFiscalValidator(clienteRepo, entidadFiscalRepo);

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearEntidadFiscal = CrearEntidadFiscalUseCase(entidadFiscalRepo, generarCodigo, entidadFiscalValidator);
    crearSucursal = CrearSucursalUseCase(sucursalRepo, generarCodigo);
    cambiarCicloVidaEntidadFiscal = CambiarCicloVidaEntidadFiscalUseCase(entidadFiscalRepo);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    asignarEntidadFiscal = AsignarEntidadFiscalAServicioUseCase(servicioRepo, entidadFiscalRepo);
    asignarResponsableCliente = AsignarResponsableClienteUseCase(servicioRepo, clienteRepo);
    asignarSucursalAdministrativa = AsignarSucursalAdministrativaUseCase(servicioRepo, sucursalRepo);
    guardarDireccionOperativa = GuardarDireccionOperativaServicioUseCase(servicioRepo);
    guardarResponsableInterno = GuardarResponsableInternoUseCase(servicioRepo);
    obtenerExpediente = ObtenerExpedienteServicioUseCase(
      servicioRepo,
      clienteRepo,
      entidadFiscalRepo,
      sucursalRepo,
      ServicioComercialRepositoryImpl(db),
      ConfiguracionCobroRepositoryImpl(db),
      AsignacionServicioRepositoryImpl(db),
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
    );
  });

  tearDown(() => db.close());

  Future<ClienteData> crearClienteDePrueba({String codigo = 'CLI-000001', String nombre = 'Sportium'}) {
    return clienteRepo.crear(ClienteCompanion.insert(codigo: codigo, nombreComercial: nombre));
  }

  Future<ServicioData> crearServicioDePrueba(String clienteId) async {
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    return (creado as GuardarServicioExitoso).servicio;
  }

  Future<EntidadFiscalData> crearEntidadFiscalDePrueba(String clienteId, {String rfc = 'SPO010101AA1'}) async {
    final creada = await crearEntidadFiscal.ejecutar(
      clienteId: clienteId,
      borrador: EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: rfc),
    );
    return (creada as GuardarEntidadFiscalExitoso).entidadFiscal;
  }

  Future<SucursalData> crearSucursalDePrueba() async {
    final r = await crearSucursal.ejecutar(nombre: 'Sucursal Centro', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
    return r.when(ok: (s) => s, failure: (_) => throw StateError('no debería fallar'));
  }

  group('AsignarEntidadFiscalAServicioUseCase', () {
    test('asigna una Entidad fiscal activa del mismo Cliente', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidad = await crearEntidadFiscalDePrueba(cliente.id);

      final resultado = await asignarEntidadFiscal.ejecutar(servicioId: servicio.id, entidadFiscalId: entidad.id);

      expect(resultado, isA<AsignarEntidadFiscalAServicioExitoso>());
      expect((resultado as AsignarEntidadFiscalAServicioExitoso).servicio.entidadFiscalId, entidad.id);
    });

    test('rechaza una Entidad fiscal de otro Cliente', () async {
      final cliente = await crearClienteDePrueba();
      final otroCliente = await crearClienteDePrueba(codigo: 'CLI-000002', nombre: 'Miluyole');
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidadAjena = await crearEntidadFiscalDePrueba(otroCliente.id);

      final resultado = await asignarEntidadFiscal.ejecutar(servicioId: servicio.id, entidadFiscalId: entidadAjena.id);

      expect(resultado, isA<AsignarEntidadFiscalAServicioNoPerteneceAlCliente>());
    });

    test('rechaza una Entidad fiscal archivada al asignarla como nueva', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidad = await crearEntidadFiscalDePrueba(cliente.id);
      await cambiarCicloVidaEntidadFiscal.ejecutar(entidadFiscalId: entidad.id, nuevo: CicloVidaRegistro.archivado);

      final resultado = await asignarEntidadFiscal.ejecutar(servicioId: servicio.id, entidadFiscalId: entidad.id);

      expect(resultado, isA<AsignarEntidadFiscalAServicioNoDisponible>());
    });

    test('quitar la asignación siempre funciona, incluso sin validaciones', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidad = await crearEntidadFiscalDePrueba(cliente.id);
      await asignarEntidadFiscal.ejecutar(servicioId: servicio.id, entidadFiscalId: entidad.id);

      final resultado = await asignarEntidadFiscal.ejecutar(servicioId: servicio.id, entidadFiscalId: null);

      expect(resultado, isA<AsignarEntidadFiscalAServicioExitoso>());
      expect((resultado as AsignarEntidadFiscalAServicioExitoso).servicio.entidadFiscalId, isNull);
    });

    test('una Entidad fiscal ya asignada que se archiva después conserva la relación', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final entidad = await crearEntidadFiscalDePrueba(cliente.id);
      await asignarEntidadFiscal.ejecutar(servicioId: servicio.id, entidadFiscalId: entidad.id);

      await cambiarCicloVidaEntidadFiscal.ejecutar(entidadFiscalId: entidad.id, nuevo: CicloVidaRegistro.archivado);

      final expediente = (await obtenerExpediente.ejecutar(servicio.id)).when(
        ok: (d) => d,
        failure: (_) => throw StateError('no debería fallar'),
      );
      expect(expediente.entidadFiscal?.id, entidad.id, reason: 'la relación no se desvincula sola');
      expect(expediente.entidadFiscalArchivada, isTrue);
    });
  });

  group('AsignarResponsableClienteUseCase', () {
    test('asigna un Contacto activo del mismo Cliente', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final contacto = await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: cliente.id, nombre: 'Juan Pérez', tipo: 'comercial'),
      );

      final resultado = await asignarResponsableCliente.ejecutar(servicioId: servicio.id, contactoId: contacto.id);

      expect(resultado, isA<AsignarResponsableClienteExitoso>());
      expect((resultado as AsignarResponsableClienteExitoso).servicio.responsableClienteContactoId, contacto.id);
    });

    test('rechaza un Contacto de otro Cliente', () async {
      final cliente = await crearClienteDePrueba();
      final otroCliente = await crearClienteDePrueba(codigo: 'CLI-000002', nombre: 'Miluyole');
      final servicio = await crearServicioDePrueba(cliente.id);
      final contactoAjeno = await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: otroCliente.id, nombre: 'Ana López', tipo: 'operativo'),
      );

      final resultado = await asignarResponsableCliente.ejecutar(servicioId: servicio.id, contactoId: contactoAjeno.id);

      expect(resultado, isA<AsignarResponsableClienteNoPerteneceAlCliente>());
    });

    test('rechaza un Contacto archivado al asignarlo como nuevo', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final contacto = await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: cliente.id, nombre: 'Juan Pérez', tipo: 'comercial'),
      );
      await clienteRepo.archivarContacto(contacto.id);

      final resultado = await asignarResponsableCliente.ejecutar(servicioId: servicio.id, contactoId: contacto.id);

      expect(resultado, isA<AsignarResponsableClienteNoDisponible>());
    });

    test('un Contacto ya asignado que se archiva después conserva la relación', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final contacto = await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: cliente.id, nombre: 'Juan Pérez', tipo: 'comercial'),
      );
      await asignarResponsableCliente.ejecutar(servicioId: servicio.id, contactoId: contacto.id);

      await clienteRepo.archivarContacto(contacto.id);

      final expediente = (await obtenerExpediente.ejecutar(servicio.id)).when(
        ok: (d) => d,
        failure: (_) => throw StateError('no debería fallar'),
      );
      expect(expediente.responsableCliente?.id, contacto.id);
      expect(expediente.responsableClienteArchivado, isTrue);
    });
  });

  group('AsignarSucursalAdministrativaUseCase', () {
    test('asigna una Sucursal activa', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final sucursal = await crearSucursalDePrueba();

      final resultado = await asignarSucursalAdministrativa.ejecutar(servicioId: servicio.id, sucursalId: sucursal.id);

      expect(resultado, isA<AsignarSucursalAdministrativaExitoso>());
      expect((resultado as AsignarSucursalAdministrativaExitoso).servicio.sucursalAdministrativaId, sucursal.id);
    });

    test('rechaza una Sucursal inexistente', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado =
          await asignarSucursalAdministrativa.ejecutar(servicioId: servicio.id, sucursalId: 'sucursal-inexistente');

      expect(resultado, isA<AsignarSucursalAdministrativaNoExiste>());
    });

    test('rechaza una Sucursal archivada al asignarla como nueva', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final sucursal = await crearSucursalDePrueba();
      await (db.update(db.sucursal)..where((t) => t.id.equals(sucursal.id)))
          .write(const SucursalCompanion(cicloVidaRegistro: Value('archivado')));

      final resultado = await asignarSucursalAdministrativa.ejecutar(servicioId: servicio.id, sucursalId: sucursal.id);

      expect(resultado, isA<AsignarSucursalAdministrativaNoDisponible>());
    });

    test('una Sucursal ya asignada que se archiva después conserva la relación', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final sucursal = await crearSucursalDePrueba();
      await asignarSucursalAdministrativa.ejecutar(servicioId: servicio.id, sucursalId: sucursal.id);

      await (db.update(db.sucursal)..where((t) => t.id.equals(sucursal.id)))
          .write(const SucursalCompanion(cicloVidaRegistro: Value('archivado')));

      final expediente = (await obtenerExpediente.ejecutar(servicio.id)).when(
        ok: (d) => d,
        failure: (_) => throw StateError('no debería fallar'),
      );
      expect(expediente.sucursalAdministrativa?.id, sucursal.id);
      expect(expediente.sucursalAdministrativaArchivada, isTrue);
    });

    test('quitar la asignación siempre funciona', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final sucursal = await crearSucursalDePrueba();
      await asignarSucursalAdministrativa.ejecutar(servicioId: servicio.id, sucursalId: sucursal.id);

      final resultado = await asignarSucursalAdministrativa.ejecutar(servicioId: servicio.id, sucursalId: null);

      expect(resultado, isA<AsignarSucursalAdministrativaExitoso>());
      expect((resultado as AsignarSucursalAdministrativaExitoso).servicio.sucursalAdministrativaId, isNull);
    });
  });

  group('GuardarDireccionOperativaServicioUseCase', () {
    test('captura una Dirección operativa completa', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado =
          await guardarDireccionOperativa.ejecutar(servicioId: servicio.id, domicilio: _direccionCompleta);

      expect(resultado, isA<GuardarDireccionOperativaServicioExitoso>());
      final direccion = (resultado as GuardarDireccionOperativaServicioExitoso).direccion;
      expect(direccion!.calle, 'Av. Toluca');
      expect(direccion.tipoDireccion, 'operativa');
    });

    test('rechaza una Dirección parcialmente incompleta', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado = await guardarDireccionOperativa.ejecutar(
        servicioId: servicio.id,
        domicilio: const DireccionBorrador(calle: 'Av. Toluca'),
      );

      expect(resultado, isA<GuardarDireccionOperativaServicioErroresValidacion>());
    });

    test('vaciar la Dirección la archiva sin borrarla, y nunca duplica al recapturar', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      await guardarDireccionOperativa.ejecutar(servicioId: servicio.id, domicilio: _direccionCompleta);

      final vacio = await guardarDireccionOperativa.ejecutar(servicioId: servicio.id, domicilio: null);
      expect((vacio as GuardarDireccionOperativaServicioExitoso).direccion, isNull);
      expect(await servicioRepo.tieneDireccionOperativaActiva(servicio.id), isFalse);

      await guardarDireccionOperativa.ejecutar(servicioId: servicio.id, domicilio: _direccionCompleta);
      final todas = await db.select(db.direccion).get();
      expect(todas.where((d) => d.servicioId == servicio.id), hasLength(1), reason: 'nunca debe duplicar la fila');
    });

    test('al guardar una Dirección operativa válida, el Servicio puede activarse', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final bloqueado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
      expect(bloqueado, isA<CambiarEstatusServicioFaltaDireccionOperativa>());

      await guardarDireccionOperativa.ejecutar(servicioId: servicio.id, domicilio: _direccionCompleta);

      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
      expect(resultado, isA<CambiarEstatusServicioExitoso>());
    });
  });

  group('GuardarResponsableInternoUseCase', () {
    test('guarda, actualiza y limpia el texto', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final guardado = await guardarResponsableInterno.ejecutar(servicioId: servicio.id, texto: 'Juan Pérez');
      expect(guardado.responsableInterno, 'Juan Pérez');

      final actualizado = await guardarResponsableInterno.ejecutar(servicioId: servicio.id, texto: '  Ana López  ');
      expect(actualizado.responsableInterno, 'Ana López');

      final limpiado = await guardarResponsableInterno.ejecutar(servicioId: servicio.id, texto: '   ');
      expect(limpiado.responsableInterno, isNull);
    });
  });

  group('ObtenerExpedienteServicioUseCase (composite extendido)', () {
    test('incluye el Cliente propietario de solo lectura', () async {
      final cliente = await crearClienteDePrueba(nombre: 'Sportium');
      final servicio = await crearServicioDePrueba(cliente.id);

      final expediente = (await obtenerExpediente.ejecutar(servicio.id)).when(
        ok: (d) => d,
        failure: (_) => throw StateError('no debería fallar'),
      );
      expect(expediente.cliente.nombreComercial, 'Sportium');
    });

    test('sin vinculaciones asignadas, todos los campos opcionales son null y ninguna advertencia se activa', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final expediente = (await obtenerExpediente.ejecutar(servicio.id)).when(
        ok: (d) => d,
        failure: (_) => throw StateError('no debería fallar'),
      );
      expect(expediente.entidadFiscal, isNull);
      expect(expediente.responsableCliente, isNull);
      expect(expediente.sucursalAdministrativa, isNull);
      expect(expediente.direccionOperativa, isNull);
      expect(expediente.entidadFiscalArchivada, isFalse);
      expect(expediente.responsableClienteArchivado, isFalse);
      expect(expediente.sucursalAdministrativaArchivada, isFalse);
    });
  });
}
