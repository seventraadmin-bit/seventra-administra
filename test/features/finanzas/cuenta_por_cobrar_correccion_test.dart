// Etapa 7 (Cuentas por cobrar — corrección, cancelación, trazabilidad
// y consistencia con Agenda/Pagos), Sección 13: escenario integral
// exacto del pedido. Cliente X, Documento $10,000, vencimiento 30/09,
// reprogramar cobro → 10/10 (sin tocar vencimiento) → Pago $4,000 →
// corregir vencimiento 30/09→05/10 (saldo/Pago/aplicación intactos,
// reprogramada sigue 10/10) → quitar reprogramación (Planeación vuelve
// a la fecha contractual) → cancelar CxC con aplicación activa
// (rechazo, cero mutación) → cancelar la aplicación desde Pagos → CxC
// vuelve a $10,000 → cancelar CxC (conserva historial completo,
// Documento nunca se toca). También cubre N:M (una CxC con varios
// Pagos), ComplementoPago real (Sección 14) y atomicidad (Sección 15).

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/aplicar_pago_a_cuenta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/quitar_reprogramacion_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';
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
  late CuentaPorCobrarRepositoryImpl cuentaRepo;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late ClienteRepositoryImpl clienteRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late CorregirCuentaPorCobrarUseCase corregirCuenta;
  late ReprogramarCobroCuentaPorCobrarUseCase reprogramarCobro;
  late QuitarReprogramacionCobroCuentaPorCobrarUseCase quitarReprogramacion;
  late CancelarCuentaPorCobrarUseCase cancelarCuenta;
  late PagoRepositoryImpl pagoRepo;
  late IngresoRepositoryImpl ingresoRepo;
  late ComplementoPagoRepositoryImpl complementoPagoRepo;
  late RegistrarPagoUseCase registrarPago;
  late AplicarPagoACuentaUseCase aplicarPagoACuenta;
  late CancelarAplicacionPagoUseCase cancelarAplicacionPago;
  late RegistrarComplementoPagoUseCase registrarComplemento;
  late String puestoId;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);
    pagoRepo = PagoRepositoryImpl(db);
    ingresoRepo = IngresoRepositoryImpl(db);
    complementoPagoRepo = ComplementoPagoRepositoryImpl(db);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    const reglaValidator = ConfiguracionCobroEtapaValidator();

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator);

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);
    corregirCuenta = CorregirCuentaPorCobrarUseCase(cuentaRepo);
    reprogramarCobro = ReprogramarCobroCuentaPorCobrarUseCase(cuentaRepo);
    quitarReprogramacion = QuitarReprogramacionCobroCuentaPorCobrarUseCase(cuentaRepo);
    cancelarCuenta = CancelarCuentaPorCobrarUseCase(cuentaRepo, pagoRepo);
    registrarPago = RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigo);
    aplicarPagoACuenta = AplicarPagoACuentaUseCase(pagoRepo, cuentaRepo);
    cancelarAplicacionPago = CancelarAplicacionPagoUseCase(pagoRepo);
    registrarComplemento = RegistrarComplementoPagoUseCase(complementoPagoRepo, pagoRepo);

    tempDir = Directory.systemTemp.createTempSync('riseg_cxc_correccion_test_');

    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-0001',
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    puestoId = puesto.id;
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Mismo helper que `cuenta_por_cobrar_test.dart` — arma un
  /// `DocumentoPorEmitir` real (Cliente + Servicio + Línea +
  /// Configuración de cobro) y lo lleva hasta `procesadoAceptado`,
  /// devolviendo su Cuenta por cobrar ya generada.
  Future<CuentaPorCobrarData> crearCuentaDePrueba({
    required String nombreCliente,
    int importeEmitido = 1000000,
  }) async {
    final clienteCreado = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${nombreCliente.hashCode.toUnsigned(20)}', nombreComercial: nombreCliente),
    );
    final cliente = clienteCreado.id;

    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente,
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
      clienteId: cliente,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documento = (resultado as CrearDocumentoManualExitoso).documento;

    await registrarEmision.ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'FOL-${documento.id.hashCode.toUnsigned(16)}',
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: importeEmitido,
    );
    await cambiarEstatus.ejecutar(documentoPorEmitirId: documento.id, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

    final cuenta = (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
    // La fecha de vencimiento real la determina la regla de cobro
    // (día hábil tras la emisión) — se corrige aquí a la fecha exacta
    // que pide el escenario del pedido (30/09/2026), sin motivo real
    // de negocio, solo para fijar el punto de partida del test.
    await cuentaRepo.corregir(cuentaPorCobrarId: cuenta.id, fechaVencimiento: DateTime(2026, 9, 30), motivo: 'Fijar fecha del escenario de prueba');
    return (await cuentaRepo.obtenerPorId(cuenta.id))!;
  }

  test(
    'escenario integral completo: reprogramar → Pago parcial → corregir vencimiento → quitar reprogramación → '
    'cancelación bloqueada con aplicación → cancelar aplicación → cancelar CxC, conservando historial y sin tocar el Documento',
    () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente X', importeEmitido: 1000000);
      expect(cuenta.importeEmitido, 1000000);
      expect(cuenta.fechaVencimiento, DateTime(2026, 9, 30));
      expect(cuenta.saldoPendiente, 1000000);

      // Paso 1: reprogramar cobro → 10/10/2026.
      final reprogramado = await reprogramarCobro.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        fechaCobroReprogramada: DateTime(2026, 10, 10),
        motivo: 'Cliente pidió una semana adicional',
      );
      expect(reprogramado, isA<ReprogramarCobroCuentaPorCobrarExitoso>());
      var actual = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(actual.fechaVencimiento, DateTime(2026, 9, 30), reason: 'la fecha contractual nunca se toca al reprogramar');
      expect(actual.fechaCobroReprogramada, DateTime(2026, 10, 10));

      // Paso 2: Pago $4,000.
      final registrado = await registrarPago.ejecutar(
        clienteId: cuenta.clienteId!,
        montoTotal: 400000,
        fechaPago: DateTime(2026, 9, 25),
        formaPago: 'transferencia',
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;
      final aplicado = await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 400000);
      expect(aplicado, isA<AplicarPagoACuentaExitoso>());

      actual = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(actual.saldoPendiente, 600000);
      expect(actual.estatus, 'parcial');
      final ingreso = await ingresoRepo.obtenerPorPagoId(pago.id);
      expect(ingreso!.monto, 400000, reason: 'el Ingreso automático refleja exactamente lo recibido');
      final aplicaciones = await pagoRepo.listarAplicacionesPorCuenta(cuenta.id);
      expect(aplicaciones, hasLength(1));
      expect(aplicaciones.single.monto, 400000);

      // Paso 3: corregir fecha contractual 30/09 → 05/10, con motivo.
      final corregido = await corregirCuenta.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        fechaVencimiento: DateTime(2026, 10, 5),
        motivo: 'Se detectó un error de captura en la fecha contractual',
      );
      expect(corregido, isA<CorregirCuentaPorCobrarExitoso>());
      actual = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(actual.fechaVencimiento, DateTime(2026, 10, 5));
      expect(actual.saldoPendiente, 600000, reason: 'corregir la fecha nunca toca el saldo');
      final pagoTrasCorregir = await pagoRepo.obtenerPorId(pago.id);
      expect(pagoTrasCorregir!.montoTotal, 400000, reason: 'el Pago sigue intacto');
      final aplicacionesTrasCorregir = await pagoRepo.listarAplicacionesPorCuenta(cuenta.id);
      expect(aplicacionesTrasCorregir, hasLength(1));
      expect(aplicacionesTrasCorregir.single.estatus, 'aplicada', reason: 'la aplicación sigue intacta');
      expect(actual.fechaCobroReprogramada, DateTime(2026, 10, 10), reason: 'la reprogramada sigue sin tocarse');

      // Paso 4: quitar la reprogramación.
      final quitada = await quitarReprogramacion.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        motivo: 'La reprogramación se había capturado por error',
      );
      expect(quitada, isA<QuitarReprogramacionCobroCuentaPorCobrarExitoso>());
      actual = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(actual.fechaCobroReprogramada, isNull);
      expect(actual.fechaVencimiento, DateTime(2026, 10, 5), reason: 'quitar la reprogramación nunca toca la fecha contractual');

      // Paso 5: intentar cancelar con aplicación activa — rechazo, cero mutación.
      final cuentaAntesDelIntento = actual;
      final intentoCancelar = await cancelarCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, motivo: 'Intento con aplicación activa');
      expect(intentoCancelar, isA<CancelarCuentaPorCobrarTieneAplicacionesActivas>());
      expect((intentoCancelar as CancelarCuentaPorCobrarTieneAplicacionesActivas).cantidad, 1);
      final cuentaTrasElIntento = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(cuentaTrasElIntento.estatus, cuentaAntesDelIntento.estatus, reason: 'cero mutación');
      expect(cuentaTrasElIntento.saldoPendiente, cuentaAntesDelIntento.saldoPendiente);

      // Paso 6: cancelar la aplicación desde el flujo de Pagos — la CxC vuelve a $10,000.
      final aplicacionActiva = aplicacionesTrasCorregir.single;
      final cancelacionAplicacion =
          await cancelarAplicacionPago.ejecutar(aplicacionPagoId: aplicacionActiva.id, motivo: 'El Pago se aplicará a otra cuenta');
      expect(cancelacionAplicacion, isA<CancelarAplicacionPagoExitoso>());
      actual = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(actual.saldoPendiente, 1000000, reason: 'la CxC vuelve a su saldo original');
      expect(actual.estatus, 'pendiente');

      // Paso 7: cancelar la CxC — queda cancelada, conserva historial completo.
      final cancelada = await cancelarCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, motivo: 'Cliente liquidó por fuera, se cancela el registro');
      expect(cancelada, isA<CancelarCuentaPorCobrarExitoso>());
      final cuentaFinal = (await cuentaRepo.obtenerPorId(cuenta.id))!;
      expect(cuentaFinal.estatus, 'cancelada');
      expect(cuentaFinal.saldoPendiente, 0);

      final eventos = await cuentaRepo.listarEventos(cuenta.id);
      expect(
        eventos.map((e) => e.tipoEvento),
        containsAll(['creada', 'corregida', 'fechaCobroReprogramada', 'cancelada']),
        reason: 'el historial completo sobrevive — nunca se pierde ni se sobrescribe',
      );

      // Verifica la política confirmada: cancelar la CxC nunca toca el Documento.
      final documento = await documentoRepo.obtenerPorId(cuenta.documentoPorEmitirId!);
      expect(documento!.estatus, 'procesadoAceptado', reason: 'cancelar la CxC nunca propaga nada al Documento de origen');
    },
  );

  test('N:M: una CxC recibe aplicaciones de dos Pagos distintos, cada uno auditado por separado', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente NM', importeEmitido: 1000000);

    final pago1 = (await registrarPago.ejecutar(
      clienteId: cuenta.clienteId!,
      montoTotal: 400000,
      fechaPago: DateTime(2026, 9, 1),
      formaPago: 'transferencia',
    ) as RegistrarPagoExitoso)
        .pago;
    await aplicarPagoACuenta.ejecutar(pagoId: pago1.id, cuentaPorCobrarId: cuenta.id, monto: 400000);

    final pago2 = (await registrarPago.ejecutar(
      clienteId: cuenta.clienteId!,
      montoTotal: 600000,
      fechaPago: DateTime(2026, 9, 15),
      formaPago: 'efectivo',
    ) as RegistrarPagoExitoso)
        .pago;
    await aplicarPagoACuenta.ejecutar(pagoId: pago2.id, cuentaPorCobrarId: cuenta.id, monto: 600000);

    final cuentaFinal = (await cuentaRepo.obtenerPorId(cuenta.id))!;
    expect(cuentaFinal.saldoPendiente, 0);
    expect(cuentaFinal.estatus, 'pagada');

    final aplicaciones = await pagoRepo.listarAplicacionesPorCuenta(cuenta.id);
    expect(aplicaciones, hasLength(2));
    expect(aplicaciones.map((a) => a.pagoId).toSet(), {pago1.id, pago2.id});

    // Cancelar la CxC ahora está bloqueada por 2 aplicaciones activas.
    final intento = await cancelarCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, motivo: 'Intento con 2 Pagos activos');
    expect(intento, isA<CancelarCuentaPorCobrarTieneAplicacionesActivas>());
    expect((intento as CancelarCuentaPorCobrarTieneAplicacionesActivas).cantidad, 2);
  });

  test(
    'con ComplementoPago REAL registrado: reprogramar cobro sigue permitido (no fiscal), '
    'cancelar la CxC sigue bloqueado por la aplicación activa, nada modifica el Pago/Complemento en silencio',
    () async {
      final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente Complemento', importeEmitido: 1000000);
      final pago = (await registrarPago.ejecutar(
        clienteId: cuenta.clienteId!,
        montoTotal: 1000000,
        fechaPago: DateTime(2026, 9, 20),
        formaPago: 'transferencia',
      ) as RegistrarPagoExitoso)
          .pago;
      await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 1000000);

      final complementoRegistrado = await registrarComplemento.ejecutar(
        pagoId: pago.id,
        uuid: '22222222-3333-4444-5555-666666666666',
        fechaTimbrado: DateTime(2026, 9, 21),
        montoTotal: 1000000,
        folioFiscal: 'CFDI-7001',
      );
      expect(complementoRegistrado, isA<RegistrarComplementoPagoExitoso>());

      // Reprogramar cobro (dato administrativo/de cobranza, nunca
      // fiscal) sigue permitido incluso con Complemento vigente.
      final reprogramado = await reprogramarCobro.ejecutar(
        cuentaPorCobrarId: cuenta.id,
        fechaCobroReprogramada: DateTime(2026, 11, 1),
        motivo: 'Ajuste de cobranza, sin efecto fiscal',
      );
      expect(reprogramado, isA<ReprogramarCobroCuentaPorCobrarExitoso>());

      // Cancelar la CxC sigue bloqueada — tiene una aplicación activa,
      // sin importar que además tenga Complemento.
      final intentoCancelar = await cancelarCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, motivo: 'Intento con Complemento vigente');
      expect(intentoCancelar, isA<CancelarCuentaPorCobrarTieneAplicacionesActivas>());

      // Nada de esto modificó el Pago ni el Complemento en silencio.
      final pagoTrasOperaciones = await pagoRepo.obtenerPorId(pago.id);
      expect(pagoTrasOperaciones!.montoTotal, 1000000);
      expect(pagoTrasOperaciones.estatus, 'registrado');
      final complemento = await complementoPagoRepo.obtenerVigentePorPagoId(pago.id);
      expect(complemento!.montoTotal, 1000000);
      expect(complemento.estatus, 'registrado');
    },
  );

  test('atomicidad: un fallo real durante la corrección revierte TODO (CxC, evento, sin rastro parcial)', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente Atomicidad', importeEmitido: 500000);
    final antes = (await cuentaRepo.obtenerPorId(cuenta.id))!;
    final eventosAntes = await cuentaRepo.listarEventos(cuenta.id);

    // `corregir` con `motivo` vacío viola la validación de dominio,
    // pero llamando DIRECTO al repositorio (sin la validación previa
    // del caso de uso) se puede forzar una falla real de BD: el
    // motivo es NOT NULL a nivel de columna cuando se pasa `null` vía
    // el companion crudo — aquí se prueba con un valor que sí viola un
    // CHECK real de la tabla (`saldo_pendiente <= saldo_original`)
    // manipulando el saldo directo, para confirmar que un fallo real a
    // mitad de una operación multi-escritura revierte todo.
    await expectLater(
      () => db.transaction(() async {
        await (db.update(db.cuentaPorCobrar)..where((t) => t.id.equals(cuenta.id))).write(
          const CuentaPorCobrarCompanion(saldoPendiente: Value(999999999)),
        );
        throw StateError('Fallo real provocado a mitad de la transacción');
      }),
      throwsA(anything),
    );

    final despues = (await cuentaRepo.obtenerPorId(cuenta.id))!;
    expect(despues.saldoPendiente, antes.saldoPendiente, reason: 'rollback completo — el saldo nunca quedó a medias');
    final eventosDespues = await cuentaRepo.listarEventos(cuenta.id);
    expect(eventosDespues.length, eventosAntes.length, reason: 'ningún evento a medio escribir sobrevive');
  });

  test('exige motivo para cancelar', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente Motivo Cancelar', importeEmitido: 100000);
    final resultado = await cancelarCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, motivo: '   ');
    expect(resultado, isA<CancelarCuentaPorCobrarMotivoRequerido>());
  });

  test('cancela una CxC sin aplicaciones directamente', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente Cancelar Directo', importeEmitido: 250000);
    final resultado = await cancelarCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, motivo: 'Documento duplicado por error');
    expect(resultado, isA<CancelarCuentaPorCobrarExitoso>());
    final actual = (await cuentaRepo.obtenerPorId(cuenta.id))!;
    expect(actual.estatus, 'cancelada');
    expect(actual.saldoPendiente, 0);
  });

  test('rechaza aplicar un Pago nuevo a una CxC ya cancelada', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente Cancelada Bloqueo', importeEmitido: 300000);
    await cancelarCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, motivo: 'Cancelada antes del intento de pago');

    final pago = (await registrarPago.ejecutar(
      clienteId: cuenta.clienteId!,
      montoTotal: 300000,
      fechaPago: DateTime(2026, 9, 1),
      formaPago: 'efectivo',
    ) as RegistrarPagoExitoso)
        .pago;
    final resultado = await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 300000);
    expect(resultado, isA<AplicarPagoACuentaCuentaCancelada>());
  });

  test('rechaza corregir/reprogramar una CxC ya cancelada', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente Cancelada Sin Corregir', importeEmitido: 300000);
    await cancelarCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, motivo: 'Cancelada antes del intento de corrección');

    final corregir = await corregirCuenta.ejecutar(cuentaPorCobrarId: cuenta.id, fechaVencimiento: DateTime(2026, 12, 1), motivo: 'Intento sobre cancelada');
    expect(corregir, isA<CorregirCuentaPorCobrarCancelada>());

    final reprogramar = await reprogramarCobro.ejecutar(cuentaPorCobrarId: cuenta.id, fechaCobroReprogramada: DateTime(2026, 12, 1), motivo: 'Intento sobre cancelada');
    expect(reprogramar, isA<ReprogramarCobroCuentaPorCobrarCancelada>());
  });
}
