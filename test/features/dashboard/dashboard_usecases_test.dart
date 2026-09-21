// Etapa 13 (Dashboard) — pruebas de los use cases genuinamente nuevos
// de esta etapa: cruce Personal↔Inventario para "empleados de baja con
// Inventario pendiente" (no existía ninguna consulta que lo resolviera
// antes), agregación de alertas del Dashboard, y la composición de
// "actividad reciente" (permiso independiente por dominio, sin
// consultar lo que no se incluyó). Los 6 use cases de Reportes que el
// Dashboard reutiliza tal cual ya están probados en sus propias
// etapas (12A-12D) — no se repiten aquí.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_credito_disponible_tarjetas_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/nomina/domain/repositories/nomina_repository.dart';
import 'package:riseg_one/features/notificaciones/domain/usecases/obtener_notificaciones_documentos_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/documento_por_emitir_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/vacante_operativa_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/recarga_linea_telefonica_repository.dart';

import 'package:riseg_one/features/dashboard/domain/usecases/obtener_actividad_reciente_usecase.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_alertas_dashboard_usecase.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_empleados_baja_con_pendiente_usecase.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_proxima_nomina_usecase.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_resumen_cobranza_usecase.dart';

/// Solo implementa `listar()` — lo único que `ObtenerAlertasDashboardUseCase`
/// invoca; el resto no aplica a esta prueba de agregación pura.
class _CuentaPorCobrarRepositoryDePrueba implements CuentaPorCobrarRepository {

  @override
  Future<CuentaPorCobrarData> crearDeServicioEventual({
    required String servicioEventualId,
    String? clienteId,
    required String tipoDocumento,
    required String metodo,
    required bool requiereComplemento,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? observaciones,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CuentaPorCobrarData?> obtenerPorServicioEventualId(String servicioEventualId) =>
      throw UnimplementedError();
  @override
  Future<Map<String, CuentaPorCobrarData>> porServiciosEventuales(Iterable<String> servicioEventualIds) =>
      throw UnimplementedError();


  @override
  Future<CuentaPorCobrarData> sincronizarConDocumentoFiscal({
    required String cuentaPorCobrarId,
    String? folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required String metodo,
    required bool requiereComplemento,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CuentaPorCobrarData> corregirImporte({
    required String cuentaPorCobrarId,
    required int importeEmitido,
    required String motivo,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  _CuentaPorCobrarRepositoryDePrueba(this.cuentas);
  final List<CuentaPorCobrarData> cuentas;

  @override
  Future<List<CuentaPorCobrarData>> listar({
    String? clienteId,
    String? servicioId,
    String? entidadFiscalId,
    String? tipoDocumento,
    String? estatus,
    String? documentoPorEmitirId,
    String? servicioEventualId,
  }) async =>
      cuentas;

  @override
  Future<CuentaPorCobrarData?> obtenerPorId(String id) => throw UnimplementedError();
  @override
  Future<CuentaPorCobrarData?> obtenerPorDocumentoPorEmitirId(String documentoPorEmitirId) => throw UnimplementedError();
  @override
  Future<CuentaPorCobrarData> crear({
    required String documentoPorEmitirId,
    required String clienteId,
    required String tipoDocumento,
    required String metodo,
    required bool requiereComplemento,
    String? folioDocumento,
    String? serieFiscal,
    String? folioFiscal,
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();
  @override
  Future<CuentaPorCobrarData> corregir({
    required String cuentaPorCobrarId,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();
  @override
  Future<CuentaPorCobrarData> reprogramarCobro({
    required String cuentaPorCobrarId,
    required DateTime? fechaCobroReprogramada,
    required String motivo,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();
  @override
  Future<CuentaPorCobrarData> cancelar({
    required String cuentaPorCobrarId,
    required String motivo,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();
  @override
  Future<List<CuentaPorCobrarEventoData>> listarEventos(String cuentaPorCobrarId) => throw UnimplementedError();
}

CuentaPorCobrarData _cuentaDePrueba({
  required String id,
  required int saldoPendiente,
  DateTime? fechaVencimiento,
  String estatus = 'pendiente',
  int? importeEmitido,
}) {
  final ahora = DateTime(2026, 1, 1);
  return CuentaPorCobrarData(
    id: id,
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    documentoPorEmitirId: 'doc-$id',
    clienteId: 'cliente-1',
    tipoDocumento: 'factura',
    metodo: 'pue',
    requiereComplemento: false,
    fechaEmisionReal: ahora,
    importeEmitido: importeEmitido ?? saldoPendiente,
    saldoOriginal: importeEmitido ?? saldoPendiente,
    saldoPendiente: saldoPendiente,
    moneda: 'MXN',
    estatus: estatus,
    fechaVencimiento: fechaVencimiento,
  );
}

/// Fakes triviales para `ObtenerActividadRecienteUseCase` — solo se
/// prueba aquí la guardia por permiso (qué se consulta y qué no),
/// nunca el contenido real de cada repositorio (ya cubierto en sus
/// propias etapas).
class _CompraRepositoryVacio implements CompraRepository {
  var listarLlamado = false;
  @override
  Future<List<CompraData>> listar({DateTime? desde, DateTime? hasta, String? folio, String? proveedor, String? articuloId, String? estatus, String? formaPago}) async {
    listarLlamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('ObtenerEmpleadosBajaConPendienteUseCase', () {
    late AppDatabase db;
    late EmpleadoRepository empleadoRepo;
    late AsignacionRepository asignacionRepo;
    late ArticuloRepository articuloRepo;
    late InventarioRepository inventarioRepo;
    late CrearArticuloUseCase crearArticulo;
    late CrearAsignacionUseCase crearAsignacion;
    late RegistrarEntradaUseCase registrarEntrada;
    late ObtenerEmpleadosBajaConPendienteUseCase obtenerEmpleadosBajaConPendiente;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      asignacionRepo = AsignacionRepositoryImpl(db);
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      articuloRepo = ArticuloRepositoryImpl(db);
      inventarioRepo = InventarioRepositoryImpl(db);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
      crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
      crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
      registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
      obtenerEmpleadosBajaConPendiente = ObtenerEmpleadosBajaConPendienteUseCase(empleadoRepo, asignacionRepo);
      addTearDown(db.close);
      // ignore: unused_local_variable, discard_returned_futures
      crearCategoria;
    });

    Future<EmpleadoData> crearEmpleadoDirecto({required String estatus, int n = 1}) {
      return db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: n,
              nombres: 'Empleado$n',
              apellidoPaterno: 'Prueba',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ90010${n}HDFXXX0$n',
              rfc: 'PEXJ90010${n}AB$n',
              nss: '123456789$n',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 1,
              estatus: Value(estatus),
              fechaBaja: estatus == 'baja' ? Value(DateTime(2026, 1, 1)) : const Value.absent(),
              motivoBaja: estatus == 'baja' ? const Value('renuncia') : const Value.absent(),
            ),
          );
    }

    Future<String> crearArticuloDePrueba() async {
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final categoria = await categoriaRepo.crear(nombre: 'Categoria de prueba');
      final resultado = await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: 'Radio', manejaVariante: false, manejaSerie: false);
      final articuloId = (resultado as CrearArticuloExitoso).articulo.id;
      await registrarEntrada.ejecutar(articuloId: articuloId, cantidad: 5, fecha: DateTime(2025, 1, 1));
      return articuloId;
    }

    test('empleado de baja con Asignacion activa aparece en la alerta', () async {
      final empleado = await crearEmpleadoDirecto(estatus: 'baja', n: 1);
      final articuloId = await crearArticuloDePrueba();
      await crearAsignacion.ejecutar(
        articuloId: articuloId,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2025, 6, 1),
      );

      final resultado = await obtenerEmpleadosBajaConPendiente.ejecutar();

      expect(resultado, hasLength(1));
      expect(resultado.single.empleado.id, empleado.id);
      expect(resultado.single.cantidadAsignaciones, 1);
    });

    test('empleado de baja SIN Asignacion activa no aparece', () async {
      await crearEmpleadoDirecto(estatus: 'baja', n: 2);

      final resultado = await obtenerEmpleadosBajaConPendiente.ejecutar();

      expect(resultado, isEmpty);
    });

    test('empleado activo con Asignacion no aparece (solo bajas)', () async {
      final empleado = await crearEmpleadoDirecto(estatus: 'activo', n: 3);
      final articuloId = await crearArticuloDePrueba();
      await crearAsignacion.ejecutar(
        articuloId: articuloId,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2025, 6, 1),
      );

      final resultado = await obtenerEmpleadosBajaConPendiente.ejecutar();

      expect(resultado, isEmpty);
    });
  });

  group('ObtenerAlertasDashboardUseCase — CxC vencida', () {
    test('cuenta cuentas vencidas (rango != alCorriente) y suma su saldo, excluye alCorriente y pagadas', () async {
      final repo = _CuentaPorCobrarRepositoryDePrueba([
        _cuentaDePrueba(id: 'vencida-30', saldoPendiente: 10000, fechaVencimiento: DateTime(2025, 12, 15)), // vencida
        _cuentaDePrueba(id: 'al-corriente', saldoPendiente: 5000, fechaVencimiento: DateTime(2026, 2, 1)), // futura, no vencida
        _cuentaDePrueba(id: 'sin-vencimiento', saldoPendiente: 7000, fechaVencimiento: null), // nunca vencida
        _cuentaDePrueba(id: 'pagada-vencida', saldoPendiente: 0, fechaVencimiento: DateTime(2025, 1, 1), estatus: 'pagada'),
      ]);

      // ObtenerAlertasDashboardUseCase compone CxC + empleados-baja-pendiente;
      // aquí solo se ejercita la sección CxC (incluirEmpleadosBajaConPendiente: false).
      final useCase = ObtenerAlertasDashboardUseCase(
        repo,
        ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
        _DeudaRepoVacio(),
        ObtenerNotificacionesDocumentosPorEmitirUseCase(_DocumentoPorEmitirRepoVacio(), _ClienteRepoVacio()),
      );

      final alertas = await useCase.ejecutar(
        incluirCxC: true,
        incluirEmpleadosBajaConPendiente: false,
        incluirTarjetas: false,
        incluirDocumentosPorEmitir: false,
        hoy: DateTime(2026, 1, 15),
      );

      expect(alertas.cxcVencida!.cantidadCuentas, 1);
      expect(alertas.cxcVencida!.montoTotal, 10000);
      expect(alertas.empleadosBajaConPendiente, isNull);
    });

    test('incluirCxC: false nunca consulta el repositorio (guardia real, no cosmética)', () async {
      final repo = _CuentaPorCobrarRepositoryConBandera();
      final useCase = ObtenerAlertasDashboardUseCase(
        repo,
        ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
        _DeudaRepoVacio(),
        ObtenerNotificacionesDocumentosPorEmitirUseCase(_DocumentoPorEmitirRepoVacio(), _ClienteRepoVacio()),
      );

      final alertas = await useCase.ejecutar(
        incluirCxC: false,
        incluirEmpleadosBajaConPendiente: false,
        incluirTarjetas: false,
        incluirDocumentosPorEmitir: false,
      );

      expect(alertas.cxcVencida, isNull);
      expect(repo.listarLlamado, isFalse);
    });

    test('Etapa 19B: tarjeta con utilización >= 80% aparece en alerta', () async {
      final repo = _CuentaPorCobrarRepositoryDePrueba(const []);
      final useCase = ObtenerAlertasDashboardUseCase(
        repo,
        ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
        _DeudaRepoConTarjetas([_tarjetaDePrueba(id: 'alta', saldoActual: 8000000, tarjetaLimiteCredito: 10000000)]),
        ObtenerNotificacionesDocumentosPorEmitirUseCase(_DocumentoPorEmitirRepoVacio(), _ClienteRepoVacio()),
      );

      final alertas = await useCase.ejecutar(
        incluirCxC: false,
        incluirEmpleadosBajaConPendiente: false,
        incluirTarjetas: true,
        incluirDocumentosPorEmitir: false,
        hoy: DateTime(2026, 1, 15),
      );

      expect(alertas.tarjetasEnAlerta, hasLength(1));
      expect(alertas.tarjetasEnAlerta!.single.utilizacion, 80);
    });

    test('Etapa 19B: tarjeta con pago venciendo en <= 7 días aparece en alerta aunque la utilización sea baja', () async {
      final repo = _CuentaPorCobrarRepositoryDePrueba(const []);
      final useCase = ObtenerAlertasDashboardUseCase(
        repo,
        ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
        _DeudaRepoConTarjetas([
          _tarjetaDePrueba(id: 'pago-proximo', saldoActual: 100000, tarjetaLimiteCredito: 10000000, tarjetaDiaPago: 20),
        ]),
        ObtenerNotificacionesDocumentosPorEmitirUseCase(_DocumentoPorEmitirRepoVacio(), _ClienteRepoVacio()),
      );

      final alertas = await useCase.ejecutar(
        incluirCxC: false,
        incluirEmpleadosBajaConPendiente: false,
        incluirTarjetas: true,
        incluirDocumentosPorEmitir: false,
        hoy: DateTime(2026, 1, 15),
      );

      expect(alertas.tarjetasEnAlerta, hasLength(1));
    });

    test('Etapa 19B: tarjeta con utilización baja y sin pago próximo NO aparece', () async {
      final repo = _CuentaPorCobrarRepositoryDePrueba(const []);
      final useCase = ObtenerAlertasDashboardUseCase(
        repo,
        ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
        _DeudaRepoConTarjetas([
          _tarjetaDePrueba(id: 'sana', saldoActual: 100000, tarjetaLimiteCredito: 10000000, tarjetaDiaPago: 1),
        ]),
        ObtenerNotificacionesDocumentosPorEmitirUseCase(_DocumentoPorEmitirRepoVacio(), _ClienteRepoVacio()),
      );

      final alertas = await useCase.ejecutar(
        incluirCxC: false,
        incluirEmpleadosBajaConPendiente: false,
        incluirTarjetas: true,
        incluirDocumentosPorEmitir: false,
        hoy: DateTime(2026, 1, 15),
      );

      expect(alertas.tarjetasEnAlerta, isEmpty);
    });

    test('Etapa 19B: tarjeta en saldo 0 nunca aparece en alerta, sin importar la fecha de pago', () async {
      final repo = _CuentaPorCobrarRepositoryDePrueba(const []);
      final useCase = ObtenerAlertasDashboardUseCase(
        repo,
        ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
        _DeudaRepoConTarjetas([_tarjetaDePrueba(id: 'saldada', saldoActual: 0, tarjetaLimiteCredito: 10000000, tarjetaDiaPago: 15)]),
        ObtenerNotificacionesDocumentosPorEmitirUseCase(_DocumentoPorEmitirRepoVacio(), _ClienteRepoVacio()),
      );

      final alertas = await useCase.ejecutar(
        incluirCxC: false,
        incluirEmpleadosBajaConPendiente: false,
        incluirTarjetas: true,
        incluirDocumentosPorEmitir: false,
        hoy: DateTime(2026, 1, 15),
      );

      expect(alertas.tarjetasEnAlerta, isEmpty);
    });

    test(
      'Etapa "Dashboard: posición financiera": un ciclo cubierto viejo con ciclos saltados marca la tarjeta '
      'como vencida, con proximaFechaPago expuesta',
      () async {
        final repo = _CuentaPorCobrarRepositoryDePrueba(const []);
        final useCase = ObtenerAlertasDashboardUseCase(
          repo,
          ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
          _DeudaRepoConTarjetas([
            _tarjetaDePrueba(
              id: 'vencida',
              saldoActual: 100000,
              tarjetaLimiteCredito: 10000000,
              tarjetaDiaPago: 10,
              tarjetaVencimientoCubiertoHasta: DateTime(2025, 1, 10),
            ),
          ]),
          ObtenerNotificacionesDocumentosPorEmitirUseCase(_DocumentoPorEmitirRepoVacio(), _ClienteRepoVacio()),
        );

        final alertas = await useCase.ejecutar(
          incluirCxC: false,
          incluirEmpleadosBajaConPendiente: false,
          incluirTarjetas: true,
          incluirDocumentosPorEmitir: false,
          hoy: DateTime(2026, 1, 15),
        );

        expect(alertas.tarjetasEnAlerta, hasLength(1));
        final alerta = alertas.tarjetasEnAlerta!.single;
        expect(alerta.vencida, isTrue, reason: 'antes de tarjetaVencimientoCubiertoHasta esto era estructuralmente imposible');
        expect(alerta.proximaFechaPago, DateTime(2025, 2, 10));
        expect(alerta.diasParaPago, isNotNull);
        expect(alerta.diasParaPago! < 0, isTrue);
      },
    );

    test('una tarjeta sin conciliar (tarjetaVencimientoCubiertoHasta null) nunca aparece como vencida', () async {
      final repo = _CuentaPorCobrarRepositoryDePrueba(const []);
      final useCase = ObtenerAlertasDashboardUseCase(
        repo,
        ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
        _DeudaRepoConTarjetas([
          _tarjetaDePrueba(id: 'pago-proximo', saldoActual: 100000, tarjetaLimiteCredito: 10000000, tarjetaDiaPago: 20),
        ]),
        ObtenerNotificacionesDocumentosPorEmitirUseCase(_DocumentoPorEmitirRepoVacio(), _ClienteRepoVacio()),
      );

      final alertas = await useCase.ejecutar(
        incluirCxC: false,
        incluirEmpleadosBajaConPendiente: false,
        incluirTarjetas: true,
        incluirDocumentosPorEmitir: false,
        hoy: DateTime(2026, 1, 15),
      );

      expect(alertas.tarjetasEnAlerta, hasLength(1));
      expect(alertas.tarjetasEnAlerta!.single.vencida, isFalse);
    });
  });

  group('ObtenerCreditoDisponibleTarjetasUseCase', () {
    test('sin ninguna TDC activa: hayTarjetas false, nunca "\$0.00" disfrazado', () async {
      final useCase = ObtenerCreditoDisponibleTarjetasUseCase(_DeudaRepoVacio());
      final resultado = await useCase.ejecutar();
      expect(resultado.hayTarjetas, isFalse);
      expect(resultado.totalDisponible, 0);
    });

    test('suma el disponible de todas las TDC activas — misma fórmula que el listado de Deudas y crédito', () async {
      final useCase = ObtenerCreditoDisponibleTarjetasUseCase(_DeudaRepoConTarjetas([
        _tarjetaDePrueba(id: 'konfio', saldoActual: 3000000, tarjetaLimiteCredito: 4000000), // disponible $10,000
        _tarjetaDePrueba(id: 'clara', saldoActual: 500000, tarjetaLimiteCredito: 2000000), // disponible $15,000
      ]));

      final resultado = await useCase.ejecutar();
      expect(resultado.hayTarjetas, isTrue);
      expect(resultado.totalDisponible, 2500000, reason: r'$10,000 + $15,000 = $25,000');
    });

    test(r'una tarjeta sin límite capturado se excluye de la suma — nunca se asume $0 de disponible', () async {
      final useCase = ObtenerCreditoDisponibleTarjetasUseCase(_DeudaRepoConTarjetas([
        _tarjetaDePrueba(id: 'konfio', saldoActual: 3000000, tarjetaLimiteCredito: 4000000), // disponible $10,000
        _tarjetaDePrueba(id: 'sin-limite', saldoActual: 500000, tarjetaLimiteCredito: null),
      ]));

      final resultado = await useCase.ejecutar();
      expect(resultado.hayTarjetas, isTrue);
      expect(resultado.totalDisponible, 1000000, reason: 'la tarjeta sin límite se excluye — nunca resta como si su disponible fuera 0');
    });
  });

  group('ObtenerActividadRecienteUseCase — guardia por permiso', () {
    test('incluirCompras: false nunca invoca CompraRepository.listar', () async {
      final compraRepo = _CompraRepositoryVacio();
      final useCase = ObtenerActividadRecienteUseCase(
        compraRepo,
        _PagoRepoVacio(),
        _ClienteRepoVacio(),
        _InventarioRepoVacio(),
        _ArticuloRepoVacio(),
        _RecargaRepoVacio(),
        _LineaTelefonicaRepoVacio(),
        _VacanteOperativaRepoVacio(),
        _ServicioRepoVacio(),
      );

      final actividad = await useCase.ejecutar(
        incluirCompras: false,
        incluirPagos: false,
        incluirInventario: false,
        incluirTelefonia: false,
        incluirComercial: false,
      );

      expect(actividad.comprasRecientes, isNull);
      expect(actividad.pagosRecientes, isNull);
      expect(actividad.movimientosRecientes, isNull);
      expect(actividad.recargasRecientes, isNull);
      expect(compraRepo.listarLlamado, isFalse);
    });
  });

  group('ObtenerResumenCobranzaUseCase — escenario 9 (Parte V) e invariante de exclusividad (Parte U)', () {
    test('clasifica pagada/vencida/próxima/en proceso sin traslape y sin perder ninguna cuenta', () async {
      final hoy = DateTime(2026, 3, 1);
      final pagada = _cuentaDePrueba(id: 'pagada', saldoPendiente: 0, importeEmitido: 500000, estatus: 'pagada');
      final vencida = _cuentaDePrueba(id: 'vencida', saldoPendiente: 250000, fechaVencimiento: DateTime(2026, 2, 20));
      final proxima = _cuentaDePrueba(id: 'proxima', saldoPendiente: 100000, fechaVencimiento: DateTime(2026, 3, 5));
      final enProceso = _cuentaDePrueba(id: 'proceso', saldoPendiente: 75000, fechaVencimiento: DateTime(2026, 4, 1));

      final repo = _CuentaPorCobrarRepositoryDePrueba([pagada, vencida, proxima, enProceso]);
      final useCase = ObtenerResumenCobranzaUseCase(repo);

      final resumen = await useCase.ejecutar(hoy: hoy);

      expect(resumen.pagado.cantidad, 1);
      expect(resumen.pagado.importe, 500000);
      expect(resumen.vencido.cantidad, 1);
      expect(resumen.vencido.importe, 250000);
      expect(resumen.proximoAVencer.cantidad, 1);
      expect(resumen.proximoAVencer.importe, 100000);
      expect(resumen.enProceso.cantidad, 1);
      expect(resumen.enProceso.importe, 75000);

      // Invariante (Parte U): ninguna cuenta cuenta dos veces ni se
      // pierde — la suma de las 4 categorías es exactamente el total.
      final totalClasificado =
          resumen.pagado.cantidad + resumen.vencido.cantidad + resumen.proximoAVencer.cantidad + resumen.enProceso.cantidad;
      expect(totalClasificado, 4);

      // Invariante (Parte U): "por cobrar" nunca incluye lo ya pagado.
      expect(resumen.totalPorCobrar, 250000 + 100000 + 75000);

      expect(resumen.documentosVencidos.single.diasVencido, 9);
    });
  });

  group('ObtenerProximaNominaUseCase — escenario 10 (Parte V)', () {
    test('una Nómina pagada y una cerrada pendiente → solo se muestra la pendiente, nunca la pagada', () async {
      final pagada = _nominaDePrueba(id: 'n-pagada', estatus: 'pagada', fechaPagoOrdinaria: DateTime(2026, 2, 5), folio: 'NOM-000001');
      final pendiente =
          _nominaDePrueba(id: 'n-pendiente', estatus: 'cerrada', fechaPagoOrdinaria: DateTime(2026, 2, 20), folio: 'NOM-000002');
      final repo = _NominaRepoDePrueba([pagada, pendiente]);
      final useCase = ObtenerProximaNominaUseCase(repo);

      final proxima = await useCase.ejecutar();

      expect(proxima, isNotNull);
      expect(proxima!.id, 'n-pendiente');
      expect(proxima.estatus, 'cerrada');
    });

    test('dos Nóminas cerradas pendientes → se muestra la de fecha de pago más próxima', () async {
      final lejana = _nominaDePrueba(id: 'n-lejana', estatus: 'cerrada', fechaPagoOrdinaria: DateTime(2026, 3, 5), folio: 'NOM-000003');
      final cercana = _nominaDePrueba(id: 'n-cercana', estatus: 'cerrada', fechaPagoOrdinaria: DateTime(2026, 2, 20), folio: 'NOM-000004');
      final repo = _NominaRepoDePrueba([lejana, cercana]);
      final useCase = ObtenerProximaNominaUseCase(repo);

      final proxima = await useCase.ejecutar();
      expect(proxima!.id, 'n-cercana');
    });

    test('sin ninguna Nómina cerrada → null ("Sin nómina pendiente")', () async {
      final pagada = _nominaDePrueba(id: 'n-pagada', estatus: 'pagada', fechaPagoOrdinaria: DateTime(2026, 2, 5));
      final repo = _NominaRepoDePrueba([pagada]);
      final useCase = ObtenerProximaNominaUseCase(repo);

      expect(await useCase.ejecutar(), isNull);
    });
  });
}

NominaData _nominaDePrueba({
  required String id,
  required String estatus,
  required DateTime fechaPagoOrdinaria,
  String folio = 'NOM-000001',
}) {
  final ahora = DateTime(2026, 1, 1);
  return NominaData(
    id: id,
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    folio: folio,
    anio: 2026,
    mes: 2,
    tipoPeriodo: 'segunda',
    fechaInicioPeriodo: DateTime(2026, 2, 16),
    fechaFinPeriodo: DateTime(2026, 2, 28),
    fechaPagoOrdinaria: fechaPagoOrdinaria,
    estatus: estatus,
    fechaCierre: estatus == 'pagada' || estatus == 'cerrada' ? ahora : null,
    observaciones: null,
  );
}

class _NominaRepoDePrueba implements NominaRepository {
  _NominaRepoDePrueba(this.nominas);
  final List<NominaData> nominas;

  @override
  Future<List<NominaData>> listarEnRango({DateTime? rangoInicio, DateTime? rangoFin, String? estatus}) async {
    if (estatus == null) return nominas;
    return nominas.where((n) => n.estatus == estatus).toList();
  }

  @override
  Future<List<NominaEmpleadoData>> listarEmpleados(String nominaId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _EmpleadoRepoVacio implements EmpleadoRepository {
  @override
  Future<List<EmpleadoReporteRow>> listarParaReporte({String? estatus}) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _AsignacionRepoVacio implements AsignacionRepository {
  @override
  Future<List<AsignacionData>> listarTodasActivas() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _DeudaRepoVacio implements DeudaRepository {
  @override
  Future<List<DeudaData>> listarTarjetasActivas() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _DeudaRepoConTarjetas implements DeudaRepository {
  _DeudaRepoConTarjetas(this.tarjetas);
  final List<DeudaData> tarjetas;
  @override
  Future<List<DeudaData>> listarTarjetasActivas() async => tarjetas;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

DeudaData _tarjetaDePrueba({
  required String id,
  required int saldoActual,
  int? tarjetaLimiteCredito,
  int? tarjetaDiaPago,
  DateTime? tarjetaVencimientoCubiertoHasta,
}) {
  final ahora = DateTime(2026, 1, 1);
  return DeudaData(
    id: id,
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    folio: 'DEU-$id',
    nombre: 'Tarjeta $id',
    tipo: 'tarjetaCredito',
    fechaOrigen: ahora,
    importeOriginal: saldoActual,
    saldoActual: saldoActual,
    estatus: 'activa',
    tarjetaLimiteCredito: tarjetaLimiteCredito,
    tarjetaDiaPago: tarjetaDiaPago,
    // Regla explícita (Etapa "corrección Próximo vencimiento TDC") —
    // `proximaFechaPagoDeuda` ya no infiere "día fijo" de la sola
    // presencia de `tarjetaDiaPago`, mismo criterio que una fila real
    // capturada por el diálogo actual (que siempre fija la regla).
    tarjetaReglaFechaPago: tarjetaDiaPago == null ? null : 'diaFijo',
    tarjetaVencimientoCubiertoHasta: tarjetaVencimientoCubiertoHasta,
  );
}

class _CuentaPorCobrarRepositoryConBandera implements CuentaPorCobrarRepository {

  @override
  Future<CuentaPorCobrarData> crearDeServicioEventual({
    required String servicioEventualId,
    String? clienteId,
    required String tipoDocumento,
    required String metodo,
    required bool requiereComplemento,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    DateTime? fechaVencimiento,
    String? observaciones,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CuentaPorCobrarData?> obtenerPorServicioEventualId(String servicioEventualId) =>
      throw UnimplementedError();
  @override
  Future<Map<String, CuentaPorCobrarData>> porServiciosEventuales(Iterable<String> servicioEventualIds) =>
      throw UnimplementedError();


  @override
  Future<CuentaPorCobrarData> sincronizarConDocumentoFiscal({
    required String cuentaPorCobrarId,
    String? folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required String metodo,
    required bool requiereComplemento,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CuentaPorCobrarData> corregirImporte({
    required String cuentaPorCobrarId,
    required int importeEmitido,
    required String motivo,
    String? actorUsuarioId,
  }) =>
      throw UnimplementedError();

  var listarLlamado = false;
  @override
  Future<List<CuentaPorCobrarData>> listar({
    String? clienteId,
    String? servicioId,
    String? entidadFiscalId,
    String? tipoDocumento,
    String? estatus,
    String? documentoPorEmitirId,
    String? servicioEventualId,
  }) async {
    listarLlamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _PagoRepoVacio implements PagoRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ClienteRepoVacio implements ClienteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _DocumentoPorEmitirRepoVacio implements DocumentoPorEmitirRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _InventarioRepoVacio implements InventarioRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ArticuloRepoVacio implements ArticuloRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _RecargaRepoVacio implements RecargaLineaTelefonicaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _LineaTelefonicaRepoVacio implements LineaTelefonicaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _VacanteOperativaRepoVacio implements VacanteOperativaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ServicioRepoVacio implements ServicioRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
