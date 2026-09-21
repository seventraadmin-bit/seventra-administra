// Etapa "Auditoría central completa" — §12.D (permisos) y §15
// (responsive) sobre la pantalla real.
//
// La regla que se fija aquí es la que más fácil se rompe sin querer:
// `auditoria.ver` abre la pantalla y deja VER que algo ocurrió, pero no
// es un atajo para entrar a donde ocurrió. El botón "Ver origen" se
// resuelve con `permisosQueAbrenRuta` — el mismo mecanismo del router —
// y con el candado de Maestro para Bóveda.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/auditoria/auditoria_screen.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _Sesion extends SesionController {
  _Sesion({required this.esMaestro, required this.permisos});
  final bool esMaestro;
  final Set<String> permisos;

  @override
  SesionUsuario? build() => SesionUsuario(
        usuarioId: 'usuario-a',
        nombre: 'Auditor',
        nombreUsuario: 'auditor',
        esMaestro: esMaestro,
        permisos: permisos,
      );
}

const _anchos = <String, Size>{
  '1536': Size(1536, 1000),
  '1366': Size(1366, 900),
  '1024': Size(1024, 900),
  '700': Size(700, 900),
  '500': Size(500, 900),
};

/// Textos deliberadamente largos: es donde una celda o un chip revienta.
const _nombreCredencialLargo =
    'Portal SAT — Buzón Tributario de RISEG Seguridad Privada S.A. de C.V. (contribuyente principal)';
const _motivoLargo =
    'Se corrigió el número de serie porque la etiqueta física del equipo no coincidía con la captura '
    'original del alta, verificado contra la factura del proveedor y el acta de entrega firmada.';

void main() {
  late AppDatabase db;
  late String articuloId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-a'),
            nombre: 'Auditor',
            nombreUsuario: 'auditor',
            passwordHash: 'x',
          ),
        );

    // --- Un evento de Bóveda, con nombre largo ---
    final credencial = await db.into(db.bovedaCredencial).insertReturning(
          BovedaCredencialCompanion.insert(
            nombre: _nombreCredencialLargo,
            tipo: 'portal',
            secretoCifrado: const Value(r'aesgcm$1$aXY=$SECRETO-QUE-NO-DEBE-SALIR'),
          ),
        );
    await db.into(db.bovedaCredencialEvento).insert(
          BovedaCredencialEventoCompanion.insert(
            credencialId: credencial.id,
            fechaHora: DateTime(2026, 9, 1, 10),
            tipoEvento: 'secretoRevelado',
            actorUsuarioId: const Value('usuario-a'),
          ),
        );

    // --- Un evento de Inventario, con motivo largo y cambio real ---
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Cómputo'),
        );
    final articulo = await db.into(db.articulo).insertReturning(
          ArticuloCompanion.insert(
            folio: 'ART-000007',
            nombre: 'Laptop Dell Latitude 5440',
            categoriaId: categoria.id,
            manejaSerie: const Value(true),
          ),
        );
    articuloId = articulo.id;
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(
            articuloId: articulo.id,
            codigo: 'ART-000007-001',
            numeroSerie: 'SN-CORREGIDO-02',
          ),
        );
    await db.into(db.articuloUnidadEvento).insert(
          ArticuloUnidadEventoCompanion.insert(
            unidadId: unidad.id,
            fechaHora: DateTime(2026, 9, 2, 11),
            tipoEvento: 'correccionIdentidad',
            campo: 'numeroSerie',
            valorAnterior: const Value('SN-MAL-000000000000001'),
            valorNuevo: const Value('SN-CORREGIDO-02'),
            motivo: _motivoLargo,
            actorUsuarioId: const Value('usuario-a'),
          ),
        );

    // --- Un evento con JSON de cambios largo (Vehículos) ---
    final vehiculo = await db.into(db.vehiculo).insertReturning(
          VehiculoCompanion.insert(
            codigo: 'VEH-000001',
            marca: 'Nissan',
            modelo: 'NP300',
            tipoVehiculo: 'pickup',
          ),
        );
    await db.into(db.vehiculoEvento).insert(
          VehiculoEventoCompanion.insert(
            vehiculoId: vehiculo.id,
            fechaHora: DateTime(2026, 9, 3, 12),
            tipoEvento: 'corregido',
            observacion: const Value(_motivoLargo),
            actorUsuarioId: const Value('usuario-a'),
            estadoAnterior: const Value(
              '{"placas":"ABC-123-45","vin":"3N6DD23T5MK000001","numeroMotor":"MOT-0001",'
              '"color":"Blanco","costoAdquisicion":48500000}',
            ),
            estadoNuevo: const Value(
              '{"placas":"XYZ-999-88","vin":"3N6DD23T5MK000002","numeroMotor":"MOT-0002",'
              '"color":"Gris Oxford metálico","costoAdquisicion":49250075}',
            ),
          ),
        );

    // --- Un movimiento de TDC: acción compuesta + saldo formateado ---
    final deuda = await db.into(db.deuda).insertReturning(
          DeudaCompanion.insert(
            folio: 'DEU-000003',
            nombre: 'TDC Konfío Empresarial — línea revolvente principal de la operación',
            tipo: 'tarjetaCredito',
            saldoActual: 3326608,
            tarjetaUltimosDigitos: const Value('4821'),
          ),
        );
    final compra = await db.into(db.compra).insertReturning(
          CompraCompanion.insert(folioCompra: 'COM-000001', fecha: DateTime(2026, 9, 4), formaPago: 'tarjeta'),
        );
    await db.into(db.movimientoDeuda).insert(
          MovimientoDeudaCompanion.insert(
            deudaId: deuda.id,
            fecha: DateTime(2026, 9, 4, 13),
            tipo: 'cargoCompra',
            importe: 1200000,
            saldoAnterior: 3326608,
            saldoPosterior: 4526608,
            compraId: Value(compra.id),
            actorUsuarioId: const Value('usuario-a'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> montar(
    WidgetTester tester, {
    required Size tamano,
    required bool oscuro,
    required bool esMaestro,
    required Set<String> permisos,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(() => _Sesion(esMaestro: esMaestro, permisos: permisos)),
        ],
        child: MaterialApp(
          theme: oscuro ? AppTheme.dark() : AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AuditoriaScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('§12.D — auditoria.ver deja VER el evento, no saltarse el módulo', () {
    testWidgets('con solo auditoria.ver, el evento de Bóveda SE VE pero no ofrece abrir la Bóveda', (tester) async {
      await montar(
        tester,
        tamano: const Size(1366, 900),
        oscuro: false,
        esMaestro: false,
        permisos: {'auditoria.ver'},
      );

      // El evento está en la lista, con su credencial identificada.
      expect(find.text('secretoRevelado'), findsOneWidget);
      expect(find.textContaining('Portal SAT'), findsWidgets);

      await tester.tap(find.text('secretoRevelado'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('auditoria_ver_origen')),
        findsNothing,
        reason: 'la Bóveda es Maestro-only: auditoria.ver no puede abrirla',
      );
      // Y el detalle sigue siendo útil: acción, actor y credencial.
      expect(find.textContaining('secretoRevelado'), findsWidgets);
    });

    testWidgets('el Maestro sí puede navegar al origen del evento de Bóveda', (tester) async {
      await montar(
        tester,
        tamano: const Size(1366, 900),
        oscuro: false,
        esMaestro: true,
        permisos: const {},
      );

      await tester.tap(find.text('secretoRevelado'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auditoria_ver_origen')), findsOneWidget);
    });

    testWidgets('sin inventario.ver NO se ofrece abrir el artículo', (tester) async {
      await montar(
        tester,
        tamano: const Size(1366, 900),
        oscuro: false,
        esMaestro: false,
        permisos: {'auditoria.ver'},
      );
      await tester.tap(find.text('correccionIdentidad'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('auditoria_ver_origen')),
        findsNothing,
        reason: 'ver el evento no concede entrar al expediente de Inventario',
      );
    });

    testWidgets('CON inventario.ver sí se ofrece — la ausencia anterior no es vacía', (tester) async {
      await montar(
        tester,
        tamano: const Size(1366, 900),
        oscuro: false,
        esMaestro: false,
        permisos: {'auditoria.ver', 'inventario.ver'},
      );
      await tester.tap(find.text('correccionIdentidad'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('auditoria_ver_origen')),
        findsOneWidget,
        reason: 'con el permiso del módulo origen, la navegación sí se ofrece',
      );
    });

    testWidgets('la pantalla NUNCA muestra el secreto de una credencial', (tester) async {
      await montar(
        tester,
        tamano: const Size(1366, 900),
        oscuro: false,
        esMaestro: true,
        permisos: const {},
      );
      await tester.tap(find.text('secretoRevelado'));
      await tester.pumpAndSettle();

      expect(find.textContaining('SECRETO-QUE-NO-DEBE-SALIR'), findsNothing);
      expect(find.textContaining('aesgcm'), findsNothing);
    });
  });

  group('§7 — estándar único de presentación, sin aplanar el origen', () {
    testWidgets('el cambio de Inventario se lee campo: antes → después', (tester) async {
      await montar(
        tester,
        tamano: const Size(1366, 900),
        oscuro: false,
        esMaestro: true,
        permisos: const {},
      );
      await tester.tap(find.text('correccionIdentidad'));
      await tester.pumpAndSettle();

      expect(find.textContaining('numeroSerie: SN-MAL-000000000000001 → SN-CORREGIDO-02'), findsOneWidget);
    });

    testWidgets('una revelación de credencial no muestra bloque de Cambios ni de Motivo', (tester) async {
      await montar(
        tester,
        tamano: const Size(1366, 900),
        oscuro: false,
        esMaestro: true,
        permisos: const {},
      );
      await tester.tap(find.text('secretoRevelado'));
      await tester.pumpAndSettle();

      expect(find.text('Cambios'), findsNothing);
      expect(find.textContaining('Motivo:'), findsNothing, reason: '§9: nunca un "Sin motivo" inventado');
    });
  });

  group('Deudas — el efecto financiero se lee distinto del evento de negocio', () {
    testWidgets('la acción dice de dónde vino el cargo, y el saldo va formateado', (tester) async {
      await montar(
        tester,
        tamano: const Size(1366, 900),
        oscuro: false,
        esMaestro: true,
        permisos: const {},
      );

      final fila = find.text('Cargo a TDC por Compras');
      expect(fila, findsOneWidget, reason: 'nunca "cargoCompra" crudo, ni confundible con "Compra corregida"');

      await tester.ensureVisible(fila);
      await tester.pumpAndSettle();
      await tester.tap(fila);
      await tester.pumpAndSettle();

      expect(find.textContaining(r'saldo: $33,266.08 → $45,266.08'), findsOneWidget);
      expect(find.textContaining(r'Importe: $12,000.00'), findsOneWidget);
      expect(find.textContaining('4821'), findsNothing, reason: 'ningún dato bancario innecesario');
    });
  });

  group('§15 — responsive', () {
    for (final entrada in _anchos.entries) {
      for (final oscuro in [false, true]) {
        final tema = oscuro ? 'oscuro' : 'claro';

        testWidgets('Auditoría (${entrada.key}, $tema): cero overflow', (tester) async {
          await montar(
            tester,
            tamano: entrada.value,
            oscuro: oscuro,
            esMaestro: true,
            permisos: const {},
          );

          expect(tester.takeException(), isNull);
          // Las 3 filas están, con nombre de credencial y motivo largos.
          expect(find.text('correccionIdentidad'), findsOneWidget);
        });

        testWidgets('Detalle con cambios JSON largos (${entrada.key}, $tema): cero overflow', (tester) async {
          await montar(
            tester,
            tamano: entrada.value,
            oscuro: oscuro,
            esMaestro: true,
            permisos: const {},
          );
          final fila = find.text('corregido');
          await tester.ensureVisible(fila);
          await tester.pumpAndSettle();
          await tester.tap(fila);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Cambios'), findsOneWidget);
        });
      }
    }
  });

  testWidgets('el filtro de Módulo ofrece Tiempos Extra y Bóveda, que no son módulos de permiso', (tester) async {
    await montar(
      tester,
      tamano: const Size(1366, 900),
      oscuro: false,
      esMaestro: true,
      permisos: const {},
    );

    final select = tester.widget<RisegSelect<String?>>(
      find.ancestor(
        of: find.text('Módulo'),
        matching: find.byType(RisegSelect<String?>),
      ),
    );
    final valores = select.items.map((i) => i.value).toList();

    expect(valores, contains('tiempoExtra'));
    expect(valores, contains('boveda'));
    expect(valores, contains('inventario'));
    expect(select.items.firstWhere((i) => i.value == 'boveda').label, 'Bóveda de Accesos');
    expect(articuloId, isNotEmpty);
  });
}
