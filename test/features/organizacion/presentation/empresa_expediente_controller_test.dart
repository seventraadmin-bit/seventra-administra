import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_input.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_state.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

const _datosGeneralesValidos = EmpresaDatosGeneralesInput(nombreComercial: 'Seguridad Privada RISEG');

/// Sesión Maestro fija — Etapa 11C activó autorización real en
/// `EmpresaExpedienteController`; sin este override todas las acciones
/// serían rechazadas por `AuthorizationService` (mismo criterio que
/// `areas_list_screen_test.dart`).
class _SesionControllerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
    );
    addTearDown(container.dispose);
    // El provider es autoDispose: sin un listener persistente, cada
    // `container.read` suelto podría recrear su estado desde cero.
    container.listen(empresaExpedienteControllerProvider, (_, _) {});
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  Future<void> esperarCargaInicial() async {
    while (container.read(empresaExpedienteControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial resuelve la Empresa activa sembrada', () async {
    await esperarCargaInicial();
    final state = container.read(empresaExpedienteControllerProvider);
    expect(state.cargando, isFalse);
    expect(state.errorCarga, isNull);
    expect(state.datos?.empresa.codigo, 'RSG-01');
    expect(state.modo, EmpresaExpedienteModo.consulta);
  });

  test('entrarModoEdicion cambia a edición y limpia errores previos', () async {
    await esperarCargaInicial();
    final notifier = container.read(empresaExpedienteControllerProvider.notifier);

    notifier.entrarModoEdicion();

    final state = container.read(empresaExpedienteControllerProvider);
    expect(state.modo, EmpresaExpedienteModo.edicion);
    expect(state.tieneCambiosSinGuardar, isFalse);
  });

  test('marcarCambiosSinGuardar activa el indicador de cambios sin guardar', () async {
    await esperarCargaInicial();
    final notifier = container.read(empresaExpedienteControllerProvider.notifier);
    notifier.entrarModoEdicion();

    notifier.marcarCambiosSinGuardar();

    expect(container.read(empresaExpedienteControllerProvider).tieneCambiosSinGuardar, isTrue);
  });

  test('cancelarEdicion regresa a consulta y limpia el indicador de cambios', () async {
    await esperarCargaInicial();
    final notifier = container.read(empresaExpedienteControllerProvider.notifier);
    notifier.entrarModoEdicion();
    notifier.marcarCambiosSinGuardar();

    notifier.cancelarEdicion();

    final state = container.read(empresaExpedienteControllerProvider);
    expect(state.modo, EmpresaExpedienteModo.consulta);
    expect(state.tieneCambiosSinGuardar, isFalse);
  });

  test('guardar con datos válidos persiste y regresa a consulta', () async {
    await esperarCargaInicial();
    final notifier = container.read(empresaExpedienteControllerProvider.notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(
      const EmpresaExpedienteInput(
        datosGenerales: EmpresaDatosGeneralesInput(
          nombreComercial: 'RISEG actualizado',
          rfc: 'xaxx010101000',
        ),
      ),
    );

    expect(exito, isTrue);
    final state = container.read(empresaExpedienteControllerProvider);
    expect(state.modo, EmpresaExpedienteModo.consulta);
    expect(state.guardando, isFalse);
    // El RFC se normaliza antes de reflejarse de vuelta en el estado.
    expect(state.datos?.empresa.rfc, 'XAXX010101000');
  });

  test('guardar con RFC inválido reporta el error estructurado sin persistir', () async {
    await esperarCargaInicial();
    final notifier = container.read(empresaExpedienteControllerProvider.notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(
      const EmpresaExpedienteInput(
        datosGenerales: EmpresaDatosGeneralesInput(nombreComercial: 'RISEG', rfc: 'CORTO'),
      ),
    );

    expect(exito, isFalse);
    final state = container.read(empresaExpedienteControllerProvider);
    expect(state.modo, EmpresaExpedienteModo.edicion);
    expect(state.erroresGuardado, isNotEmpty);
  });

  test('una segunda llamada a guardar mientras la primera está en curso se ignora', () async {
    await esperarCargaInicial();
    final notifier = container.read(empresaExpedienteControllerProvider.notifier);
    notifier.entrarModoEdicion();

    final primera = notifier.guardar(const EmpresaExpedienteInput(datosGenerales: _datosGeneralesValidos));
    // Mientras la primera sigue en curso, el estado ya debe reflejar
    // `guardando = true`.
    expect(container.read(empresaExpedienteControllerProvider).guardando, isTrue);

    final segunda = await notifier.guardar(
      const EmpresaExpedienteInput(datosGenerales: _datosGeneralesValidos),
    );
    expect(segunda, isFalse);

    final resultadoPrimera = await primera;
    expect(resultadoPrimera, isTrue);
  });

  test('reintentarCarga vuelve a intentar tras un error de carga', () async {
    await esperarCargaInicial();
    final notifier = container.read(empresaExpedienteControllerProvider.notifier);

    await notifier.reintentarCarga();

    final state = container.read(empresaExpedienteControllerProvider);
    expect(state.cargando, isFalse);
    expect(state.datos, isNotNull);
  });
}
