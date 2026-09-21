// Pedido explícito: "me gustaria que aqui ponga lo de complemento
// como estatus, pendiente o realizado para saber que falta por hacer"
// — la columna "Complemento" del listado de Pagos debe reflejar
// exactamente la misma regla que ya usan `PagoDetalleDialog`/
// `CuentaPorCobrarDetalleDialog` (`pagoRequiereComplemento`/
// `complementoPendiente`), nunca una segunda lógica: No aplica /
// Pendiente / Realizado.

import 'dart:io';

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
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart';
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

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('riseg_pagos_complemento_test_'));

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Arma los tres escenarios reales que la columna debe distinguir:
  /// un Pago simple sin Cuenta PPD (No aplica), un Pago que liquidó una
  /// Cuenta PPD sin Complemento todavía (Pendiente), y uno con
  /// Complemento ya registrado (Realizado). Mismos use cases/flujo que
  /// `complemento_pago_test.dart`.
  Future<void> sembrarEscenarios() async {
    db = AppDatabase(NativeDatabase.memory());
    final clienteRepo = ClienteRepositoryImpl(db);
    final generarCodigoInterno = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    final pagoRepo = PagoRepositoryImpl(db);
    final complementoRepo = ComplementoPagoRepositoryImpl(db);
    final documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);

    final crearServicio = CrearServicioUseCase(
      servicioRepo,
      generarCodigoInterno,
      ServicioValidator(clienteRepo, catalogoRepo),
    );
    final crearLineaComercial = CrearLineaComercialUseCase(
      comercialRepo,
      servicioRepo,
      LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo),
    );
    final crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo),
      const ConfiguracionCobroEtapaValidator(),
    );
    final crearManual = CrearDocumentoManualUseCase(
      documentoRepo,
      configuracionCobroRepo,
      servicioRepo,
      EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo),
      generarCodigoInterno,
    );
    final registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    final cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);
    final registrarPagoAplicado = RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, generarCodigoInterno);
    final registrarComplemento = RegistrarComplementoPagoUseCase(complementoRepo, pagoRepo);

    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(codigo: 'PUE-0001', nombre: 'Guardia', areaId: SeedIds.areaOperaciones, tipo: 'operativo', nivelJerarquico: 5),
    );

    Future<CuentaPorCobrarData> crearCuentaPpd(String nombreCliente) async {
      final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-${nombreCliente.hashCode.toUnsigned(20)}', nombreComercial: nombreCliente));
      final entidad = await entidadFiscalRepo.crear(
        EntidadFiscalCompanion.insert(
          codigo: 'ENF-${nombreCliente.hashCode.toUnsigned(20)}',
          clienteId: cliente.id,
          razonSocial: '$nombreCliente SA de CV',
          rfc: 'RFC${nombreCliente.hashCode.toUnsigned(20)}',
        ),
      );
      final servicioCreado = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(
          nombre: 'Vigilancia $nombreCliente ${DateTime.now().microsecondsSinceEpoch}',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;
      await crearLineaComercial.ejecutar(
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
      await crearConfiguracionCobro.ejecutar(
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
      final resultado = await crearManual.ejecutar(
        clienteId: cliente.id,
        servicioIds: [servicioId],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 31),
        entidadFiscalId: entidad.id,
      );
      final documento = (resultado as CrearDocumentoManualExitoso).documento;
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documento.id,
        folioDocumento: 'A-${documento.id.hashCode.toUnsigned(16)}',
        uuid: '11111111-1111-1111-1111-${nombreCliente.hashCode.toUnsigned(48).toString().padLeft(12, '0')}',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 500000,
      );
      await cambiarEstatus.ejecutar(documentoPorEmitirId: documento.id, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);
      return (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
    }

    // Escenario 1 — Pago simple sin Cuenta PPD asociada: No aplica.
    await RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigoInterno).ejecutar(
      clienteId: (await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-SIMPLE', nombreComercial: 'Cliente Simple'))).id,
      montoTotal: 100000,
      fechaPago: DateTime(2026, 1, 15),
      formaPago: 'efectivo',
    );

    // Escenario 2 — liquida una Cuenta PPD, sin Complemento aún: Pendiente.
    final cuentaPendiente = await crearCuentaPpd('Cliente Pendiente');
    await registrarPagoAplicado.ejecutar(
      cuentaPorCobrarId: cuentaPendiente.id,
      monto: cuentaPendiente.saldoPendiente,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
    );

    // Escenario 3 — liquida una Cuenta PPD y ya tiene Complemento
    // registrado (no cancelado): Realizado.
    final cuentaRealizada = await crearCuentaPpd('Cliente Realizado');
    final pagoResultado = await registrarPagoAplicado.ejecutar(
      cuentaPorCobrarId: cuentaRealizada.id,
      monto: cuentaRealizada.saldoPendiente,
      fechaPago: DateTime(2026, 1, 21),
      formaPago: 'transferencia',
    );
    final pagoRealizado = (pagoResultado as RegistrarPagoAplicadoExitoso).pago;
    await registrarComplemento.ejecutar(
      pagoId: pagoRealizado.id,
      uuid: '22222222-2222-2222-2222-222222222222',
      serieFiscal: 'REP',
      folioFiscal: '001',
      fechaTimbrado: DateTime(2026, 1, 22),
      montoTotal: cuentaRealizada.saldoOriginal,
    );
  }

  testWidgets('la columna Complemento distingue No aplica / Pendiente / Realizado, igual que el detalle del Pago', (tester) async {
    await sembrarEscenarios();

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
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

    expect(
      find.byWidgetPredicate((w) => w is RisegStatusBadge && w.label == l10n.pagosComplementoNoAplica),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) => w is RisegStatusBadge && w.label == l10n.pagosComplementoPendiente),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) => w is RisegStatusBadge && w.label == l10n.pagosComplementoRealizado),
      findsOneWidget,
    );
  });
}
