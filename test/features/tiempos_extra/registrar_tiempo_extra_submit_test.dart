// Regresión REAL reportada por Marlon: con "Origen de la cobertura =
// Vacante", externo informado y todo lo financiero completo, el botón
// Registrar bloqueaba con «Selecciona quién faltó.».
//
// Causa raíz: dos prevalidaciones heredadas en `onConfirm` del diálogo
// (`empleadoAusenteId == null` y `motivoAusencia == null`) que corrían
// ANTES de mirar el discriminador. Sobrevivieron a la etapa porque
// todas las pruebas nuevas entraban por el caso de uso, nunca por el
// botón.
//
// Por eso este archivo prueba la ruta COMPLETA —UI → controller → caso
// de uso → repositorio— apretando el botón de verdad. Si la regla de
// obligatoriedad vuelve a duplicarse fuera de
// `TiempoExtraValidator.validarOrigen`, aquí se nota.

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
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/vacante_operativa_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/presentation/widgets/registrar_tiempo_extra_dialog.dart';
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
  late String servicioId;

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

    final asignacionRepo = AsignacionServicioRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionRepo);
    final clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final vacanteRepo = VacanteOperativaRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);

    final cliente =
        await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    final creado = await CrearServicioUseCase(
      servicioRepo,
      GenerarCodigoUseCase(codigoSecuencia),
      ServicioValidator(clienteRepo, catalogoRepo),
    ).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (creado as GuardarServicioExitoso).servicio.id;

    // Un empleado real, para el caso "quién cubre = Empleado".
    await db.into(db.empleado).insert(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Cubre',
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

    // Una vacante REAL, por el camino real: la línea pide 2 elementos
    // y sólo 1 está cubierto.
    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-0001',
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    final linea = await comercialRepo.crearLinea(
      servicioId: servicioId,
      datos: LineaComercialValidada(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 2,
        precioUnitario: 100000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        sueldoMensualReferenciaPersonal: 1500000,
        bonoMensualReferenciaPersonal: 0,
      ),
    );
    await vacanteRepo.sincronizarLinea(
      servicioId: servicioId,
      lineaComercialId: linea.linea.id,
      requerido: 2,
      cubierto: 1,
      fecha: DateTime(2026, 9, 1),
      motivoApertura: 'bajaEmpleado',
    );

    await db.into(db.cuentaFinanciera).insert(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-0001',
            nombre: 'BBVA Empresarial',
            tipo: TipoCuentaFinanciera.banco.name,
            saldoInicial: 1000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  // El tamaño de ventana no es lo que se prueba aquí — de eso se
  // encarga la prueba responsive del diálogo. Se usa el tamaño
  // predeterminado y se llega a cada campo por scroll, como haría una
  // persona.
  Future<void> abrirDialogo(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: RisegButton(
                  label: 'Abrir',
                  onPressed: () => mostrarDialogoRegistrarTiempoExtra(context, ref),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  /// Elige una opción de un `RisegSelect` localizado por [clave].
  Future<void> elegirEnSelect(WidgetTester tester, Key clave, String etiquetaOpcion) async {
    final selector = find.byKey(clave);
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(etiquetaOpcion).last);
    await tester.pumpAndSettle();
  }

  Future<void> escribirEn(WidgetTester tester, Key clave, String texto) async {
    final campo = find.byKey(clave);
    await tester.ensureVisible(campo);
    await tester.pumpAndSettle();
    await tester.enterText(campo, texto);
    await tester.pumpAndSettle();
  }

  Future<void> apretarRegistrar(WidgetTester tester, AppLocalizations l10n) async {
    final boton = find.widgetWithText(RisegButton, l10n.registrarTiempoExtraBotonConfirmar);
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  /// El Servicio se elige ANTES del origen: el catálogo de vacantes
  /// depende de él, igual que en el formulario real.
  Future<void> elegirServicio(WidgetTester tester) async {
    await elegirEnSelect(
      tester,
      const Key('tiempo_extra_campo_servicio'),
      'Sportium · Vigilancia Sportium',
    );
  }

  /// Turno, monto y origen financiero — lo común a todos los escenarios.
  Future<void> completarPago(WidgetTester tester) async {
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_turno'), '24×24');
    await escribirEn(tester, const Key('tiempo_extra_campo_monto'), '1500.00');
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_cuenta_origen'), 'BBVA Empresarial');
  }

  testWidgets(
    'ESCENARIO REPORTADO: Vacante + quién cubre Externo + pago y cuenta → registra, '
    'sin pedir quién faltó',
    (tester) async {
      await abrirDialogo(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await elegirServicio(tester);
      await elegirEnSelect(tester, const Key('tiempo_extra_campo_origen'), l10n.origenCoberturaVacante);
      await elegirEnSelect(tester, const Key('tiempo_extra_campo_vacante'), 'Guardia — 24×24');

      // Quién cubre: Externo.
      await tester.tap(find.byKey(const Key('tiempo_extra_cobertura_externo')));
      await tester.pumpAndSettle();
      await escribirEn(tester, const Key('tiempo_extra_campo_nombre_externo'), 'Cobertura Externa SA');

      await completarPago(tester);
      await apretarRegistrar(tester, l10n);

      expect(
        find.text(l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido),
        findsNothing,
        reason: 'en una vacante no falta nadie: pedir quién faltó era el bug',
      );
      expect(find.text(l10n.registrarTiempoExtraExito), findsOneWidget);

      final tex = (await db.select(db.tiempoExtra).get()).single;
      expect(tex.origenCobertura, OrigenCoberturaTiempoExtra.vacante.name);
      expect(tex.empleadoAusenteId, isNull);
      expect(tex.motivoAusencia, isNull);
      expect(tex.vacanteOperativaId, isNotNull);
      expect(tex.nombreExternoCubre, 'Cobertura Externa SA');
      expect(tex.montoTiempoExtra, 150000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Vacante + quién cubre Empleado interno → registra, sin empleado ausente', (tester) async {
    await abrirDialogo(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await elegirServicio(tester);
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_origen'), l10n.origenCoberturaVacante);
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_vacante'), 'Guardia — 24×24');
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_empleado_cubre'), 'Juan Cubre');

    await completarPago(tester);
    await apretarRegistrar(tester, l10n);

    expect(find.text(l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido), findsNothing);
    expect(find.text(l10n.registrarTiempoExtraExito), findsOneWidget);

    final tex = (await db.select(db.tiempoExtra).get()).single;
    expect(tex.origenCobertura, OrigenCoberturaTiempoExtra.vacante.name);
    expect(tex.empleadoAusenteId, isNull);
    expect(tex.empleadoCubreId, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Otro + descripción → registra, sin empleado ausente', (tester) async {
    await abrirDialogo(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await elegirServicio(tester);
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_origen'), l10n.origenCoberturaOtro);
    await escribirEn(tester, const Key('tiempo_extra_campo_descripcion_origen'), 'Reforzamiento por evento masivo');
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_empleado_cubre'), 'Juan Cubre');

    await completarPago(tester);
    await apretarRegistrar(tester, l10n);

    expect(find.text(l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido), findsNothing);
    expect(find.text(l10n.registrarTiempoExtraExito), findsOneWidget);

    final tex = (await db.select(db.tiempoExtra).get()).single;
    expect(tex.origenCobertura, OrigenCoberturaTiempoExtra.otro.name);
    expect(tex.empleadoAusenteId, isNull);
    expect(tex.descripcionOrigen, 'Reforzamiento por evento masivo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vacante SIN vacante elegida → pide la vacante, nunca quién faltó', (tester) async {
    await abrirDialogo(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await elegirServicio(tester);
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_origen'), l10n.origenCoberturaVacante);
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_empleado_cubre'), 'Juan Cubre');

    await completarPago(tester);
    await apretarRegistrar(tester, l10n);

    expect(find.text(l10n.registrarTiempoExtraErrorVacanteRequerida), findsOneWidget);
    expect(find.text(l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido), findsNothing);
    expect(await db.select(db.tiempoExtra).get(), isEmpty);
  });

  testWidgets('Otro SIN descripción → pide la descripción, nunca quién faltó', (tester) async {
    await abrirDialogo(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await elegirServicio(tester);
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_origen'), l10n.origenCoberturaOtro);
    await elegirEnSelect(tester, const Key('tiempo_extra_campo_empleado_cubre'), 'Juan Cubre');

    await completarPago(tester);
    await apretarRegistrar(tester, l10n);

    expect(find.text(l10n.registrarTiempoExtraErrorDescripcionOrigenRequerida), findsOneWidget);
    expect(find.text(l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido), findsNothing);
    expect(await db.select(db.tiempoExtra).get(), isEmpty);
  });

  testWidgets(
    'Ausencia de empleado SIN empleado ausente → SÍ pide quién faltó (el mensaje sigue vivo donde toca)',
    (tester) async {
      await abrirDialogo(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      // El origen por defecto ya es Ausencia de empleado.
      await elegirServicio(tester);
      await elegirEnSelect(tester, const Key('tiempo_extra_campo_empleado_cubre'), 'Juan Cubre');
      await completarPago(tester);
      await apretarRegistrar(tester, l10n);

      expect(find.text(l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido), findsOneWidget);
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    },
  );

  testWidgets(
    'Ausencia CON empleado ausente pero SIN motivo → pide el motivo, no "quién faltó"',
    (tester) async {
      await abrirDialogo(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await elegirServicio(tester);
      await elegirEnSelect(tester, const Key('tiempo_extra_campo_empleado_ausente'), 'Juan Cubre');
      // Quién cubre: externo, para no chocar con "el mismo empleado".
      await tester.tap(find.byKey(const Key('tiempo_extra_cobertura_externo')));
      await tester.pumpAndSettle();
      await escribirEn(tester, const Key('tiempo_extra_campo_nombre_externo'), 'Cobertura Externa SA');

      await completarPago(tester);
      await apretarRegistrar(tester, l10n);

      expect(
        find.text(l10n.registrarTiempoExtraErrorMotivoAusenciaRequerido),
        findsOneWidget,
        reason: 'empleado y motivo son campos distintos: cada uno con su mensaje',
      );
      expect(find.text(l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido), findsNothing);
      expect(await db.select(db.tiempoExtra).get(), isEmpty);
    },
  );
}
