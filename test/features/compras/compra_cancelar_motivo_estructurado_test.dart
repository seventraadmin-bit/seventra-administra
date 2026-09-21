// Etapa 15 — motivo estructurado de cancelación de Compra (bug real
// COM-000021, ver el doc comment de `compra_cancelar_stock_consumido_test.dart`
// para la causa raíz completa). Esta prueba cubre exclusivamente el
// rediseño del motivo: cada valor del enum `MotivoCancelacionCompra` es
// aceptado, `otro` exige `detalle`, la Compra cancelada conserva su
// motivo/detalle/observaciones y el actor de la auditoría, y — el
// requisito explícito de Marlon de "si cualquier parte falla, no debe
// quedar una cancelación parcial" — un fallo real a medio camino de la
// reversión (el Egreso asociado ya no existe) revierte TODO, incluida
// la reversión de Inventario que ya se había aplicado antes de tocar
// el Egreso.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/cancelar_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/existencia_articulo.dart' show ExistenciaInsuficienteException;

void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CancelarCompraUseCase cancelarCompra;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    cancelarCompra = CancelarCompraUseCase(compraRepo);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloDePrueba(String nombre) async {
    final crearCategoria = CrearCategoriaArticuloUseCase(CategoriaArticuloRepositoryImpl(db));
    final categoria = (await crearCategoria.ejecutar(nombre: '$nombre-categoria') as CrearCategoriaArticuloExitoso).categoria;
    final crearArticulo =
        CrearArticuloUseCase(articuloRepo, CategoriaArticuloRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final resultado = await crearArticulo.ejecutar(
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: false,
      manejaSerie: false,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<EmpleadoData> crearEmpleadoDePrueba() {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<CompraData> registrarCompraDeGastoDirecto() async {
    final resultado = await registrarCompra.ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Papelería', cantidad: 1, costoUnitario: 45000),
      ],
    );
    return (resultado as RegistrarCompraExitosa).compra;
  }

  group('cada motivo estructurado', () {
    for (final motivo in MotivoCancelacionCompra.values.where((m) => m != MotivoCancelacionCompra.otro)) {
      test('${motivo.name} es aceptado sin detalle', () async {
        final compra = await registrarCompraDeGastoDirecto();
        final resultado = await cancelarCompra.ejecutar(compraId: compra.id, motivo: motivo, actorUsuarioId: 'usuario-maestro');
        expect(resultado, isA<CancelarCompraExitosa>(), reason: 'motivo ${motivo.name} debe ser válido por sí solo');
        final cancelada = (resultado as CancelarCompraExitosa).compra;
        expect(cancelada.motivoCancelacionCodigo, motivo.name);
        expect(cancelada.motivoCancelacionDetalle, isNull);
      });
    }

    test('otro sin detalle es rechazado, sin modificar la Compra', () async {
      final compra = await registrarCompraDeGastoDirecto();
      final resultado = await cancelarCompra.ejecutar(compraId: compra.id, motivo: MotivoCancelacionCompra.otro);
      expect(resultado, isA<CancelarCompraDetalleRequerido>());

      final sinCambios = await compraRepo.obtenerPorId(compra.id);
      expect(sinCambios!.estatus, 'registrada');
      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.estatus, 'registrado');
    });

    test('otro con detalle es aceptado y conserva detalle + observaciones', () async {
      final compra = await registrarCompraDeGastoDirecto();
      final resultado = await cancelarCompra.ejecutar(
        compraId: compra.id,
        motivo: MotivoCancelacionCompra.otro,
        detalle: 'El proveedor nunca entregó la mercancía',
        observaciones: 'Se le notificó por correo el 10/08/2026',
        actorUsuarioId: 'usuario-maestro',
      );
      expect(resultado, isA<CancelarCompraExitosa>());
      final cancelada = (resultado as CancelarCompraExitosa).compra;
      expect(cancelada.motivoCancelacionCodigo, 'otro');
      expect(cancelada.motivoCancelacionDetalle, 'El proveedor nunca entregó la mercancía');
      expect(cancelada.motivoCancelacionObservaciones, 'Se le notificó por correo el 10/08/2026');
    });
  });

  test('la Compra cancelada conserva su historial completo: estatus, motivo, detalle, observaciones y actor', () async {
    final compra = await registrarCompraDeGastoDirecto();

    await cancelarCompra.ejecutar(
      compraId: compra.id,
      motivo: MotivoCancelacionCompra.proveedorCancelo,
      observaciones: 'Confirmado por teléfono',
      actorUsuarioId: 'usuario-maestro',
    );

    final releida = await compraRepo.obtenerPorId(compra.id);
    expect(releida!.estatus, 'cancelada');
    expect(releida.motivoCancelacionCodigo, MotivoCancelacionCompra.proveedorCancelo.name);
    expect(releida.motivoCancelacionObservaciones, 'Confirmado por teléfono');

    final eventos = await compraRepo.listarEventos(compra.id);
    final eventoCancelacion = eventos.singleWhere((e) => e.tipoEvento == 'cancelada');
    expect(eventoCancelacion.actorUsuarioId, 'usuario-maestro', reason: 'auditoría: quién ejecutó la cancelación');
    expect(eventoCancelacion.observacion, MotivoCancelacionCompra.proveedorCancelo.etiqueta);
  });

  test(
    'un fallo real a medio camino de la reversión (2ª partida ya consumida por una Asignacion, race real entre el '
    'chequeo proactivo y la reversión) revierte TODO, incluida la baja de reversa ya aplicada a la 1ª partida — '
    'nunca una cancelación parcial',
    () async {
      // `CompraRepositoryImpl.cancelar` en sí mismo (a diferencia de
      // `CancelarCompraUseCase`) no vuelve a validar antes de revertir
      // — se llama directo aquí (mismo camino que tomaría una carrera
      // real entre el chequeo proactivo del caso de uso y la reversión
      // efectiva) para probar que la ausencia de ese chequeo en el
      // repositorio no importa: la transacción de Drift sigue
      // revirtiendo TODO ante cualquier fallo real a medio camino.
      final articulo1 = await crearArticuloDePrueba('Chaleco táctico');
      final articulo2 = await crearArticuloDePrueba('Radio portátil');
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo1.id, cantidad: 5, costoUnitario: 40000),
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo2.id, cantidad: 3, costoUnitario: 60000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      // La mercancía de la 2ª partida ya se consumió — se asignó
      // completa a un Empleado, dejando su `disponible` en 0.
      final empleado = await crearEmpleadoDePrueba();
      await asignacionRepo.crear(
        articuloId: articulo2.id,
        cantidad: 3,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      );

      // Acto: llamar al repositorio directo (sin el chequeo proactivo
      // del caso de uso) — la reversión de la 1ª partida se aplica
      // primero, y falla al llegar a la 2ª.
      await expectLater(
        () => compraRepo.cancelar(compraId: creada.id, motivo: MotivoCancelacionCompra.errorDeCaptura.name),
        throwsA(isA<ExistenciaInsuficienteException>()),
      );

      final compraSinCambios = await compraRepo.obtenerPorId(creada.id);
      expect(compraSinCambios!.estatus, 'registrada', reason: 'el fallo a medio camino no debe dejar la Compra cancelada');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.estatus, 'registrado', reason: 'el Egreso tampoco debe quedar cancelado si el resto falló');

      final existencia1 = await inventarioRepo.calcularExistencia(articuloId: articulo1.id);
      expect(existencia1.disponible, 5, reason: 'la baja de reversa de la 1ª partida, ya aplicada, debe deshacerse con el resto');

      final movimientos1 = await inventarioRepo.listarMovimientos(articuloId: articulo1.id);
      expect(movimientos1, hasLength(1), reason: 'solo debe sobrevivir la entrada original de la 1ª partida — ninguna baja huérfana');
      expect(movimientos1.single.tipoMovimiento, 'entrada');
    },
  );

  test(
    'una baja MANUAL (sin ninguna Asignacion) sobre el mismo artículo también bloquea la cancelación — la política '
    'conservadora cubre todo movimiento de salida, no solo Asignacion (verificación explícita de Marlon)',
    () async {
      final articulo = await crearArticuloDePrueba('Guantes tácticos');
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 5, costoUnitario: 20000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      // Baja manual (ej. inventario físico encontró menos piezas) —
      // nunca pasa por Asignacion, solo por RegistrarBajaUseCase.
      await inventarioRepo.registrarBaja(articuloId: articulo.id, cantidad: 2, observaciones: 'Ajuste por conteo físico');

      final resultado = await cancelarCompra.ejecutar(compraId: creada.id, motivo: MotivoCancelacionCompra.errorDeCaptura);

      expect(resultado, isA<CancelarCompraBloqueadaPorArticulosConsumidos>());
      final detalles = (resultado as CancelarCompraBloqueadaPorArticulosConsumidos).detalles;
      expect(detalles.single, contains(articulo.nombre));

      final sinCambios = await compraRepo.obtenerPorId(creada.id);
      expect(sinCambios!.estatus, 'registrada');
      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 3, reason: 'sin cambios adicionales por el bloqueo — solo la baja manual previa');
    },
  );

  test(
    'CompraRepositoryImpl.cancelar es idempotente por sí mismo: un segundo llamado directo sobre una Compra ya '
    'cancelada nunca vuelve a descontar Inventario ni a cancelar el Egreso (defensa en profundidad, más allá del '
    'chequeo de estatus que ya hace CancelarCompraUseCase antes de llegar aquí)',
    () async {
      final articulo = await crearArticuloDePrueba('Botas tácticas');
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articulo.id, cantidad: 4, costoUnitario: 50000),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      // Primera cancelación — llamando al repositorio directo (mismo
      // camino que tomaría cualquier código futuro que no pase por el
      // caso de uso).
      final primera = await compraRepo.cancelar(compraId: creada.id, motivo: MotivoCancelacionCompra.errorDeCaptura.name);
      expect(primera.estatus, 'cancelada');
      final existenciaTrasPrimera = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existenciaTrasPrimera.disponible, 0);
      final movimientosTrasPrimera = await inventarioRepo.listarMovimientos(articuloId: articulo.id);
      expect(movimientosTrasPrimera, hasLength(2), reason: 'una entrada y una baja de reversa, nada más');

      // Segundo intento directo — debe ser un no-op exacto.
      final segunda = await compraRepo.cancelar(compraId: creada.id, motivo: MotivoCancelacionCompra.compraDuplicada.name);
      expect(segunda.estatus, 'cancelada');
      expect(
        segunda.motivoCancelacionCodigo,
        MotivoCancelacionCompra.errorDeCaptura.name,
        reason: 'el segundo intento es un no-op — ni siquiera reescribe el motivo con el nuevo valor recibido',
      );

      final existenciaTrasSegunda = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existenciaTrasSegunda.disponible, 0, reason: 'nunca queda negativa por un segundo descuento');
      final movimientosTrasSegunda = await inventarioRepo.listarMovimientos(articuloId: articulo.id);
      expect(movimientosTrasSegunda, hasLength(2), reason: 'el segundo intento no debe generar ninguna baja adicional');

      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.estatus, 'cancelado');
    },
  );
}
