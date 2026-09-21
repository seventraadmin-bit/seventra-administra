// Etapa 1 (rediseño del catálogo de permisos) — el antiguo
// `personal.gestionarDescuentos` cubría lectura y escritura a la vez;
// al dividirse en `descuentos.crear`/`corregir`/`cancelar` (más el
// nuevo `descuentos.ver`, exclusivo de lectura) se abrió el mismo
// hueco de visibilidad que tenía Nómina antes de su corrección (ver
// `personal_shell_nomina_permisos_test.dart` y el doc comment de
// `NominasController.tieneNomina`): un usuario con `personal.ver` pero
// sin `descuentos.ver` podía seguir viendo los datos reales de
// Descuentos porque `DescuentosPersonalController._cargar()` los
// cargaba sin volver a preguntar. Esta prueba ejercita la barrera real
// (el controller, nunca solo la pestaña) directo sobre
// `ProviderContainer` — mismo criterio que
// `tiempos_extra_controller_invalidacion_test.dart`, sin necesidad de
// montar ningún widget.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuentos_personal_controller.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// `personal.ver` sin `descuentos.ver` — puede entrar a Personal, pero
/// no debe ver ningún Descuento real (mismo caso pedido que
/// `_SesionPersonalSinNominaDePrueba`).
class _SesionPersonalSinDescuentosDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-sin-descuentos',
      nombre: 'RRHH sin descuentos',
      nombreUsuario: 'rrhh-sin-descuentos',
      esMaestro: false,
      permisos: {'personal.ver'},
    );
  }
}

class _SesionPersonalConDescuentosVerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-con-descuentos',
      nombre: 'RRHH con descuentos',
      nombreUsuario: 'rrhh-con-descuentos',
      esMaestro: false,
      permisos: {'personal.ver', 'descuentos.ver'},
    );
  }
}

/// Sondeo acotado (nunca `pumpAndSettle` — esto no es un widget test):
/// si la carga nunca sale de `cargando`, el `expect` posterior falla
/// por VALOR (timeout de la propia prueba), nunca en falso positivo.
Future<void> _esperarHasta(bool Function() condicion, {int intentos = 100}) async {
  for (var i = 0; i < intentos && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late String descuentoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final descuentoRepo = DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db));
    final registrar = RegistrarDescuentoProgramadoUseCase(
      descuentoRepo,
      empleadoRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
    );

    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );

    final resultado = await registrar.ejecutar(
      empleadoId: empleado.id,
      tipo: 'prestamo',
      fechaRegistro: DateTime(2026, 1, 1),
      importeOriginal: 60000,
      numeroCuotas: 2,
      fechaPrimeraCuota: DateTime(2026, 2, 5),
    ) as RegistrarDescuentoProgramadoExitoso;
    descuentoId = resultado.descuento.id;
  });

  tearDown(() => db.close());

  test('personal.ver sin descuentos.ver: el controller no expone el Descuento real (ni en el listado ni por id)', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionPersonalSinDescuentosDePrueba.new),
      ],
    );
    addTearDown(container.dispose);

    container.listen(descuentosPersonalControllerProvider, (_, __) {}, fireImmediately: true);
    await _esperarHasta(() => container.read(descuentosPersonalControllerProvider).cargando == false);

    expect(
      container.read(descuentosPersonalControllerProvider).descuentos,
      isEmpty,
      reason: 'sin descuentos.ver, el listado nunca debe traer el préstamo real sembrado en setUp',
    );

    final porId = await container.read(descuentosPersonalControllerProvider.notifier).obtenerPorId(descuentoId);
    expect(porId, isNull, reason: 'sin descuentos.ver, obtenerPorId tampoco debe exponer el registro real por su id');
  });

  test('personal.ver + descuentos.ver: el controller sí expone el Descuento real', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionPersonalConDescuentosVerDePrueba.new),
      ],
    );
    addTearDown(container.dispose);

    container.listen(descuentosPersonalControllerProvider, (_, __) {}, fireImmediately: true);
    await _esperarHasta(() => container.read(descuentosPersonalControllerProvider).cargando == false);

    expect(container.read(descuentosPersonalControllerProvider).descuentos, hasLength(1));
    expect(container.read(descuentosPersonalControllerProvider).descuentos.single.descuento.id, descuentoId);

    final porId = await container.read(descuentosPersonalControllerProvider.notifier).obtenerPorId(descuentoId);
    expect(porId, isNotNull);
    expect(porId!.id, descuentoId);
  });
}
