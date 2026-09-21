// Etapa 15 — reproducción real del bug reportado: la CxC no
// actualizaba su badge de estatus en el LISTADO inmediatamente después
// de registrar un pago desde su diálogo de detalle (el saldo sí se
// veía correcto, el estatus se quedaba obsoleto hasta cambiar de
// pestaña). Mismo patrón de prueba ya usado y validado para el bug
// análogo de Clientes en esta sesión (`cliente_expediente_controller_test.dart`):
// se opera directamente sobre el `ProviderContainer`, sin navegar ni
// recargar manualmente, para aislar la corrección real
// (`ref.invalidate(cuentasPorCobrarControllerProvider)` en
// `CuentaPorCobrarDetalleDialog`) del selector de fecha nativo de
// Material (`RisegDateField`), cuya interacción en un árbol de 3
// diálogos apilados dispara una condición de carrera propia del
// framework de Flutter, ajena a este hallazgo.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
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

  /// Arma una CxC real (CFDI, sin línea comercial — el subtotal
  /// calculado es irrelevante: `importeEmitido` se captura directo y
  /// es lo único que determina el saldo) por $500.00, en
  /// `procesadoAceptado`. Devuelve el id de la CxC generada.
  Future<String> crearCuentaPorCobrarDePrueba(AppDatabase db, {required int importeEmitido}) async {
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
    final documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), cuentaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'MILUYOLE'));
    final entidad = await entidadFiscalRepo.crear(
      EntidadFiscalCompanion.insert(
        codigo: 'ENF-000001',
        clienteId: cliente.id,
        razonSocial: 'MILUYOLE SA de CV',
        rfc: 'MIL010101AAA',
      ),
    );
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final servicioCreado = await CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia MILUYOLE',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo);
    await CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      configuracionCobroValidator,
      const ConfiguracionCobroEtapaValidator(),
    ).ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.cfdi,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.pue,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        entidadFiscalId: entidad.id,
      ),
      etapas: const [],
    );

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    final crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo);
    final resultado = await crearManual.ejecutar(
      clienteId: cliente.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 30),
    );
    final documento = (resultado as CrearDocumentoManualExitoso).documento;

    await RegistrarEmisionDocumentoPorEmitirUseCase(documentoRepo).ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'F-0001',
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: importeEmitido,
    );
    await CambiarEstatusDocumentoPorEmitirUseCase(documentoRepo).ejecutar(
      documentoPorEmitirId: documento.id,
      nuevo: EstatusDocumentoPorEmitir.procesadoAceptado,
    );

    return (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!.id;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // `RegistrarPagoAplicadoUseCase` registra `actorUsuarioId` en
    // `PagoEvento` (FK real hacia `Usuario`) — el actor de la sesión de
    // prueba debe existir físicamente o la operación falla por
    // violación de FK, nunca por el bug de estatus obsoleto que esta
    // prueba investiga.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    cuentaId = await crearCuentaPorCobrarDePrueba(db, importeEmitido: 50000);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() => db.close());

  Future<void> esperarCarga() async {
    container.listen(cuentasPorCobrarControllerProvider, (_, _) {});
    while (container.read(cuentasPorCobrarControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'sin invalidar el provider del listado, un pago aplicado por otra vía queda obsoleto — '
    'confirma el mecanismo real del bug (mismo patrón que Clientes)',
    () async {
      await esperarCarga();
      expect(container.read(cuentasPorCobrarControllerProvider).cuentas.single.estatus, 'pendiente');

      // Aplica el pago exactamente como lo hace el diálogo real
      // (mismo provider, `registrarPagoAplicadoAutorizadoProvider`),
      // pero SIN la invalidación — reproduce el estado previo al fix.
      final resultado = await container.read(registrarPagoAplicadoAutorizadoProvider)(
        cuentaPorCobrarId: cuentaId,
        monto: 50000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
      );
      if (resultado is RegistrarPagoAplicadoErrorInesperado) {
        fail('RegistrarPagoAplicadoErrorInesperado inesperado en la prueba: ${resultado.mensaje}');
      }
      expect(resultado, isA<RegistrarPagoAplicadoExitoso>());

      // El provider del listado NUNCA se enteró — sigue "pendiente"
      // aunque la CxC ya esté pagada en la base de datos.
      expect(container.read(cuentasPorCobrarControllerProvider).cuentas.single.estatus, 'pendiente');
    },
  );

  test('invalidar cuentasPorCobrarControllerProvider (el fix real) refleja el pago total de inmediato', () async {
    await esperarCarga();

    await container.read(registrarPagoAplicadoAutorizadoProvider)(
      cuentaPorCobrarId: cuentaId,
      monto: 50000,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'transferencia',
    );
    // Exactamente lo que `CuentaPorCobrarDetalleDialog._registrarPago`
    // hace ahora tras un pago exitoso.
    container.invalidate(cuentasPorCobrarControllerProvider);
    await esperarCarga();

    final cuenta = container.read(cuentasPorCobrarControllerProvider).cuentas.single;
    expect(cuenta.saldoPendiente, 0);
    expect(cuenta.estatus, 'pagada');
  });

  test('pago parcial: el saldo disminuye y el estatus pasa a Parcial (nunca Pagada antes de tiempo)', () async {
    await esperarCarga();

    await container.read(registrarPagoAplicadoAutorizadoProvider)(
      cuentaPorCobrarId: cuentaId,
      monto: 20000,
      fechaPago: DateTime(2026, 1, 20),
      formaPago: 'efectivo',
    );
    container.invalidate(cuentasPorCobrarControllerProvider);
    await esperarCarga();

    final cuenta = container.read(cuentasPorCobrarControllerProvider).cuentas.single;
    expect(cuenta.saldoPendiente, 30000);
    expect(cuenta.estatus, 'parcial');
  });
}
