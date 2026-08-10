import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/domain/usecases/obtener_empleados_responsables_servicio_usecase.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

/// Cubre `ObtenerEmpleadosResponsablesServicioUseCase` — el ajuste de
/// cierre de 7B que saca la lectura de Personal fuera de la UI de
/// Inventario (`InventarioAsignadoServicioSection`) y la deja detrás
/// de un caso de uso propio del dominio Inventario, mismo patrón que
/// `ObtenerExpedienteServicioUseCase` (Organización) ya usa para leer
/// Personal.
void main() {
  late AppDatabase db;
  late ObtenerEmpleadosResponsablesServicioUseCase obtenerEmpleadosResponsables;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    obtenerEmpleadosResponsables = ObtenerEmpleadosResponsablesServicioUseCase(asignacionServicioRepo, empleadoRepo);
  });

  tearDown(() => db.close());

  Future<ServicioData> crearServicioDePrueba() async {
    final tipoServicio = await db
        .into(db.tipoServicio)
        .insertReturning(TipoServicioCompanion.insert(id: 'tipo-servicio-prueba', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'));
    final cliente = await db
        .into(db.cliente)
        .insertReturning(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    return db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: tipoServicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  }

  Future<EmpleadoData> crearEmpleadoDePrueba(int numero) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0$numero',
            rfc: 'PEXJ900101AB$numero',
            nss: '1234567890$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  test('devuelve el personal actualmente asignado al Servicio, sin duplicar datos de Empleado', () async {
    final servicio = await crearServicioDePrueba();
    final empleado = await crearEmpleadoDePrueba(1);
    await db.into(db.asignacionServicio).insert(
          AsignacionServicioCompanion.insert(
            empleadoId: empleado.id,
            servicioId: servicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );

    final opciones = await obtenerEmpleadosResponsables.ejecutar(servicio.id);

    expect(opciones, hasLength(1));
    expect(opciones.single.id, empleado.id);
    expect(opciones.single.nombre, 'Juan Pérez');
  });

  test('no incluye asignaciones ya terminadas ni empleados de otro Servicio', () async {
    final servicio = await crearServicioDePrueba();
    final empleadoVigente = await crearEmpleadoDePrueba(1);
    final empleadoRetirado = await crearEmpleadoDePrueba(2);

    await db.into(db.asignacionServicio).insert(
          AsignacionServicioCompanion.insert(
            empleadoId: empleadoVigente.id,
            servicioId: servicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    await db.into(db.asignacionServicio).insert(
          AsignacionServicioCompanion.insert(
            empleadoId: empleadoRetirado.id,
            servicioId: servicio.id,
            fechaInicio: DateTime(2025, 1, 1),
            fechaTermino: Value(DateTime(2025, 12, 31)),
            motivoTermino: const Value('solicitudCliente'),
          ),
        );

    final opciones = await obtenerEmpleadosResponsables.ejecutar(servicio.id);

    expect(opciones.map((e) => e.id), [empleadoVigente.id]);
  });
}
