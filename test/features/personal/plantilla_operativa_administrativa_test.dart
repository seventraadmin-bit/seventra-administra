// Etapa "Plantilla operativa vs. administrativa" — casos A-H del pedido
// de Marlon, contra BD real (nunca mocks).
//
// Regla de negocio que protegen:
//   SERVICIO  = operación que RISEG presta a un cliente → OPERATIVO.
//   SUCURSAL  = oficina/estructura interna propia       → ADMINISTRATIVO.
//   ninguno   = sin asignación (la plantilla a la que PERTENECE la
//               resuelve `Puesto.tipo`, que ya existía).
//   ambos     = INCONSISTENCIA, nunca se reparte a conveniencia.
//
// Bug real que cierran: el Dashboard dividía "empleados con Servicio"
// entre "todos los activos", así que un administrativo correctamente
// adscrito a su Sucursal hundía el indicador (15/16 = 93.75% ≈ 94%) y
// aparecía como "1 sin asignar".

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart' show TipoPuesto;
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/domain/plantilla_personal.dart';
import 'package:riseg_one/features/personal/domain/usecases/obtener_plantilla_personal_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/obtener_rotacion_personal_usecase.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late AsignacionServicioRepositoryImpl asignacionRepo;
  late ObtenerPlantillaPersonalUseCase obtenerPlantilla;
  late ObtenerRotacionPersonalUseCase obtenerRotacion;

  late String puestoOperativoId;
  late String puestoAdministrativoId;
  late String servicioId;
  late String otroServicioId;
  late String sucursalId;
  late String otraSucursalId;
  var numero = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionRepo);
    final puestoRepo = PuestoRepositoryImpl(db);
    obtenerPlantilla = ObtenerPlantillaPersonalUseCase(empleadoRepo, asignacionRepo, puestoRepo);
    obtenerRotacion = ObtenerRotacionPersonalUseCase(empleadoRepo, asignacionRepo);

    final area = await db.select(db.area).get();
    final areaId = area.first.id;

    puestoOperativoId = (await db.into(db.puesto).insertReturning(
              PuestoCompanion.insert(
                codigo: 'PUE-OP',
                nombre: 'Elemento Operativo',
                areaId: areaId,
                tipo: TipoPuesto.operativo.name,
                nivelJerarquico: 1,
              ),
            ))
        .id;
    puestoAdministrativoId = (await db.into(db.puesto).insertReturning(
              PuestoCompanion.insert(
                codigo: 'PUE-ADM',
                nombre: 'DIRECCION GENERAL',
                areaId: areaId,
                tipo: TipoPuesto.administrativo.name,
                nivelJerarquico: 10,
              ),
            ))
        .id;

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    servicioId = (await db.into(db.servicio).insertReturning(
              ServicioCompanion.insert(
                codigo: 'SRV-0001',
                nombre: 'Sportium Satélite',
                clienteId: cliente.id,
                tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
                fechaInicio: DateTime(2026, 1, 1),
              ),
            ))
        .id;
    otroServicioId = (await db.into(db.servicio).insertReturning(
              ServicioCompanion.insert(
                codigo: 'SRV-0002',
                nombre: 'Morgan Atlacomulco',
                clienteId: cliente.id,
                tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
                fechaInicio: DateTime(2026, 1, 1),
              ),
            ))
        .id;
    sucursalId = (await db.into(db.sucursal).insertReturning(
              SucursalCompanion.insert(codigo: 'SUC-0001', nombre: 'Toluca', tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa),
            ))
        .id;
    otraSucursalId = (await db.into(db.sucursal).insertReturning(
              SucursalCompanion.insert(codigo: 'SUC-0002', nombre: 'Metepec', tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa),
            ))
        .id;
    numero = 0;
  });

  tearDown(() => db.close());

  Future<EmpleadoData> crearEmpleado({
    required bool operativo,
    String? sucursal,
    DateTime? fechaIngreso,
    DateTime? fechaBaja,
    String estatus = 'activo',
  }) async {
    numero++;
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'Empleado',
            apellidoPaterno: '$numero',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ90010${numero.toString().padLeft(2, '0')}HDFXX1',
            rfc: 'PEXJ9001${numero.toString().padLeft(2, '0')}',
            nss: '1000000${numero.toString().padLeft(4, '0')}',
            estadoCivil: 'soltero',
            fechaIngreso: fechaIngreso ?? DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 1,
            estatus: Value(estatus),
            fechaBaja: Value(fechaBaja),
            motivoBaja: Value(fechaBaja == null ? null : 'renuncia'),
            puestoId: Value(operativo ? puestoOperativoId : puestoAdministrativoId),
            sucursalId: Value(sucursal),
          ),
        );
  }

  Future<void> asignarAServicio(
    String empleadoId, {
    String? servicio,
    DateTime? inicio,
    DateTime? termino,
  }) async {
    await db.into(db.asignacionServicio).insert(
          AsignacionServicioCompanion.insert(
            empleadoId: empleadoId,
            servicioId: servicio ?? servicioId,
            turnoId: const Value(SeedIds.modalidadTurno24x24),
            fechaInicio: inicio ?? DateTime(2026, 1, 1),
            fechaTermino: Value(termino),
          ),
        );
  }

  group('CASO A — 15 operativos asignados + 1 administrativo en Sucursal', () {
    test('el administrativo NO reduce el porcentaje: 15/15 = 100%', () async {
      for (var i = 0; i < 15; i++) {
        final e = await crearEmpleado(operativo: true);
        await asignarAServicio(e.id);
      }
      await crearEmpleado(operativo: false, sucursal: sucursalId);

      final plantilla = await obtenerPlantilla.ejecutar();

      expect(plantilla.totalActivos, 16, reason: 'total empresa');
      expect(plantilla.operativa.activos, 15);
      expect(plantilla.operativa.asignados, 15);
      expect(plantilla.operativa.sinAsignar, 0);
      expect(plantilla.operativa.porcentajeAsignados, 100, reason: 'NUNCA 94%');
      expect(plantilla.administrativa.activos, 1);
      expect(plantilla.administrativa.asignados, 1);
      expect(plantilla.administrativa.sinAsignar, 0);
      expect(plantilla.sinAsignacion, isEmpty, reason: 'NUNCA "1 sin asignar"');
      expect(plantilla.inconsistentes, isEmpty);
    });
  });

  group('CASO B — un operativo realmente pendiente de asignación', () {
    test('14 de 15 operativos asignados = 93.333…%, y el administrativo no lo altera', () async {
      for (var i = 0; i < 14; i++) {
        final e = await crearEmpleado(operativo: true);
        await asignarAServicio(e.id);
      }
      // Puesto operativo, sin Servicio y sin Sucursal: pertenece a la
      // plantilla operativa (por `Puesto.tipo`) pero está sin asignar.
      await crearEmpleado(operativo: true);
      await crearEmpleado(operativo: false, sucursal: sucursalId);

      final plantilla = await obtenerPlantilla.ejecutar();

      expect(plantilla.operativa.activos, 15);
      expect(plantilla.operativa.asignados, 14);
      expect(plantilla.operativa.sinAsignar, 1);
      expect(plantilla.operativa.porcentajeAsignados, closeTo(93.33333333, 0.0000001));
      expect(plantilla.administrativa.activos, 1);
      expect(plantilla.sinAsignacion, hasLength(1));
      expect(plantilla.sinAsignacion.single.plantilla, PlantillaPersonal.operativa);
    });
  });

  group('CASO C — administrativo correctamente asignado', () {
    test('nunca aparece como operativo sin asignar', () async {
      final admin = await crearEmpleado(operativo: false, sucursal: sucursalId);

      final plantilla = await obtenerPlantilla.ejecutar();
      final clasificacion = plantilla.clasificaciones.single;

      expect(clasificacion.empleado.id, admin.id);
      expect(clasificacion.asignacion, AsignacionEstructural.sucursal);
      expect(clasificacion.plantilla, PlantillaPersonal.administrativa);
      expect(clasificacion.estaAsignado, isTrue);
      expect(plantilla.operativa.activos, 0);
      expect(plantilla.sinAsignacion, isEmpty);
    });
  });

  group('CASO D — Servicio + Sucursal', () {
    test('se detecta como inconsistencia y no se cuenta en ninguna plantilla', () async {
      final e = await crearEmpleado(operativo: true, sucursal: sucursalId);
      await asignarAServicio(e.id);

      final plantilla = await obtenerPlantilla.ejecutar();

      expect(plantilla.inconsistentes, hasLength(1));
      expect(plantilla.inconsistentes.single.asignacion, AsignacionEstructural.inconsistente);
      expect(plantilla.inconsistentes.single.plantilla, isNull, reason: 'nunca se elige una prioridad arbitraria');
      expect(plantilla.operativa.activos, 0, reason: 'no se cuenta silenciosamente en uno de los dos grupos');
      expect(plantilla.administrativa.activos, 0);
      expect(plantilla.totalActivos, 1, reason: 'sigue existiendo, no se oculta');
    });
  });

  group('CASO E — rotación', () {
    test('inicio 15, 2 bajas, 1 alta, cierre 14 → 13.793103…%', () async {
      final inicio = DateTime(2026, 8, 1);
      final fin = DateTime(2026, 8, 31);

      // 13 operativos que atraviesan el mes completo.
      for (var i = 0; i < 13; i++) {
        final e = await crearEmpleado(operativo: true, fechaIngreso: DateTime(2026, 5, 1));
        await asignarAServicio(e.id, inicio: DateTime(2026, 5, 1));
      }
      // 2 que estaban al inicio y causan baja dentro del mes.
      for (var i = 0; i < 2; i++) {
        final e = await crearEmpleado(
          operativo: true,
          fechaIngreso: DateTime(2026, 5, 1),
          fechaBaja: DateTime(2026, 8, 10),
          estatus: 'baja',
        );
        await asignarAServicio(e.id, inicio: DateTime(2026, 5, 1), termino: DateTime(2026, 8, 10));
      }
      // 1 alta dentro del mes.
      final alta = await crearEmpleado(operativo: true, fechaIngreso: DateTime(2026, 8, 15));
      await asignarAServicio(alta.id, inicio: DateTime(2026, 8, 15));

      final rotacion = await obtenerRotacion.ejecutarOperativa(rangoInicio: inicio, rangoFin: fin);

      expect(rotacion.activosInicio, 15);
      expect(rotacion.activosCierre, 14);
      expect(rotacion.bajas, 2);
      expect(rotacion.altas, 1);
      expect(rotacion.plantillaPromedio, 14.5);
      expect(rotacion.porcentaje, closeTo(13.793103448275861, 0.000000001));
      expect(rotacion.porcentaje!.toStringAsFixed(1), '13.8', reason: 'la UI redondea, el cálculo no');
    });

    test('un administrativo que causa baja NO entra en la rotación operativa', () async {
      final inicio = DateTime(2026, 8, 1);
      final fin = DateTime(2026, 8, 31);

      final operativo = await crearEmpleado(operativo: true, fechaIngreso: DateTime(2026, 5, 1));
      await asignarAServicio(operativo.id, inicio: DateTime(2026, 5, 1));
      // Administrativo dado de baja en el mismo mes: nunca tuvo
      // Servicio, así que no es señal operativa.
      await crearEmpleado(
        operativo: false,
        sucursal: sucursalId,
        fechaIngreso: DateTime(2026, 5, 1),
        fechaBaja: DateTime(2026, 8, 10),
        estatus: 'baja',
      );

      final rotacion = await obtenerRotacion.ejecutarOperativa(rangoInicio: inicio, rangoFin: fin);

      expect(rotacion.bajas, 0, reason: 'la baja administrativa no mezcla con la señal operativa');
      expect(rotacion.porcentaje, 0);
    });

    test('la rotación histórica NO usa el estado de hoy: un periodo ya cerrado se reconstruye', () async {
      // Alguien que entró y salió en junio: HOY no está activo, pero
      // junio debe verlo.
      final e = await crearEmpleado(
        operativo: true,
        fechaIngreso: DateTime(2026, 6, 1),
        fechaBaja: DateTime(2026, 6, 20),
        estatus: 'baja',
      );
      await asignarAServicio(e.id, inicio: DateTime(2026, 6, 1), termino: DateTime(2026, 6, 20));

      final junio = await obtenerRotacion.ejecutarOperativa(
        rangoInicio: DateTime(2026, 6, 1),
        rangoFin: DateTime(2026, 6, 30),
      );
      expect(junio.altas, 1);
      expect(junio.bajas, 1);

      final agosto = await obtenerRotacion.ejecutarOperativa(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      );
      expect(agosto.altas, 0, reason: 'agosto no hereda los eventos de junio');
      expect(agosto.bajas, 0);
    });
  });

  group('CASO F — reingreso', () {
    test('la antigüedad parte del reingreso, pero los eventos históricos siguen contando en su mes', () async {
      // Ciclo cerrado: 1 ene → 15 mar. Ciclo vigente: 1 jun.
      final e = await crearEmpleado(operativo: true, fechaIngreso: DateTime(2026, 6, 1));
      await db.into(db.empleadoPeriodoLaboral).insert(
            EmpleadoPeriodoLaboralCompanion.insert(
              empleadoId: e.id,
              fechaIngreso: DateTime(2026, 1, 1),
              fechaBaja: DateTime(2026, 3, 15),
              motivoBaja: 'renuncia',
            ),
          );
      await asignarAServicio(e.id, inicio: DateTime(2026, 1, 1), termino: DateTime(2026, 3, 15));
      await asignarAServicio(e.id, inicio: DateTime(2026, 6, 1));

      // La antigüedad vigente arranca en el reingreso: nunca acumula.
      final plantilla = await obtenerPlantilla.ejecutar();
      expect(plantilla.clasificaciones.single.empleado.fechaIngreso, DateTime(2026, 6, 1));

      // Marzo ve la baja del ciclo anterior…
      final marzo = await obtenerRotacion.ejecutarOperativa(
        rangoInicio: DateTime(2026, 3, 1),
        rangoFin: DateTime(2026, 3, 31),
      );
      expect(marzo.bajas, 1);
      expect(marzo.altas, 0);

      // …y junio ve el reingreso como alta de un ciclo nuevo.
      final junio = await obtenerRotacion.ejecutarOperativa(
        rangoInicio: DateTime(2026, 6, 1),
        rangoFin: DateTime(2026, 6, 30),
      );
      expect(junio.altas, 1);
      expect(junio.reingresos, 1, reason: 'se distingue de una contratación nueva, sin fusionar ciclos');
      expect(junio.bajas, 0);

      // El ciclo histórico sigue existiendo, no se borró ni se fusionó.
      final archivados = await empleadoRepo.listarPeriodosLaboralesArchivados(e.id);
      expect(archivados, hasLength(1));
      expect(archivados.single.fechaIngreso, DateTime(2026, 1, 1));
    });
  });

  group('CASO G — mover un administrativo entre Sucursales', () {
    test('nunca toca la cobertura ni el porcentaje operativo', () async {
      for (var i = 0; i < 3; i++) {
        final e = await crearEmpleado(operativo: true);
        await asignarAServicio(e.id);
      }
      final admin = await crearEmpleado(operativo: false, sucursal: sucursalId);

      final antes = await obtenerPlantilla.ejecutar();

      await (db.update(db.empleado)..where((t) => t.id.equals(admin.id)))
          .write(EmpleadoCompanion(sucursalId: Value(otraSucursalId)));

      final despues = await obtenerPlantilla.ejecutar();

      expect(despues.operativa.activos, antes.operativa.activos);
      expect(despues.operativa.asignados, antes.operativa.asignados);
      expect(despues.operativa.porcentajeAsignados, 100);
      expect(despues.administrativa.activos, 1);
      expect(despues.administrativa.asignados, 1, reason: 'sigue asignado, solo cambió de sucursal');
    });
  });

  group('CASO H — mover un operativo entre Servicios', () {
    test('sigue siendo operativo durante la transición, sin baja/alta laboral artificial', () async {
      final e = await crearEmpleado(operativo: true, fechaIngreso: DateTime(2026, 1, 1));
      await asignarAServicio(e.id, inicio: DateTime(2026, 1, 1), termino: DateTime(2026, 8, 10));
      await asignarAServicio(e.id, servicio: otroServicioId, inicio: DateTime(2026, 8, 10));

      final plantilla = await obtenerPlantilla.ejecutar();
      expect(plantilla.operativa.activos, 1);
      expect(plantilla.operativa.asignados, 1);
      expect(plantilla.operativa.porcentajeAsignados, 100);
      expect(plantilla.clasificaciones.single.servicioId, otroServicioId);

      // El cambio de Servicio NO es un evento laboral: ni alta ni baja.
      final agosto = await obtenerRotacion.ejecutarOperativa(
        rangoInicio: DateTime(2026, 8, 1),
        rangoFin: DateTime(2026, 8, 31),
      );
      expect(agosto.altas, 0, reason: 'nunca terminó su relación laboral');
      expect(agosto.bajas, 0);
      expect(agosto.activosInicio, 1);
      expect(agosto.activosCierre, 1);
    });
  });

  group('Sin plantilla conocida', () {
    test('sin destino y sin puesto capturado no se inventa una plantilla', () async {
      numero++;
      await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: numero,
              nombres: 'Sin',
              apellidoPaterno: 'Puesto',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900199HDFXX9',
              rfc: 'PEXJ900199',
              nss: '10000009999',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 1,
            ),
          );

      final plantilla = await obtenerPlantilla.ejecutar();

      expect(plantilla.sinPlantillaConocida, hasLength(1));
      expect(plantilla.operativa.activos, 0);
      expect(plantilla.administrativa.activos, 0);
      expect(plantilla.sinAsignacion, hasLength(1));
    });
  });
}
