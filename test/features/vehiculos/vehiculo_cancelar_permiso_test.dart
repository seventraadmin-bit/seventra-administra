// `vehiculos.cancelar` — la facultad separada de anular un
// mantenimiento (schemaVersion 80, pedido explícito de Marlon).
//
// POR QUÉ EXISTE: anular un mantenimiento es la única acción de
// Vehículos que revierte DINERO REAL — cancela el `Egreso` de una
// `CuentaFinanciera`, o libera el cargo de una TDC con un ajuste
// negativo. Quien está autorizado para capturar la operación no
// necesariamente debe poder revertirla. Mismo criterio que
// `compras.cancelar`, `tiempoExtra.cancelar` y `nomina.cancelarPago`.
//
// Lo que estas pruebas fijan es la INDEPENDENCIA de los dos códigos, en
// las dos direcciones, y que el rechazo no deja ninguna mutación
// financiera a medias — la compuerta está en la fachada autorizada, no
// en la UI: aquí se llama el provider directo, sin diálogo de por medio.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/core/permissions/plantillas_permiso.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart' show MotivoBajaVehiculo;
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/dar_de_baja_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/eliminar_vehiculo_fisicamente_usecase.dart';
import 'package:riseg_one/features/vehiculos/presentation/vehiculos_controller.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cancelar_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart';

/// Sesión con un conjunto exacto de códigos — nunca Maestro, para que
/// la única puerta sea `PermisoUsuario`.
class _SesionCon extends SesionController {
  _SesionCon(this._permisos);
  final Set<String> _permisos;

  @override
  SesionUsuario? build() => SesionUsuario(
        usuarioId: 'usuario-normal',
        nombre: 'Usuario normal',
        nombreUsuario: 'normal',
        esMaestro: false,
        permisos: _permisos,
      );
}

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-maestro',
        nombre: 'Maestro',
        nombreUsuario: 'maestro',
        esMaestro: true,
        // Un Maestro real no tiene filas de PermisoUsuario: pasa por
        // `SessionPermissionService.esMaestroActivo`.
        permisos: {},
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final id in ['usuario-normal', 'usuario-maestro']) {
      await db.into(db.usuario).insert(
            UsuarioCompanion.insert(
              id: Value(id),
              nombre: id,
              nombreUsuario: id,
              passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
              esMaestro: Value(id == 'usuario-maestro'),
            ),
          );
    }
  });

  tearDown(() => db.close());

  /// Un contenedor con la sesión indicada. Se siembra SIEMPRE con el
  /// mismo escenario: una cuenta con saldo, una TDC con límite, un
  /// vehículo, y un mantenimiento pagado desde la cuenta.
  Future<({ProviderContainer container, String cuentaId, String tarjetaId, VehiculoMantenimientoData registro})>
      escenario(SesionController Function() sesion) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(sesion),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);

    // Etapa 3B: la autorización se revalida contra la base. Se persiste
    // la sesión que ESTE escenario va a usar, leída del propio
    // contenedor — así lo sembrado y lo inyectado no pueden divergir, y
    // una prueba sin permiso sigue sin él.
    final sesionDelEscenario = container.read(sesionControllerProvider);
    if (sesionDelEscenario != null) await sembrarSesionEnBase(db, sesionDelEscenario);

    final cuenta = await container.read(cuentaFinancieraRepositoryProvider).crear(
          codigo: 'CTA-BBVA',
          nombre: 'BBVA Empresarial',
          tipo: 'banco',
          saldoInicial: 2000000,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        );
    final tarjeta = await db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(
            folio: 'DEU-KONFIO',
            nombre: 'TDC Konfío',
            tipo: TipoDeuda.tarjetaCredito.name,
            saldoActual: 0,
            tarjetaLimiteCredito: const Value(1500000),
          ),
        );
    final vehiculo = await container.read(vehiculoRepositoryProvider).crear(
          codigo: 'VEH-000001',
          marca: 'Nissan',
          modelo: 'NP300',
          tipoVehiculo: 'pickup',
        );

    // El alta se hace SIN pasar por la fachada autorizada: el escenario
    // debe existir aunque la sesión bajo prueba no pueda registrarlo.
    final alta = await container.read(registrarMantenimientoVehiculoUseCaseProvider).ejecutar(
          vehiculoId: vehiculo.id,
          fecha: DateTime(2026, 5, 10),
          tipo: TipoMantenimientoVehiculo.servicioGeneral.name,
          descripcion: 'Afinación',
          costo: 250000,
          origen: OrigenFinancieroCuenta(cuenta.id),
        );

    return (
      container: container,
      cuentaId: cuenta.id,
      tarjetaId: tarjeta.id,
      registro: (alta as RegistrarMantenimientoVehiculoExitoso).registro,
    );
  }

  group('el catálogo declara el código nuevo, y no cambió el viejo', () {
    test('vehiculos.cancelar existe y convive con vehiculos.operar', () {
      final vehiculos = modulosPermiso.firstWhere((m) => m.codigo == 'vehiculos');

      expect(vehiculos.accionesEspeciales, contains('vehiculos.cancelar'));
      expect(vehiculos.accionesEspeciales, contains('vehiculos.operar'), reason: 'el código viejo NO se retiró');
      expect(todosLosCodigosDePermiso(), contains('vehiculos.cancelar'), reason: 'aparece en el selector de permisos');
    });

    test('ninguna plantilla lo concede automáticamente', () {
      for (final plantilla in plantillasPermiso) {
        expect(
          codigosDePlantilla(plantilla.codigo),
          isNot(contains('vehiculos.cancelar')),
          reason: 'la plantilla "${plantilla.codigo}" no debe otorgar una facultad que revierte dinero real',
        );
      }
    });

    test('Operaciones conserva vehiculos.operar — la separación no le quitó nada más', () {
      final operaciones = codigosDePlantilla('operaciones');

      expect(operaciones, contains('vehiculos.operar'));
      expect(operaciones, contains('vehiculos.crear'));
      expect(operaciones, contains('vehiculos.modificar'));
      expect(operaciones, contains('vehiculos.archivar'));
    });

    test('vehiculos.cancelar por sí solo no arrastra ningún otro código', () {
      // `normalizarPermisos` solo completa el `.ver` de las acciones
      // BASE; una acción especial nunca concede nada implícito.
      final normalizado = normalizarPermisos({'vehiculos.cancelar'});

      expect(normalizado, {'vehiculos.cancelar'});
      expect(normalizado, isNot(contains('vehiculos.operar')));
      expect(normalizado, isNot(contains('vehiculos.crear')));
      expect(normalizado.any((c) => c.startsWith('egresos.')), isFalse, reason: 'cero acceso a Finanzas');
      expect(normalizado.any((c) => c.startsWith('deudas.')), isFalse);
      expect(normalizado.any((c) => c.startsWith('cuentasFinancieras.')), isFalse);
    });
  });

  group('vehiculos.operar registra y corrige, pero NO anula', () {
    test('puede registrar un mantenimiento con costo', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.operar'}));

      final r = await e.container.read(registrarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoId: e.registro.vehiculoId,
        fecha: DateTime(2026, 6, 1),
        tipo: TipoMantenimientoVehiculo.llantas.name,
        descripcion: 'Llantas nuevas',
        costo: 300000,
        origen: OrigenFinancieroCuenta(e.cuentaId),
      );

      expect(r, isA<RegistrarMantenimientoVehiculoExitoso>());
    });

    test('puede corregir, conservando motivo y auditoría', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.operar'}));

      final r = await e.container.read(corregirMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: e.registro.id,
        costo: 320000,
        origen: OrigenFinancieroCuenta(e.cuentaId),
        motivo: 'La factura del taller trae otro importe',
      );

      expect(r, isA<CorregirMantenimientoVehiculoExitoso>());
      final eventos = await e.container.read(vehiculoRepositoryProvider).listarEventos(e.registro.vehiculoId);
      final correccion = eventos.singleWhere((ev) => ev.tipoEvento == 'mantenimientoCorregido');
      expect(correccion.observacion, contains('factura'), reason: 'motivo + actor + evento siguen exigiéndose');
      expect(correccion.actorUsuarioId, 'usuario-normal');
    });

    test('NO puede anular, aunque tenga todos los demás códigos de Vehículos', () async {
      final e = await escenario(
        () => _SesionCon({'vehiculos.ver', 'vehiculos.crear', 'vehiculos.modificar', 'vehiculos.archivar', 'vehiculos.operar'}),
      );

      final r = await e.container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: e.registro.id,
        motivo: 'Intento sin la facultad financiera',
      );

      expect(r, isA<CancelarMantenimientoVehiculoErrorInesperado>());
      expect((r as CancelarMantenimientoVehiculoErrorInesperado).mensaje, contains('No tiene permiso'));
    });
  });

  group('el rechazo por permisos deja CERO mutación financiera', () {
    test('ni el registro, ni el Egreso, ni el saldo de la cuenta cambian', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.operar'}));
      final cuentaRepo = e.container.read(cuentaFinancieraRepositoryProvider);
      final saldoAntes = await cuentaRepo.calcularSaldo(e.cuentaId);

      await e.container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: e.registro.id,
        motivo: 'Intento sin permiso',
      );

      final sinCambios = await e.container.read(vehiculoMantenimientoRepositoryProvider).obtenerPorId(e.registro.id);
      expect(sinCambios!.estatus, EstatusMantenimientoVehiculo.registrado.name);
      expect(sinCambios.motivoCancelacion, isNull);
      expect(sinCambios.egresoId, e.registro.egresoId, reason: 'el Egreso sigue vinculado');

      final egreso = await e.container.read(egresoRepositoryProvider).obtenerPorId(e.registro.egresoId!);
      expect(egreso!.estatus, isNot('cancelado'));
      expect(await cuentaRepo.calcularSaldo(e.cuentaId), saldoAntes, reason: 'el dinero no se movió ni un centavo');

      // Tampoco se escribió un evento de anulación en el historial.
      final eventos = await e.container.read(vehiculoRepositoryProvider).listarEventos(e.registro.vehiculoId);
      expect(eventos.where((ev) => ev.tipoEvento == 'mantenimientoCancelado'), isEmpty);
    });
  });

  group('vehiculos.cancelar anula — y no concede nada más', () {
    test('con el acceso mínimo al módulo (ver) + cancelar, la anulación procede', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.cancelar'}));

      final r = await e.container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: e.registro.id,
        motivo: 'El servicio nunca se realizó',
      );

      expect(r, isA<CancelarMantenimientoVehiculoExitoso>());
    });

    test('pero NO puede registrar ni corregir un mantenimiento', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.cancelar'}));

      final registro = await e.container.read(registrarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoId: e.registro.vehiculoId,
        fecha: DateTime(2026, 6, 1),
        tipo: TipoMantenimientoVehiculo.llantas.name,
        descripcion: 'Llantas',
        costo: 300000,
        origen: OrigenFinancieroCuenta(e.cuentaId),
      );
      expect(registro, isA<RegistrarMantenimientoVehiculoErrorInesperado>());

      final correccion = await e.container.read(corregirMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: e.registro.id,
        costo: 999999,
        origen: OrigenFinancieroCuenta(e.cuentaId),
        motivo: 'Intento de corregir sin operar',
      );
      expect(correccion, isA<CorregirMantenimientoVehiculoErrorInesperado>());

      // Y el registro quedó exactamente como estaba.
      final intacto = await e.container.read(vehiculoMantenimientoRepositoryProvider).obtenerPorId(e.registro.id);
      expect(intacto!.costo, 250000);
    });

    test('tampoco puede corregir el expediente del vehículo ni darlo de baja', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.cancelar'}));
      final controller = e.container.read(vehiculosControllerProvider.notifier);

      final correccion = await controller.corregirVehiculo(
        vehiculoId: e.registro.vehiculoId,
        placas: 'XYZ-999',
        motivo: 'Intento con la sola facultad de anular',
      );
      expect(correccion, isA<CorregirVehiculoErrorInesperado>());
      expect((correccion as CorregirVehiculoErrorInesperado).mensaje, contains('No tiene permiso'));

      final baja = await controller.darDeBaja(
        vehiculoId: e.registro.vehiculoId,
        fechaBaja: DateTime(2026, 6, 1),
        motivoBaja: MotivoBajaVehiculo.venta,
      );
      expect(baja, isA<DarDeBajaVehiculoErrorInesperado>());

      // Y las placas no cambiaron.
      final intacto = await e.container.read(vehiculoRepositoryProvider).obtenerPorId(e.registro.vehiculoId);
      expect(intacto!.placas, isNull);
      expect(intacto.fechaBaja, isNull);
    });

    test('y la eliminación física sigue siendo exclusiva del Maestro', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.cancelar'}));

      final r = await e.container.read(eliminarVehiculoFisicamenteAutorizadoProvider)(
        vehiculoId: e.registro.vehiculoId,
        motivo: 'Intento de borrado físico sin ser Maestro',
      );

      expect(r, isA<EliminarVehiculoFisicamenteErrorInesperado>());
      expect(
        (r as EliminarVehiculoFisicamenteErrorInesperado).mensaje,
        contains('Maestro'),
        reason: 'exigirMaestro no consulta ningún código de PermisoUsuario',
      );
      expect(await e.container.read(vehiculoRepositoryProvider).obtenerPorId(e.registro.vehiculoId), isNotNull);
    });
  });

  group('el Maestro conserva acceso total', () {
    test('anula sin tener una sola fila de PermisoUsuario', () async {
      final e = await escenario(_SesionMaestro.new);

      final r = await e.container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: e.registro.id,
        motivo: 'Anulación del Maestro',
      );

      expect(r, isA<CancelarMantenimientoVehiculoExitoso>());
    });
  });

  group('la anulación autorizada revierte EXACTAMENTE una vez', () {
    test('origen Cuenta: el saldo vuelve al importe exacto, y no dos veces', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.cancelar'}));
      final cuentaRepo = e.container.read(cuentaFinancieraRepositoryProvider);
      expect(await cuentaRepo.calcularSaldo(e.cuentaId), 1750000);

      await e.container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: e.registro.id,
        motivo: 'El servicio nunca se realizó',
      );
      expect(await cuentaRepo.calcularSaldo(e.cuentaId), 2000000);

      // Segunda llamada: el caso de uso la rechaza por estar ya
      // anulado — el saldo NO se acredita otra vez.
      final segunda = await e.container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: e.registro.id,
        motivo: 'Segundo intento',
      );
      expect(segunda, isA<CancelarMantenimientoVehiculoYaCancelado>());
      expect(await cuentaRepo.calcularSaldo(e.cuentaId), 2000000, reason: 'nunca una doble reversión');
    });

    test('origen TDC: el crédito se libera una sola vez', () async {
      final e = await escenario(() => _SesionCon({'vehiculos.ver', 'vehiculos.cancelar'}));
      final deudaRepo = e.container.read(deudaRepositoryProvider);

      final conTarjeta = (await e.container.read(registrarMantenimientoVehiculoUseCaseProvider).ejecutar(
            vehiculoId: e.registro.vehiculoId,
            fecha: DateTime(2026, 5, 12),
            tipo: TipoMantenimientoVehiculo.frenos.name,
            descripcion: 'Balatas',
            costo: 800000,
            origen: OrigenFinancieroTarjeta(e.tarjetaId),
          )) as RegistrarMantenimientoVehiculoExitoso;
      expect(await deudaRepo.totalCargadoEnRango(), 800000);

      await e.container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: conTarjeta.registro.id,
        motivo: 'Se cargó a la tarjeta equivocada',
      );
      expect(await deudaRepo.totalCargadoEnRango(), 0);

      final segunda = await e.container.read(cancelarMantenimientoVehiculoAutorizadoProvider)(
        vehiculoMantenimientoId: conTarjeta.registro.id,
        motivo: 'Segundo intento',
      );
      expect(segunda, isA<CancelarMantenimientoVehiculoYaCancelado>());
      expect(await deudaRepo.totalCargadoEnRango(), 0);
    });
  });
}
