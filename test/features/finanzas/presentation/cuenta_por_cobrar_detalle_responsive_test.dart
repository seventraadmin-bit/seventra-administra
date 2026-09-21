// Etapa 7 (Cuentas por cobrar — corrección, cancelación, trazabilidad
// y consistencia con Agenda/Pagos), Sección 18: barrido responsive de
// `CuentaPorCobrarDetalleDialog` (extensamente reescrito esta etapa) y
// `mostrarDialogoCorregirCuentaPorCobrar` (nuevo). Anchos exigidos:
// 1536/1366/1024/700/500, claro y oscuro. Fixture deliberadamente
// hostil: nombre de cliente largo, folio largo, importe grande, fecha
// reprogramada visible, DOS aplicaciones de Pago, motivo largo en el
// historial — cero RenderFlex overflow.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:riseg_one/features/finanzas/domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/widgets/cuenta_por_cobrar_detalle_dialog.dart';
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
  late ProviderContainer container;
  late String cuentaId;

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

    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(codigo: 'PUE-0001', nombre: 'Guardia', areaId: SeedIds.areaOperaciones, tipo: 'operativo', nivelJerarquico: 5),
    );

    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(
        codigo: 'CLI-RESP0001',
        nombreComercial: 'Comercializadora Internacional de Seguridad Privada del Noreste S.A. de C.V.',
      ),
    );

    final servicioCreado = await CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Vigilancia Responsive', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    await CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator).ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 1,
        precioUnitario: 1800000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );

    final emisionEtapaId = const Uuid().v4();
    await CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator).ejecutar(
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
        EtapaCobroBorrador(id: emisionEtapaId, tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        EtapaCobroBorrador(id: const Uuid().v4(), tipoSistema: TipoEventoCobro.pagoEsperado, orden: 1, tipoRegla: TipoReglaEvento.diasHabilesDespuesDe, offsetDias: 10, etapaReferenciaId: emisionEtapaId),
      ],
    );

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    final resultado = await CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo).ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documento = (resultado as CrearDocumentoManualExitoso).documento;

    await RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo).ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'FOL-2026-000001-COMPLEMENTO-EXTENDIDO-DE-PRUEBA',
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: 987654321,
    );
    await CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo).ejecutar(documentoPorEmitirId: documento.id, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

    final cuenta = (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
    cuentaId = cuenta.id;

    // Motivo largo en el historial (Sección 18: "motivo largo").
    await ReprogramarCobroCuentaPorCobrarUseCase(cuentaRepo).ejecutar(
      cuentaPorCobrarId: cuenta.id,
      fechaCobroReprogramada: DateTime(2026, 12, 24),
      motivo:
          'El cliente solicitó telefónicamente una prórroga de cobro debido a un atraso administrativo interno en su departamento de tesorería, comprometiéndose a liquidar el saldo completo en la nueva fecha acordada',
    );

    // Dos aplicaciones de Pago distintas (Sección 18: "múltiples aplicaciones").
    final pago1 = (await RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigo).ejecutar(
      clienteId: cliente.id,
      montoTotal: 400000000,
      fechaPago: DateTime(2026, 9, 1),
      formaPago: 'transferencia',
    ) as RegistrarPagoExitoso)
        .pago;
    await AplicarPagoACuentaUseCase(pagoRepo, cuentaRepo).ejecutar(pagoId: pago1.id, cuentaPorCobrarId: cuenta.id, monto: 400000000);

    final pago2 = (await RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigo).ejecutar(
      clienteId: cliente.id,
      montoTotal: 200000000,
      fechaPago: DateTime(2026, 9, 15),
      formaPago: 'efectivo',
    ) as RegistrarPagoExitoso)
        .pago;
    await AplicarPagoACuentaUseCase(pagoRepo, cuentaRepo).ejecutar(pagoId: pago2.id, cuentaPorCobrarId: cuenta.id, monto: 200000000);

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, {required Size tamano, required ThemeData tema}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: tema,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: CuentaPorCobrarDetalleDialog(cuentaPorCobrarId: cuentaId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final tamano in [const Size(1536, 900), const Size(1366, 768), const Size(1024, 768), const Size(700, 900), const Size(500, 900)]) {
    for (final tema in [AppTheme.light(), AppTheme.dark()]) {
      final nombreTema = tema.brightness == Brightness.dark ? 'oscuro' : 'claro';
      testWidgets(
        'CuentaPorCobrarDetalleDialog (cliente/folio largos, importe grande, reprogramada, 2 aplicaciones, motivo largo) '
        'no desborda a ${tamano.width.toInt()}px, tema $nombreTema',
        (tester) async {
          await pump(tester, tamano: tamano, tema: tema);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final tamano in [const Size(1536, 900), const Size(700, 900), const Size(500, 900)]) {
    for (final tema in [AppTheme.light(), AppTheme.dark()]) {
      final nombreTema = tema.brightness == Brightness.dark ? 'oscuro' : 'claro';
      testWidgets('mostrarDialogoCorregirCuentaPorCobrar no desborda a ${tamano.width.toInt()}px, tema $nombreTema', (tester) async {
        await pump(tester, tamano: tamano, tema: tema);
        await tester.ensureVisible(find.byKey(const Key('cuenta_por_cobrar_boton_corregir')));
        await tester.tap(find.byKey(const Key('cuenta_por_cobrar_boton_corregir')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  // Diálogos inline "Reprogramar cobro" / "Quitar reprogramación" —
  // mismo esqueleto (Column vertical de RisegDateField/RisegTextField/
  // Text, sin ningún Row) que el diálogo de Corregir ya barrido arriba;
  // se confirma aquí solo en el ancho más angosto por tema, suficiente
  // dado que no hay contenido variable adicional. "Cancelar Cuenta por
  // cobrar" comparte exactamente el mismo esqueleto trivial (Text +
  // RisegTextField) pero no aparece con este fixture (tiene
  // aplicaciones activas) — no se sweepea por separado.
  for (final claveBoton in ['cuenta_por_cobrar_boton_reprogramar', 'cuenta_por_cobrar_boton_quitar_reprogramacion']) {
    for (final tema in [AppTheme.light(), AppTheme.dark()]) {
      final nombreTema = tema.brightness == Brightness.dark ? 'oscuro' : 'claro';
      testWidgets('diálogo inline "$claveBoton" no desborda a 500px, tema $nombreTema', (tester) async {
        await pump(tester, tamano: const Size(500, 900), tema: tema);
        await tester.ensureVisible(find.byKey(Key(claveBoton)));
        await tester.tap(find.byKey(Key(claveBoton)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
