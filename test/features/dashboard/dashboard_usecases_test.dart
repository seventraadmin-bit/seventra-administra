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
import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';
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
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/recarga_linea_telefonica_repository.dart';

import 'package:riseg_one/features/dashboard/domain/usecases/obtener_actividad_reciente_usecase.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_alertas_dashboard_usecase.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_empleados_baja_con_pendiente_usecase.dart';

/// Solo implementa `listar()` — lo único que `ObtenerAlertasDashboardUseCase`
/// invoca; el resto no aplica a esta prueba de agregación pura.
class _CuentaPorCobrarRepositoryDePrueba implements CuentaPorCobrarRepository {
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
  Future<CuentaPorCobrarData> actualizarFechaVencimiento({
    required String cuentaPorCobrarId,
    required DateTime fechaVencimiento,
    String? motivo,
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
    importeEmitido: saldoPendiente,
    saldoOriginal: saldoPendiente,
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
  Future<List<CompraData>> listar({DateTime? desde, DateTime? hasta, String? folio, String? proveedor, String? articuloId, String? estatus}) async {
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
      );

      final alertas = await useCase.ejecutar(incluirCxC: true, incluirEmpleadosBajaConPendiente: false, hoy: DateTime(2026, 1, 15));

      expect(alertas.cxcVencida!.cantidadCuentas, 1);
      expect(alertas.cxcVencida!.montoTotal, 10000);
      expect(alertas.empleadosBajaConPendiente, isNull);
    });

    test('incluirCxC: false nunca consulta el repositorio (guardia real, no cosmética)', () async {
      final repo = _CuentaPorCobrarRepositoryConBandera();
      final useCase = ObtenerAlertasDashboardUseCase(
        repo,
        ObtenerEmpleadosBajaConPendienteUseCase(_EmpleadoRepoVacio(), _AsignacionRepoVacio()),
      );

      final alertas = await useCase.ejecutar(incluirCxC: false, incluirEmpleadosBajaConPendiente: false);

      expect(alertas.cxcVencida, isNull);
      expect(repo.listarLlamado, isFalse);
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
      );

      final actividad = await useCase.ejecutar(
        incluirCompras: false,
        incluirPagos: false,
        incluirInventario: false,
        incluirTelefonia: false,
      );

      expect(actividad.comprasRecientes, isNull);
      expect(actividad.pagosRecientes, isNull);
      expect(actividad.movimientosRecientes, isNull);
      expect(actividad.recargasRecientes, isNull);
      expect(compraRepo.listarLlamado, isFalse);
    });
  });
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

class _CuentaPorCobrarRepositoryConBandera implements CuentaPorCobrarRepository {
  var listarLlamado = false;
  @override
  Future<List<CuentaPorCobrarData>> listar({
    String? clienteId,
    String? servicioId,
    String? entidadFiscalId,
    String? tipoDocumento,
    String? estatus,
    String? documentoPorEmitirId,
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
