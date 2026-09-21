// Etapa 7 (Cuentas por cobrar — corrección, cancelación, trazabilidad
// y consistencia con Agenda/Pagos), Sección 12: navegación por ID real
// en ambos sentidos. "Ver Documento" (CxC→Agenda, llave l10n antes
// huérfana), "Ver Pago" (CxC→Pagos, ya existía) y "Ver Cuenta por
// cobrar" (Pagos→CxC, nuevo botón por aplicación) — cada uno abre el
// diálogo real con el id correcto, nunca una ruta aparte.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/aplicar_pago_a_cuenta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/widgets/cuenta_por_cobrar_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/widgets/pago_detalle_dialog.dart';
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
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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
  late String puestoId;
  late String cuentaId;
  late String folioDocumento;
  late String folioPago;

  Future<void> crearFixture() async {
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    final documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);
    final pagoRepo = PagoRepositoryImpl(db);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    const reglaValidator = ConfiguracionCobroEtapaValidator();

    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    final crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    final crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator);
    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    final crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo);
    final registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    final cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-NAV0001', nombreComercial: 'Cliente Navegación'));

    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Vigilancia Navegación', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    await crearLineaComercial.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puestoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 1,
        precioUnitario: 1800000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );

    final emisionEtapaId = const Uuid().v4();
    await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.noAplica,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
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

    final resultado = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documento = (resultado as CrearDocumentoManualExitoso).documento;

    folioDocumento = 'FOL-NAV-0001';
    await registrarEmision.ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: folioDocumento,
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: 500000,
    );
    await cambiarEstatus.ejecutar(documentoPorEmitirId: documento.id, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

    final cuenta = (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
    cuentaId = cuenta.id;

    final registrado = await RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigo).ejecutar(
      clienteId: cliente.id,
      montoTotal: 500000,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
    );
    final pago = (registrado as RegistrarPagoExitoso).pago;
    folioPago = pago.folioPago;
    await AplicarPagoACuentaUseCase(pagoRepo, cuentaRepo).ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 500000);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    final puestoRepo = PuestoRepositoryImpl(db);
    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(codigo: 'PUE-0001', nombre: 'Guardia', areaId: SeedIds.areaOperaciones, tipo: 'operativo', nivelJerarquico: 5),
    );
    puestoId = puesto.id;
    await crearFixture();
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
          attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(context: context, builder: (_) => CuentaPorCobrarDetalleDialog(cuentaPorCobrarId: cuentaId)),
                child: const Text('Abrir CxC'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir CxC'));
    await tester.pumpAndSettle();
  }

  testWidgets('"Ver Documento" abre el Documento por emitir real de origen (CxC→Agenda)', (tester) async {
    await pump(tester);
    expect(find.byType(CuentaPorCobrarDetalleDialog), findsOneWidget);
    expect(find.text('Cliente Navegación'), findsWidgets, reason: 'confirma que abrió la CxC correcta');

    await tester.tap(find.byKey(const Key('cuenta_por_cobrar_boton_ver_documento')));
    await tester.pumpAndSettle();

    expect(find.text(folioDocumento), findsWidgets, reason: 'el Documento abierto es el de origen real, por ID');
  });

  testWidgets('"Ver Pago" abre el Pago real de una aplicación (CxC→Pagos)', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Detalle del Pago'));
    await tester.pumpAndSettle();

    expect(find.byType(PagoDetalleDialog), findsOneWidget);
    expect(find.text(folioPago), findsWidgets, reason: 'el Pago abierto es el real de la aplicación, por ID');
  });

  testWidgets('"Ver Cuenta por cobrar" desde el Pago regresa a la misma CxC real (Pagos→CxC)', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Detalle del Pago'));
    await tester.pumpAndSettle();
    expect(find.byType(PagoDetalleDialog), findsOneWidget);

    await tester.tap(find.text('Ver Cuenta por cobrar'));
    await tester.pumpAndSettle();

    expect(find.byType(CuentaPorCobrarDetalleDialog), findsNWidgets(2), reason: 'se apila un segundo diálogo de CxC, el mismo id real');
    expect(find.text(folioDocumento), findsWidgets, reason: 'la CxC a la que regresa es la misma, no una genérica');
  });
}
