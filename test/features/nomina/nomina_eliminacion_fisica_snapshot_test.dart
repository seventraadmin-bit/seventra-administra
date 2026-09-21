// Etapa 4 (Nómina — corrección, cancelación y trazabilidad integral),
// Sección 12: la auditoría de Etapa 2 encontró que `NominaEvento` es
// `cascade` desde `Nomina`/`NominaEmpleado` — antes de esta etapa, el
// snapshot de `EliminacionFisicaEvento` no lo capturaba, así que el
// propio historial de correcciones de una Nómina desaparecía sin
// dejar rastro justo en el momento en que más importa preservarlo
// (antes de un borrado irreversible). Prueba que el fix realmente
// preserva esa evidencia — y que `eliminarRenglon` ya no destruye el
// historial previo de un renglón al borrarlo.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_nomina_fisicamente_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';

void main() {
  late AppDatabase db;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late EliminarNominaFisicamenteUseCase eliminarFisicamente;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-prueba'), nombre: 'Usuario de prueba', nombreUsuario: 'usuario-prueba', passwordHash: 'x'),
        );

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    final pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    nominaRepo = NominaRepositoryImpl(
      db,
      AsignacionRepositoryImpl(db),
      DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)),
      TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, CodigoSecuenciaService(db), empleadoRepo, servicioRepo),
      pagoNominaRepo,
    );
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    eliminarFisicamente = EliminarNominaFisicamenteUseCase(nominaRepo);

    final crearEmpleado = CrearEmpleadoUseCase(
      empleadoRepo,
      GenerarNumeroUseCase(CodigoSecuenciaService(db)),
      const EmpleadoValidator(),
      servicioRepo,
      ServicioComercialRepositoryImpl(db),
    );
    await crearEmpleado.ejecutar(
      nombres: 'Ana',
      apellidoPaterno: 'Gómez',
      sexo: SexoEmpleado.femenino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'GOXA900101MDFXXX01',
      rfc: 'GOXA900101AB1',
      nss: '10000000001',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
      sueldoMensualAdministrativo: 1500000,
    );
  });

  tearDown(() => db.close());

  test(
    'eliminarFisicamente: el snapshot de EliminacionFisicaEvento SÍ conserva el historial de NominaEvento '
    '(antes de esta etapa, se perdía por completo al cascade-delete)',
    () async {
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final nominaId = generado.nomina.id;
      final renglon = (await nominaRepo.listarEmpleados(nominaId)).single;

      // Genera un segundo evento real (además de 'generada') antes de
      // eliminar — una corrección de Borrador.
      await nominaRepo.actualizarRenglon(
        nominaEmpleadoId: renglon.id,
        prestamo: 0,
        tiempoExtra: 0,
        bono: renglon.bono + 1000,
        bonoModificadoManualmente: true,
        faltas: renglon.faltas,
        otrosDescuentos: renglon.otrosDescuentos,
        observaciones: null,
        tipoEvento: 'movimientoModificado',
      );
      final eventosAntes = await nominaRepo.listarEventos(nominaId);
      expect(eventosAntes.map((e) => e.tipoEvento), containsAll(['generada', 'movimientoModificado']));

      final resultado = await eliminarFisicamente.ejecutar(nominaId: nominaId, motivo: MotivoEliminacionFisicaNomina.nominaDePrueba);
      expect(resultado, isA<EliminarNominaFisicamenteExitoso>());
      expect(await nominaRepo.obtenerPorId(nominaId), isNull);

      final eliminacionEvento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(nominaId))).getSingle();
      final snapshot = jsonDecode(eliminacionEvento.snapshotJson) as Map;
      expect(snapshot.containsKey('eventos'), isTrue);
      final eventosSnapshot = (snapshot['eventos'] as List).cast<Map>();
      expect(
        eventosSnapshot.map((e) => e['tipoEvento']),
        containsAll(['generada', 'movimientoModificado']),
        reason: 'el historial completo de la Nómina sobrevive en el snapshot, aunque las filas reales ya se borraron',
      );
    },
  );

  test(
    'eliminarRenglon ya no destruye el historial previo del renglón — lo desvincula (nominaEmpleadoId = null) '
    'en vez de dejar que el cascade lo borre',
    () async {
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final nominaId = generado.nomina.id;
      final renglon = (await nominaRepo.listarEmpleados(nominaId)).single;

      // Un evento previo real sobre este renglón.
      await nominaRepo.actualizarRenglon(
        nominaEmpleadoId: renglon.id,
        prestamo: 0,
        tiempoExtra: 0,
        bono: renglon.bono + 1000,
        bonoModificadoManualmente: true,
        faltas: renglon.faltas,
        otrosDescuentos: renglon.otrosDescuentos,
        observaciones: null,
        tipoEvento: 'movimientoModificado',
      );
      final eventoPrevioId = (await nominaRepo.listarEventos(nominaId)).firstWhere((e) => e.tipoEvento == 'movimientoModificado').id;

      // Eliminación del renglón (mismo mecanismo real que usa
      // `ActualizarNominaDesdePersonalUseCase` cuando el Empleado ya
      // no tiene días pagables) — probado directo a nivel repositorio
      // para aislar exactamente el comportamiento bajo prueba.
      await nominaRepo.eliminarRenglon(renglon.id, motivo: 'Ya no tiene días pagables', actorUsuarioId: 'usuario-prueba');
      expect(await nominaRepo.obtenerEmpleado(renglon.id), isNull, reason: 'el renglón sí se eliminó');

      final eventosTras = await nominaRepo.listarEventos(nominaId);
      final eventoPrevio = eventosTras.firstWhere((e) => e.id == eventoPrevioId);
      expect(eventoPrevio.nominaEmpleadoId, isNull, reason: 'desvinculado, nunca cascade-eliminado junto con el renglón');
      expect(
        eventosTras.where((e) => e.tipoEvento == 'renglonEliminado'),
        isNotEmpty,
        reason: 'la eliminación del renglón en sí también queda auditada',
      );
    },
  );
}
