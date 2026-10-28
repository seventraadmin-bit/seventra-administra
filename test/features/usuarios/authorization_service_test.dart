// Pruebas de autorización real en casos de uso (Etapa 11C) — el
// mecanismo central (`AuthorizationService`) más una muestra por
// dominio que confirma que la protección vive en la capa de
// aplicación, no solo en la UI: una llamada directa al Controller
// (sin pasar por ningún diálogo/botón) también se rechaza cuando
// falta el permiso, un Maestro siempre pasa, y una operación
// compuesta (Compra → Inventario + Egreso) no exige ningún permiso
// secundario sobre los dominios que solo compone internamente.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/compras/compras_providers.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_controller.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cambiar_responsable_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/corregir_identidad_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_ajuste_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nominas_controller.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_area_resultado.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/telefonia_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/presentation/vehiculos_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import '../../support/sesion_en_base.dart';

class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;
  @override
  SesionUsuario? build() => _sesion;
}

const _mensajePermiso = 'No tiene permiso para realizar esta acción.';

Future<ProviderContainer> _container(AppDatabase db, SesionUsuario? sesion) async {
  // Etapa 3B: la autorización se revalida contra la base, así que
  // el escenario de ESTA prueba se persiste aquí — no en el `setUp`,
  // porque cada prueba declara su propio conjunto de permisos y
  // sembrar uno solo volvería positivas las pruebas negativas.
  if (sesion != null) await sembrarSesionEnBase(db, sesion);
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

SesionUsuario _sesionCon(Set<String> permisos) => SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: false,
      permisos: permisos,
    );

const _sesionMaestro = SesionUsuario(
  usuarioId: 'maestro-prueba',
  nombre: 'Maestro de prueba',
  nombreUsuario: 'maestro',
  esMaestro: true,
  permisos: {},
);

/// Filas reales de Usuario para los `usuarioId` de `_sesionCon`/
/// `_sesionMaestro` (Etapa 11D): `actorUsuarioId` ahora es una FK real
/// hacia `Usuario` en las tablas de evento que estos casos de uso
/// escriben, así que un id inventado que no exista en la base rompe la
/// restricción — antes pasaba inadvertido porque `actorUsuarioId`
/// siempre llegaba `null`.
Future<void> _sembrarUsuariosDePrueba(AppDatabase db) async {
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('usuario-prueba'),
          nombre: 'Usuario de prueba',
          nombreUsuario: 'usuario-prueba',
          passwordHash: 'x',
        ),
      );
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('maestro-prueba'),
          nombre: 'Maestro de prueba',
          nombreUsuario: 'maestro-prueba',
          passwordHash: 'x',
        ),
      );
}

void main() {
  group('AuthorizationService — mecanismo central', () {
    test('verificar() devuelve null cuando el código está en la sesión', () {
      final service = AuthorizationService(SessionPermissionService(_sesionCon({'compras.crear'})));
      expect(service.verificar('compras.crear'), isNull);
    });

    test('verificar() devuelve PermisoDenegado con el código exacto cuando falta', () {
      final service = AuthorizationService(SessionPermissionService(_sesionCon({'compras.ver'})));
      final resultado = service.verificar('compras.crear');
      expect(resultado, isA<PermisoDenegado>());
      expect((resultado as PermisoDenegado).codigo, 'compras.crear');
    });

    test('un Maestro pasa cualquier verificación, sin ninguna fila de permisos', () {
      final service = const AuthorizationService(SessionPermissionService(_sesionMaestro));
      expect(service.verificar('compras.crear'), isNull);
      expect(service.verificar('cualquier.cosa.inventada'), isNull);
    });

    test('sin sesión activa, cualquier verificación se rechaza', () {
      final service = const AuthorizationService(SessionPermissionService(null));
      expect(service.verificar('personal.ver'), isA<PermisoDenegado>());
    });
  });

  group('Compras — registrarCompra llamado directo al Controller (sin UI)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('compras.ver sin compras.crear: rechazada, ninguna Compra se crea', () async {
      final container = await _container(db, _sesionCon({'compras.ver'}));
      final resultado = await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 1, 1),
            formaPago: 'efectivo',
            partidas: const [
              PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Gasolina', cantidad: 1, costoUnitario: 10000),
            ],
          );

      expect(resultado, isA<RegistrarCompraErrorInesperado>());
      expect((resultado as RegistrarCompraErrorInesperado).mensaje, _mensajePermiso);
      expect(await container.read(compraRepositoryProvider).listar(), isEmpty);
    });

    test('compras.crear presente: se registra, sin necesitar inventario.crear '
        '(la Compra compone Inventario/Finanzas automáticamente)', () async {
      final container = await _container(db, _sesionCon({'compras.ver', 'compras.crear'}));
      final resultado = await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 1, 1),
            formaPago: 'efectivo',
            partidas: const [
              PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Gasolina', cantidad: 1, costoUnitario: 10000),
            ],
          );

      expect(resultado, isA<RegistrarCompraExitosa>());
      expect(await container.read(compraRepositoryProvider).listar(), hasLength(1));
    });

    test('un Maestro registra sin ninguna fila de PermisoUsuario', () async {
      final container = await _container(db, _sesionMaestro);
      final resultado = await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 1, 1),
            formaPago: 'efectivo',
            partidas: const [
              PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Gasolina', cantidad: 1, costoUnitario: 10000),
            ],
          );

      expect(resultado, isA<RegistrarCompraExitosa>());
    });

    test('sin ninguna sesión activa, la operación también se rechaza', () async {
      final container = await _container(db, null);
      final resultado = await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 1, 1),
            formaPago: 'efectivo',
            partidas: const [
              PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Gasolina', cantidad: 1, costoUnitario: 10000),
            ],
          );

      expect(resultado, isA<RegistrarCompraErrorInesperado>());
    });
  });

  group('Nómina — generar llamado directo al Controller (sin UI)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('nomina.ver sin nomina.crear: rechazada antes de tocar el dominio', () async {
      final container = await _container(db, _sesionCon({'nomina.ver'}));
      final resultado = await container
          .read(nominasControllerProvider.notifier)
          .generar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      expect(resultado, isA<GenerarNominaErrorInesperado>());
      expect((resultado as GenerarNominaErrorInesperado).mensaje, _mensajePermiso);
    });

    test('nomina.crear presente: la solicitud llega al dominio real (sin Empleados, '
        'devuelve el resultado de negocio, no el de permiso)', () async {
      final container = await _container(db, _sesionCon({'nomina.ver', 'nomina.crear'}));
      final resultado = await container
          .read(nominasControllerProvider.notifier)
          .generar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);

      expect(resultado, isA<GenerarNominaSinEmpleados>());
    });
  });

  group('Nómina — cerrar/actualizarRenglon, sin pasar por diálogo', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('cerrar: nomina.ver sin nomina.cerrar se rechaza', () async {
      final container = await _container(db, _sesionCon({'nomina.ver', 'nomina.crear'}));
      final resultado = await container.read(nominasControllerProvider.notifier).cerrar('nomina-inexistente');

      expect(resultado, isA<CerrarNominaErrorInesperado>());
      expect((resultado as CerrarNominaErrorInesperado).mensaje, _mensajePermiso);
    });

    test('cerrar: con nomina.cerrar llega al dominio real (nómina inexistente, '
        'no el error de permiso)', () async {
      final container = await _container(db, _sesionCon({'nomina.ver', 'nomina.cerrar'}));
      final resultado = await container.read(nominasControllerProvider.notifier).cerrar('nomina-inexistente');

      expect(resultado, isA<CerrarNominaNoExiste>());
    });

    test('actualizarRenglon: sin nomina.modificar se rechaza (movimientos y distribución comparten el mismo gate)', () async {
      final container = await _container(db, _sesionCon({'nomina.ver'}));
      final resultado = await container.read(nominasControllerProvider.notifier).actualizarRenglon(
            nominaEmpleadoId: 'renglon-inexistente',
            prestamo: 0,
            distribucionManual: (montoFiscal: 0, montoNoFiscal: 0),
          );

      expect(resultado, isA<ActualizarRenglonNominaErrorInesperado>());
    });

    test('un Maestro puede cerrar/actualizarRenglon sin filas de permiso', () async {
      final container = await _container(db, _sesionMaestro);
      final cerrar = await container.read(nominasControllerProvider.notifier).cerrar('nomina-inexistente');
      final actualizado = await container.read(nominasControllerProvider.notifier).actualizarRenglon(
            nominaEmpleadoId: 'renglon-inexistente',
            prestamo: 0,
            distribucionManual: (montoFiscal: 0, montoNoFiscal: 0),
          );

      // Ninguno de los dos debe ser el resultado de "permiso denegado" —
      // el Maestro siempre llega al dominio real, sea cual sea el
      // resultado de negocio.
      expect(cerrar, isNot(isA<CerrarNominaErrorInesperado>()));
      expect(actualizado, isNot(isA<ActualizarRenglonNominaErrorInesperado>()));
    });
  });

  group('Personal — crearEmpleadoAutorizadoProvider llamado directo, sin montar widgets', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('personal.ver sin personal.crear: creación rechazada desde la fachada de aplicación', () async {
      final container = await _container(db, _sesionCon({'personal.ver'}));
      final resultado = await container.read(crearEmpleadoAutorizadoProvider)(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 1, 1),
        aniosExperienciaSeguridad: 0,
      );

      expect(resultado, isA<CrearEmpleadoErrorInesperado>());
      expect((resultado as CrearEmpleadoErrorInesperado).mensaje, _mensajePermiso);
    });

    test('personal.crear presente: llega al dominio real (nombres vacío, no el error de permiso)', () async {
      final container = await _container(db, _sesionCon({'personal.ver', 'personal.crear'}));
      final resultado = await container.read(crearEmpleadoAutorizadoProvider)(
        nombres: '',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 1, 1),
        aniosExperienciaSeguridad: 0,
      );

      expect(resultado, isA<CrearEmpleadoNombresRequerido>());
    });

    test('sin sesión activa, la creación se rechaza', () async {
      final container = await _container(db, null);
      final resultado = await container.read(crearEmpleadoAutorizadoProvider)(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 1, 1),
        aniosExperienciaSeguridad: 0,
      );

      expect(resultado, isA<CrearEmpleadoErrorInesperado>());
    });
  });

  group('Finanzas — registrarManual (Ingreso) llamado directo al Controller (sin UI)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('finanzas.ver sin ingresos.crear: rechazado', () async {
      final container = await _container(db, _sesionCon({'finanzas.ver'}));
      final resultado = await container.read(ingresosControllerProvider.notifier).registrarManual(
            monto: 50000,
            fecha: DateTime(2026, 1, 1),
            formaPago: 'efectivo',
            concepto: 'Ingreso de prueba',
          );

      expect(resultado, isA<RegistrarIngresoManualErrorInesperado>());
      expect((resultado as RegistrarIngresoManualErrorInesperado).mensaje, _mensajePermiso);
    });

    test('ingresos.crear presente: se registra', () async {
      final container = await _container(db, _sesionCon({'finanzas.ver', 'ingresos.crear'}));
      final resultado = await container.read(ingresosControllerProvider.notifier).registrarManual(
            monto: 50000,
            fecha: DateTime(2026, 1, 1),
            formaPago: 'efectivo',
            concepto: 'Ingreso de prueba',
          );

      expect(resultado, isA<RegistrarIngresoManualExitoso>());
    });
  });

  group('Inventario — registrarAjuste llamado directo al Controller (sin UI)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('inventario.ver sin inventario.ajustarExistencia: ajuste rechazado', () async {
      final container = await _container(db, _sesionCon({'inventario.ver'}));
      final resultado = await container.read(articulosControllerProvider.notifier).registrarAjuste(
            articuloId: 'articulo-inexistente',
            cantidad: 1,
            esEntrada: true,
            observaciones: 'Ajuste de prueba',
          );

      expect(resultado, isA<RegistrarAjusteErrorInesperado>());
      expect((resultado as RegistrarAjusteErrorInesperado).mensaje, _mensajePermiso);
    });

    test('inventario.ajustarExistencia presente: llega al dominio real (artículo inexistente, '
        'no el error de permiso)', () async {
      final container = await _container(db, _sesionCon({'inventario.ver', 'inventario.ajustarExistencia'}));
      final resultado = await container.read(articulosControllerProvider.notifier).registrarAjuste(
            articuloId: 'articulo-inexistente',
            cantidad: 1,
            esEntrada: true,
            observaciones: 'Ajuste de prueba',
          );

      expect(resultado, isA<RegistrarAjusteArticuloNoExiste>());
    });

    test('un Maestro ajusta sin ninguna fila de PermisoUsuario', () async {
      final container = await _container(db, _sesionMaestro);
      final resultado = await container.read(articulosControllerProvider.notifier).registrarAjuste(
            articuloId: 'articulo-inexistente',
            cantidad: 1,
            esEntrada: true,
            observaciones: 'Ajuste de prueba',
          );

      expect(resultado, isNot(isA<RegistrarAjusteErrorInesperado>()));
    });
  });

  group('Vehículos — corregirVehiculo llamado directo al Controller (sin UI)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('vehiculos.ver sin vehiculos.modificar: modificación rechazada', () async {
      final container = await _container(db, _sesionCon({'vehiculos.ver'}));
      final resultado = await container.read(vehiculosControllerProvider.notifier).corregirVehiculo(
            vehiculoId: 'vehiculo-inexistente',
            marca: 'Nissan',
            modelo: 'Versa',
            // schemaVersion 80: la corrección exige motivo.
            motivo: 'Prueba de autorización',
          );

      expect(resultado, isA<CorregirVehiculoErrorInesperado>());
      expect((resultado as CorregirVehiculoErrorInesperado).mensaje, _mensajePermiso);
    });

    test('vehiculos.modificar presente: llega al dominio real (vehículo inexistente, '
        'no el error de permiso)', () async {
      final container = await _container(db, _sesionCon({'vehiculos.ver', 'vehiculos.modificar'}));
      final resultado = await container.read(vehiculosControllerProvider.notifier).corregirVehiculo(
            vehiculoId: 'vehiculo-inexistente',
            marca: 'Nissan',
            modelo: 'Versa',
            // schemaVersion 80: la corrección exige motivo.
            motivo: 'Prueba de autorización',
          );

      expect(resultado, isA<CorregirVehiculoNoExiste>());
    });

    test('un Maestro corrige sin ninguna fila de PermisoUsuario', () async {
      final container = await _container(db, _sesionMaestro);
      final resultado = await container.read(vehiculosControllerProvider.notifier).corregirVehiculo(
            vehiculoId: 'vehiculo-inexistente',
            marca: 'Nissan',
            modelo: 'Versa',
            // schemaVersion 80: la corrección exige motivo.
            motivo: 'Prueba de autorización',
          );

      expect(resultado, isNot(isA<CorregirVehiculoErrorInesperado>()));
    });
  });

  group('Telefonía — recarga vía fachada autorizada, sin montar widgets', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('telefonia.ver sin telefonia.recargar: recarga rechazada', () async {
      final container = await _container(db, _sesionCon({'telefonia.ver'}));
      final resultado = await container.read(registrarRecargaLineaTelefonicaAutorizadoProvider)(
        lineaTelefonicaId: 'linea-inexistente',
        fecha: DateTime(2026, 1, 1),
        importe: 10000,
        formaPago: FormaPago.efectivo.name,
      );

      expect(resultado, isA<RegistrarRecargaLineaTelefonicaErrorInesperado>());
      expect((resultado as RegistrarRecargaLineaTelefonicaErrorInesperado).mensaje, _mensajePermiso);
    });

    test('telefonia.recargar presente: llega al dominio real (línea inexistente, '
        'no el error de permiso)', () async {
      final container = await _container(db, _sesionCon({'telefonia.ver', 'telefonia.recargar'}));
      final resultado = await container.read(registrarRecargaLineaTelefonicaAutorizadoProvider)(
        lineaTelefonicaId: 'linea-inexistente',
        fecha: DateTime(2026, 1, 1),
        importe: 10000,
        formaPago: FormaPago.efectivo.name,
      );

      expect(resultado, isA<RegistrarRecargaLineaTelefonicaLineaNoExiste>());
    });

    test('un Maestro registra recargas sin ninguna fila de PermisoUsuario', () async {
      final container = await _container(db, _sesionMaestro);
      final resultado = await container.read(registrarRecargaLineaTelefonicaAutorizadoProvider)(
        lineaTelefonicaId: 'linea-inexistente',
        fecha: DateTime(2026, 1, 1),
        importe: 10000,
        formaPago: FormaPago.efectivo.name,
      );

      expect(resultado, isNot(isA<RegistrarRecargaLineaTelefonicaErrorInesperado>()));
    });
  });

  group('Organización — crearAreaAutorizadoProvider llamado directo, sin montar widgets', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('organizacion.ver sin organizacion.crear: escritura rechazada sin UI', () async {
      final container = await _container(db, _sesionCon({'organizacion.ver'}));
      final resultado = await container.read(crearAreaAutorizadoProvider)(nombre: 'Área de prueba');

      expect(resultado, isA<GuardarAreaErrorInesperado>());
      expect((resultado as GuardarAreaErrorInesperado).mensaje, _mensajePermiso);
    });

    test('organizacion.crear presente: llega al dominio real (nombre vacío, '
        'no el error de permiso)', () async {
      final container = await _container(db, _sesionCon({'organizacion.ver', 'organizacion.crear'}));
      final resultado = await container.read(crearAreaAutorizadoProvider)(nombre: '');

      expect(resultado, isA<GuardarAreaNombreRequerido>());
    });

    test('un Maestro crea sin ninguna fila de PermisoUsuario', () async {
      final container = await _container(db, _sesionMaestro);
      final resultado = await container.read(crearAreaAutorizadoProvider)(nombre: 'Área de prueba');

      expect(resultado, isNot(isA<GuardarAreaErrorInesperado>()));
    });
  });

  group(
    'Inventario — cambiarResponsableAsignacionAutorizadoProvider llamado directo, sin montar widgets '
    '(Etapa 9D, ajuste aprobado por Marlon)',
    () {
      late AppDatabase db;

      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        await _sembrarUsuariosDePrueba(db);
      });
      tearDown(() => db.close());

      test('inventario.ver sin inventario.modificar: cambiar responsable rechazado', () async {
        final container = await _container(db, _sesionCon({'inventario.ver'}));
        final resultado = await container.read(cambiarResponsableAsignacionAutorizadoProvider)(
          asignacionId: 'asignacion-inexistente',
          nuevoEmpleadoId: 'empleado-cualquiera',
          fecha: DateTime(2026, 1, 1),
        );

        expect(resultado, isA<CambiarResponsableAsignacionErrorInesperado>());
        expect((resultado as CambiarResponsableAsignacionErrorInesperado).mensaje, _mensajePermiso);
      });

      test('inventario.corregir presente: llega al dominio real (asignación inexistente, '
          'no el error de permiso)', () async {
        final container = await _container(db, _sesionCon({'inventario.ver', 'inventario.corregir'}));
        final resultado = await container.read(cambiarResponsableAsignacionAutorizadoProvider)(
          asignacionId: 'asignacion-inexistente',
          nuevoEmpleadoId: 'empleado-cualquiera',
          fecha: DateTime(2026, 1, 1),
        );

        expect(resultado, isA<CambiarResponsableAsignacionNoExiste>());
      });

      test('un Maestro cambia responsable sin ninguna fila de PermisoUsuario', () async {
        final container = await _container(db, _sesionMaestro);
        final resultado = await container.read(cambiarResponsableAsignacionAutorizadoProvider)(
          asignacionId: 'asignacion-inexistente',
          nuevoEmpleadoId: 'empleado-cualquiera',
          fecha: DateTime(2026, 1, 1),
        );

        expect(resultado, isNot(isA<CambiarResponsableAsignacionErrorInesperado>()));
      });
    },
  );

  group(
    'Inventario — corregirIdentidadUnidadAutorizadoProvider llamado directo, sin montar widgets '
    '(Etapa 9D, tercer ajuste posterior)',
    () {
      late AppDatabase db;

      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        await _sembrarUsuariosDePrueba(db);
      });
      tearDown(() => db.close());

      test('inventario.ver sin inventario.corregir: corregir identidad rechazado', () async {
        final container = await _container(db, _sesionCon({'inventario.ver'}));
        final resultado = await container.read(corregirIdentidadUnidadAutorizadoProvider)(
          unidadId: 'unidad-inexistente',
          motivo: 'prueba',
        );

        expect(resultado, isA<CorregirIdentidadUnidadErrorInesperado>());
        expect((resultado as CorregirIdentidadUnidadErrorInesperado).mensaje, _mensajePermiso);
      });

      test('inventario.corregir presente: llega al dominio real (unidad inexistente, '
          'no el error de permiso)', () async {
        final container = await _container(db, _sesionCon({'inventario.ver', 'inventario.corregir'}));
        final resultado = await container.read(corregirIdentidadUnidadAutorizadoProvider)(
          unidadId: 'unidad-inexistente',
          motivo: 'prueba',
        );

        expect(resultado, isA<CorregirIdentidadUnidadNoExiste>());
      });

      test('un Maestro corrige identidad sin ninguna fila de PermisoUsuario', () async {
        final container = await _container(db, _sesionMaestro);
        final resultado = await container.read(corregirIdentidadUnidadAutorizadoProvider)(
          unidadId: 'unidad-inexistente',
          motivo: 'prueba',
        );

        expect(resultado, isNot(isA<CorregirIdentidadUnidadErrorInesperado>()));
      });
    },
  );

  group('Comercial — crearClienteAutorizadoProvider llamado directo, sin montar widgets', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _sembrarUsuariosDePrueba(db);
    });
    tearDown(() => db.close());

    test('comercial.ver sin clientes.crear: escritura rechazada sin UI', () async {
      final container = await _container(db, _sesionCon({'comercial.ver'}));
      final resultado = await container.read(crearClienteAutorizadoProvider)(nombreComercial: 'Cliente de prueba');

      expect(resultado.isFailure, isTrue);
      final failure = (resultado as Err).failure;
      expect(failure, isA<PermissionFailure>());
      expect(failure.message, _mensajePermiso);
    });

    test('clientes.crear presente: llega al dominio real (nombre vacío, '
        'no el error de permiso)', () async {
      final container = await _container(db, _sesionCon({'comercial.ver', 'clientes.crear'}));
      final resultado = await container.read(crearClienteAutorizadoProvider)(nombreComercial: '');

      expect(resultado.isFailure, isTrue);
      final failure = (resultado as Err).failure;
      expect(failure, isA<ValidationFailure>());
    });

    test('un Maestro crea sin ninguna fila de PermisoUsuario', () async {
      final container = await _container(db, _sesionMaestro);
      final resultado = await container.read(crearClienteAutorizadoProvider)(nombreComercial: 'Cliente de prueba');

      expect(resultado.isOk, isTrue);
    });
  });
}
