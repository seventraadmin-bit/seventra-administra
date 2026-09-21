// Reproducción del crash real al guardar un Complemento de pago:
//
//   'package:flutter/src/widgets/framework.dart': Failed assertion:
//   line 6179 pos 14: '_dependents.isEmpty': is not true.
//   #2 InheritedElement.debugDeactivated
//   #4 _InactiveElements._deactivateRecursively
//
// Esa aserción sólo se rompe cuando un InheritedElement se desactiva
// mientras alguien que dependía de él sigue vivo — es decir, cuando un
// subárbol se retira sin llevarse a sus dependientes.
//
// El recorrido es el de Marlon: Finanzas -> Pagos -> abrir el Pago con
// complemento pendiente -> "Registrar complemento" -> llenar -> guardar.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart';
import 'package:riseg_one/features/notificaciones/presentation/widgets/notification_bell.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// Maestro: el guardado pasa por `autorizarUseCase`, y sin sesion el
/// caso de uso nunca corre.
class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'usuario-maestro',
        nombre: 'MARLON',
        nombreUsuario: 'MARLONRH',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('riseg_complemento_crash_'));

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Un Pago que liquidó una Cuenta por cobrar CFDI/PPD y todavía no
  /// tiene Complemento: el caso exacto en el que aparece el botón.
  Future<void> sembrarPagoConComplementoPendiente() async {
    db = AppDatabase(NativeDatabase.memory());
    // El guardado sella `actorUsuarioId`: sin la fila del Usuario, la
    // insercion muere por llave foranea y el error se ve como un
    // "error inesperado" generico.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'MARLONRH',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );
    final clienteRepo = ClienteRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    final pagoRepo = PagoRepositoryImpl(db);
    final documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);

    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-0001',
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'MORGAN'),
    );
    final entidad = await entidadFiscalRepo.crear(
      EntidadFiscalCompanion.insert(
        codigo: 'ENF-000001',
        clienteId: cliente.id,
        razonSocial: 'Morgan SA de CV',
        rfc: 'MOR010101AAA',
      ),
    );
    final servicioCreado = await CrearServicioUseCase(
      servicioRepo,
      generarCodigo,
      ServicioValidator(clienteRepo, catalogoRepo),
    ).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Morgan',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    await CrearLineaComercialUseCase(
      comercialRepo,
      servicioRepo,
      LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo),
    ).ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 1,
        precioUnitario: 1800000,
        tratamientoIva: TratamientoIva.masIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );

    final emisionEtapaId = const Uuid().v4();
    await CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo),
      const ConfiguracionCobroEtapaValidator(),
    ).ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.cfdi,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.ppd,
        requiereComplemento: true,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        entidadFiscalId: entidad.id,
      ),
      etapas: [
        EtapaCobroBorrador(
          id: emisionEtapaId,
          tipoSistema: TipoEventoCobro.emision,
          orden: 0,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 1,
        ),
        EtapaCobroBorrador(
          id: const Uuid().v4(),
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 1,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDias: 10,
          etapaReferenciaId: emisionEtapaId,
        ),
      ],
    );

    final resultado = await CrearDocumentoManualUseCase(
      documentoRepo,
      configuracionCobroRepo,
      servicioRepo,
      EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo),
      generarCodigo,
    ).ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
      entidadFiscalId: entidad.id,
    );
    final documento = (resultado as CrearDocumentoManualExitoso).documento;
    await RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo).ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'A-001',
      uuid: '11111111-1111-1111-1111-111111111111',
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: 5715900,
    );
    await CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo)
        .ejecutar(documentoPorEmitirId: documento.id, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

    final cuenta = (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
    await RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, generarCodigo).ejecutar(
      cuentaPorCobrarId: cuenta.id,
      monto: cuenta.saldoPendiente,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
    );
  }

  testWidgets('guardar un Complemento no revienta el árbol de widgets', (tester) async {
    await sembrarPagoConComplementoPendiente();

    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestro.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // La campana va en el árbol porque el guardado la invalida:
          // si el fallo nace de ahí, montarla sola no bastaría.
          home: const Scaffold(
            appBar: null,
            body: Column(
              children: [
                Align(alignment: Alignment.topRight, child: NotificationBell()),
                Expanded(child: PagosListScreen()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    // Abrir el Pago.
    await tester.tap(find.textContaining('PAG-').first);
    await tester.pumpAndSettle();

    // "Registrar complemento".
    final boton = find.widgetWithText(RisegButton, l10n.pagoDetalleBotonRegistrarComplemento);
    expect(boton, findsOneWidget, reason: 'el complemento debe estar pendiente');
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();

    // Llenar el formulario.
    await tester.enterText(
      find.widgetWithText(RisegTextField, l10n.registrarComplementoCampoUuid),
      '33333333-3333-3333-3333-333333333333',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(RisegTextField, l10n.registrarComplementoCampoMontoTotal),
      '57159.00',
    );
    await tester.pumpAndSettle();

    // La fecha de timbrado pasa por el selector real.
    await tester.tap(find.widgetWithText(RisegDateField, l10n.registrarComplementoCampoFechaTimbrado));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextButton)).last);
    await tester.pumpAndSettle();

    // Guardar.
    await tester.tap(find.widgetWithText(RisegButton, l10n.registrarComplementoBotonConfirmar));
    await tester.pumpAndSettle();

    // Lo que reventaba: los controllers se liberaban mientras la ruta
    // todavia animaba la salida.
    expect(tester.takeException(), isNull, reason: 'guardar no puede tirar el árbol de widgets');
    expect(
      find.text(l10n.registrarComplementoDialogoTitulo),
      findsNothing,
      reason: 'el dialogo cierra al guardar',
    );
    expect(await db.select(db.complementoPago).get(), hasLength(1));
  });

  testWidgets('guardar sin UUID deja el dialogo abierto y muestra el error', (tester) async {
    await sembrarPagoConComplementoPendiente();

    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestro.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PagosListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    await tester.tap(find.textContaining('PAG-').first);
    await tester.pumpAndSettle();

    final boton = find.widgetWithText(RisegButton, l10n.pagoDetalleBotonRegistrarComplemento);
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();

    // Guardar con el formulario vacio.
    await tester.tap(find.widgetWithText(RisegButton, l10n.registrarComplementoBotonConfirmar));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.registrarComplementoDialogoTitulo),
      findsOneWidget,
      reason: 'un error de captura nunca cierra el formulario',
    );
    expect(find.text(l10n.registrarComplementoErrorUuidFormatoInvalido), findsWidgets);
    expect(await db.select(db.complementoPago).get(), isEmpty);
  });
}
