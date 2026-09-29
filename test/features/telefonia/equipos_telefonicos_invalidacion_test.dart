// Corrección de invalidación (Etapa 9D, hallazgo real reportado):
// "Configurar equipo" guardaba correctamente en base de datos, pero
// `EquiposTelefonicosListScreen` mantenía su propia consulta como
// estado local (`initState` + `setState`) — la fila no reflejaba el
// cambio hasta forzar un remount completo (cambiar a Líneas y volver).
// Causa raíz: no había NINGÚN provider Riverpod detrás del listado de
// Equipos que una mutación pudiera invalidar. La corrección introduce
// `EquiposTelefonicosController` (mismo patrón que `TelefoniaController`
// para Líneas) y agrega `ref.invalidate(...)` en cada mutador real de
// Telefonía que cambia algo visible en Equipos y/o Líneas.
//
// Estas pruebas ejercitan la UI real de punta a punta (diálogo →
// Guardar → pantalla ya montada, SIN cambiar de pestaña) — reproducen
// exactamente el reporte original, no solo la lógica de negocio (que
// ya estaba correcta: el guardado en base de datos nunca falló).

import 'package:drift/drift.dart' show Value;
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
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/categoria_articulo_table.dart' show AplicacionEspecializadaCategoriaArticulo;
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
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

/// Crea una `ArticuloUnidad` disponible/serializada sin `ArticuloUnidadTelefono`
/// todavía — exactamente el conjunto elegible que
/// `mostrarDialogoConfigurarEquipoTelefonico` ofrece en su selector
/// cuando `unidadId == null`. Reutiliza los mismos casos de uso reales
/// que `equipo_telefonico_test.dart` (nunca un mock de la capa de
/// datos).
Future<({String unidadId, String codigo})> _crearUnidadTelefonoElegible(
  AppDatabase db, {
  String nombre = 'MOTOROLA MOTO G34 5G',
  String numeroSerie = 'SN-TEL-0001',
}) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
  final registrarEntrada = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);

  // `aplicacionEspecializada: telefonia` es requisito del propio filtro
  // de elegibilidad de `mostrarDialogoConfigurarEquipoTelefonico` — se
  // llama al repositorio directo porque `CrearCategoriaArticuloUseCase`
  // no expone ese parámetro (solo `CategoriaArticuloRepository.actualizar` lo hace).
  final categoria = await categoriaRepo.crear(
    nombre: '$nombre-categoria',
    aplicacionEspecializada: AplicacionEspecializadaCategoriaArticulo.telefonia,
  );
  final articulo =
      (await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: nombre, manejaSerie: true) as CrearArticuloExitoso).articulo;
  final unidad = (await registrarEntrada.ejecutar(
    articuloId: articulo.id,
    numeroSerie: numeroSerie,
    marca: 'MOTOROLA',
    modelo: 'MOTO G34 5G',
    fecha: DateTime(2026, 1, 1),
  ) as RegistrarEntradaUnidadExitoso)
      .unidad;

  return (unidadId: unidad.id, codigo: unidad.codigo);
}

Future<void> _crearLineaDePrueba(AppDatabase db, {String? numero}) async {
  final asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
  final asignacionRepo = AsignacionRepositoryImpl(db);
  final equipoLineaRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, asignacionRepo);
  final lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoLineaRepo);
  final crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
  await crearLinea.ejecutar(numero: numero, operador: 'telcel', modalidadSim: 'fisica');
}

Finder _campoTexto(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegTextField && w.label == label),
      matching: find.byType(TextFormField),
    );

Finder _selector(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegSelect && w.label == label),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );

/// [opcionTexto] se busca por subcadena (`textContaining`), no por
/// igualdad exacta — las opciones del selector de unidad combinan
/// código + descripción ("UNI-000001 · MOTOROLA MOTO G34 5G"), nunca
/// solo el código.
Future<void> _elegirEnSelector(WidgetTester tester, String label, String opcionTexto) async {
  await tester.ensureVisible(_selector(label));
  await tester.tap(_selector(label));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(opcionTexto).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppLocalizations> cargarL10n() => AppLocalizations.delegate.load(const Locale('es'));

  Future<void> pumpEnEquipos(WidgetTester tester, AppDatabase db) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // `EquipoTelefonicoEvento.actorUsuarioId`/`LineaTelefonicaEquipoEvento...`
    // son FK reales hacia `Usuario` — deben existir de antemano o el
    // registro falla con `ErrorInesperado` (mismo hallazgo real ya
    // documentado en otras pruebas de invalidación en tiempo real).
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-prueba'),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'prueba',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
        ],
        child: RisegOneApp(router: createAppRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_item_telefonia')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Configurar equipo actualiza inmediatamente la fila del listado, sin cambiar de pestaña (reproducción exacta del reporte)',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final unidad = await _crearUnidadTelefonoElegible(db);
      final l10n = await cargarL10n();

      await pumpEnEquipos(tester, db);

      // `EquiposTelefonicosListScreen.listarUnidadesTelefono` solo
      // incluye unidades que YA tienen `ArticuloUnidadTelefono` — antes
      // de "Configurar equipo" esta unidad todavía no aparece aquí (es
      // el punto entero del alta), así que no hay nada que verificar
      // todavía en el listado.
      await tester.tap(find.text(l10n.equiposTelefonicosBotonConfigurar));
      await tester.pumpAndSettle();

      await _elegirEnSelector(tester, l10n.equipoTelefonicoConfigurarCampoUnidad, unidad.codigo);
      await tester.enterText(_campoTexto(l10n.equipoTelefonicoConfigurarCampoImei1), '351234567890123');
      await tester.tap(find.text(l10n.equipoTelefonicoConfigurarBotonConfirmar));
      await tester.pumpAndSettle();

      // El diálogo navega directo al expediente del equipo recién
      // configurado — se regresa al listado (todavía montado debajo,
      // nunca destruido) sin tocar ninguna otra pestaña.
      expect(find.text('351234567890123'), findsOneWidget, reason: 'el expediente ya muestra el IMEI recién guardado');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text(l10n.equiposTelefonicosListadoTitulo), findsOneWidget, reason: 'de vuelta en el listado de Equipos');
      expect(
        find.text('351234567890123'),
        findsOneWidget,
        reason: 'la fila debe reflejar el IMEI inmediatamente — sin cambiar de pestaña ni recargar manualmente',
      );
    },
  );

  testWidgets('Cambiar IMEI desde el expediente vuelve a mostrar el nuevo valor inmediatamente en el listado', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final unidad = await _crearUnidadTelefonoElegible(db);
    final l10n = await cargarL10n();

    await pumpEnEquipos(tester, db);

    // Configura el IMEI inicial.
    await tester.tap(find.text(l10n.equiposTelefonicosBotonConfigurar));
    await tester.pumpAndSettle();
    await _elegirEnSelector(tester, l10n.equipoTelefonicoConfigurarCampoUnidad, unidad.codigo);
    await tester.enterText(_campoTexto(l10n.equipoTelefonicoConfigurarCampoImei1), '351111111111111');
    await tester.tap(find.text(l10n.equipoTelefonicoConfigurarBotonConfirmar));
    await tester.pumpAndSettle();

    // Ya en el expediente — edita el IMEI a un valor distinto.
    await tester.tap(find.text(l10n.equipoTelefonicoBotonEditarImei));
    await tester.pumpAndSettle();
    final campoImei = _campoTexto(l10n.equipoTelefonicoConfigurarCampoImei1);
    await tester.enterText(campoImei, '352222222222222');
    await tester.tap(find.text(l10n.equipoTelefonicoConfigurarBotonConfirmar));
    await tester.pumpAndSettle();

    expect(find.text('352222222222222'), findsOneWidget);
    expect(find.text('351111111111111'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(
      find.text('352222222222222'),
      findsOneWidget,
      reason: 'el listado debe mostrar el IMEI nuevo, nunca el anterior ni uno obsoleto',
    );
    expect(find.text('351111111111111'), findsNothing);
  });

  testWidgets(
    'Una operación fallida (IMEI duplicado) no altera artificialmente el listado',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final unidadA = await _crearUnidadTelefonoElegible(db, nombre: 'EQUIPO A', numeroSerie: 'SN-A-0001');
      final unidadB = await _crearUnidadTelefonoElegible(db, nombre: 'EQUIPO B', numeroSerie: 'SN-B-0001');
      final l10n = await cargarL10n();

      await pumpEnEquipos(tester, db);

      // Configura IMEI en la unidad A.
      await tester.tap(find.text(l10n.equiposTelefonicosBotonConfigurar));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.equipoTelefonicoConfigurarCampoUnidad, unidadA.codigo);
      await tester.enterText(_campoTexto(l10n.equipoTelefonicoConfigurarCampoImei1), '359999999999999');
      await tester.tap(find.text(l10n.equipoTelefonicoConfigurarBotonConfirmar));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Intenta configurar la unidad B con el MISMO IMEI — debe
      // rechazarse (duplicado) y el diálogo debe permanecer abierto
      // mostrando el error, sin tocar el estado de la unidad B.
      await tester.tap(find.text(l10n.equiposTelefonicosBotonConfigurar));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.equipoTelefonicoConfigurarCampoUnidad, unidadB.codigo);
      await tester.enterText(_campoTexto(l10n.equipoTelefonicoConfigurarCampoImei1), '359999999999999');
      await tester.tap(find.text(l10n.equipoTelefonicoConfigurarBotonConfirmar));
      await tester.pumpAndSettle();

      // El diálogo sigue abierto (falló, `onConfirm` devolvió `null`).
      expect(
        find.text(l10n.equipoTelefonicoConfigurarBotonConfirmar),
        findsOneWidget,
        reason: 'el diálogo no se cerró — la operación fue rechazada',
      );

      // Cancela y confirma que el listado nunca mostró la unidad B como
      // configurada.
      await tester.tap(find.text(l10n.lineaTelefonicaBotonCancelar));
      await tester.pumpAndSettle();

      // `unidadB` nunca llegó a configurarse (la operación fue
      // rechazada) — sigue sin `ArticuloUnidadTelefono`, así que ni
      // siquiera aparece todavía en este listado (mismo criterio que
      // `unidadA` antes de configurarse). Solo una fila con el IMEI
      // usado (la de la unidad A) — la operación fallida no generó una
      // segunda copia ni "casi-configuró" la unidad B.
      expect(find.text('359999999999999'), findsOneWidget);
    },
  );

  testWidgets(
    'Asociar un equipo a una línea sincroniza Equipos y Líneas de inmediato (misma operación, dos pantallas)',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final unidad = await _crearUnidadTelefonoElegible(db);
      await _crearLineaDePrueba(db, numero: '5512345678');
      final l10n = await cargarL10n();

      // Configura el equipo primero (IMEI requerido antes de poder
      // asociarlo a una línea, mismo flujo real).
      await pumpEnEquipos(tester, db);
      await tester.tap(find.text(l10n.equiposTelefonicosBotonConfigurar));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.equipoTelefonicoConfigurarCampoUnidad, unidad.codigo);
      await tester.enterText(_campoTexto(l10n.equipoTelefonicoConfigurarCampoImei1), '351234500000000');
      await tester.tap(find.text(l10n.equipoTelefonicoConfigurarBotonConfirmar));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Antes de asociar: "Línea actual" muestra "—".
      final filaAntes = find.ancestor(of: find.text(unidad.codigo), matching: find.byType(Row)).first;
      expect(find.descendant(of: filaAntes, matching: find.text('—')), findsWidgets);

      // Navega a Líneas y asocia el equipo desde el expediente de la
      // línea (el otro lado de la misma relación).
      await tester.tap(find.byKey(const Key('nav_item_telefonia')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.telefoniaTabLineas));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5512345678'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(l10n.lineaTelefonicaBotonAsociarEquipo));
      await tester.tap(find.text(l10n.lineaTelefonicaBotonAsociarEquipo));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.lineaTelefonicaEquipoCampoUnidad, unidad.codigo);
      await tester.tap(find.text(l10n.lineaTelefonicaAsociarEquipoBotonConfirmar));
      await tester.pumpAndSettle();

      // El propio expediente de la línea ya muestra el equipo asociado
      // (etiqueta combinada "código · descripción", nunca solo el
      // código).
      expect(find.textContaining(unidad.codigo), findsWidgets);

      // Vuelve a Líneas (mismo tab) y luego a Equipos — SIN pasar por
      // el expediente de nuevo — ambos listados deben reflejar la
      // asociación de inmediato.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('5512345678'), findsOneWidget);

      await tester.tap(find.text(l10n.telefoniaTabEquipos));
      await tester.pumpAndSettle();

      expect(
        find.text('5512345678'),
        findsOneWidget,
        reason: 'Equipos debe mostrar la línea asociada de inmediato — misma operación, ambas pantallas sincronizadas',
      );
    },
  );

  testWidgets(
    'Cambiar a Líneas y volver a Equipos no produce una segunda versión distinta del estado, ni duplica filas',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final unidad = await _crearUnidadTelefonoElegible(db);
      final l10n = await cargarL10n();

      await pumpEnEquipos(tester, db);
      await tester.tap(find.text(l10n.equiposTelefonicosBotonConfigurar));
      await tester.pumpAndSettle();
      await _elegirEnSelector(tester, l10n.equipoTelefonicoConfigurarCampoUnidad, unidad.codigo);
      await tester.enterText(_campoTexto(l10n.equipoTelefonicoConfigurarCampoImei1), '351230001110000');
      await tester.tap(find.text(l10n.equipoTelefonicoConfigurarBotonConfirmar));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('351230001110000'), findsOneWidget);
      expect(find.text(unidad.codigo), findsOneWidget, reason: 'una sola fila para esta unidad');

      // Cambia a Líneas y de vuelta a Equipos (el remount forzado que
      // antes era la única forma de ver el dato correcto).
      await tester.tap(find.text(l10n.telefoniaTabLineas));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.telefoniaTabEquipos));
      await tester.pumpAndSettle();

      // El estado debe seguir siendo exactamente el mismo — nunca una
      // fila duplicada, nunca un IMEI distinto/perdido.
      expect(find.text('351230001110000'), findsOneWidget);
      expect(find.text(unidad.codigo), findsOneWidget);
    },
  );
}
