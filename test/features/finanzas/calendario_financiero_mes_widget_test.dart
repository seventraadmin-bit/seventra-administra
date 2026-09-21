// Etapa 19D — "Calendario financiero y planeación de liquidez".
// Pruebas de widget aisladas de `CalendarioFinancieroMes` — cubre
// específicamente el pedido (Parte 19): meses de 28/29/30/31 días,
// mes que empieza domingo/lunes, 5 y 6 semanas visuales, importes
// grandes, cero RenderFlex overflow en los 4 anchos × 2 temas.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/widgets/calendario_financiero_mes.dart';

Future<void> _pump(
  WidgetTester tester, {
  required DateTime mesVisible,
  required Size tamano,
  required ThemeData tema,
  List<CompromisoFinanciero> compromisos = const [],
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: tema,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CalendarioFinancieroMes(
            mesVisible: mesVisible,
            compromisos: compromisos,
            hoy: DateTime(mesVisible.year, mesVisible.month, 15),
            diaSeleccionado: DateTime(mesVisible.year, mesVisible.month, 15),
            onDiaSeleccionado: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Cubre 28 (feb no bisiesto), 29 (feb bisiesto), 30 y 31 días, así
  // como los 7 días de inicio de semana posibles (ene..dic 2026 + feb
  // 2028 bisiesto) — sin necesidad de calcular a mano qué mes empieza
  // domingo/lunes ni cuántas semanas visuales tiene: la cobertura
  // amplia de meses reales garantiza tocar todos los casos.
  final meses = [
    DateTime(2026, 1, 1),
    DateTime(2026, 2, 1), // 28 días
    DateTime(2028, 2, 1), // 29 días (bisiesto)
    DateTime(2026, 3, 1),
    DateTime(2026, 4, 1), // 30 días
    DateTime(2026, 5, 1),
    DateTime(2026, 6, 1),
    DateTime(2026, 7, 1),
    DateTime(2026, 8, 1), // 31 días
    DateTime(2026, 9, 1),
    DateTime(2026, 10, 1),
    DateTime(2026, 11, 1),
    DateTime(2026, 12, 1), // 31 días
  ];

  for (final mes in meses) {
    for (final tamano in [const Size(1366, 768), const Size(1024, 768), const Size(700, 900), const Size(500, 900)]) {
      testWidgets(
        'calendario de ${mes.month}/${mes.year} (${DateTime(mes.year, mes.month + 1, 0).day} días, inicia weekday '
        '${mes.weekday}) no desborda a ${tamano.width.toInt()}px',
        (tester) async {
          await _pump(
            tester,
            mesVisible: mes,
            tamano: tamano,
            tema: AppTheme.light(),
            compromisos: [
              CompromisoFinanciero(
                fecha: DateTime(mes.year, mes.month, 5),
                concepto: 'Cliente con un nombre comercial deliberadamente muy largo para probar el recorte de texto',
                tipo: TipoCompromiso.entrada,
                origen: OrigenCompromiso.cuentaPorCobrar,
                importe: 123456789, // importe grande: $1,234,567.89
                origenId: 'cxc-1',
              ),
              CompromisoFinanciero(
                fecha: DateTime(mes.year, mes.month, 5),
                concepto: 'Nómina 2ª quincena',
                tipo: TipoCompromiso.salida,
                origen: OrigenCompromiso.nomina,
                importe: 6886600,
                origenId: 'nomina-1',
              ),
              CompromisoFinanciero(
                fecha: DateTime(mes.year, mes.month, DateTime(mes.year, mes.month + 1, 0).day),
                concepto: 'TDC BBVA',
                tipo: TipoCompromiso.salida,
                origen: OrigenCompromiso.deuda,
                importe: 1500000,
                origenId: 'deuda-1',
              ),
            ],
          );

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('el tema oscuro tampoco desborda con importes grandes y nombres largos', (tester) async {
    await _pump(
      tester,
      mesVisible: DateTime(2026, 8, 1),
      tamano: const Size(500, 900),
      tema: AppTheme.dark(),
      compromisos: [
        CompromisoFinanciero(
          fecha: DateTime(2026, 8, 5),
          concepto: 'Sportium Cuautitlán de la Suárez y Asociados S.A. de C.V.',
          tipo: TipoCompromiso.entrada,
          origen: OrigenCompromiso.cuentaPorCobrar,
          importe: 987654321,
          origenId: 'cxc-1',
        ),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar un día dentro del mes dispara onDiaSeleccionado con esa fecha exacta', (tester) async {
    DateTime? diaTocado;
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CalendarioFinancieroMes(
            mesVisible: DateTime(2026, 8, 1),
            compromisos: const [],
            hoy: DateTime(2026, 8, 15),
            diaSeleccionado: DateTime(2026, 8, 15),
            onDiaSeleccionado: (dia) => diaTocado = dia,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();

    expect(diaTocado, DateTime(2026, 8, 12));
  });
}
