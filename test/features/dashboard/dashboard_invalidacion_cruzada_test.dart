// Auditoría de "actualización en tiempo real" (pedido explícito de
// Marlon: cambios en un módulo no se reflejaban en otros sin cerrar y
// reabrir el programa). Se confirmó que Vehículos, Telefonía e
// Inventario (entrada/baja/ajuste) nunca invalidaban
// `dashboardControllerProvider` — a diferencia de Compras/Nómina/
// Personal/Finanzas/Organización, que ya lo hacían. Estas pruebas
// prueban el mecanismo real (invalidación de Riverpod), no el cálculo
// del resumen en sí (ya cubierto por sus propias pruebas).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/presentation/telefonia_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/presentation/vehiculos_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // `MovimientoInventario.actorUsuarioId` es una FK real hacia `Usuario`.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-prueba'), nombre: 'Usuario de prueba', nombreUsuario: 'prueba', passwordHash: 'x'),
        );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        // Etapa 20: el Dashboard ahora también lee
        // `documentoPorEmitirRepositoryProvider` (alerta de documentos
        // por emitir) — depende de `attachmentStorageProvider`/
        // `path_provider` (no disponible bajo `flutter test`).
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  Future<void> esperarCarga<T>(ProviderListenable<T> provider, bool Function(T) cargando) async {
    while (cargando(container.read(provider))) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('crear un Vehículo invalida el Dashboard sin recargar manualmente', () async {
    container.listen(dashboardControllerProvider, (_, _) {});
    await esperarCarga(dashboardControllerProvider, (s) => s.cargando);
    var reconstrucciones = 0;
    container.listen(dashboardControllerProvider, (_, _) => reconstrucciones++);

    final resultado = await container.read(vehiculosControllerProvider.notifier).crearVehiculo(
          marca: 'Nissan',
          modelo: 'NP300',
          tipoVehiculo: 'pickup',
        );

    expect(resultado, isA<CrearVehiculoExitoso>());
    // `invalidate` reprograma la reconstrucción para el siguiente
    // microtask, nunca es síncrono con la llamada.
    await Future<void>.delayed(Duration.zero);
    expect(reconstrucciones, greaterThan(0), reason: 'bug real: Vehículos nunca invalidaba dashboardControllerProvider');
  });

  test('crear una Línea telefónica invalida el Dashboard sin recargar manualmente', () async {
    container.listen(dashboardControllerProvider, (_, _) {});
    await esperarCarga(dashboardControllerProvider, (s) => s.cargando);
    var reconstrucciones = 0;
    container.listen(dashboardControllerProvider, (_, _) => reconstrucciones++);

    final resultado = await container.read(telefoniaControllerProvider.notifier).crearLinea(
          operador: 'telcel',
          modalidadSim: 'fisica',
        );

    expect(resultado, isA<CrearLineaTelefonicaExitoso>());
    await Future<void>.delayed(Duration.zero);
    expect(reconstrucciones, greaterThan(0), reason: 'bug real: Telefonía nunca invalidaba dashboardControllerProvider');
  });

  test('registrar una entrada de Inventario invalida el Dashboard sin recargar manualmente', () async {
    final articuloRepo = ArticuloRepositoryImpl(db);
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
        .categoria;
    final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
      categoriaId: categoria.id,
      nombre: 'Pantalón',
      manejaVariante: false,
      manejaSerie: false,
    ) as CrearArticuloExitoso)
        .articulo;

    container.listen(dashboardControllerProvider, (_, _) {});
    await esperarCarga(dashboardControllerProvider, (s) => s.cargando);
    var reconstrucciones = 0;
    container.listen(dashboardControllerProvider, (_, _) => reconstrucciones++);

    final resultado = await container.read(articulosControllerProvider.notifier).registrarEntrada(
          articuloId: articulo.id,
          cantidad: 5,
          fecha: DateTime(2026, 8, 20),
        );

    expect(resultado, isA<RegistrarEntradaExitoso>());
    await Future<void>.delayed(Duration.zero);
    expect(reconstrucciones, greaterThan(0), reason: 'bug real: entrada de Inventario nunca invalidaba dashboardControllerProvider');
  });
}
