// Etapa 15 — 20. Providers/vistas afectadas se actualizan de inmediato
// tras una corrección de partidas: una corrección que cambia el costo
// de una partida toca Inventario (existencia/costo) y el Egreso
// relacionado (monto sincronizado) — mismo criterio de invalidación
// cruzada ya usado en `registrarCompra`/`cancelarCompra`
// (`ComprasController.corregirCompra` invalida `egresosControllerProvider`/
// `articulosControllerProvider`/`dashboardControllerProvider` cuando
// `cambiosPartidas` no viene vacío).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/correccion_partida_compra.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';
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
  late String articuloId;
  late String compraId;
  late String compraPartidaId;

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
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
    );
    addTearDown(container.dispose);

    final categoriaResultado = await container.read(crearCategoriaArticuloUseCaseProvider).ejecutar(nombre: 'Uniformes');
    final categoria = (categoriaResultado as CrearCategoriaArticuloExitoso).categoria;
    final articulo = await container.read(crearArticuloUseCaseProvider).ejecutar(
          categoriaId: categoria.id,
          nombre: 'Camisola',
          manejaVariante: false,
          manejaSerie: false,
        );
    articuloId = (articulo as CrearArticuloExitoso).articulo.id;

    final compraResultado = await container.read(comprasControllerProvider.notifier).registrarCompra(
          fecha: DateTime(2026, 8, 10),
          formaPago: FormaPago.efectivo.name,
          partidas: [PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articuloId, cantidad: 5, costoUnitario: 33000)],
        );
    compraId = compraResultado.runtimeType.toString() == 'RegistrarCompraExitosa'
        ? (compraResultado as dynamic).compra.id as String
        : throw StateError('No se pudo preparar la Compra de prueba');
    compraPartidaId = (await container.read(comprasControllerProvider.notifier).obtenerPartidas(compraId)).single.id;
  });

  tearDown(() => db.close());

  test(
    '20. corregir una partida (costo) refleja de inmediato la existencia/costo en Inventario y el nuevo monto en '
    'Egresos, sin cambiar de pestaña ni recargar manualmente',
    () async {
      container.listen(egresosControllerProvider, (_, _) {});
      container.listen(articulosControllerProvider, (_, _) {});
      while (container.read(egresosControllerProvider).cargando || container.read(articulosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(egresosControllerProvider).egresos.single.monto, 5 * 33000);
      expect(container.read(articulosControllerProvider).articulos.single.existencia.total, 5);

      final resultado = await container.read(comprasControllerProvider.notifier).corregirCompra(
            compraId: compraId,
            cambiosPartidas: [CorreccionPartidaCantidadCosto(compraPartidaId: compraPartidaId, nuevaCantidad: 8, nuevoCostoUnitario: 35000)],
            motivo: 'Se recibieron 8 a \$350.00, no 5 a \$330.00',
          );
      expect(resultado.runtimeType.toString(), 'CorregirCompraExitosa');

      await Future<void>.delayed(Duration.zero);
      while (container.read(egresosControllerProvider).cargando || container.read(articulosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(container.read(egresosControllerProvider).egresos.single.monto, 8 * 35000, reason: 'Finanzas ve el nuevo monto sin recargar manualmente');
      expect(container.read(articulosControllerProvider).articulos.single.existencia.total, 8, reason: 'Inventario ve la nueva existencia sin recargar manualmente');
    },
  );
}
