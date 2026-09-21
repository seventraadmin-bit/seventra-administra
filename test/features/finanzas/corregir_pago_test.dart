// Etapa 6 (Pagos de clientes — corrección completa, reaplicación y
// consistencia con CxC/Ingreso), Sección 12: escenario integral exacto
// del pedido. Cliente X con CxC A/B/C, BBVA inicial $20,000, se
// registra un Pago $10,000 aplicado a A/B, se corrige el monto hacia
// arriba ($12,000) redistribuyendo entre A/B/C, luego hacia abajo
// ($8,000) redistribuyendo de nuevo — verifica BBVA, saldo de cada
// CxC, `Pago.montoAplicado`, auditoría completa y cero duplicados.
// También cubre el bloqueo por ComplementoPago vigente (Sección 13,
// con un Complemento REAL registrado, nunca un booleano falso) y
// atomicidad (Sección 14, un fallo real a mitad de la redistribución).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/complemento_pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/aplicar_pago_a_cuenta_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_usecase.dart';
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
  late PagoRepositoryImpl pagoRepo;
  late IngresoRepositoryImpl ingresoRepo;
  late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
  late ComplementoPagoRepositoryImpl complementoPagoRepo;
  late ClienteRepositoryImpl clienteRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late CambiarEstatusDocumentoPorEmitirUseCase cambiarEstatus;
  late RegistrarPagoUseCase registrarPago;
  late AplicarPagoACuentaUseCase aplicarPagoACuenta;
  late CorregirPagoUseCase corregirPago;
  late CancelarPagoUseCase cancelarPago;
  late RegistrarComplementoPagoUseCase registrarComplemento;
  late String puestoId;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generarCodigoInterno = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    pagoRepo = PagoRepositoryImpl(db);
    ingresoRepo = IngresoRepositoryImpl(db);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    complementoPagoRepo = ComplementoPagoRepositoryImpl(db);
    final documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    const reglaValidator = ConfiguracionCobroEtapaValidator();

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigoInterno, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(configuracionCobroRepo, servicioRepo, configuracionCobroValidator, reglaValidator);

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigoInterno);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    cambiarEstatus = CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo);

    registrarPago = RegistrarPagoUseCase(pagoRepo, clienteRepo, generarCodigoInterno);
    aplicarPagoACuenta = AplicarPagoACuentaUseCase(pagoRepo, cuentaRepo);
    corregirPago = CorregirPagoUseCase(pagoRepo, cuentaRepo, complementoPagoRepo);
    cancelarPago = CancelarPagoUseCase(pagoRepo, complementoPagoRepo);
    registrarComplemento = RegistrarComplementoPagoUseCase(complementoPagoRepo, pagoRepo);

    tempDir = Directory.systemTemp.createTempSync('riseg_corregir_pago_test_');

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

  Future<CuentaPorCobrarData> crearCuentaDePrueba({
    required String nombreCliente,
    int importeEmitido = 500000,
    String? clienteIdExistente,
  }) async {
    String cliente;
    if (clienteIdExistente != null) {
      cliente = clienteIdExistente;
    } else {
      final clienteCreado = await clienteRepo.crear(
        ClienteCompanion.insert(codigo: 'CLI-${nombreCliente.hashCode.toUnsigned(20)}', nombreComercial: nombreCliente),
      );
      cliente = clienteCreado.id;
    }

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

    return (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
  }

  test(
    'escenario integral completo: BBVA \$20,000 → Pago \$10,000 (A\$6k/B\$4k) → corrige a \$12,000 (A\$5k/B\$4k/C\$3k) '
    '→ corrige a \$8,000 (A\$4k/B\$4k) — Caja, saldos de CxC y auditoría exactos, cero duplicados',
    () async {
      final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-X', nombreComercial: 'Cliente X'));
      final cuentaA = await crearCuentaDePrueba(nombreCliente: 'Cliente X', importeEmitido: 600000, clienteIdExistente: cliente.id);
      final cuentaB = await crearCuentaDePrueba(nombreCliente: 'Cliente X', importeEmitido: 400000, clienteIdExistente: cliente.id);
      final cuentaC = await crearCuentaDePrueba(nombreCliente: 'Cliente X', importeEmitido: 300000, clienteIdExistente: cliente.id);

      final bbva = await cuentaFinancieraRepo.crear(
        codigo: 'BBVA-001',
        nombre: 'BBVA',
        tipo: TipoCuentaFinanciera.banco.name,
        saldoInicial: 2000000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );

      // Registrar Pago $10,000 aplicado a A ($6,000) y B ($4,000).
      final registrado = await registrarPago.ejecutar(
        clienteId: cliente.id,
        montoTotal: 1000000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: bbva.id,
      );
      final pago = (registrado as RegistrarPagoExitoso).pago;
      await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaA.id, monto: 600000);
      await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaB.id, monto: 400000);

      expect(await cuentaFinancieraRepo.calcularSaldo(bbva.id), 3000000, reason: r'BBVA $20,000 + $10,000 recibido = $30,000');
      expect((await cuentaRepo.obtenerPorId(cuentaA.id))!.saldoPendiente, 0);
      expect((await cuentaRepo.obtenerPorId(cuentaB.id))!.saldoPendiente, 0);
      expect((await cuentaRepo.obtenerPorId(cuentaC.id))!.saldoPendiente, 300000);
      expect((await pagoRepo.obtenerPorId(pago.id))!.montoAplicado, 1000000);

      // Corrige a $12,000, redistribuyendo A $5,000 / B $4,000 / C $3,000.
      final arriba = await corregirPago.ejecutar(
        pagoId: pago.id,
        montoTotal: 1200000,
        nuevaDistribucion: [
          (cuentaPorCobrarId: cuentaA.id, monto: 500000),
          (cuentaPorCobrarId: cuentaB.id, monto: 400000),
          (cuentaPorCobrarId: cuentaC.id, monto: 300000),
        ],
        motivo: r'Se detectó un pago adicional de $2,000 no capturado, se redistribuye entre las 3 cuentas',
      );
      expect(arriba, isA<CorregirPagoExitoso>());

      expect(await cuentaFinancieraRepo.calcularSaldo(bbva.id), 3200000, reason: r'BBVA sube exactamente $2,000 más: $32,000');
      expect((await cuentaRepo.obtenerPorId(cuentaA.id))!.saldoPendiente, 100000, reason: r'A: $600,000 - $500,000 aplicados = $100,000 pendiente');
      expect((await cuentaRepo.obtenerPorId(cuentaB.id))!.saldoPendiente, 0);
      expect((await cuentaRepo.obtenerPorId(cuentaC.id))!.saldoPendiente, 0);
      final pagoArriba = (await pagoRepo.obtenerPorId(pago.id))!;
      expect(pagoArriba.montoTotal, 1200000);
      expect(pagoArriba.montoAplicado, 1200000);
      final ingresoArriba = await ingresoRepo.obtenerPorPagoId(pago.id);
      expect(ingresoArriba!.monto, 1200000, reason: 'el Ingreso automático sigue el nuevo monto total, nunca un segundo Ingreso');
      final ingresosTotales = await ingresoRepo.listar();
      expect(ingresosTotales.where((i) => i.pagoId == pago.id), hasLength(1), reason: 'nunca un segundo Ingreso para el mismo Pago');

      // Corrige a $8,000, redistribuyendo A $4,000 / B $4,000 (C queda sin cubrir).
      final abajo = await corregirPago.ejecutar(
        pagoId: pago.id,
        montoTotal: 800000,
        nuevaDistribucion: [
          (cuentaPorCobrarId: cuentaA.id, monto: 400000),
          (cuentaPorCobrarId: cuentaB.id, monto: 400000),
        ],
        motivo: r'El monto real recibido era $8,000, no $12,000 — se corrige y se retira la cobertura de C',
      );
      expect(abajo, isA<CorregirPagoExitoso>());

      expect(await cuentaFinancieraRepo.calcularSaldo(bbva.id), 2800000, reason: r'BBVA baja a $28,000 respecto del registro original');
      expect((await cuentaRepo.obtenerPorId(cuentaA.id))!.saldoPendiente, 200000, reason: r'A: $600,000 - $400,000 = $200,000 pendiente');
      expect((await cuentaRepo.obtenerPorId(cuentaB.id))!.saldoPendiente, 0);
      expect((await cuentaRepo.obtenerPorId(cuentaC.id))!.saldoPendiente, 300000, reason: 'C vuelve a estar completamente pendiente');
      final pagoAbajo = (await pagoRepo.obtenerPorId(pago.id))!;
      expect(pagoAbajo.montoTotal, 800000);
      expect(pagoAbajo.montoAplicado, 800000);
      final ingresoAbajo = await ingresoRepo.obtenerPorPagoId(pago.id);
      expect(ingresoAbajo!.monto, 800000);

      // Auditoría: exactamente 1 Ingreso (sin duplicados), y el
      // historial del Pago/Ingreso refleja ambas correcciones.
      final eventosPago = await pagoRepo.listarEventos(pago.id);
      expect(eventosPago.where((e) => e.tipoEvento == 'corregido'), hasLength(2), reason: 'una corrección por cada llamada, cero duplicados');
      final eventosIngreso = await ingresoRepo.listarEventos(ingresoAbajo.id);
      expect(eventosIngreso.where((e) => e.tipoEvento == 'corregido'), hasLength(2));
      final aplicacionesTotales = await pagoRepo.listarAplicacionesPorPago(pago.id);
      // 2 originales + 3 de la redistribución a $12,000 + 2 de la
      // redistribución a $8,000 = 7 filas totales, nunca menos (nunca
      // se borra una AplicacionPago, Resolución 6 de Marlon).
      expect(aplicacionesTotales, hasLength(7));
      expect(aplicacionesTotales.where((a) => a.estatus == 'aplicada'), hasLength(2), reason: 'solo las 2 de la distribución final siguen activas');
    },
  );

  test('bloquea corregir monto/fecha/forma de pago/aplicaciones cuando existe un ComplementoPago REAL vigente — cero mutación', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente con Complemento', importeEmitido: 1000000);
    final registrado = await registrarPago.ejecutar(
      clienteId: cuenta.clienteId!,
      montoTotal: 1000000,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
    );
    final pago = (registrado as RegistrarPagoExitoso).pago;
    await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 1000000);

    final complementoRegistrado = await registrarComplemento.ejecutar(
      pagoId: pago.id,
      uuid: '11111111-2222-3333-4444-555555555555',
      fechaTimbrado: DateTime(2026, 1, 21),
      montoTotal: 1000000,
      folioFiscal: 'CFDI-8001',
    );
    expect(complementoRegistrado, isA<RegistrarComplementoPagoExitoso>());

    final pagoAntes = (await pagoRepo.obtenerPorId(pago.id))!;
    final aplicacionesAntes = await pagoRepo.listarAplicacionesPorPago(pago.id);

    final resultado = await corregirPago.ejecutar(
      pagoId: pago.id,
      montoTotal: 1200000,
      fechaPago: DateTime(2026, 1, 22),
      formaPago: 'efectivo',
      nuevaDistribucion: [(cuentaPorCobrarId: cuenta.id, monto: 1200000)],
      motivo: 'Intento de corrección con Complemento vigente',
    );
    expect(resultado, isA<CorregirPagoComplementoVigente>());
    expect((resultado as CorregirPagoComplementoVigente).uuid, '11111111-2222-3333-4444-555555555555');

    final pagoDespues = (await pagoRepo.obtenerPorId(pago.id))!;
    expect(pagoDespues.montoTotal, pagoAntes.montoTotal, reason: 'cero mutación');
    expect(pagoDespues.fechaPago, pagoAntes.fechaPago);
    expect(pagoDespues.formaPago, pagoAntes.formaPago);
    final aplicacionesDespues = await pagoRepo.listarAplicacionesPorPago(pago.id);
    expect(aplicacionesDespues.length, aplicacionesAntes.length, reason: 'cero mutación en la distribución');

    // Cancelar el Pago también debe estar bloqueado mientras el
    // Complemento siga vigente (Sección 9).
    final cancelacion = await cancelarPago.ejecutar(pagoId: pago.id, motivo: 'Intento de cancelación con Complemento vigente');
    expect(cancelacion, isA<CancelarPagoComplementoVigente>());
    expect((await pagoRepo.obtenerPorId(pago.id))!.estatus, isNot('cancelado'));

    // Campos no fiscales SÍ siguen siendo corregibles con Complemento vigente.
    final corregibleNoFiscal = await corregirPago.ejecutar(
      pagoId: pago.id,
      referencia: 'REF-NUEVA',
      cuentaFinancieraId: null,
      observaciones: 'Aclaración administrativa, sin efecto fiscal',
      motivo: 'Corrección de un campo no fiscal con Complemento vigente',
    );
    expect(corregibleNoFiscal, isA<CorregirPagoExitoso>());
    expect((corregibleNoFiscal as CorregirPagoExitoso).pago.referencia, 'REF-NUEVA');
  });

  test('atomicidad: un fallo real a mitad de la redistribución revierte TODO (Pago/Ingreso/aplicaciones/saldos de CxC)', () async {
    final cuentaA = await crearCuentaDePrueba(nombreCliente: 'Cliente Atomicidad', importeEmitido: 500000);
    final registrado = await registrarPago.ejecutar(
      clienteId: cuentaA.clienteId!,
      montoTotal: 500000,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
    );
    final pago = (registrado as RegistrarPagoExitoso).pago;
    await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaA.id, monto: 500000);

    final pagoAntes = (await pagoRepo.obtenerPorId(pago.id))!;
    final ingresoAntes = (await ingresoRepo.obtenerPorPagoId(pago.id))!;
    final cuentaAAntes = (await cuentaRepo.obtenerPorId(cuentaA.id))!;
    final aplicacionesAntes = await pagoRepo.listarAplicacionesPorPago(pago.id);

    // Llama directo al repositorio (sin la validación previa del caso
    // de uso) para forzar una falla real a mitad de la transacción: la
    // primera fila de la redistribución es válida y alcanza a
    // aplicarse, la segunda referencia una Cuenta por cobrar
    // inexistente y truena — Drift debe revertir la transacción
    // completa, incluyendo el `montoTotal` ya escrito y las
    // aplicaciones ya reventidas/insertadas.
    await expectLater(
      pagoRepo.corregir(
        pagoId: pago.id,
        montoTotal: 900000,
        nuevaDistribucion: [
          (cuentaPorCobrarId: cuentaA.id, monto: 500000),
          (cuentaPorCobrarId: 'cxc-que-no-existe', monto: 400000),
        ],
        motivo: 'Corrección que debe fallar a mitad de camino',
      ),
      throwsA(anything),
    );

    final pagoDespues = (await pagoRepo.obtenerPorId(pago.id))!;
    expect(pagoDespues.montoTotal, pagoAntes.montoTotal, reason: 'rollback completo — montoTotal nunca quedó a medias');
    expect(pagoDespues.montoAplicado, pagoAntes.montoAplicado);

    final ingresoDespues = (await ingresoRepo.obtenerPorPagoId(pago.id))!;
    expect(ingresoDespues.monto, ingresoAntes.monto, reason: 'el Ingreso automático nunca se sincronizó a medias');

    final cuentaADespues = (await cuentaRepo.obtenerPorId(cuentaA.id))!;
    expect(cuentaADespues.saldoPendiente, cuentaAAntes.saldoPendiente, reason: 'el saldo de A nunca quedó revertido a medias');
    expect(cuentaADespues.estatus, cuentaAAntes.estatus);

    final aplicacionesDespues = await pagoRepo.listarAplicacionesPorPago(pago.id);
    expect(aplicacionesDespues.length, aplicacionesAntes.length, reason: 'ninguna aplicación de la redistribución sobrevive el rollback');
    expect(aplicacionesDespues.single.estatus, aplicacionesAntes.single.estatus, reason: 'la aplicación original nunca se marcó cancelada a medias');
  });

  test('exige motivo para corregir', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente Motivo', importeEmitido: 100000);
    final registrado = await registrarPago.ejecutar(
      clienteId: cuenta.clienteId!,
      montoTotal: 100000,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'efectivo',
    );
    final pago = (registrado as RegistrarPagoExitoso).pago;

    final resultado = await corregirPago.ejecutar(pagoId: pago.id, referencia: 'REF', motivo: '   ');
    expect(resultado, isA<CorregirPagoMotivoRequerido>());
  });

  test('bloquea reducir montoTotal por debajo de lo ya aplicado sin proveer una nueva distribución', () async {
    final cuenta = await crearCuentaDePrueba(nombreCliente: 'Cliente Sin Redistribucion', importeEmitido: 500000);
    final registrado = await registrarPago.ejecutar(
      clienteId: cuenta.clienteId!,
      montoTotal: 500000,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'efectivo',
    );
    final pago = (registrado as RegistrarPagoExitoso).pago;
    await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuenta.id, monto: 500000);

    final resultado = await corregirPago.ejecutar(pagoId: pago.id, montoTotal: 300000, motivo: 'Intento sin redistribución');
    expect(resultado, isA<CorregirPagoMontoMenorQueAplicado>());
    expect((resultado as CorregirPagoMontoMenorQueAplicado).montoAplicado, 500000);
    expect((await pagoRepo.obtenerPorId(pago.id))!.montoTotal, 500000, reason: 'cero mutación');
  });

  test('rechaza una fila de la nueva distribución que referencia una Cuenta de otro Cliente', () async {
    final cuentaClienteA = await crearCuentaDePrueba(nombreCliente: 'Cliente A Redistribucion', importeEmitido: 500000);
    final cuentaClienteB = await crearCuentaDePrueba(nombreCliente: 'Cliente B Redistribucion', importeEmitido: 500000);
    final registrado = await registrarPago.ejecutar(
      clienteId: cuentaClienteA.clienteId!,
      montoTotal: 500000,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'efectivo',
    );
    final pago = (registrado as RegistrarPagoExitoso).pago;
    await aplicarPagoACuenta.ejecutar(pagoId: pago.id, cuentaPorCobrarId: cuentaClienteA.id, monto: 500000);

    final resultado = await corregirPago.ejecutar(
      pagoId: pago.id,
      nuevaDistribucion: [(cuentaPorCobrarId: cuentaClienteB.id, monto: 500000)],
      motivo: 'Intento de redistribuir a otro Cliente',
    );
    expect(resultado, isA<CorregirPagoClienteNoCoincide>());
  });
}
