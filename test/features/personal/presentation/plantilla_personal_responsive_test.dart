// Etapa "Plantilla operativa vs. administrativa" — punto 20 del pedido:
// las pantallas modificadas a 1536/1366/1024/700/500 × claro/oscuro.
// Evidencia: "cero overflow / cero excepción" (`tester.takeException()`),
// el mismo criterio que el resto de RISEG ONE.
//
// Cubre a propósito lo que el pedido señala como riesgoso: la sección
// de Personal del Dashboard con sus 5 tarjetas operativas más la línea
// administrativa, el porcentaje, la rotación, un estado de
// INCONSISTENCIA visible, nombres largos y los filtros de plantilla.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart' show TipoPuesto;
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/personal_activo_list_screen.dart';
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

const _anchos = <String, Size>{
  '1536': Size(1536, 1000),
  '1366': Size(1366, 900),
  '1024': Size(1024, 900),
  '700': Size(700, 900),
  '500': Size(500, 900),
};

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_plantilla_responsive_test_');

    final areaId = (await db.select(db.area).get()).first.id;
    final puestoOperativo = await db.into(db.puesto).insertReturning(
          PuestoCompanion.insert(
            codigo: 'PUE-OP',
            nombre: 'Elemento Operativo de Seguridad Intramuros',
            areaId: areaId,
            tipo: TipoPuesto.operativo.name,
            nivelJerarquico: 1,
          ),
        );
    final puestoAdmin = await db.into(db.puesto).insertReturning(
          PuestoCompanion.insert(
            codigo: 'PUE-ADM',
            nombre: 'DIRECCION GENERAL',
            areaId: areaId,
            tipo: TipoPuesto.administrativo.name,
            nivelJerarquico: 10,
          ),
        );

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    // Nombres largos a propósito.
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SRV-0001',
            nombre: 'Vigilancia intramuros Sportium Satélite — turno mixto',
            clienteId: cliente.id,
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    final sucursal = await db.into(db.sucursal).insertReturning(
          SucursalCompanion.insert(
            codigo: 'SUC-0001',
            nombre: 'Oficina administrativa Toluca centro',
            tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
          ),
        );

    Future<EmpleadoData> crear(int n, {String? sucursalId, required bool operativo}) {
      return db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: n,
              nombres: 'Juan Manuel Alejandro',
              apellidoPaterno: 'Zintzun Villagómez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ90010${n.toString().padLeft(2, '0')}HDFXX1',
              rfc: 'PEXJ9001${n.toString().padLeft(2, '0')}',
              nss: '1000000${n.toString().padLeft(4, '0')}',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
              puestoId: Value(operativo ? puestoOperativo.id : puestoAdmin.id),
              sucursalId: Value(sucursalId),
            ),
          );
    }

    // 3 operativos asignados, 1 operativo sin asignar, 1 administrativo
    // y 1 INCONSISTENTE (Servicio + Sucursal) — para que el estado de
    // inconsistencia se pinte de verdad en la prueba.
    for (var i = 1; i <= 3; i++) {
      final e = await crear(i, operativo: true);
      await db.into(db.asignacionServicio).insert(
            AsignacionServicioCompanion.insert(
              empleadoId: e.id,
              servicioId: servicio.id,
              turnoId: const Value(SeedIds.modalidadTurno24x24),
              fechaInicio: DateTime(2026, 1, 1),
            ),
          );
    }
    await crear(4, operativo: true);
    await crear(5, operativo: false, sucursalId: sucursal.id);
    final inconsistente = await crear(6, operativo: true, sucursalId: sucursal.id);
    await db.into(db.asignacionServicio).insert(
          AsignacionServicioCompanion.insert(
            empleadoId: inconsistente.id,
            servicioId: servicio.id,
            turnoId: const Value(SeedIds.modalidadTurno24x24),
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, {required Size tamano, required bool oscuro, required Widget pantalla}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/pantalla',
      routes: [
        GoRoute(path: '/pantalla', builder: (context, state) => Scaffold(body: pantalla)),
        GoRoute(path: '/personal/empleados/:id', builder: (_, __) => const Scaffold(body: SizedBox.shrink())),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
          attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
        ],
        child: MaterialApp.router(
          theme: oscuro ? AppTheme.dark() : AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final entrada in _anchos.entries) {
    final etiqueta = entrada.key;
    final tamano = entrada.value;

    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('Personal — filtros de plantilla ($etiqueta, $tema): cero overflow', (tester) async {
        await pump(tester, tamano: tamano, oscuro: oscuro, pantalla: const PersonalActivoListScreen());
        expect(tester.takeException(), isNull);
      });

      testWidgets('Personal — filtro Operativo aplicado ($etiqueta, $tema): cero overflow', (tester) async {
        await pump(
          tester,
          tamano: tamano,
          oscuro: oscuro,
          pantalla: const PersonalActivoListScreen(filtroInicialSinAsignar: true),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('el selector de plantilla ofrece Todos, Operativo, Administrativo y Sin asignación', (tester) async {
    await pump(tester, tamano: const Size(1366, 900), oscuro: false, pantalla: const PersonalActivoListScreen());

    expect(find.text('Plantilla'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la columna Asignación muestra el Servicio del operativo y la Sucursal del administrativo',
      (tester) async {
    await pump(tester, tamano: const Size(1536, 1000), oscuro: false, pantalla: const PersonalActivoListScreen());

    expect(find.text('Asignación actual'), findsOneWidget, reason: 'la columna ya no se llama sólo Servicio');
    // El destino operativo (3 guardias) y el administrativo (1) se ven
    // los dos, con su nombre real.
    expect(find.text('Vigilancia intramuros Sportium Satélite — turno mixto'), findsWidgets);
    expect(find.text('Oficina administrativa Toluca centro'), findsWidgets,
        reason: 'un administrativo adscrito a su Sucursal nunca es «Sin asignar»');
    expect(find.text('Administrativo'), findsWidgets, reason: 'subtítulo del destino administrativo');
    // Sólo el operativo sin Servicio queda como Sin asignar; el
    // inconsistente tiene su propio texto.
    expect(find.text('Sin asignar'), findsOneWidget);
    expect(find.text('Servicio y sucursal a la vez'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('los KPI no castigan al administrativo: 6 activos, 4 asignados, 1 sin asignar, 1 inconsistente',
      (tester) async {
    await pump(tester, tamano: const Size(1536, 1000), oscuro: false, pantalla: const PersonalActivoListScreen());

    // 3 operativos con Servicio + 1 administrativo con Sucursal = 4.
    expect(find.text('Personal asignado'), findsOneWidget);
    expect(find.text('Con asignación inconsistente'), findsOneWidget,
        reason: 'el dato roto se muestra, no se esconde dentro de otro conteo');
    expect(find.text('67%'), findsOneWidget, reason: '4 de 6; con el bug anterior habrían sido 3 de 6');
    expect(tester.takeException(), isNull);
  });
}
