// El mensaje de saldo insuficiente, presentado igual en todas las
// pantallas.
//
// Cierra el requisito UX: una pantalla sin multicuenta dice "Selecciona
// otra cuenta"; Nómina, que sí reparte, añade la variante; y cualquier
// error que NO sea de saldo sigue usando su mensaje genérico.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async => l10n = await AppLocalizations.delegate.load(const Locale('es')));

  const insuficiente = SaldoInsuficiente(
    cuentaId: 'cta-1',
    cuentaNombre: 'Cuenta de prueba',
    disponible: 469867,
    requerido: 980000,
  );

  group('Texto del veredicto', () {
    test('1. sin multicuenta: pide elegir otra cuenta, con los tres números', () {
      final mensaje = mensajeDeVeredictoSaldo(l10n, insuficiente)!;

      expect(mensaje, contains('Cuenta de prueba'));
      expect(mensaje, contains(r'$4,698.67'), reason: 'disponible');
      expect(mensaje, contains(r'$9,800.00'), reason: 'requerido');
      expect(mensaje, contains(r'$5,101.33'), reason: 'faltante');
      expect(mensaje, contains('Selecciona otra cuenta.'));
      expect(
        mensaje,
        isNot(contains('distribuye')),
        reason: 'sugerir repartir sería una instrucción falsa donde no se puede',
      );
    });

    test('2. con multicuenta (Nómina): añade la opción de distribuir', () {
      final mensaje = mensajeDeVeredictoSaldo(l10n, insuficiente, soportaMulticuenta: true)!;

      expect(mensaje, contains('Cuenta de prueba'));
      expect(mensaje, contains(r'$5,101.33'));
      expect(mensaje, contains('distribuye el pago entre varias cuentas'));
    });

    test('el faltante se deriva, nunca se pasa a mano', () {
      expect(insuficiente.faltante, 980000 - 469867);
    });

    test('la fecha anterior al saldo inicial tiene su propio texto', () {
      final mensaje = mensajeDeVeredictoSaldo(
        l10n,
        FechaAnteriorAlSaldoInicial(
          cuentaId: 'cta-1',
          cuentaNombre: 'Cuenta de prueba',
          fechaMovimiento: DateTime(2026, 5, 31),
          fechaSaldoInicial: DateTime(2026, 6, 1),
        ),
      )!;
      expect(mensaje, contains('Cuenta de prueba'));
      expect(mensaje, contains('01/06/2026'));
      expect(mensaje, contains('fecha igual o posterior'));
    });

    test('un saldo suficiente no produce mensaje', () {
      expect(mensajeDeVeredictoSaldo(l10n, const SaldoSuficiente()), isNull);
    });
  });

  group('El mecanismo central', () {
    testWidgets('traduce la excepción del embudo y no deja pasar el resultado', (tester) async {
      String? capturado;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final r = await ejecutarMostrandoSaldoInsuficiente<String>(
                    context,
                    AppLocalizations.of(context)!,
                    () async => throw SaldoInsuficienteException(insuficiente),
                  );
                  capturado = r;
                },
                child: const Text('ir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ir'));
      await tester.pumpAndSettle();

      expect(capturado, isNull, reason: 'devuelve null para que el formulario siga abierto');
      expect(find.textContaining('Saldo insuficiente en Cuenta de prueba'), findsOneWidget);
      expect(find.textContaining('Selecciona otra cuenta.'), findsOneWidget);
    });

    testWidgets('3. un error que NO es de saldo se propaga: lo maneja el mensaje genérico', (tester) async {
      Object? propagado;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  try {
                    await ejecutarMostrandoSaldoInsuficiente<String>(
                      context,
                      AppLocalizations.of(context)!,
                      () async => throw StateError('otra cosa'),
                    );
                  } catch (e) {
                    propagado = e;
                  }
                },
                child: const Text('ir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ir'));
      await tester.pumpAndSettle();

      expect(propagado, isA<StateError>(), reason: 'el helper NO se traga otros errores');
      expect(find.byType(SnackBar), findsNothing, reason: 'y no muestra el mensaje de saldo');
    });

    testWidgets('con éxito devuelve el resultado tal cual y no muestra nada', (tester) async {
      String? capturado;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  capturado = await ejecutarMostrandoSaldoInsuficiente<String>(
                    context,
                    AppLocalizations.of(context)!,
                    () async => 'ok',
                  );
                },
                child: const Text('ir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ir'));
      await tester.pumpAndSettle();

      expect(capturado, 'ok');
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  test('el formato de importes es el canónico del proyecto, no uno por módulo', () {
    expect(formatoImporteSaldo(469867), r'$4,698.67');
    expect(formatoImporteSaldo(0), r'$0.00');
  });
}
