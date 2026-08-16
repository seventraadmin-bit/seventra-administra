// Etapa 15 (segunda corrección tras el CFDI real de MILUYOLE): la
// "diferencia" de un documento `masIva` comparaba un importe emitido
// con IVA contra una base sin IVA — este archivo prueba que
// `DocumentoPorEmitirDetalle.totalesEsperados`/`diferenciaEmision`
// ahora comparan contra el Total esperado (base + IVA cuando aplica),
// nunca contra la base cruda.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
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
import 'package:riseg_one/features/organizacion/domain/usecases/resumen_iva_documento_por_emitir.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

void main() {
  late AppDatabase db;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLineaComercial;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late CrearDocumentoManualUseCase crearManual;
  late RegistrarEmisionDocumentoPorEmitirUseCase registrarEmision;
  late ActualizarAjusteManualDocumentoPorEmitirUseCase actualizarAjuste;
  late ClienteRepositoryImpl clienteRepo;
  late String puestoId;

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
    final cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaComercialValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
    crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      configuracionCobroValidator,
      const ConfiguracionCobroEtapaValidator(),
    );
    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, ensamblar, generarCodigo);
    registrarEmision = RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo);
    actualizarAjuste = ActualizarAjusteManualDocumentoPorEmitirUseCase(documentoRepo);

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

  tearDown(() => db.close());

  /// Arma un documento con una única línea comercial cuyo subtotal
  /// proporcional (30 días completos, 1 elemento) reproduce
  /// exactamente `precioUnitarioCentavos` — mismo criterio ya
  /// verificado en `calcular_importe_proporcional_test.dart`.
  Future<String> crearDocumentoConLinea({
    required String nombreCliente,
    required int precioUnitarioCentavos,
    required TratamientoIva tratamientoIva,
  }) async {
    // Regla de negocio real ya existente (`ConfiguracionCobroValidator`):
    // un CFDI nunca es `noAplica` (`cfdiIncompatibleConIvaNoAplica`) y un
    // recibo siempre es `noAplica` (`reciboRequiereIvaNoAplica`) — no es
    // parte de lo que esta prueba investiga, solo una precondición real
    // del dominio que hay que respetar para poder crear la Configuración
    // de cobro.
    final esRecibo = tratamientoIva == TratamientoIva.noAplica;
    final tipoDocumento = esRecibo ? TipoDocumentoCobro.reciboDePago : TipoDocumentoCobro.cfdi;
    final metodo = esRecibo ? MetodoPagoCobro.noAplica : MetodoPagoCobro.pue;
    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${nombreCliente.hashCode.toUnsigned(20)}', nombreComercial: nombreCliente),
    );

    final servicioCreado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia $nombreCliente',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    final lineaResultado = await crearLineaComercial.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puestoId,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 1,
        precioUnitario: precioUnitarioCentavos,
        tratamientoIva: tratamientoIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    );
    if (lineaResultado is! CrearLineaComercialExitoso) {
      throw StateError('crearLineaComercial falló: $lineaResultado');
    }

    String? entidadFiscalId;
    if (!esRecibo) {
      final entidad = await EntidadFiscalRepositoryImpl(db).crear(
        EntidadFiscalCompanion.insert(
          codigo: 'ENF-${nombreCliente.hashCode.toUnsigned(20)}',
          clienteId: cliente.id,
          razonSocial: nombreCliente,
          rfc: 'XXX010101AAA',
        ),
      );
      entidadFiscalId = entidad.id;
    }

    final configResultado = await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: tipoDocumento,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: metodo,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        entidadFiscalId: entidadFiscalId,
      ),
      etapas: const [],
    );
    if (configResultado is CrearConfiguracionCobroErroresValidacion) {
      throw StateError('crearConfiguracionCobro falló: ${configResultado.errores} / ${configResultado.erroresEtapas}');
    }
    if (configResultado is! CrearConfiguracionCobroExitoso) {
      throw StateError('crearConfiguracionCobro falló: $configResultado');
    }

    final resultado = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 30),
    );
    if (resultado is! CrearDocumentoManualExitoso) {
      throw StateError('crearManual falló: $resultado');
    }
    return resultado.documento.id;
  }

  group('DocumentoPorEmitirDetalle.totalesEsperados — caso real MILUYOLE', () {
    test('Más IVA: base \$21,800.00 → IVA esperado \$3,488.00 → total esperado \$25,288.00', () async {
      final documentoId = await crearDocumentoConLinea(
        nombreCliente: 'MILUYOLE',
        precioUnitarioCentavos: 2180000,
        tratamientoIva: TratamientoIva.masIva,
      );

      final detalle = await documentoRepo.obtenerDetalle(documentoId);
      expect(detalle!.documento.importeBaseEsperado, 2180000);
      expect(detalle.resumenIva, ResumenIvaDocumento.masIva);
      expect(detalle.totalesEsperados!.base, 2180000);
      expect(detalle.totalesEsperados!.ivaEsperado, 348800);
      expect(detalle.totalesEsperados!.totalEsperado, 2528800);
    });

    test('importe emitido \$25,288.00 (Total real) → diferencia \$0.00', () async {
      final documentoId = await crearDocumentoConLinea(
        nombreCliente: 'MILUYOLE Exacto',
        precioUnitarioCentavos: 2180000,
        tratamientoIva: TratamientoIva.masIva,
      );
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'F-1523',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 2528800,
      );

      final detalle = await documentoRepo.obtenerDetalle(documentoId);
      expect(detalle!.diferenciaEmision, 0);
    });

    test('importe emitido \$25,000.00 → diferencia -\$288.00 (nunca contra la base sin IVA)', () async {
      final documentoId = await crearDocumentoConLinea(
        nombreCliente: 'MILUYOLE Distinto',
        precioUnitarioCentavos: 2180000,
        tratamientoIva: TratamientoIva.masIva,
      );
      await registrarEmision.ejecutar(
        documentoPorEmitirId: documentoId,
        folioDocumento: 'F-1524',
        fechaEmisionReal: DateTime(2026, 1, 5),
        importeEmitido: 2500000,
      );

      final detalle = await documentoRepo.obtenerDetalle(documentoId);
      expect(detalle!.diferenciaEmision, -28800);
    });

    test('noAplica: total esperado = base, sin IVA (Tikal, \$34,000.00)', () async {
      final documentoId = await crearDocumentoConLinea(
        nombreCliente: 'Tikal',
        precioUnitarioCentavos: 3400000,
        tratamientoIva: TratamientoIva.noAplica,
      );

      final detalle = await documentoRepo.obtenerDetalle(documentoId);
      expect(detalle!.resumenIva, ResumenIvaDocumento.noAplica);
      expect(detalle.totalesEsperados!.ivaEsperado, 0);
      expect(detalle.totalesEsperados!.totalEsperado, 3400000);
    });

    test('ivaIncluido: total esperado = importe configurado, sin volver a sumar IVA', () async {
      final documentoId = await crearDocumentoConLinea(
        nombreCliente: 'IVA Incluido',
        precioUnitarioCentavos: 2528800,
        tratamientoIva: TratamientoIva.ivaIncluido,
      );

      final detalle = await documentoRepo.obtenerDetalle(documentoId);
      expect(detalle!.resumenIva, ResumenIvaDocumento.ivaIncluido);
      expect(detalle.totalesEsperados!.ivaEsperado, 0);
      expect(detalle.totalesEsperados!.totalEsperado, 2528800);
    });

    test('ajuste comercial + Más IVA: el IVA se calcula sobre la base final ajustada', () async {
      final documentoId = await crearDocumentoConLinea(
        nombreCliente: 'Ajuste MasIva',
        precioUnitarioCentavos: 2180000,
        tratamientoIva: TratamientoIva.masIva,
      );
      await actualizarAjuste.ejecutar(documentoPorEmitirId: documentoId, ajusteManual: -180000, motivoAjuste: 'Descuento');

      final detalle = await documentoRepo.obtenerDetalle(documentoId);
      expect(detalle!.documento.importeFinalEsperado, 2000000, reason: 'base ajustada: 2,180,000 - 180,000');
      expect(detalle.totalesEsperados!.base, 2000000);
      expect(detalle.totalesEsperados!.ivaEsperado, 320000, reason: '16% de la base YA ajustada, no de la base cruda');
      expect(detalle.totalesEsperados!.totalEsperado, 2320000);
    });
  });
}
