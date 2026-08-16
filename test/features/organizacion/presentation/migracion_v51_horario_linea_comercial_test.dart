// Reproducción del bloqueo real reportado por Marlon (Etapa 15,
// Horario personalizado): al abrir el expediente de un Servicio real
// con `ServicioLineaComercialVigencia` ya existentes, cuya base de
// datos todavía estaba en `schemaVersion` 50 (nunca reabierta tras el
// cambio de código a 51 — el escenario real fue un hot reload que
// nunca disparó `onUpgrade`), la pantalla lanzaba
// `SqliteException(1): no such table: servicio_linea_comercial_vigencia_horario`.
//
// Confirmado que NO era un bug del wiring (`migrarHorarioLineaComercialV51`
// ya estaba correctamente enlazado en `MigrationStrategy.onUpgrade`,
// `to >= 51 && from <= 50`) — el problema era exclusivamente que la
// base real del usuario seguía en `user_version = 50`. Esta prueba
// cubre exactamente la ruta real de migración (nunca solo el schema
// dump aislado): parte de un snapshot v50 con datos reales de
// Servicio/Línea/Vigencia, migra con el código actual, y confirma que
// el expediente completo abre sin excepción — no solo que la tabla
// exista.

import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../../generated_migrations/schema.dart';

class _SesionControllerDePrueba extends SesionController {
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

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget pantalla) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: pantalla,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'migración real 50 → 51: tabla nueva creada, datos intactos, FK/integrity limpios, y '
    'ServicioExpedienteScreen abre sin excepción sobre una línea comercial real ya existente',
    (tester) async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schemaV50 = await verifier.schemaAt(50);
      final raw = schemaV50.rawDatabase;

      raw.execute('''
        INSERT INTO usuario (id, nombre, nombre_usuario, password_hash, created_at, updated_at, ciclo_vida_registro)
        VALUES ('usuario-prueba', 'Usuario de prueba', 'usuario-prueba', 'x', 1700000000, 1700000000, 'activo');
      ''');
      raw.execute('''
        INSERT INTO cliente (id, codigo, nombre_comercial, estatus, fecha_alta, created_at, updated_at, ciclo_vida_registro)
        VALUES ('cliente-real', 'CLI-000091', 'Vigilancia Real', 'activo', 1700000000, 1700000000, 1700000000, 'activo');
      ''');
      raw.execute('''
        INSERT INTO tipo_servicio (id, codigo, nombre, created_at, updated_at)
        VALUES ('${SeedIds.tipoServicioVigilanciaFija}', 'VIGILANCIA_FIJA', 'Vigilancia fija', 1700000000, 1700000000);
      ''');
      raw.execute('''
        INSERT INTO area (id, codigo, nombre, activo, created_at, updated_at)
        VALUES ('${SeedIds.areaOperaciones}', 'OPERACIONES', 'Operaciones', 1, 1700000000, 1700000000);
      ''');
      raw.execute('''
        INSERT INTO tipo_modalidad_turno (id, codigo, nombre, created_at, updated_at)
        VALUES ('${SeedIds.modalidadTurno24x24}', '24X24', '24x24', 1700000000, 1700000000);
      ''');
      raw.execute('''
        INSERT INTO servicio (
          id, codigo, cliente_id, nombre, tipo_servicio_id, estatus, fecha_inicio,
          elementos_autorizados, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'servicio-real', 'SRV-000091', 'cliente-real', 'Vigilancia Real', '${SeedIds.tipoServicioVigilanciaFija}',
          'activo', 1700000000, 2, 1700000000, 1700000000, 'activo'
        );
      ''');
      raw.execute('''
        INSERT INTO puesto (id, codigo, nombre, area_id, tipo, nivel_jerarquico, created_at, updated_at, ciclo_vida_registro)
        VALUES ('puesto-real', 'PUE-000091', 'Elemento Operativo', '${SeedIds.areaOperaciones}', 'operativo', 5,
          1700000000, 1700000000, 'activo');
      ''');
      raw.execute('''
        INSERT INTO servicio_linea_comercial (id, servicio_id, created_at, updated_at, ciclo_vida_registro)
        VALUES ('linea-real', 'servicio-real', 1700000000, 1700000000, 'activo');
      ''');
      raw.execute('''
        INSERT INTO servicio_linea_comercial_vigencia (
          id, linea_comercial_id, puesto_id, modalidad_turno_id, cantidad_elementos, precio_unitario,
          tratamiento_iva, fecha_inicio_vigencia, created_at, updated_at, ciclo_vida_registro
        ) VALUES (
          'vigencia-real', 'linea-real', 'puesto-real', '${SeedIds.modalidadTurno24x24}',
          2, 1500000, 'masIva', 1700000000, 1700000000, 1700000000, 'activo'
        );
      ''');

      final db = AppDatabase(schemaV50.newConnection());
      await verifier.migrateAndValidate(db, 51);

      // 1. La tabla nueva existe.
      final tablas = (await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'servicio_linea_comercial_vigencia_horario'",
      ).get());
      expect(tablas, hasLength(1), reason: 'la migración 50→51 debe crear servicio_linea_comercial_vigencia_horario');

      // 2. Los datos anteriores permanecen intactos.
      final vigencia =
          await (db.select(db.servicioLineaComercialVigencia)..where((t) => t.id.equals('vigencia-real'))).getSingle();
      expect(vigencia.cantidadElementos, 2);
      expect(vigencia.precioUnitario, 1500000);
      final servicio = await (db.select(db.servicio)..where((t) => t.id.equals('servicio-real'))).getSingle();
      expect(servicio.nombre, 'Vigilancia Real');

      // 3. FK check sin violaciones.
      final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violacionesFk, isEmpty);

      // 4. integrity_check = ok.
      final integridad =
          await db.customSelect('PRAGMA integrity_check').map((r) => r.data['integrity_check'] as String).get();
      expect(integridad, ['ok']);

      // 5. El expediente real abre sin excepción — exactamente la
      // pantalla que fallaba en producción con la base sin migrar.
      await _pump(tester, db, const ServicioExpedienteScreen(servicioId: 'servicio-real'));
      expect(tester.takeException(), isNull, reason: 'el expediente debe abrir sin excepción con datos reales migrados de v50 a v51');
      expect(find.text('Vigilancia Real'), findsWidgets);
      expect(find.text('Elemento Operativo'), findsOneWidget);

      await db.close();
    },
  );
}
