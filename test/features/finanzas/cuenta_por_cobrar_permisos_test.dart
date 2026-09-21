// Etapa 7 (Cuentas por cobrar — corrección, cancelación, trazabilidad
// y consistencia con Agenda/Pagos), Sección 16: `cuentaPorCobrar.
// corregir`, `cuentaPorCobrar.reprogramarCobro` y `cuentaPorCobrar.
// cancelar` son códigos INDEPENDIENTES — un usuario con exactamente
// uno puede realizar solo esa acción, nunca las otras. El Maestro
// tiene acceso completo sin necesitar ninguna fila de `PermisoUsuario`
// (mismo criterio de autorización que el resto del proyecto). Mismo
// patrón que `pago_permisos_test.dart`: `_SesionFija`/`_container`,
// llamada directa al Controller, sin montar ningún widget.

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
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/quitar_reprogramacion_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
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

const _mensajePermiso = 'No tiene permiso para realizar esta acción.';

class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;

  @override
  SesionUsuario? build() => _sesion;
}

SesionUsuario _sesionCon(Set<String> permisos, {bool esMaestro = false}) => SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: esMaestro,
      permisos: permisos,
    );

ProviderContainer _container(AppDatabase db, SesionUsuario sesion) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late AppDatabase db;
  late String puestoId;

  /// Arma una CxC real completa (Cliente→Servicio→Línea→Configuración de
  /// cobro→Documento emitido/aceptado) — mismo camino de creación único
  /// que el resto de los tests de Etapa 7 (Resolución A de Marlon: nunca
  /// un documento aceptado sin su Cuenta por cobrar).
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
            id: const Value('usuario-prueba'),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'usuario-prueba',
            passwordHash: 'x',
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
  });

  tearDown(() => db.close());

  test('cuentaPorCobrar.corregir sin las otras: SÍ corrige, NO reprograma, NO cancela', () async {
    final cuenta = await crearCuentaDePrueba('Cliente Solo Corregir');
    final container = _container(db, _sesionCon({'cuentaPorCobrar.corregir'}));
    final controller = container.read(cuentasPorCobrarControllerProvider.notifier);

    final corregido = await controller.corregir(
      cuentaPorCobrarId: cuenta.id,
      fechaVencimiento: DateTime(2026, 12, 1),
      motivo: 'Corrección con el permiso correcto',
    );
    expect(corregido, isA<CorregirCuentaPorCobrarExitoso>());

    final reprogramado = await controller.reprogramarCobro(
      cuentaPorCobrarId: cuenta.id,
      fechaCobroReprogramada: DateTime(2026, 12, 15),
      motivo: 'Intento sin el permiso de reprogramar',
    );
    expect(reprogramado, isA<ReprogramarCobroCuentaPorCobrarErrorInesperado>());
    expect((reprogramado as ReprogramarCobroCuentaPorCobrarErrorInesperado).mensaje, _mensajePermiso);

    final cancelado = await controller.cancelar(cuentaPorCobrarId: cuenta.id, motivo: 'Intento sin el permiso de cancelar');
    expect(cancelado, isA<CancelarCuentaPorCobrarErrorInesperado>());
    expect((cancelado as CancelarCuentaPorCobrarErrorInesperado).mensaje, _mensajePermiso);
  });

  test('cuentaPorCobrar.reprogramarCobro sin las otras: SÍ reprograma y quita reprogramación, NO corrige, NO cancela', () async {
    final cuenta = await crearCuentaDePrueba('Cliente Solo Reprogramar');
    final container = _container(db, _sesionCon({'cuentaPorCobrar.reprogramarCobro'}));
    final controller = container.read(cuentasPorCobrarControllerProvider.notifier);

    final reprogramado = await controller.reprogramarCobro(
      cuentaPorCobrarId: cuenta.id,
      fechaCobroReprogramada: DateTime(2026, 12, 15),
      motivo: 'Reprogramación con el permiso correcto',
    );
    expect(reprogramado, isA<ReprogramarCobroCuentaPorCobrarExitoso>());

    final quitada = await controller.quitarReprogramacion(cuentaPorCobrarId: cuenta.id, motivo: 'Misma facultad, acción inversa');
    expect(quitada, isA<QuitarReprogramacionCobroCuentaPorCobrarExitoso>());

    final corregido = await controller.corregir(
      cuentaPorCobrarId: cuenta.id,
      fechaVencimiento: DateTime(2026, 12, 1),
      motivo: 'Intento sin el permiso de corregir',
    );
    expect(corregido, isA<CorregirCuentaPorCobrarErrorInesperado>());
    expect((corregido as CorregirCuentaPorCobrarErrorInesperado).mensaje, _mensajePermiso);

    final cancelado = await controller.cancelar(cuentaPorCobrarId: cuenta.id, motivo: 'Intento sin el permiso de cancelar');
    expect(cancelado, isA<CancelarCuentaPorCobrarErrorInesperado>());
    expect((cancelado as CancelarCuentaPorCobrarErrorInesperado).mensaje, _mensajePermiso);
  });

  test('cuentaPorCobrar.cancelar sin las otras: SÍ cancela, NO corrige, NO reprograma', () async {
    final cuenta = await crearCuentaDePrueba('Cliente Solo Cancelar');
    final container = _container(db, _sesionCon({'cuentaPorCobrar.cancelar'}));
    final controller = container.read(cuentasPorCobrarControllerProvider.notifier);

    final corregido = await controller.corregir(
      cuentaPorCobrarId: cuenta.id,
      fechaVencimiento: DateTime(2026, 12, 1),
      motivo: 'Intento sin el permiso de corregir',
    );
    expect(corregido, isA<CorregirCuentaPorCobrarErrorInesperado>());
    expect((corregido as CorregirCuentaPorCobrarErrorInesperado).mensaje, _mensajePermiso);

    final reprogramado = await controller.reprogramarCobro(
      cuentaPorCobrarId: cuenta.id,
      fechaCobroReprogramada: DateTime(2026, 12, 15),
      motivo: 'Intento sin el permiso de reprogramar',
    );
    expect(reprogramado, isA<ReprogramarCobroCuentaPorCobrarErrorInesperado>());
    expect((reprogramado as ReprogramarCobroCuentaPorCobrarErrorInesperado).mensaje, _mensajePermiso);

    final cancelado = await controller.cancelar(cuentaPorCobrarId: cuenta.id, motivo: 'Cancelación con el permiso correcto');
    expect(cancelado, isA<CancelarCuentaPorCobrarExitoso>());
  });

  test('Maestro: acceso completo a corregir/reprogramar/quitar reprogramación/cancelar sin ninguna fila de PermisoUsuario', () async {
    final cuenta = await crearCuentaDePrueba('Cliente Maestro');
    final container = _container(db, _sesionCon({}, esMaestro: true));
    final controller = container.read(cuentasPorCobrarControllerProvider.notifier);

    final corregido = await controller.corregir(
      cuentaPorCobrarId: cuenta.id,
      fechaVencimiento: DateTime(2026, 12, 1),
      motivo: 'Maestro corrige sin permisos otorgados',
    );
    expect(corregido, isA<CorregirCuentaPorCobrarExitoso>());

    final reprogramado = await controller.reprogramarCobro(
      cuentaPorCobrarId: cuenta.id,
      fechaCobroReprogramada: DateTime(2026, 12, 15),
      motivo: 'Maestro reprograma sin permisos otorgados',
    );
    expect(reprogramado, isA<ReprogramarCobroCuentaPorCobrarExitoso>());

    final quitada = await controller.quitarReprogramacion(cuentaPorCobrarId: cuenta.id, motivo: 'Maestro quita reprogramación');
    expect(quitada, isA<QuitarReprogramacionCobroCuentaPorCobrarExitoso>());

    final cancelado = await controller.cancelar(cuentaPorCobrarId: cuenta.id, motivo: 'Maestro cancela sin permisos otorgados');
    expect(cancelado, isA<CancelarCuentaPorCobrarExitoso>());
  });
}
