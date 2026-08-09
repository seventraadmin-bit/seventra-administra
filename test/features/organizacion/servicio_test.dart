import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/ubicacion_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/listar_servicios_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late UbicacionRepositoryImpl ubicacionRepo;
  late CrearServicioUseCase crearServicio;
  late ActualizarServicioUseCase actualizarServicio;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;
  late ListarServiciosUseCase listarServicios;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    ubicacionRepo = UbicacionRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final validator = ServicioValidator(clienteRepo, catalogoRepo);

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, validator);
    actualizarServicio = ActualizarServicioUseCase(servicioRepo, validator);
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    listarServicios = ListarServiciosUseCase(servicioRepo);
  });

  tearDown(() => db.close());

  Future<ClienteData> crearClienteDePrueba({
    String codigo = 'CLI-000001',
    String nombre = 'Sportium',
    EstatusCliente? estatus,
  }) async {
    final creado = await clienteRepo.crear(ClienteCompanion.insert(codigo: codigo, nombreComercial: nombre));
    if (estatus != null) {
      return clienteRepo.cambiarEstatus(id: creado.id, nuevo: estatus);
    }
    return creado;
  }

  const borradorBase = ServicioBorrador(
    nombre: 'Vigilancia Sportium Centro',
    tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
    fechaInicio: null,
  );
  ServicioBorrador borrador({String? nombre, String? tipoServicioId, DateTime? fechaInicio, String? observaciones}) {
    return ServicioBorrador(
      nombre: nombre ?? borradorBase.nombre,
      tipoServicioId: tipoServicioId ?? borradorBase.tipoServicioId,
      fechaInicio: fechaInicio ?? DateTime(2026, 1, 1),
      observaciones: observaciones,
    );
  }

  group('CrearServicioUseCase', () {
    test('crea un Servicio con código SER-0001 y Ubicación raíz automática, sin Dirección', () async {
      final cliente = await crearClienteDePrueba();
      final resultado = await crearServicio.ejecutar(clienteId: cliente.id, borrador: borrador());

      expect(resultado, isA<GuardarServicioExitoso>());
      final servicio = (resultado as GuardarServicioExitoso).servicio;
      expect(servicio.codigo, 'SER-000001');
      expect(servicio.estatus, 'cotizado');
      expect(servicio.sucursalAdministrativaId, isNull);

      final raiz = await ubicacionRepo.obtenerRaizDeServicio(servicio.id);
      expect(raiz, isNotNull, reason: 'la Ubicación raíz debe crearse aunque no haya Dirección todavía');
      expect(raiz!.tipoUbicacion, TipoUbicacion.servicio.name);
      expect(raiz.parentId, isNull);

      final tieneDireccion = await servicioRepo.tieneDireccionOperativaActiva(servicio.id);
      expect(tieneDireccion, isFalse);
    });

    test('Sportium: un Cliente puede tener cuatro Servicios distintos', () async {
      final sportium = await crearClienteDePrueba(nombre: 'Sportium');

      final nombres = ['Vigilancia Sportium Toluca', 'Vigilancia Sportium Interlomas', 'Vigilancia Sportium Satélite', 'Rondín Sportium CDMX'];
      final ids = <String>{};
      for (final nombre in nombres) {
        final resultado = await crearServicio.ejecutar(clienteId: sportium.id, borrador: borrador(nombre: nombre));
        expect(resultado, isA<GuardarServicioExitoso>());
        ids.add((resultado as GuardarServicioExitoso).servicio.id);
      }

      expect(ids, hasLength(4));
      final servicios = await listarServicios.ejecutar();
      final deSportium = servicios.where((s) => s.servicio.clienteId == sportium.id);
      expect(deSportium, hasLength(4));
    });

    test('Construcciones Habitacionales → Servicio Mirabilia, Tipo de Servicio Vigilancia fija', () async {
      final cliente = await crearClienteDePrueba(nombre: 'Construcciones Habitacionales');
      final resultado = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: borrador(nombre: 'Mirabilia', tipoServicioId: SeedIds.tipoServicioVigilanciaFija),
      );

      expect(resultado, isA<GuardarServicioExitoso>());
      final servicio = (resultado as GuardarServicioExitoso).servicio;
      expect(servicio.nombre, 'Mirabilia');
      expect(servicio.tipoServicioId, SeedIds.tipoServicioVigilanciaFija);

      final listado = await listarServicios.ejecutar();
      final item = listado.singleWhere((s) => s.servicio.id == servicio.id);
      expect(item.clienteNombre, 'Construcciones Habitacionales');
      expect(item.tipoServicioNombre, 'Vigilancia fija');
    });

    test('rechaza nombre vacío', () async {
      final cliente = await crearClienteDePrueba();
      final resultado = await crearServicio.ejecutar(clienteId: cliente.id, borrador: borrador(nombre: '   '));

      expect(resultado, isA<GuardarServicioErroresValidacion>());
      final errores = (resultado as GuardarServicioErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoServicio.nombre), isTrue);
    });

    test('rechaza fechaInicio nula', () async {
      final cliente = await crearClienteDePrueba();
      final resultado = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: const ServicioBorrador(
          nombre: 'Servicio sin fecha',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: null,
        ),
      );
      final errores = (resultado as GuardarServicioErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoServicio.fechaInicio), isTrue);
    });

    test('rechaza un Tipo de Servicio inexistente', () async {
      final cliente = await crearClienteDePrueba();
      final resultado = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: borrador(tipoServicioId: 'tipo-servicio-inexistente'),
      );
      final errores = (resultado as GuardarServicioErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoServicio.tipoServicio), isTrue);
    });

    test('rechaza un Cliente inexistente', () async {
      final resultado = await crearServicio.ejecutar(clienteId: 'cliente-inexistente', borrador: borrador());
      final errores = (resultado as GuardarServicioErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoServicio.cliente), isTrue);
    });

    test('rechaza un Cliente archivado (cicloVidaRegistro)', () async {
      final cliente = await crearClienteDePrueba();
      await (db.update(db.cliente)..where((t) => t.id.equals(cliente.id)))
          .write(const ClienteCompanion(cicloVidaRegistro: Value('archivado')));

      final resultado = await crearServicio.ejecutar(clienteId: cliente.id, borrador: borrador());
      final errores = (resultado as GuardarServicioErroresValidacion).errores;
      expect(errores.any((e) => e.campo == CampoServicio.cliente), isTrue);
    });

    for (final estatus in [EstatusCliente.suspendido, EstatusCliente.terminado, EstatusCliente.descartado]) {
      test('rechaza un Cliente con estatus $estatus', () async {
        final cliente = await crearClienteDePrueba(estatus: estatus);
        final resultado = await crearServicio.ejecutar(clienteId: cliente.id, borrador: borrador());

        expect(resultado, isA<GuardarServicioErroresValidacion>());
        final errores = (resultado as GuardarServicioErroresValidacion).errores;
        final errorCliente = errores.firstWhere((e) => e.campo == CampoServicio.cliente);
        expect(errorCliente.codigo, CodigoErrorServicio.clienteNoDisponible);
      });
    }

    for (final estatus in [EstatusCliente.prospecto, EstatusCliente.activo]) {
      test('acepta un Cliente con estatus $estatus', () async {
        final cliente = await crearClienteDePrueba(estatus: estatus);
        final resultado = await crearServicio.ejecutar(clienteId: cliente.id, borrador: borrador());
        expect(resultado, isA<GuardarServicioExitoso>());
      });
    }
  });

  group('ActualizarServicioUseCase', () {
    test('actualiza nombre, tipo, fecha de inicio y observaciones', () async {
      final cliente = await crearClienteDePrueba();
      final creado = (await crearServicio.ejecutar(clienteId: cliente.id, borrador: borrador())) as GuardarServicioExitoso;

      final resultado = await actualizarServicio.ejecutar(
        id: creado.servicio.id,
        borrador: borrador(nombre: 'Vigilancia Sportium Renombrada', observaciones: 'Actualizado'),
      );

      expect(resultado, isA<GuardarServicioExitoso>());
      final actualizado = (resultado as GuardarServicioExitoso).servicio;
      expect(actualizado.nombre, 'Vigilancia Sportium Renombrada');
      expect(actualizado.observaciones, 'Actualizado');
      expect(actualizado.clienteId, cliente.id, reason: 'la relación con el Cliente es inmutable');
    });
  });

  group('CambiarEstatusServicioUseCase', () {
    Future<ServicioData> crearServicioDePrueba({EstatusCliente? estatusCliente}) async {
      final cliente = await crearClienteDePrueba(estatus: estatusCliente);
      final creado = (await crearServicio.ejecutar(clienteId: cliente.id, borrador: borrador())) as GuardarServicioExitoso;
      return creado.servicio;
    }

    test('cotizado → suspendido no requiere Dirección operativa', () async {
      final servicio = await crearServicioDePrueba();
      final resultado = await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.suspendido,
      );
      expect(resultado, isA<CambiarEstatusServicioExitoso>());
      expect((resultado as CambiarEstatusServicioExitoso).servicio.estatus, 'suspendido');
    });

    test('rechaza activar sin Dirección operativa (bloqueo real durante toda la Etapa 4F.1)', () async {
      final servicio = await crearServicioDePrueba();
      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
      expect(resultado, isA<CambiarEstatusServicioFaltaDireccionOperativa>());
    });

    test('permite activar cuando sí existe una Dirección operativa activa', () async {
      final servicio = await crearServicioDePrueba();
      await db.into(db.direccion).insert(
            DireccionCompanion.insert(
              servicioId: Value(servicio.id),
              tipoDireccion: TipoDireccion.operativa.name,
              calle: 'Av. Toluca',
              numeroExterior: '50',
              colonia: 'Centro',
              municipioAlcaldia: 'Toluca',
              estado: 'Estado de México',
              codigoPostal: '50000',
            ),
          );

      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
      expect(resultado, isA<CambiarEstatusServicioExitoso>());
    });

    test('rechaza activar si el Cliente ya no está disponible', () async {
      final servicio = await crearServicioDePrueba();
      await db.into(db.direccion).insert(
            DireccionCompanion.insert(
              servicioId: Value(servicio.id),
              tipoDireccion: TipoDireccion.operativa.name,
              calle: 'Av. Toluca',
              numeroExterior: '50',
              colonia: 'Centro',
              municipioAlcaldia: 'Toluca',
              estado: 'Estado de México',
              codigoPostal: '50000',
            ),
          );
      await clienteRepo.cambiarEstatus(id: servicio.clienteId, nuevo: EstatusCliente.suspendido);
      await (db.update(db.cliente)..where((t) => t.id.equals(servicio.clienteId)))
          .write(const ClienteCompanion(cicloVidaRegistro: Value('archivado')));

      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
      expect(resultado, isA<CambiarEstatusServicioClienteNoDisponible>());
    });

    test('rechaza una transición no permitida (activo → cotizado)', () async {
      final servicio = await crearServicioDePrueba();
      // Fuerza el estado 'activo' directamente en el repositorio — el
      // camino normal (cambiarEstatusServicio) no puede llegar ahí
      // todavía sin Dirección, pero la regla de transición debe seguir
      // aplicando sin importar cómo se haya llegado al estado actual.
      await servicioRepo.cambiarEstatus(id: servicio.id, nuevo: EstatusServicio.activo);

      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.cotizado);
      expect(resultado, isA<CambiarEstatusServicioTransicionInvalida>());
    });

    test('terminar sin fechaTermino previa y sin proporcionar una exige la fecha efectiva', () async {
      final servicio = await crearServicioDePrueba();
      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.terminado);
      expect(resultado, isA<CambiarEstatusServicioRequiereFechaTermino>());
    });

    test('terminar con fecha efectiva la persiste sin asignarla automáticamente', () async {
      final servicio = await crearServicioDePrueba();
      final resultado = await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2026, 6, 15),
      );
      expect(resultado, isA<CambiarEstatusServicioExitoso>());
      expect((resultado as CambiarEstatusServicioExitoso).servicio.fechaTermino, DateTime(2026, 6, 15));
    });

    test('rechaza una fecha de término efectiva anterior a la fecha de inicio', () async {
      final servicio = await crearServicioDePrueba();
      final resultado = await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2025, 1, 1),
      );
      expect(resultado, isA<CambiarEstatusServicioFechaTerminoInvalida>());
    });

    test('terminar cuando ya existe fechaTermino no la sobrescribe sin una nueva', () async {
      final servicio = await crearServicioDePrueba();
      await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2026, 6, 15),
      );
      // Regresa a 'suspendido' vía repositorio directo (el propio
      // dominio no permite terminado → suspendido; se hace así solo
      // para poder volver a probar la acción de terminar) preservando
      // explícitamente la fechaTermino ya existente — igual que hace el
      // caso de uso real, que nunca la sobrescribe con `null` por
      // accidente.
      await servicioRepo.cambiarEstatus(
        id: servicio.id,
        nuevo: EstatusServicio.suspendido,
        fechaTermino: DateTime(2026, 6, 15),
      );
      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.terminado);

      expect(resultado, isA<CambiarEstatusServicioExitoso>());
      expect((resultado as CambiarEstatusServicioExitoso).servicio.fechaTermino, DateTime(2026, 6, 15));
    });

    test('reactivar desde terminado aplica las mismas validaciones que activar', () async {
      final servicio = await crearServicioDePrueba();
      await servicioRepo.cambiarEstatus(id: servicio.id, nuevo: EstatusServicio.terminado, fechaTermino: DateTime(2026, 3, 1));

      final resultado = await cambiarEstatusServicio.ejecutar(servicioId: servicio.id, nuevo: EstatusServicio.activo);
      expect(resultado, isA<CambiarEstatusServicioFaltaDireccionOperativa>());
    });
  });
}
