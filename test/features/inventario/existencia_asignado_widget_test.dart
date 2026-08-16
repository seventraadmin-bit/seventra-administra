// Etapa 15 — confirma en pantalla real (no solo en el cálculo) que
// "Asignado" aparece tanto en el expediente del Artículo como en el
// listado general de Inventario, con el mismo valor real: caso
// SMARTPHONE, 5 unidades (3 disponibles + 2 asignadas).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

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

Future<String> _sembrarSmartphoneConAsignados(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final asignacionRepo = AsignacionRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso)
          .categoria;
  final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
    categoriaId: categoria.id,
    nombre: 'SMARTPHONE',
    manejaVariante: false,
    manejaSerie: true,
  ) as CrearArticuloExitoso)
      .articulo;

  final registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
  final unidades = <ArticuloUnidadData>[];
  for (var i = 1; i <= 5; i++) {
    final resultado = await registrarEntradaUnidad.ejecutar(articuloId: articulo.id, numeroSerie: 'SN-W00$i', fecha: DateTime(2026, 8, 13));
    unidades.add((resultado as RegistrarEntradaUnidadExitoso).unidad);
  }

  final crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
  for (var i = 0; i < 2; i++) {
    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: i + 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0${i + 1}',
            rfc: 'PEXJ900101AB${i + 1}',
            nss: '1234567890${i + 1}',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    await crearAsignacion.ejecutar(
      articuloId: articulo.id,
      unidadId: unidades[i].id,
      cantidad: 1,
      empleadoId: empleado.id,
      fechaEntrega: DateTime(2026, 8, 13),
    );
  }

  return articulo.id;
}

Future<void> _pumpApp(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        contarUsuariosProvider.overrideWith((ref) async => 1),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
      child: RisegOneApp(router: createAppRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'listado general muestra la columna Asignado, y el expediente del artículo muestra el mismo valor (SMARTPHONE: 2)',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _sembrarSmartphoneConAsignados(db);

      await _pumpApp(tester, db);
      await tester.tap(find.byKey(const Key('nav_item_inventario')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      // Listado: columna Asignado presente, con el valor real (2).
      expect(find.text(l10n.inventarioColumnaAsignado), findsOneWidget);
      expect(find.text('2'), findsWidgets, reason: 'columna Asignado del listado, valor real');

      // Expediente: mismo valor real en el bloque superior de Existencia.
      await tester.tap(find.text('SMARTPHONE').first);
      await tester.pumpAndSettle();

      // "Asignado" también aparece como etiqueta de estatus en cada fila
      // de la tabla de Unidades (2 unidades asignadas) — no solo en el
      // encabezado del resumen, así que aquí se confirma presencia, no
      // unicidad.
      expect(find.text(l10n.articuloExpedienteCampoAsignado), findsWidgets);
      expect(find.text('2'), findsWidgets, reason: 'Asignado en el expediente, mismo valor que el listado');
      expect(find.text('5'), findsWidgets, reason: 'Total sigue en 5');
      expect(find.text('3'), findsWidgets, reason: 'Disponible sigue en 3');
    },
  );
}
