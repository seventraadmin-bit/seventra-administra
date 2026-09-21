import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_domicilio_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/listar_entidades_fiscales_de_cliente_usecase.dart';

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;
  late CrearEntidadFiscalUseCase crearEntidadFiscal;
  late ActualizarEntidadFiscalUseCase actualizarEntidadFiscal;
  late CambiarCicloVidaEntidadFiscalUseCase cambiarCicloVida;
  late GuardarDomicilioFiscalUseCase guardarDomicilio;
  late ListarEntidadesFiscalesDeClienteUseCase listarEntidadesFiscales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clienteRepo = ClienteRepositoryImpl(db);
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final validator = EntidadFiscalValidator(clienteRepo, entidadFiscalRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    crearEntidadFiscal = CrearEntidadFiscalUseCase(entidadFiscalRepo, generarCodigo, validator);
    actualizarEntidadFiscal = ActualizarEntidadFiscalUseCase(entidadFiscalRepo, validator);
    cambiarCicloVida = CambiarCicloVidaEntidadFiscalUseCase(entidadFiscalRepo);
    guardarDomicilio = GuardarDomicilioFiscalUseCase(entidadFiscalRepo);
    listarEntidadesFiscales = ListarEntidadesFiscalesDeClienteUseCase(entidadFiscalRepo);
  });

  tearDown(() => db.close());

  Future<ClienteData> crearClienteDePrueba({String codigo = 'CLI-000001', String nombre = 'Sportium'}) {
    return clienteRepo.crear(ClienteCompanion.insert(codigo: codigo, nombreComercial: nombre));
  }

  Future<void> archivarCliente(String clienteId) {
    return (db.update(db.cliente)..where((t) => t.id.equals(clienteId))).write(
      const ClienteCompanion(cicloVidaRegistro: Value('archivado')),
    );
  }

  group('CrearEntidadFiscalUseCase', () {
    test('crea una Entidad fiscal con código ENF-0001', () async {
      final cliente = await crearClienteDePrueba();
      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Toluca SA de CV', rfc: 'STO010101AB1'),
      );

      expect(resultado, isA<GuardarEntidadFiscalExitoso>());
      final entidad = (resultado as GuardarEntidadFiscalExitoso).entidadFiscal;
      expect(entidad.codigo, 'ENF-0001');
      expect(entidad.razonSocial, 'Sportium Toluca SA de CV');
      expect(entidad.rfc, 'STO010101AB1');
      expect(entidad.clienteId, cliente.id);
    });

    test('permite más de una Entidad fiscal por Cliente (caso Sportium)', () async {
      final cliente = await crearClienteDePrueba();
      await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Toluca SA de CV', rfc: 'STO010101AB1'),
      );
      await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Interlomas SA de CV', rfc: 'SIN010101AB2'),
      );

      final entidades = await listarEntidadesFiscales.ejecutar(cliente.id);
      expect(entidades, hasLength(2));
    });

    test('rechaza RFC duplicado entre Entidades fiscales de Clientes distintos', () async {
      final cliente1 = await crearClienteDePrueba();
      final cliente2 = await crearClienteDePrueba(codigo: 'CLI-000002', nombre: 'Miluyole');

      await crearEntidadFiscal.ejecutar(
        clienteId: cliente1.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: cliente2.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Otra razón social SA', rfc: 'STO010101AB1'),
      );

      expect(resultado, isA<GuardarEntidadFiscalErroresValidacion>());
      final errores = (resultado as GuardarEntidadFiscalErroresValidacion).errores;
      final campoRfc = errores.whereType<ErrorCampoEntidadFiscalGeneral>().map((e) => e.error).where(
            (e) => e.campo == CampoEntidadFiscal.rfc,
          );
      expect(campoRfc.single.codigo, CodigoErrorEntidadFiscal.yaExiste);
    });

    test('normaliza el RFC a mayúsculas antes de comparar unicidad', () async {
      final cliente1 = await crearClienteDePrueba();
      final cliente2 = await crearClienteDePrueba(codigo: 'CLI-000002', nombre: 'Miluyole');

      await crearEntidadFiscal.ejecutar(
        clienteId: cliente1.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'sto010101ab1'),
      );
      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: cliente2.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Otra razón social SA', rfc: 'STO010101AB1'),
      );

      expect(resultado, isA<GuardarEntidadFiscalErroresValidacion>());
    });

    test('un RFC archivado sigue reservado (no libera su RFC)', () async {
      final cliente1 = await crearClienteDePrueba();
      final cliente2 = await crearClienteDePrueba(codigo: 'CLI-000002', nombre: 'Miluyole');

      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: cliente1.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidad = (creada as GuardarEntidadFiscalExitoso).entidadFiscal;
      await cambiarCicloVida.ejecutar(entidadFiscalId: entidad.id, nuevo: CicloVidaRegistro.archivado, motivo: 'Motivo de prueba');

      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: cliente2.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Otra razón social SA', rfc: 'STO010101AB1'),
      );
      expect(resultado, isA<GuardarEntidadFiscalErroresValidacion>());
    });

    test('rechaza razón social vacía', () async {
      final cliente = await crearClienteDePrueba();
      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: '   ', rfc: 'STO010101AB1'),
      );
      expect(resultado, isA<GuardarEntidadFiscalErroresValidacion>());
      final errores = (resultado as GuardarEntidadFiscalErroresValidacion).errores;
      expect(
        errores.whereType<ErrorCampoEntidadFiscalGeneral>().any((e) => e.error.campo == CampoEntidadFiscal.razonSocial),
        isTrue,
      );
    });

    test('rechaza RFC vacío', () async {
      final cliente = await crearClienteDePrueba();
      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: ''),
      );
      final errores = (resultado as GuardarEntidadFiscalErroresValidacion).errores;
      final errorRfc = errores.whereType<ErrorCampoEntidadFiscalGeneral>().firstWhere((e) => e.error.campo == CampoEntidadFiscal.rfc);
      expect(errorRfc.error.codigo, CodigoErrorEntidadFiscal.requerido);
    });

    test('rechaza formato de RFC inválido', () async {
      final cliente = await crearClienteDePrueba();
      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'AB'),
      );
      final errores = (resultado as GuardarEntidadFiscalErroresValidacion).errores;
      final errorRfc = errores.whereType<ErrorCampoEntidadFiscalGeneral>().firstWhere((e) => e.error.campo == CampoEntidadFiscal.rfc);
      expect(errorRfc.error.codigo, CodigoErrorEntidadFiscal.formatoInvalido);
    });

    test('rechaza si el Cliente propietario no está activo (cicloVidaRegistro)', () async {
      final cliente = await crearClienteDePrueba();
      await archivarCliente(cliente.id);

      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final errores = (resultado as GuardarEntidadFiscalErroresValidacion).errores;
      expect(
        errores.whereType<ErrorCampoEntidadFiscalGeneral>().any((e) => e.error.campo == CampoEntidadFiscal.cliente),
        isTrue,
      );
    });
  });

  group('ActualizarEntidadFiscalUseCase', () {
    test('actualiza razón social y RFC', () async {
      final cliente = await crearClienteDePrueba();
      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidad = (creada as GuardarEntidadFiscalExitoso).entidadFiscal;

      final resultado = await actualizarEntidadFiscal.ejecutar(
        id: entidad.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Toluca SA de CV', rfc: 'STO010101AB1'),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<GuardarEntidadFiscalExitoso>());
      final actualizada = (resultado as GuardarEntidadFiscalExitoso).entidadFiscal;
      expect(actualizada.razonSocial, 'Sportium Toluca SA de CV');
      expect(actualizada.clienteId, cliente.id, reason: 'la relación con el Cliente es inmutable');
    });

    test('permite guardar sin cambiar el RFC propio', () async {
      final cliente = await crearClienteDePrueba();
      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidad = (creada as GuardarEntidadFiscalExitoso).entidadFiscal;

      final resultado = await actualizarEntidadFiscal.ejecutar(
        id: entidad.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Renombrada SA de CV', rfc: 'STO010101AB1'),
        motivo: 'Motivo de prueba',
      );
      expect(resultado, isA<GuardarEntidadFiscalExitoso>());
    });

    test('una Entidad fiscal archivada es de solo consulta', () async {
      final cliente = await crearClienteDePrueba();
      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidad = (creada as GuardarEntidadFiscalExitoso).entidadFiscal;
      await cambiarCicloVida.ejecutar(entidadFiscalId: entidad.id, nuevo: CicloVidaRegistro.archivado, motivo: 'Motivo de prueba');

      final resultado = await actualizarEntidadFiscal.ejecutar(
        id: entidad.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Otro nombre SA', rfc: 'STO010101AB1'),
        motivo: 'Motivo de prueba',
      );

      expect(resultado, isA<GuardarEntidadFiscalArchivada>());
      final sinCambios = await entidadFiscalRepo.obtenerPorId(entidad.id);
      expect(sinCambios!.razonSocial, 'Sportium SA de CV', reason: 'no debe modificarse mientras está archivada');
    });
  });

  group('CambiarCicloVidaEntidadFiscalUseCase', () {
    test('archiva y reactiva una Entidad fiscal', () async {
      final cliente = await crearClienteDePrueba();
      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidad = (creada as GuardarEntidadFiscalExitoso).entidadFiscal;

      final archivada = await cambiarCicloVida.ejecutar(entidadFiscalId: entidad.id, nuevo: CicloVidaRegistro.archivado, motivo: 'Motivo de prueba');
      expect((archivada as CambiarCicloVidaEntidadFiscalExitoso).entidadFiscal.cicloVidaRegistro, 'archivado');

      final reactivada = await cambiarCicloVida.ejecutar(entidadFiscalId: entidad.id, nuevo: CicloVidaRegistro.activo, motivo: 'Motivo de prueba');
      expect((reactivada as CambiarCicloVidaEntidadFiscalExitoso).entidadFiscal.cicloVidaRegistro, 'activo');
    });
  });

  group('GuardarDomicilioFiscalUseCase', () {
    Future<EntidadFiscalData> crearEntidadDePrueba() async {
      final cliente = await crearClienteDePrueba();
      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      return (creada as GuardarEntidadFiscalExitoso).entidadFiscal;
    }

    const domicilioCompleto = DireccionBorrador(
      calle: 'Av. Reforma',
      numeroExterior: '100',
      colonia: 'Juárez',
      municipioAlcaldia: 'Cuauhtémoc',
      estado: 'CDMX',
      codigoPostal: '06600',
    );

    test('captura el domicilio fiscal de una Entidad fiscal activa', () async {
      final entidad = await crearEntidadDePrueba();
      final resultado = await guardarDomicilio.ejecutar(entidadFiscalId: entidad.id, domicilio: domicilioCompleto);

      expect(resultado, isA<GuardarDomicilioFiscalExitoso>());
      final domicilio = (resultado as GuardarDomicilioFiscalExitoso).domicilio;
      expect(domicilio!.calle, 'Av. Reforma');
      expect(domicilio.tipoDireccion, 'fiscal');
      expect(domicilio.entidadFiscalId, entidad.id);

      final entidades = await listarEntidadesFiscales.ejecutar(entidad.clienteId);
      expect(entidades.single.datosFiscalesCompletos, isTrue);
    });

    test('sin domicilio, "Datos fiscales incompletos" es verdadero', () async {
      final entidad = await crearEntidadDePrueba();
      final entidades = await listarEntidadesFiscales.ejecutar(entidad.clienteId);
      expect(entidades.single.datosFiscalesCompletos, isFalse);
    });

    test('rechaza un domicilio parcialmente incompleto', () async {
      final entidad = await crearEntidadDePrueba();
      final resultado = await guardarDomicilio.ejecutar(
        entidadFiscalId: entidad.id,
        domicilio: const DireccionBorrador(calle: 'Av. Reforma'),
      );
      expect(resultado, isA<GuardarDomicilioFiscalErroresValidacion>());
    });

    test('vaciar el domicilio lo archiva sin borrarlo', () async {
      final entidad = await crearEntidadDePrueba();
      await guardarDomicilio.ejecutar(entidadFiscalId: entidad.id, domicilio: domicilioCompleto);

      final resultado = await guardarDomicilio.ejecutar(entidadFiscalId: entidad.id, domicilio: null);
      expect(resultado, isA<GuardarDomicilioFiscalExitoso>());
      expect((resultado as GuardarDomicilioFiscalExitoso).domicilio, isNull);

      final activo = await entidadFiscalRepo.obtenerDomicilioFiscal(entidad.id);
      expect(activo, isNull);

      final todos = await db.select(db.direccion).get();
      expect(todos, hasLength(1), reason: 'archivar nunca es un hard delete');
      expect(todos.single.cicloVidaRegistro, 'archivado');
    });

    test('recapturar reactiva y actualiza en vez de duplicar', () async {
      final entidad = await crearEntidadDePrueba();
      await guardarDomicilio.ejecutar(entidadFiscalId: entidad.id, domicilio: domicilioCompleto);
      await guardarDomicilio.ejecutar(entidadFiscalId: entidad.id, domicilio: null);

      const domicilioNuevo = DireccionBorrador(
        calle: 'Av. Insurgentes',
        numeroExterior: '200',
        colonia: 'Roma',
        municipioAlcaldia: 'Cuauhtémoc',
        estado: 'CDMX',
        codigoPostal: '06700',
      );
      final resultado = await guardarDomicilio.ejecutar(entidadFiscalId: entidad.id, domicilio: domicilioNuevo);
      expect((resultado as GuardarDomicilioFiscalExitoso).domicilio!.calle, 'Av. Insurgentes');

      final todos = await db.select(db.direccion).get();
      expect(todos, hasLength(1), reason: 'nunca debe quedar una segunda fila de dirección');
    });

    test('rechaza guardar domicilio si la Entidad fiscal está archivada', () async {
      final entidad = await crearEntidadDePrueba();
      await cambiarCicloVida.ejecutar(entidadFiscalId: entidad.id, nuevo: CicloVidaRegistro.archivado, motivo: 'Motivo de prueba');

      final resultado = await guardarDomicilio.ejecutar(entidadFiscalId: entidad.id, domicilio: domicilioCompleto);
      expect(resultado, isA<GuardarDomicilioFiscalArchivada>());
    });
  });

  group('ListarEntidadesFiscalesDeClienteUseCase', () {
    test('incluye Entidades fiscales archivadas', () async {
      final cliente = await crearClienteDePrueba();
      final creada = await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidad = (creada as GuardarEntidadFiscalExitoso).entidadFiscal;
      await cambiarCicloVida.ejecutar(entidadFiscalId: entidad.id, nuevo: CicloVidaRegistro.archivado, motivo: 'Motivo de prueba');

      final entidades = await listarEntidadesFiscales.ejecutar(cliente.id);
      expect(entidades, hasLength(1));
      expect(entidades.single.entidadFiscal.cicloVidaRegistro, 'archivado');
    });
  });
}
