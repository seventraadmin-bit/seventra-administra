import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_expediente_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late PuestoRepositoryImpl puestoRepo;
  late CatalogoRepositoryImpl catalogoRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;
  late ObtenerExpedienteServicioUseCase obtenerExpediente;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db);
    puestoRepo = PuestoRepositoryImpl(db);
    catalogoRepo = CatalogoRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final sucursalRepo = SucursalRepositoryImpl(db);
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo);

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    obtenerExpediente =
        ObtenerExpedienteServicioUseCase(servicioRepo, clienteRepo, entidadFiscalRepo, sucursalRepo, comercialRepo);
  });

  tearDown(() => db.close());

  Future<ClienteData> crearClienteDePrueba({String codigo = 'CLI-000001', String nombre = 'Sportium'}) {
    return clienteRepo.crear(ClienteCompanion.insert(codigo: codigo, nombreComercial: nombre));
  }

  Future<ServicioData> crearServicioDePrueba(String clienteId, {String nombre = 'Vigilancia Sportium Toluca'}) async {
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: nombre,
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    return (creado as GuardarServicioExitoso).servicio;
  }

  Future<PuestoData> crearPuestoDePrueba({String codigo = 'PUE-0001', String nombre = 'Guardia'}) {
    return puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: codigo,
        nombre: nombre,
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
  }

  group('CrearLineaComercialUseCase — casos reales obligatorios', () {
    test('Sportium: 1 elemento por club, precio por elemento', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final guardia = await crearPuestoDePrueba();

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1800000, // $18,000.00
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearLineaComercialExitoso>());
      final lineas = await comercialRepo.listarLineas(servicio.id);
      expect(lineas, hasLength(1));
      expect(lineas.single.subtotal, 1800000);
    });

    test('Toluca 32: 2 elementos 24x24, cobro mediante recibo, IVA no aplica', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-000002', nombre: 'Toluca 32');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Vigilancia Toluca 32');
      final guardia = await crearPuestoDePrueba();

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearLineaComercialExitoso>());
      final exito = resultado as CrearLineaComercialExitoso;
      expect(exito.vigencia.tratamientoIva, 'noAplica');
      expect(exito.vigencia.cantidadElementos * exito.vigencia.precioUnitario, 3000000);
    });

    test('Tikal: 2 elementos 24x24, IVA no aplica', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-000003', nombre: 'Tikal');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Vigilancia Tikal');
      final guardia = await crearPuestoDePrueba();

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1600000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearLineaComercialExitoso>());
    });

    test('Mirabilia (Servicio de Construcciones Habitacionales): 2 elementos 24x24', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-000004', nombre: 'Construcciones Habitacionales');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Mirabilia');
      final guardia = await crearPuestoDePrueba();

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1700000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearLineaComercialExitoso>());
    });

    test('Morgan: 2 elementos 24x24 y 1 elemento 12x12, con precios distintos — dos líneas', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-000005', nombre: 'Morgan');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Vigilancia Morgan');
      final guardia = await crearPuestoDePrueba();

      await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );
      await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno12x12,
          cantidadElementos: 1,
          precioUnitario: 900000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      final lineas = await comercialRepo.listarLineas(servicio.id);
      expect(lineas, hasLength(2), reason: 'mismo puesto, distinto turno/cantidad/precio → dos líneas distintas');
      final subtotales = lineas.map((l) => l.subtotal).toSet();
      expect(subtotales, {3000000, 900000});
    });

    test('Un Servicio con Guardias y un Jefe de turno con precios unitarios distintos', () async {
      final cliente = await crearClienteDePrueba(codigo: 'CLI-000006', nombre: 'Cliente con dos perfiles');
      final servicio = await crearServicioDePrueba(cliente.id, nombre: 'Servicio con dos perfiles');
      final guardia = await crearPuestoDePrueba();
      final jefeDeTurno = await crearPuestoDePrueba(codigo: 'PUE-0002', nombre: 'Jefe de turno');

      await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 3,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );
      await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: jefeDeTurno.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 2200000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      final expediente = (await obtenerExpediente.ejecutar(servicio.id)).when(
        ok: (d) => d,
        failure: (_) => throw StateError('no debería fallar'),
      );
      expect(expediente.lineasComerciales, hasLength(2));
      expect(expediente.subtotalComercial, 3 * 1500000 + 2200000);
    });
  });

  group('CrearLineaComercialUseCase — validaciones', () {
    test('rechaza un Puesto inexistente', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: 'puesto-inexistente',
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1000000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearLineaComercialErroresValidacion>());
      final errores = (resultado as CrearLineaComercialErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoLineaComercial.puesto), isTrue);
    });

    test('rechaza cantidad y precio en cero o negativos', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final guardia = await crearPuestoDePrueba();

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 0,
          precioUnitario: -100,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      expect(resultado, isA<CrearLineaComercialErroresValidacion>());
      final errores = (resultado as CrearLineaComercialErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoLineaComercial.cantidadElementos), isTrue);
      expect(errores.any((e) => e.campo == CampoLineaComercial.precioUnitario), isTrue);
    });

    test('rechaza una fecha de vigencia anterior al inicio del Servicio', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final guardia = await crearPuestoDePrueba();

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1000000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2025, 1, 1),
        ),
      );

      expect(resultado, isA<CrearLineaComercialErroresValidacion>());
      final errores = (resultado as CrearLineaComercialErroresValidacion).errores;
      expect(errores.single.codigo, CodigoErrorLineaComercial.fechaAnteriorInicioServicio);
    });

    test('rechaza agregar una línea a un Servicio terminado', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final guardia = await crearPuestoDePrueba();
      await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2026, 6, 1),
      );

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1000000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 6, 1),
        ),
      );

      expect(resultado, isA<CrearLineaComercialServicioNoDisponible>());
    });
  });

  group('Vigente vs programada (Resolución C)', () {
    test('una vigencia con fecha de inicio futura se clasifica como programada, no vigente', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final guardia = await crearPuestoDePrueba();
      final enUnAnio = DateTime.now().add(const Duration(days: 365));

      final resultado = await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1000000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: enUnAnio,
        ),
      );
      expect(resultado, isA<CrearLineaComercialExitoso>());

      final lineas = await comercialRepo.listarLineas(servicio.id);
      expect(lineas.single.vigenciaActual, isNull);
      expect(lineas.single.vigenciasProgramadas, hasLength(1));
      expect(lineas.single.subtotal, 0, reason: 'sin vigencia vigente, el subtotal de la línea es 0');
    });

    test('una vigencia que ya empezó (fecha pasada, sin fecha de fin) se clasifica como vigente', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final guardia = await crearPuestoDePrueba();

      await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 1000000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      final lineas = await comercialRepo.listarLineas(servicio.id);
      expect(lineas.single.vigenciaActual, isNotNull);
      expect(lineas.single.vigenciasProgramadas, isEmpty);
    });
  });

  group('ServicioExpedienteData — subtotal y aviso de IVA (Resolución B)', () {
    test('ivaVariaPorLinea es true cuando las líneas usan tratamientos de IVA distintos', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);
      final guardia = await crearPuestoDePrueba();
      final jefeDeTurno = await crearPuestoDePrueba(codigo: 'PUE-0002', nombre: 'Jefe de turno');

      await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: guardia.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );
      await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: jefeDeTurno.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 1,
          precioUnitario: 2200000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      final expediente = (await obtenerExpediente.ejecutar(servicio.id)).when(
        ok: (d) => d,
        failure: (_) => throw StateError('no debería fallar'),
      );
      expect(expediente.ivaVariaPorLinea, isTrue);
    });

    test('sin líneas comerciales, el subtotal es 0 y no hay aviso de IVA', () async {
      final cliente = await crearClienteDePrueba();
      final servicio = await crearServicioDePrueba(cliente.id);

      final expediente = (await obtenerExpediente.ejecutar(servicio.id)).when(
        ok: (d) => d,
        failure: (_) => throw StateError('no debería fallar'),
      );
      expect(expediente.subtotalComercial, 0);
      expect(expediente.ivaVariaPorLinea, isFalse);
    });
  });
}
