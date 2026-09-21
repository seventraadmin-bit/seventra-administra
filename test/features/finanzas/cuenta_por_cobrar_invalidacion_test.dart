// Etapa 7 (Cuentas por cobrar — corrección, cancelación, trazabilidad
// y consistencia con Agenda/Pagos), Sección 17: cada una de
// `corregir`/`reprogramarCobro`/`quitarReprogramacion`/`cancelar`
// invalida EXACTAMENTE el conjunto documentado (Resumen financiero,
// Planeación financiera, Dashboard) — nunca Pagos, que no cambia con
// ninguna de estas operaciones. Se cuenta cuántas veces cada provider
// se reconstruye (`container.listen`) antes/después de cada operación,
// en vez de solo verificar el valor final — mismo criterio de
// invalidación cruzada de `corregir_compra_invalidacion_test.dart`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
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

Future<void> _asentar(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  while (container.read(resumenFinancieroControllerProvider).cargando ||
      container.read(planeacionFinancieraControllerProvider).cargando ||
      container.read(dashboardControllerProvider).cargando) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String puestoId;

  Future<CuentaPorCobrarData> crearCuentaDePrueba(String nombreCliente) async {
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

    final clienteCreado = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-${nombreCliente.hashCode.toUnsigned(20)}', nombreComercial: nombreCliente),
    );

    final servicioCreado = await crearServicio.ejecutar(
      clienteId: clienteCreado.id,
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
      clienteId: clienteCreado.id,
      servicioIds: [servicioId],
      periodoInicio: DateTime(2026, 1, 1),
      periodoFin: DateTime(2026, 1, 31),
    );
    final documento = (resultado as CrearDocumentoManualExitoso).documento;

    await registrarEmision.ejecutar(
      documentoPorEmitirId: documento.id,
      folioDocumento: 'FOL-${documento.id.hashCode.toUnsigned(16)}',
      fechaEmisionReal: DateTime(2026, 1, 5),
      importeEmitido: 500000,
    );
    await cambiarEstatus.ejecutar(documentoPorEmitirId: documento.id, nuevo: EstatusDocumentoPorEmitir.procesadoAceptado);

    return (await cuentaRepo.obtenerPorDocumentoPorEmitirId(documento.id))!;
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
      PuestoCompanion.insert(
        codigo: 'PUE-0001',
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    puestoId = puesto.id;

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() => db.close());

  test(
    'corregir/reprogramarCobro/quitarReprogramacion/cancelar invalidan EXACTAMENTE Resumen/Planeación/Dashboard, nunca Pagos',
    () async {
      final cuenta = await crearCuentaDePrueba('Cliente Invalidación');

      var resumenCount = 0, planeacionCount = 0, dashboardCount = 0, pagosCount = 0;
      container.listen(resumenFinancieroControllerProvider, (_, _) {});
      container.listen(planeacionFinancieraControllerProvider, (_, _) {});
      container.listen(dashboardControllerProvider, (_, _) {});
      container.listen(pagosControllerProvider, (_, _) {});
      await _asentar(container);
      // Espera el asentamiento del listado de Pagos también (autodispose
      // independiente, sin `cargando` compartido con los otros tres).
      while (container.read(pagosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }

      final controller = container.read(cuentasPorCobrarControllerProvider.notifier);

      // corregir()
      container.listen(resumenFinancieroControllerProvider, (_, _) => resumenCount++);
      container.listen(planeacionFinancieraControllerProvider, (_, _) => planeacionCount++);
      container.listen(dashboardControllerProvider, (_, _) => dashboardCount++);
      container.listen(pagosControllerProvider, (_, _) => pagosCount++);

      await controller.corregir(cuentaPorCobrarId: cuenta.id, fechaVencimiento: DateTime(2026, 10, 1), motivo: 'Corrección de prueba');
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'corregir() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'corregir() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'corregir() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'corregir() nunca debe tocar Pagos');

      // reprogramarCobro()
      resumenCount = planeacionCount = dashboardCount = pagosCount = 0;
      await controller.reprogramarCobro(cuentaPorCobrarId: cuenta.id, fechaCobroReprogramada: DateTime(2026, 10, 15), motivo: 'Reprogramación de prueba');
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'reprogramarCobro() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'reprogramarCobro() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'reprogramarCobro() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'reprogramarCobro() nunca debe tocar Pagos');

      // quitarReprogramacion()
      resumenCount = planeacionCount = dashboardCount = pagosCount = 0;
      await controller.quitarReprogramacion(cuentaPorCobrarId: cuenta.id, motivo: 'Quitar reprogramación de prueba');
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'quitarReprogramacion() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'quitarReprogramacion() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'quitarReprogramacion() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'quitarReprogramacion() nunca debe tocar Pagos');

      // cancelar()
      resumenCount = planeacionCount = dashboardCount = pagosCount = 0;
      await controller.cancelar(cuentaPorCobrarId: cuenta.id, motivo: 'Cancelación de prueba');
      await _asentar(container);
      expect(resumenCount, greaterThan(0), reason: 'cancelar() debe invalidar Resumen financiero');
      expect(planeacionCount, greaterThan(0), reason: 'cancelar() debe invalidar Planeación financiera');
      expect(dashboardCount, greaterThan(0), reason: 'cancelar() debe invalidar el Dashboard');
      expect(pagosCount, 0, reason: 'cancelar() nunca debe tocar Pagos');
    },
  );
}
