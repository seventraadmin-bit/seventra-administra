// Ruta REAL del botón: UI → controller/fachada → caso de uso →
// repositorio → Finanzas.
//
// Por qué existe: en la etapa de Tiempo Extra, todas las pruebas nuevas
// entraban por el caso de uso y una prevalidación heredada del diálogo
// bloqueó el flujo en producción sin que ninguna prueba se enterara.
// Una recarga que no llega a crear su Egreso es el mismo tipo de fallo:
// invisible desde el dominio, evidente al apretar Guardar.
//
// Aquí se aprieta el botón de verdad y se verifica lo que quedó en la
// base: la recarga, su Egreso o su cargo de tarjeta, y la ausencia del
// otro.

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
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/presentation/widgets/registrar_recarga_linea_telefonica_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late String lineaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_recarga_submit_');

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );

    final linea = await db.into(db.lineaTelefonica).insertReturning(
          LineaTelefonicaCompanion.insert(
            codigo: 'LIN-000001',
            numero: const Value('7225562629'),
            operador: OperadorTelefonico.telcel.name,
            modalidadSim: ModalidadSim.fisica.name,
          ),
        );
    lineaId = linea.id;

    await db.into(db.cuentaFinanciera).insert(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-0001',
            nombre: 'BBVA Empresarial',
            tipo: TipoCuentaFinanciera.banco.name,
            saldoInicial: 10000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );

    await db.into(db.deuda).insert(
          DeudaCompanion.insert(
            folio: 'DEU-000001',
            nombre: 'TDC Corporativa',
            tipo: TipoDeuda.tarjetaCredito.name,
            saldoActual: 0,
            tarjetaLimiteCredito: const Value(5000000),
            estatus: const Value('activa'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> abrirDialogo(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestro.new),
          attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: RisegButton(
                  label: 'Abrir',
                  onPressed: () => mostrarDialogoRegistrarRecargaLineaTelefonica(context, ref, lineaId),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> elegirEnSelect(WidgetTester tester, Key clave, String opcion) async {
    final selector = find.byKey(clave);
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    // La tarjeta se muestra como "Nombre · ", así que la
    // opción se localiza por coincidencia parcial.
    await tester.tap(find.textContaining(opcion).last);
    await tester.pumpAndSettle();
  }

  Future<void> escribirImporte(WidgetTester tester, String texto) async {
    final campo = find.byKey(const Key('recarga_campo_importe'));
    await tester.ensureVisible(campo);
    await tester.pumpAndSettle();
    await tester.enterText(campo, texto);
    await tester.pumpAndSettle();
  }

  Future<void> guardar(WidgetTester tester, AppLocalizations l10n) async {
    final boton = find.widgetWithText(RisegButton, l10n.lineaTelefonicaRecargaBotonGuardar);
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  testWidgets('Registrar recarga → Cuenta → Guardar: crea la recarga y UN Egreso real', (tester) async {
    await abrirDialogo(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await escribirImporte(tester, '200.00');
    await elegirEnSelect(tester, const Key('recarga_campo_forma_pago'), l10n.formaPagoTransferencia);
    await elegirEnSelect(tester, const Key('recarga_campo_cuenta'), 'BBVA Empresarial');
    await guardar(tester, l10n);

    expect(tester.takeException(), isNull);

    final recargas = await db.select(db.recargaLineaTelefonica).get();
    expect(recargas, hasLength(1), reason: 'el botón tiene que llegar a la base');
    expect(recargas.single.importe, 20000);
    expect(recargas.single.formaPago, 'transferencia');
    expect(recargas.single.egresoId, isNotNull, reason: 'Cuenta → Egreso automático');
    expect(recargas.single.deudaId, isNull);

    final egresos = await db.select(db.egreso).get();
    expect(egresos, hasLength(1));
    expect(egresos.single.monto, 20000);
    expect(egresos.single.concepto, contains('7225562629'));
    expect(await db.select(db.movimientoDeuda).get(), isEmpty);
  });

  testWidgets('Registrar recarga → TDC → Guardar: crea UN cargo de tarjeta y CERO Egresos', (tester) async {
    await abrirDialogo(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await escribirImporte(tester, '200.00');
    await elegirEnSelect(tester, const Key('recarga_campo_forma_pago'), l10n.formaPagoTarjeta);
    await elegirEnSelect(tester, const Key('recarga_campo_tarjeta'), 'TDC Corporativa');
    await guardar(tester, l10n);

    expect(tester.takeException(), isNull);

    final recargas = await db.select(db.recargaLineaTelefonica).get();
    expect(recargas, hasLength(1));
    expect(recargas.single.deudaId, isNotNull, reason: 'TDC → cargo a la deuda');
    expect(recargas.single.egresoId, isNull, reason: 'a crédito nunca sale dinero del banco');

    expect(await db.select(db.egreso).get(), isEmpty);
    final cargos = await db.select(db.movimientoDeuda).get();
    expect(cargos, hasLength(1));
    expect(cargos.single.importe, 20000);
    expect(cargos.single.recargaLineaTelefonicaId, recargas.single.id, reason: 'FK real, nunca por concepto');

    final tarjeta = (await db.select(db.deuda).get()).single;
    expect(tarjeta.saldoActual, 20000);
  });

  testWidgets('Sin origen de pago el botón NO registra nada y lo dice', (tester) async {
    await abrirDialogo(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await escribirImporte(tester, '200.00');
    await guardar(tester, l10n);

    expect(find.text(l10n.recargaOrigenFinancieroRequerido), findsOneWidget);
    expect(await db.select(db.recargaLineaTelefonica).get(), isEmpty,
        reason: 'una recarga sin origen financiero nunca debe llegar a la base');
    expect(await db.select(db.egreso).get(), isEmpty);
  });

  testWidgets('Forma de pago elegida pero sin cuenta: pide la cuenta, no registra', (tester) async {
    await abrirDialogo(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await escribirImporte(tester, '200.00');
    await elegirEnSelect(tester, const Key('recarga_campo_forma_pago'), l10n.formaPagoTransferencia);
    await guardar(tester, l10n);

    expect(find.text(l10n.recargaCuentaRequerida), findsOneWidget);
    expect(await db.select(db.recargaLineaTelefonica).get(), isEmpty);
  });
}
