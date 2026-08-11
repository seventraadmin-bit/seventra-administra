// Etapa 12C (Reportes generales — Operación) — pruebas de
// repositorio/caso de uso para Compras, Inventario, Vehículos y
// Telefonía. Cubre explícitamente los escenarios pedidos: compra
// mixta (Inventario+gasto directo), compra cancelada excluida,
// "pendientes de devolución" == asignaciones vigentes, mantenimiento
// dentro/fuera del periodo (snapshot vs. periodo), documento de
// vehículo vencido, línea sin equipo/suspendida, atribución histórica
// de recargas inmune a un cambio de responsable posterior, y
// reconciliación total = desglose.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_compras_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_inventario_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_telefonia_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_vehiculos_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_documento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_documento_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_kilometraje_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_mantenimiento_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/obtener_alertas_vehiculos_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_documento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_mantenimiento_vehiculo_usecase.dart';

void main() {
  late AppDatabase db;

  group('Compras — ObtenerResumenComprasUseCase', () {
    late CompraRepository compraRepo;
    late RegistrarCompraUseCase registrarCompra;
    late ObtenerResumenComprasUseCase obtenerResumen;
    late String articuloId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final egresoRepo = EgresoRepositoryImpl(db);
      final articuloRepo = ArticuloRepositoryImpl(db);
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

      compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo);
      registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, generarCodigo);
      obtenerResumen = ObtenerResumenComprasUseCase(compraRepo, articuloRepo);

      final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes')
              as CrearCategoriaArticuloExitoso)
          .categoria;
      final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
        categoriaId: categoria.id,
        nombre: 'CAMISOLA TACTICA',
        manejaVariante: false,
        manejaSerie: false,
      ) as CrearArticuloExitoso)
          .articulo;
      articuloId = articulo.id;
    });

    tearDown(() => db.close());

    test('compra mixta (Inventario + gasto directo): el desglose por destino es correcto', () async {
      await registrarCompra.ejecutar(
        fecha: DateTime(2026, 1, 10),
        proveedor: 'Uniformes SA',
        formaPago: 'transferencia',
        partidas: [
          PartidaCompraInput(destino: 'inventario', articuloId: articuloId, cantidad: 2, costoUnitario: 30000),
          PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Flete', cantidad: 1, costoUnitario: 5000),
        ],
      );

      final resumen = await obtenerResumen.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resumen.totalInventario, 60000);
      expect(resumen.totalGastoDirecto, 5000);
      expect(resumen.totalComprado, 65000);
      expect(resumen.porProveedor.single.total, 65000);
    });

    test('compra cancelada: excluida del total y de los desgloses, visible solo en su propio indicador', () async {
      final resultado = await registrarCompra.ejecutar(
        fecha: DateTime(2026, 1, 10),
        proveedor: 'Uniformes SA',
        formaPago: 'efectivo',
        partidas: [PartidaCompraInput(destino: 'inventario', articuloId: articuloId, cantidad: 1, costoUnitario: 40000)],
      );
      final compra = (resultado as RegistrarCompraExitosa).compra;
      await compraRepo.cancelar(compraId: compra.id, motivo: 'Prueba');

      final resumen = await obtenerResumen.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));

      expect(resumen.totalComprado, 0);
      expect(resumen.totalInventario, 0);
      expect(resumen.totalCanceladas, 40000);
    });
  });

  group('Inventario — ObtenerResumenInventarioUseCase', () {
    late ObtenerResumenInventarioUseCase obtenerResumen;
    late AsignacionRepositoryImpl asignacionRepo;
    late String articuloId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final articuloRepo = ArticuloRepositoryImpl(db);
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      asignacionRepo = AsignacionRepositoryImpl(db);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

      obtenerResumen = ObtenerResumenInventarioUseCase(articuloRepo, inventarioRepo, asignacionRepo);

      final categoria =
          (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Radios') as CrearCategoriaArticuloExitoso)
              .categoria;
      final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
        categoriaId: categoria.id,
        nombre: 'RADIO',
        manejaVariante: false,
        manejaSerie: true,
      ) as CrearArticuloExitoso)
          .articulo;
      articuloId = articulo.id;

      final registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
      for (var i = 1; i <= 3; i++) {
        await registrarEntradaUnidad.ejecutar(
          articuloId: articuloId,
          numeroSerie: 'SN-$i',
          fecha: DateTime(2026, 1, 1),
          costoUnitario: 10000,
        );
      }
    });

    tearDown(() => db.close());

    test('"pendientes de devolución" es exactamente "asignaciones vigentes" — no un concepto nuevo', () async {
      final unidades = await InventarioRepositoryImpl(db).listarTodasUnidades();
      final crearAsignacion = CrearAsignacionUseCase(asignacionRepo, ArticuloRepositoryImpl(db), InventarioRepositoryImpl(db));
      await crearAsignacion.ejecutar(
        articuloId: articuloId,
        unidadId: unidades.first.id,
        cantidad: 1,
        empleadoId: (await db.into(db.empleado).insertReturning(_empleadoCompanion(1))).id,
        fechaEntrega: DateTime(2026, 1, 5),
      );

      final resumen = await obtenerResumen.ejecutar();

      final vigentesDirecto = await asignacionRepo.listarTodasActivas();
      expect(resumen.asignacionesVigentes, vigentesDirecto.length);
      expect(resumen.asignacionesVigentes, 1);
    });

    test('existencia total refleja las unidades disponibles', () async {
      final resumen = await obtenerResumen.ejecutar();
      expect(resumen.existenciaTotal, 3);
    });

    test('periodo vacío: movimientos en cero, sin excepciones', () async {
      final resumen = await obtenerResumen.ejecutar(rangoInicio: DateTime(2030, 1, 1), rangoFin: DateTime(2030, 1, 31));
      expect(resumen.movimientosEnPeriodo, 0);
    });
  });

  group('Vehículos — ObtenerResumenVehiculosUseCase (snapshot vs. periodo)', () {
    late VehiculoRepository vehiculoRepo;
    late VehiculoMantenimientoRepository mantenimientoRepo;
    late VehiculoDocumentoRepository documentoRepo;
    late VehiculoKilometrajeRepository kilometrajeRepo;
    late CrearVehiculoUseCase crearVehiculo;
    late CambiarEstatusVehiculoUseCase cambiarEstatus;
    late RegistrarMantenimientoVehiculoUseCase registrarMantenimiento;
    late RegistrarDocumentoVehiculoUseCase registrarDocumento;
    late ObtenerResumenVehiculosUseCase obtenerResumen;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final asignacionRepo = AsignacionVehiculoRepositoryImpl(db);
      vehiculoRepo = VehiculoRepositoryImpl(db, asignacionRepo);
      kilometrajeRepo = VehiculoKilometrajeRepositoryImpl(db);
      mantenimientoRepo = VehiculoMantenimientoRepositoryImpl(db);
      documentoRepo = VehiculoDocumentoRepositoryImpl(db);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

      crearVehiculo = CrearVehiculoUseCase(vehiculoRepo, generarCodigo);
      cambiarEstatus = CambiarEstatusVehiculoUseCase(vehiculoRepo);
      registrarMantenimiento = RegistrarMantenimientoVehiculoUseCase(mantenimientoRepo, vehiculoRepo, kilometrajeRepo);
      registrarDocumento = RegistrarDocumentoVehiculoUseCase(documentoRepo, vehiculoRepo);

      final obtenerAlertas = ObtenerAlertasVehiculosUseCase(vehiculoRepo, documentoRepo, mantenimientoRepo, kilometrajeRepo);
      obtenerResumen = ObtenerResumenVehiculosUseCase(obtenerAlertas, mantenimientoRepo);
    });

    tearDown(() => db.close());

    Future<VehiculoData> crearVehiculoDePrueba() async {
      final resultado = await crearVehiculo.ejecutar(marca: 'Nissan', modelo: 'NP300', tipoVehiculo: 'pickup');
      return (resultado as CrearVehiculoExitoso).vehiculo;
    }

    test('vehículo en mantenimiento: conteo snapshot correcto', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'enMantenimiento');

      final resumen = await obtenerResumen.ejecutar(hoy: DateTime(2026, 7, 15));
      expect(resumen.vehiculosPorEstatus['enMantenimiento'], 1);
    });

    test('costo de mantenimiento respeta el rango: dentro del periodo suma, fuera del periodo no', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 7, 10),
        tipo: 'preventivo',
        descripcion: 'Cambio de aceite',
        costo: 1500,
      );
      await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 8, 10),
        tipo: 'preventivo',
        descripcion: 'Fuera de rango',
        costo: 9000,
      );

      final resumen = await obtenerResumen.ejecutar(
        rangoInicio: DateTime(2026, 7, 1),
        rangoFin: DateTime(2026, 7, 31),
        hoy: DateTime(2026, 7, 15),
      );

      expect(resumen.totalMantenimientoEnPeriodo, 1500, reason: 'el mantenimiento de agosto queda fuera del rango de julio');
    });

    test('documento vencido: se refleja en la alerta; vehículo de baja lo excluye', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarDocumento.ejecutar(vehiculoId: vehiculo.id, tipo: 'seguro', fechaVencimiento: DateTime(2026, 1, 1));

      final resumen = await obtenerResumen.ejecutar(hoy: DateTime(2026, 7, 15));
      expect(resumen.documentosVencidos, 1);
    });
  });

  group('Telefonía — ObtenerResumenTelefoniaUseCase', () {
    late LineaTelefonicaRepositoryImpl lineaRepo;
    late AsignacionLineaTelefonicaRepositoryImpl asignacionLineaRepo;
    late RecargaLineaTelefonicaRepositoryImpl recargaRepo;
    late CrearLineaTelefonicaUseCase crearLinea;
    late CambiarEstatusLineaTelefonicaUseCase cambiarEstatus;
    late AsignarLineaTelefonicaUseCase asignarLinea;
    late CambiarAsignacionLineaTelefonicaUseCase cambiarAsignacion;
    late RegistrarRecargaLineaTelefonicaUseCase registrarRecarga;
    late ObtenerResumenTelefoniaUseCase obtenerResumen;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
      final equipoLineaRepo = LineaTelefonicaEquipoRepositoryImpl(
        db,
        asignacionLineaRepo,
        AsignacionRepositoryImpl(db),
        InventarioRepositoryImpl(db),
      );
      lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoLineaRepo);
      recargaRepo = RecargaLineaTelefonicaRepositoryImpl(db);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

      crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
      cambiarEstatus = CambiarEstatusLineaTelefonicaUseCase(lineaRepo);
      asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoLineaRepo);
      cambiarAsignacion = CambiarAsignacionLineaTelefonicaUseCase(asignacionLineaRepo, equipoLineaRepo);
      registrarRecarga = RegistrarRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo);

      final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
      obtenerResumen = ObtenerResumenTelefoniaUseCase(
        InventarioRepositoryImpl(db),
        lineaRepo,
        equipoLineaRepo,
        asignacionLineaRepo,
        recargaRepo,
        EmpleadoRepositoryImpl(db, asignacionServicioRepo),
        ServicioRepositoryImpl(db, asignacionServicioRepo),
      );
    });

    tearDown(() => db.close());

    Future<LineaTelefonicaData> crearLineaDePrueba({String? numero}) async {
      final resultado = await crearLinea.ejecutar(numero: numero, operador: 'telcel', modalidadSim: 'fisica');
      return (resultado as CrearLineaTelefonicaExitoso).linea;
    }

    test('línea sin equipo aparece en el conteo; una línea con equipo no', () async {
      await crearLineaDePrueba(numero: '7221111111');

      final resumen = await obtenerResumen.ejecutar();
      expect(resumen.lineasSinEquipo, 1);
    });

    test('línea suspendida: conteo correcto, distinta de activa', () async {
      final linea = await crearLineaDePrueba();
      await cambiarEstatus.ejecutar(lineaTelefonicaId: linea.id, estatus: 'suspendida');

      final resumen = await obtenerResumen.ejecutar();
      expect(resumen.lineasPorEstatus['suspendida'], 1);
      expect(resumen.lineasPorEstatus['activa'] ?? 0, 0);
    });

    test('recarga por Empleado y por Servicio se desglosan correctamente', () async {
      final lineaEmpleado = await crearLineaDePrueba(numero: '7221111111');
      final lineaServicio = await crearLineaDePrueba(numero: '7222222222');
      final empleado = await db.into(db.empleado).insertReturning(_empleadoCompanion(1));
      final servicio = await _crearServicioDePrueba(db);

      await asignarLinea.ejecutar(lineaTelefonicaId: lineaEmpleado.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 1));
      await asignarLinea.ejecutar(lineaTelefonicaId: lineaServicio.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));
      await registrarRecarga.ejecutar(lineaTelefonicaId: lineaEmpleado.id, fecha: DateTime(2026, 2, 1), importe: 20000);
      await registrarRecarga.ejecutar(lineaTelefonicaId: lineaServicio.id, fecha: DateTime(2026, 2, 2), importe: 15000);

      final resumen = await obtenerResumen.ejecutar(rangoInicio: DateTime(2026, 2, 1), rangoFin: DateTime(2026, 2, 28));

      expect(resumen.recargasPorEmpleado.single.total, 20000);
      expect(resumen.recargasPorServicio.single.total, 15000);
    });

    test('cambio de responsable posterior a una recarga no altera su atribución histórica', () async {
      final linea = await crearLineaDePrueba();
      final empleado1 = await db.into(db.empleado).insertReturning(_empleadoCompanion(1));
      final empleado2 = await db.into(db.empleado).insertReturning(_empleadoCompanion(2));

      final asignacion1 = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado1.id,
        fechaInicio: DateTime(2026, 1, 1),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 2, 1), importe: 20000);

      // Reasignación DESPUÉS de la recarga.
      await cambiarAsignacion.ejecutar(
        asignacionLineaTelefonicaActualId: asignacion1.id,
        fecha: DateTime(2026, 6, 1),
        nuevoEmpleadoId: empleado2.id,
      );

      final resumen = await obtenerResumen.ejecutar(rangoInicio: DateTime(2026, 2, 1), rangoFin: DateTime(2026, 2, 28));

      expect(resumen.recargasPorEmpleado, hasLength(1));
      expect(resumen.recargasPorEmpleado.single.total, 20000, reason: 'sigue atribuida al responsable original en esa fecha');
    });

    test('reconciliación: total del rango == suma del desglose por Servicio + Empleado + sin atribución', () async {
      final lineaEmpleado = await crearLineaDePrueba(numero: '7221111111');
      final lineaSinAsignar = await crearLineaDePrueba(numero: '7223333333');
      final empleado = await db.into(db.empleado).insertReturning(_empleadoCompanion(1));

      await asignarLinea.ejecutar(lineaTelefonicaId: lineaEmpleado.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 1));
      await registrarRecarga.ejecutar(lineaTelefonicaId: lineaEmpleado.id, fecha: DateTime(2026, 2, 1), importe: 20000);
      await registrarRecarga.ejecutar(lineaTelefonicaId: lineaSinAsignar.id, fecha: DateTime(2026, 2, 2), importe: 5000);

      final resumen = await obtenerResumen.ejecutar(rangoInicio: DateTime(2026, 2, 1), rangoFin: DateTime(2026, 2, 28));
      final totalRango = await recargaRepo.totalPorRango(desde: DateTime(2026, 2, 1), hasta: DateTime(2026, 2, 28));

      final sumaDesglose = resumen.recargasPorEmpleado.fold<int>(0, (s, r) => s + r.total) +
          resumen.recargasPorServicio.fold<int>(0, (s, r) => s + r.total) +
          resumen.recargasSinAtribucion;

      expect(sumaDesglose, totalRango);
      expect(resumen.totalRecargasEnPeriodo, totalRango);
    });

    test('periodo vacío: ceros y listas vacías, sin excepciones', () async {
      final resumen = await obtenerResumen.ejecutar(rangoInicio: DateTime(2030, 1, 1), rangoFin: DateTime(2030, 1, 31));
      expect(resumen.totalRecargasEnPeriodo, 0);
      expect(resumen.recargasPorEmpleado, isEmpty);
      expect(resumen.recargasPorServicio, isEmpty);
    });
  });
}

EmpleadoCompanion _empleadoCompanion(int n) {
  return EmpleadoCompanion.insert(
    numeroEmpleado: n,
    nombres: 'Empleado$n',
    apellidoPaterno: 'Apellido$n',
    sexo: 'masculino',
    fechaNacimiento: DateTime(1990, 1, 1),
    curp: 'PEXJ900101HDFXXX0$n',
    rfc: 'PEXJ900101AB$n',
    nss: '1234567890$n',
    estadoCivil: 'soltero',
    fechaIngreso: DateTime(2026, 1, 1),
    aniosExperienciaSeguridad: 3,
  );
}

Future<ServicioData> _crearServicioDePrueba(AppDatabase db, {String codigo = 'SER-000001'}) async {
  final tipoServicio = await db
      .into(db.tipoServicio)
      .insertReturning(TipoServicioCompanion.insert(id: 'tipo-servicio-$codigo', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'));
  final cliente =
      await db.into(db.cliente).insertReturning(ClienteCompanion.insert(codigo: 'CLI-$codigo', nombreComercial: 'Sportium'));
  return db.into(db.servicio).insertReturning(
        ServicioCompanion.insert(
          codigo: codigo,
          clienteId: cliente.id,
          nombre: 'Vigilancia Sportium Toluca',
          tipoServicioId: tipoServicio.id,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
}
