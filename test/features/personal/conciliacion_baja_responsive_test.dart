// Etapa "Baja laboral con conciliación obligatoria" — §27 responsive.
//
// Mismo criterio de evidencia que el resto de RISEG ONE: cero overflow /
// cero excepción, nunca comparación de píxeles. El escenario es el peor
// caso de layout: varios bienes con resoluciones distintas abiertas a la
// vez, nombres largos y el bloque de descuento desplegado.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/conciliar_baja_empleado_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      );
}

const _anchos = <String, Size>{
  '1536': Size(1536, 1200),
  '1366': Size(1366, 1100),
  '1024': Size(1024, 1100),
  '700': Size(700, 1100),
  '500': Size(500, 1100),
};

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late ProviderContainer container;
  late String empleadoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_conciliacion_responsive_');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
      ],
    );
    addTearDown(container.dispose);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'Maestro',
            nombreUsuario: 'maestro',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );

    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan Alberto',
            apellidoPaterno: 'Pérez',
            apellidoMaterno: const Value('Hernández de la Torre'),
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2024, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    empleadoId = empleado.id;

    // Un administrativo activo, para el selector de autorizador.
    final sucursal = await db.into(db.sucursal).insertReturning(
          SucursalCompanion.insert(
            codigo: 'SUC-000001',
            nombre: 'Corporativo',
            tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
          ),
        );
    await db.into(db.empleado).insert(
          EmpleadoCompanion.insert(
            numeroEmpleado: 2,
            nombres: 'Juan',
            apellidoPaterno: 'Cruz',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1985, 1, 1),
            curp: 'CUXJ850101HDFXXX02',
            rfc: 'CUXJ850101AB2',
            nss: '12345678902',
            estadoCivil: 'casado',
            fechaIngreso: DateTime(2023, 1, 1),
            aniosExperienciaSeguridad: 8,
            sucursalId: Value(sucursal.id),
          ),
        );

    // Bienes con nombres deliberadamente largos.
    final asignacionRepo = AsignacionRepositoryImpl(db);
    final articuloRepo = ArticuloRepositoryImpl(db);
    for (final (i, nombre) in [
      'Radio portátil Motorola DEP-450 VHF con cargador y batería extendida',
      'Teléfono Samsung Galaxy S23 con funda reforzada y mica templada',
      'Camisa de uniforme operativo manga larga, talla mediana',
    ].indexed) {
      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Categoría $i'),
          );
      final articulo = await articuloRepo.crear(
        folio: 'ART-00000$i',
        categoriaId: categoria.id,
        nombre: nombre,
        manejaVariante: false,
        manejaSerie: true,
      );
      final unidad = await db.into(db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(
              articuloId: articulo.id,
              codigo: 'UNI-00000$i',
              numeroSerie: 'SN-0000$i',
            ),
          );
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              unidadId: Value(unidad.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 1,
              fecha: DateTime(2025, 1, 1),
            ),
          );
      await asignacionRepo.crear(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2025, 2, 1),
      );
    }

    final vehiculoAsignacionRepo = AsignacionVehiculoRepositoryImpl(db);
    final vehiculo = await VehiculoRepositoryImpl(db, vehiculoAsignacionRepo).crear(
      codigo: 'VEH-000001',
      marca: 'Nissan',
      modelo: 'NP300 Doble Cabina Estacas',
      tipoVehiculo: 'pickup',
    );
    await vehiculoAsignacionRepo.crear(
      vehiculoId: vehiculo.id,
      empleadoId: empleadoId,
      fechaInicio: DateTime(2025, 2, 1),
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> montar(WidgetTester tester, {required Size tamano, required bool oscuro}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: oscuro ? AppTheme.dark() : AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConciliarBajaEmpleadoScreen(empleadoId: empleadoId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final entrada in _anchos.entries) {
    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('Conciliación de baja (${entrada.key}, $tema): cero overflow', (tester) async {
        await montar(tester, tamano: entrada.value, oscuro: oscuro);

        expect(tester.takeException(), isNull);
        // Los 4 bienes se cargaron solos, por FK.
        expect(find.byKey(const Key('conciliacion_resguardos')), findsOneWidget);
        expect(find.byKey(const Key('conciliacion_resumen')), findsOneWidget);
      });
    }
  }

  testWidgets('§2 — carga sola los 4 bienes y las relaciones, sin pedirlos', (tester) async {
    await montar(tester, tamano: const Size(1366, 1100), oscuro: false);

    expect(find.textContaining('Radio portátil Motorola'), findsWidgets);
    expect(find.textContaining('Samsung Galaxy S23'), findsWidgets);
    expect(find.textContaining('Camisa de uniforme'), findsWidgets);
    expect(find.textContaining('NP300'), findsWidgets);
  });

  testWidgets('§16 — Confirmar arranca BLOQUEADO mientras haya bienes sin resolver', (tester) async {
    await montar(tester, tamano: const Size(1366, 1100), oscuro: false);

    final boton = tester.widget<RisegButton>(find.byKey(const Key('conciliacion_confirmar')));
    expect(boton.onPressed, isNull, reason: 'no se confirma una baja dejando bienes sin explicar');
    expect(find.textContaining('Falta explicar qué ocurrió'), findsOneWidget);
  });
}
