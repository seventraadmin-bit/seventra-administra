// Reproducción del bug real reportado por Marlon durante la prueba
// funcional de Compras: al cancelar COM-000021 (1 partida de
// Inventario, artículo NO serializado, cantidad 1, $250.00) la UI
// mostraba "Ocurrió un error inesperado".
//
// Causa raíz confirmada ANTES de corregir nada (commit previo de esta
// misma prueba, que reproducía el fallo exacto): `CancelarCompraUseCase`
// ya bloqueaba proactivamente la cancelación cuando una `ArticuloUnidad`
// serializada generada por la Compra dejaba de estar `disponible`
// (`CancelarCompraBloqueadaPorUnidadesNoDisponibles`) — pero no existía
// ningún chequeo equivalente para partidas por CANTIDAD (artículo sin
// número de serie). Si parte de esa cantidad ya se consumió después
// (aquí: se asignó a un Empleado, generando un movimiento
// `salidaAsignacion` que reduce `disponible`), `CancelarCompraUseCase`
// intentaba revertir la Compra completa igual, y
// `InventarioRepositoryImpl.registrarBaja` lanzaba
// `ExistenciaInsuficienteException` a medio camino de la transacción —
// esa excepción real llegaba hasta `CancelarCompraErrorInesperado`, y
// el diálogo (`cancelar_compra_dialog.dart`) ni siquiera la mostraba:
// para ese caso solo desplegaba el texto genérico
// `l10n.compraErrorInesperado`.
//
// Corrección (Etapa 15, resolución explícita de Marlon: política
// conservadora): `CancelarCompraUseCase` ahora verifica
// PROACTIVAMENTE, antes de tocar nada, si alguna partida por cantidad
// de la Compra tiene su artículo/variante con cualquier `Asignacion`
// registrada — mismo criterio exacto que ya usaban `corregir()` y
// `obtenerResumenEliminacionFisica`. Este caso ahora nunca llega a
// `InventarioRepository.registrarBaja`: se bloquea antes, con
// `CancelarCompraBloqueadaPorArticulosConsumidos`, listando el
// artículo real — nunca un mensaje genérico ni una excepción cruda.

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

void main() {
  late AppDatabase db;
  late CompraRepositoryImpl compraRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl inventarioAsignacionRepo;
  late RegistrarCompraUseCase registrarCompra;
  late CancelarCompraUseCase cancelarCompra;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    inventarioAsignacionRepo = AsignacionRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, generarCodigo);
    cancelarCompra = CancelarCompraUseCase(compraRepo);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloDePrueba({String nombre = 'Pantalón Negro Comando'}) async {
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

  test(
    'REGRESIÓN (COM-000021): cancelar una Compra de 1 unidad (artículo sin serie) ya asignada al Empleado '
    'se bloquea proactivamente, en vez de lanzar ExistenciaInsuficienteException dentro de la transacción',
    () async {
      // Exactamente el caso reportado: COM-000021, 1 partida de
      // Inventario, artículo sin número de serie, cantidad 1, $250.00.
      final articulo = await crearArticuloDePrueba();
      final creada = ((await registrarCompra.ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(
            destino: DestinoCompraPartida.inventario.name,
            articuloId: articulo.id,
            cantidad: 1,
            costoUnitario: 25000,
          ),
        ],
      )) as RegistrarCompraExitosa)
          .compra;

      // La mercancía de esta Compra específica ya se consumió: se
      // asignó al Empleado (caso real de una prueba funcional — se
      // recibe y de inmediato se entrega). `disponible` para este
      // artículo cae a 0.
      final empleado = await crearEmpleadoDePrueba();
      await inventarioAsignacionRepo.crear(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 11),
      );
      final existenciaAntes = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existenciaAntes.disponible, 0, reason: 'precondición de la reproducción: ya no queda nada disponible de esta Compra');

      // Acto — mismo llamado que dispara el diálogo real de "Cancelar
      // compra". Con el chequeo proactivo ya implementado, nunca llega
      // a InventarioRepository.registrarBaja ni a su excepción.
      final resultado = await cancelarCompra.ejecutar(compraId: creada.id, motivo: MotivoCancelacionCompra.compraDuplicada);

      expect(
        resultado,
        isA<CancelarCompraBloqueadaPorArticulosConsumidos>(),
        reason: 'bloqueo proactivo — política conservadora (Resolución de Marlon): cualquier Asignacion sobre el '
            'artículo/variante bloquea, mismo criterio que corregir()/obtenerResumenEliminacionFisica',
      );
      final detalles = (resultado as CancelarCompraBloqueadaPorArticulosConsumidos).detalles;
      expect(detalles, hasLength(1));
      expect(detalles.single, contains(articulo.nombre));

      // Nada se modifica cuando la cancelación se bloquea — ni la
      // Compra, ni el Egreso, ni la existencia.
      final compraSinCambios = await compraRepo.obtenerPorId(creada.id);
      expect(compraSinCambios!.estatus, 'registrada');
      final egreso = await db.select(db.egreso).getSingle();
      expect(egreso.estatus, 'registrado');
      final existenciaDespues = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existenciaDespues.disponible, 0, reason: 'sin cambios adicionales tras el bloqueo');
    },
  );
}
