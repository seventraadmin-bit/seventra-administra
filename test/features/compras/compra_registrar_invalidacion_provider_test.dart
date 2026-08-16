// Etapa 15 — reproducción real del bug reportado: al registrar una
// Compra con destino Inventario, Finanzas → Egresos e Inventario →
// Artículos seguían mostrando el estado previo (sin el Egreso nuevo /
// sin la existencia nueva) hasta cambiar de pestaña. Corregido:
// `ComprasController.registrarCompra` ahora invalida
// `egresosControllerProvider` y `articulosControllerProvider` (antes
// solo lo hacía `cancelarCompra`).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // `actorUsuarioId` de la sesión se propaga hasta `EgresoEvento`
    // (FK real hacia `Usuario`) — debe existir de antemano o la
    // inserción falla.
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
  });

  tearDown(() => db.close());

  test(
    'registrar una Compra con destino Inventario refleja de inmediato el Egreso nuevo y la existencia nueva, '
    'sin cambiar de pestaña ni recargar manualmente',
    () async {
      // Ambos listados ya estaban "abiertos" (providers vivos) ANTES
      // de registrar la Compra.
      container.listen(egresosControllerProvider, (_, _) {});
      container.listen(articulosControllerProvider, (_, _) {});
      while (container.read(egresosControllerProvider).cargando || container.read(articulosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(egresosControllerProvider).egresos, isEmpty);
      expect(container.read(articulosControllerProvider).articulos.single.existencia.total, 0);

      final resultado = await container.read(comprasControllerProvider.notifier).registrarCompra(
            fecha: DateTime(2026, 8, 10),
            formaPago: FormaPago.efectivo.name,
            partidas: [
              PartidaCompraInput(destino: DestinoCompraPartida.inventario.name, articuloId: articuloId, cantidad: 3, costoUnitario: 33000),
            ],
          );
      expect(resultado.runtimeType.toString(), 'RegistrarCompraExitosa');

      await Future<void>.delayed(Duration.zero);
      while (container.read(egresosControllerProvider).cargando || container.read(articulosControllerProvider).cargando) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(container.read(egresosControllerProvider).egresos, hasLength(1));
      expect(container.read(articulosControllerProvider).articulos.single.existencia.total, 3);
    },
  );
}
