// Reactividad de la eliminación física de un Tiempo Extra (bug real
// reportado: se borraba RAÚL y el renglón seguía en la tabla hasta
// cambiar de pestaña y volver).
//
// La causa era que `eliminar_tiempo_extra_fisicamente_dialog.dart`
// llamaba a `eliminarTiempoExtraFisicamenteAutorizadoProvider` DIRECTO,
// saltándose `TiemposExtraController.eliminarFisicamente` — que es
// quien recarga el listado e invalida a Finanzas. Persistía bien y no
// refrescaba nada; cambiar de pestaña destruía el provider autoDispose
// y lo reconstruía, escondiendo el defecto.
//
// Por eso esta prueba ejercita el DIÁLOGO, no el controlador: llamar al
// controlador directamente pasaría igual con el bug presente. El
// contenedor se mantiene vivo y NUNCA se navega ni se invalida a mano —
// navegar no es refrescar.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/eliminar_tiempo_extra_fisicamente_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/presentation/tiempos_extra_controller.dart';
import 'package:riseg_one/features/tiempos_extra/presentation/widgets/eliminar_tiempo_extra_fisicamente_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String tiempoExtraId;
  late String servicioId;
  late String empleadoAusenteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'usuario-maestro',
            passwordHash: 'x',
          ),
        );
    // Etapa 3B: la fila existe pero nace sin `esMaestro`, y la
    // autorización se revalida contra la base — sin esto el propio
    // `setUp` no podría ejecutar sus operaciones autorizadas.
    await sembrarSesionEnBase(db, const SesionUsuario(usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}));

    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);

    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
    );
    final servicioCreado = await CrearServicioUseCase(
      servicioRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      ServicioValidator(clienteRepo, catalogoRepo),
    ).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Raul',
            apellidoPaterno: 'Ausente',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ90010101',
            nss: '10000000001',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );

    empleadoAusenteId = empleado.id;

    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
    ]);

    final registrado = await container.read(tiemposExtraControllerProvider.notifier).registrar(
          fecha: DateTime(2026, 9, 3),
          servicioId: servicioId,
          origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
          empleadoAusenteId: empleadoAusenteId,
          motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
          nombreExternoCubre: 'Pedro Externo',
          turnoId: SeedIds.modalidadTurno24x24,
          montoTiempoExtra: 162000,
          formaPago: 'efectivo',
        );
    tiempoExtraId = (registrado as RegistrarTiempoExtraExitoso).tiempoExtra.id;

    // Sólo un Tiempo Extra cancelado es elegible para eliminación física.
    await container.read(tiemposExtraControllerProvider.notifier).cancelar(
      tiempoExtraId: tiempoExtraId,
      motivo: 'Cobertura que nunca ocurrió',
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// Pantalla mínima que consume el MISMO provider que el listado real:
  /// renglones y los tres KPIs salen de `state`, nunca de una copia
  /// local. Se queda montada de principio a fin.
  Widget pantallaQueObserva() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(tiemposExtraControllerProvider);
            return Scaffold(
              body: Column(
                children: [
                  Text('renglones=${state.registros.length}'),
                  Text('kpiRegistros=${state.resumen.totalRegistros}'),
                  Text('kpiGasto=${state.resumen.gastoTotal}'),
                  Text('kpiServicios=${state.resumen.porServicio.length}'),
                  ElevatedButton(
                    onPressed: () => mostrarDialogoEliminarTiempoExtraFisicamente(context, ref, tiempoExtraId),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  testWidgets(
    'eliminar físicamente desde el diálogo saca el renglón de la vista sin navegar ni invalidar a mano',
    (tester) async {
      await tester.pumpWidget(pantallaQueObserva());
      await tester.pumpAndSettle();

      expect(find.text('renglones=1'), findsOneWidget, reason: 'el cancelado sigue listado');
      // Ya esta cancelado, y los KPIs miden gasto REAL: no lo cuentan.
      expect(find.text('kpiRegistros=0'), findsOneWidget);
      expect(find.text('kpiGasto=0'), findsOneWidget);

      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      // Motivo obligatorio: sin él el diálogo se queda abierto.
      await tester.tap(find.byType(DropdownButtonFormField<MotivoEliminacionFisicaTiempoExtra>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registro de prueba').last);
      await tester.pumpAndSettle();

      // SQLite no avanza dentro de la zona fake-async de testWidgets:
      // el estado inicial solo estaba cargado porque setUp corrio fuera
      // de ella. runAsync deja correr el event loop real para que el
      // borrado y el _cargar() posterior ocurran de verdad.
      await tester.runAsync(() async {
        await tester.tap(find.text('Eliminar definitivamente'));
        for (var i = 0; i < 200 && container.read(tiemposExtraControllerProvider).registros.isNotEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      // No se consulta la base aqui: un await a una Future real dentro
      // del cuerpo de testWidgets cuelga la zona fake-async. No hace
      // falta — el controlador relee de SQLite en cada _cargar(), asi
      // que ver 0 renglones ya prueba que la fila se borro de verdad.

      // El renglon desaparece de la pantalla, que nunca se desmonto ni se
      // reconstruyo por navegacion. Si el dialogo vuelve a llamar al
      // provider autorizado directo, esto falla con el valor viejo.
      expect(find.text('renglones=0'), findsOneWidget);
      // Los KPIs ya estaban en cero y siguen en cero: borrar un registro
      // cancelado no puede mover el gasto real. Se afirma para que un
      // doble descuento futuro se note aqui.
      expect(find.text('kpiRegistros=0'), findsOneWidget);
      expect(find.text('kpiGasto=0'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelar bajo el filtro Registrado saca el renglón de la vista filtrada sin navegar',
    (tester) async {
      // El Tiempo Extra de setUp ya está cancelado; este segundo nace
      // registrado para poder cancelarlo con un filtro puesto. Toda la
      // preparación va en runAsync porque toca SQLite.
      late String registradoId;
      await tester.runAsync(() async {
        final r = await container.read(tiemposExtraControllerProvider.notifier).registrar(
          fecha: DateTime(2026, 9, 4),
          servicioId: servicioId,
          origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
          empleadoAusenteId: empleadoAusenteId,
          motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
          nombreExternoCubre: 'Pedro Externo',
          turnoId: SeedIds.modalidadTurno24x24,
          montoTiempoExtra: 100000,
          formaPago: 'efectivo',
        );
        registradoId = (r as RegistrarTiempoExtraExitoso).tiempoExtra.id;
      });

      await tester.pumpWidget(pantallaQueObserva());
      await tester.pump();
      expect(find.text('renglones=2'), findsOneWidget, reason: 'uno cancelado y uno registrado');
      expect(find.text('kpiRegistros=1'), findsOneWidget, reason: 'solo el registrado cuenta');
      expect(find.text('kpiGasto=100000'), findsOneWidget);

      await tester.runAsync(
        () => container.read(tiemposExtraControllerProvider.notifier).aplicarFiltros(estatus: 'registrado'),
      );
      await tester.pump();
      expect(find.text('renglones=1'), findsOneWidget, reason: 'el filtro deja solo el registrado');
      // Los KPIs son del rango, no del filtro: filtrar no los mueve.
      expect(find.text('kpiRegistros=1'), findsOneWidget);

      await tester.runAsync(
        () => container.read(tiemposExtraControllerProvider.notifier).cancelar(
              tiempoExtraId: registradoId,
              motivo: 'La cobertura no ocurrió',
            ),
      );
      await tester.pump();

      // El filtro se reevalúa contra el estatus NUEVO: cancelarlo lo saca
      // de la vista al instante, sin cambiar de pestaña.
      expect(find.text('renglones=0'), findsOneWidget);

      // Y los KPIs bajan en el mismo fotograma: cancelar revierte el
      // gasto, asi que ya no queda nada que contar en el rango.
      expect(find.text('kpiRegistros=0'), findsOneWidget);
      expect(find.text('kpiGasto=0'), findsOneWidget);
    },
  );
}
