// Prueba funcional Inventario + Personal (Marlon): asignar un artículo
// POR CANTIDAD (PANTALON NEGRO COMANDO — Total 1 / Disponible 1 /
// Asignado 0) al empleado JUAN MANUEL ZINTZUN LOPEZ actualizaba
// correctamente el expediente del empleado, pero el listado general de
// Inventario seguía mostrando el resumen viejo (Total 1 / Disponible 1
// / Asignado 0) hasta cambiar de pestaña.
//
// Causa raíz investigada ANTES de tocar nada (sin invalidate() a
// ciegas): NO es un problema de cálculo — `calcularExistencia` siempre
// recalcula desde `MovimientoInventario` en tiempo real, nunca desde un
// valor guardado, y `AsignacionRepositoryImpl.crear` sí inserta el
// movimiento `salidaAsignacion` en la misma transacción que la
// `Asignacion` (confirmado también en la prueba de reversión de
// Compras, Etapa 15). La causa real es que
// `mostrarDialogoAsignarArticulo`/`mostrarDialogoCerrarAsignacion`
// nunca invalidaban `articulosControllerProvider` (que cachea su
// estado entre visitas, a diferencia del expediente del Artículo, que
// siempre recalcula fresco en su propio `_cargar`) — mismo patrón de
// bug ya visto y corregido en `ComprasController` (invalidación
// cruzada entre módulos).
//
// Esta prueba monta `articulosControllerProvider` en un host mínimo
// (sin navegar de pestaña, para probar exactamente "se actualiza en
// tiempo real sin cambiar de pestaña") y ejerce el diálogo real de
// asignación — no una llamada directa al repositorio — para probar el
// mecanismo que realmente estaba roto (la UI nunca invalidaba, el
// dominio siempre estuvo bien).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/asignar_articulo_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

Finder _selector(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegSelect && w.label == label),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );

void main() {
  late AppDatabase db;
  late String articuloId;
  late String empleadoId;

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

    final articuloRepo = ArticuloRepositoryImpl(db);
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final inventarioRepo = InventarioRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    final categoria =
        (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
            .categoria;
    final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
      categoriaId: categoria.id,
      nombre: 'PANTALON NEGRO COMANDO',
      manejaVariante: false,
      manejaSerie: false,
    ) as CrearArticuloExitoso)
        .articulo;
    articuloId = articulo.id;

    await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(
      articuloId: articuloId,
      cantidad: 1,
      fecha: DateTime(2026, 8, 20),
    );

    empleadoId = (await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan Manuel',
            apellidoPaterno: 'Zintzun',
            apellidoMaterno: const Value('Lopez'),
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'ZILJ900101HDFXXX01',
            rfc: 'ZILJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        ))
        .id;
  });

  tearDown(() => db.close());

  testWidgets(
    'REGRESIÓN: asignar PANTALON NEGRO COMANDO desde el diálogo real actualiza Disponible/Asignado de '
    'articulosControllerProvider de inmediato, sin cambiar de pestaña ni recargar manualmente',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(articulosControllerProvider);
                  final resumen = state.articulos.where((a) => a.articulo.id == articuloId).firstOrNull;
                  return Column(
                    children: [
                      Text('disponible:${resumen?.existencia.disponible}'),
                      Text('asignado:${resumen?.existencia.asignado}'),
                      ElevatedButton(
                        key: const Key('abrir'),
                        onPressed: () => mostrarDialogoAsignarArticulo(context, ref, empleadoId: empleadoId),
                        child: const Text('abrir'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Precondición: exactamente el estado inicial reportado — Total 1
      // / Disponible 1 / Asignado 0.
      expect(find.text('disponible:1'), findsOneWidget);
      expect(find.text('asignado:0'), findsOneWidget);

      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await tester.tap(_selector(l10n.asignarArticuloCampoArticulo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PANTALON NEGRO COMANDO').last);
      await tester.pumpAndSettle();

      // Cantidad ya viene precargada en '1' — coincide con el caso
      // reportado (1 unidad completa).
      await tester.tap(find.text(l10n.asignarArticuloBotonConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(l10n.asignarArticuloExito), findsOneWidget);

      // El punto real del bug: SIN cambiar de pestaña ni recargar
      // manualmente, el mismo `Consumer` ya montado debe reflejar el
      // nuevo resumen.
      expect(find.text('disponible:0'), findsOneWidget, reason: 'bug real: seguía mostrando disponible:1');
      expect(find.text('asignado:1'), findsOneWidget, reason: 'bug real: seguía mostrando asignado:0');
    },
  );
}
