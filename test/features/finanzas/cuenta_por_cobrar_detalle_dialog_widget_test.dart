// Saneamiento post-auditoría 19A-19D — regresión visual real reportada
// en producción: el encabezado del Detalle de Cuenta por cobrar
// desbordaba cuando el nombre del Cliente + el botón "Ver expediente" +
// el badge "Cierre de cobranza pendiente (falta Complemento)" (el más
// largo de los dos badges posibles) no cabían juntos en el ancho fijo
// del diálogo (560px) — el `Expanded` del nombre del Cliente se
// exprimía a ~0px y su texto se partía letra por letra.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/widgets/cuenta_por_cobrar_detalle_dialog.dart';
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
  testWidgets(
    'nombre de Cliente largo + badge "Cierre de cobranza pendiente" no desbordan el encabezado',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.usuario).insert(
            UsuarioCompanion.insert(
              id: const Value('usuario-maestro'),
              nombre: 'Maestro de prueba',
              nombreUsuario: 'usuario-maestro',
              passwordHash: 'x',
            ),
          );

      final ahora = DateTime.now();
      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(
              codigo: 'CLI-OVERFLOW-01',
              nombreComercial: 'Sportium Cuautitlán de la Suárez y Asociados S.A. de C.V.',
            ),
          );
      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-OVERFLOW-01',
              clienteId: cliente.id,
              tipoDocumento: 'cfdi',
              agrupacion: 'porServicio',
              metodo: 'ppd',
              periodoInicio: ahora,
              periodoFin: ahora,
              generationKey: 'clave-overflow-01',
              importeBaseEsperado: 2146000,
              importeFinalEsperado: 2146000,
            ),
          );
      final cxc = await db.into(db.cuentaPorCobrar).insertReturning(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: Value(documento.id),
              clienteId: Value(cliente.id),
              tipoDocumento: 'cfdi',
              metodo: 'ppd',
              requiereComplemento: const Value(true),
              fechaEmisionReal: ahora,
              importeEmitido: 2146000,
              saldoOriginal: 2146000,
              saldoPendiente: 2146000,
              fechaVencimiento: Value(ahora.add(const Duration(days: 20))),
            ),
          );

      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ]);
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: Material(
                  child: CuentaPorCobrarDetalleDialog(cuentaPorCobrarId: cxc.id),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'el encabezado (Cliente + botón + badges) nunca debe desbordar, sin importar qué tan largos sean el nombre y el badge');
      expect(find.textContaining('Sportium Cuautitlán'), findsWidgets);
    },
  );
}
