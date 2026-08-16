// Pruebas de widget del editor de "Horario personalizado" dentro de
// `ServicioLineaComercialForm` (Etapa 15) — montado de forma aislada
// (sin base de datos ni Riverpod: el widget no depende de ninguno de
// los dos), igual criterio que `riseg_time_field_test.dart`. Cubre
// específicamente el comportamiento pedido por Marlon:
//  - elegir Personalizado hace visible la sección de horario;
//  - cambiar a otra modalidad la oculta y el borrador notificado deja
//    de llevar horario (nunca "basura inválida" capturada antes del
//    cambio).

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_comercial_section.dart';

Finder _selector(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is RisegSelect && w.label == label),
      matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
    );

Future<void> _elegirEnSelector(WidgetTester tester, String label, String opcionTexto) async {
  await tester.ensureVisible(_selector(label));
  await tester.tap(_selector(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcionTexto).last);
  await tester.pumpAndSettle();
}

void main() {
  final puestos = [
    PuestoData(
      id: 'puesto-1',
      codigo: 'PUE-0001',
      nombre: 'Elemento Operativo',
      areaId: 'area-1',
      tipo: 'operativo',
      nivelJerarquico: 5,
      cicloVidaRegistro: 'activo',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];
  final modalidades = const [
    CatalogoItem(id: SeedIds.modalidadTurno24x24, codigo: '24X24', nombre: '24×24'),
    CatalogoItem(id: SeedIds.modalidadTurnoPersonalizado, codigo: 'PERSONALIZADO', nombre: 'Personalizado'),
  ];

  Future<AppLocalizations> pumpFormulario(WidgetTester tester, {required ValueChanged<LineaComercialBorrador> onCambio}) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServicioLineaComercialForm(puestos: puestos, modalidadesTurno: modalidades, onCambio: onCambio),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.delegate.load(const Locale('es'));
  }

  testWidgets('elegir Personalizado hace visible la sección de Horario personalizado', (tester) async {
    final l10n = await pumpFormulario(tester, onCambio: (_) {});

    expect(find.text(l10n.servicioComercialHorarioPersonalizadoTitulo), findsNothing);

    await _elegirEnSelector(tester, l10n.servicioComercialCampoModalidadTurno, 'Personalizado');

    expect(find.text(l10n.servicioComercialHorarioPersonalizadoTitulo), findsOneWidget);
    expect(find.text(l10n.horarioDiaLunes), findsOneWidget);
    expect(find.text(l10n.horarioDiaDomingo), findsOneWidget);
  });

  testWidgets(
    'cambiar de Personalizado a 24×24 oculta el editor y el borrador notificado deja de llevar horario',
    (tester) async {
      LineaComercialBorrador? ultimoBorrador;
      final l10n = await pumpFormulario(tester, onCambio: (b) => ultimoBorrador = b);

      await _elegirEnSelector(tester, l10n.servicioComercialCampoModalidadTurno, 'Personalizado');
      expect(find.text(l10n.servicioComercialHorarioPersonalizadoTitulo), findsOneWidget);

      // Activa "Trabaja" el lunes y captura horas — datos reales
      // capturados antes de cambiar de modalidad.
      final switchLunes = find.byType(Switch).first;
      await tester.tap(switchLunes);
      await tester.pumpAndSettle();
      final camposHora = find.byType(RisegTimeField);
      expect(camposHora, findsNWidgets(2), reason: 'entrada y salida del lunes, único día activado');
      tester.widget<RisegTimeField>(camposHora.first).onChanged(const TimeOfDay(hour: 20, minute: 0));
      await tester.pumpAndSettle();
      tester.widget<RisegTimeField>(camposHora.last).onChanged(const TimeOfDay(hour: 7, minute: 0));
      await tester.pumpAndSettle();
      expect(ultimoBorrador!.horario, isNotNull);

      await _elegirEnSelector(tester, l10n.servicioComercialCampoModalidadTurno, '24×24');

      expect(find.text(l10n.servicioComercialHorarioPersonalizadoTitulo), findsNothing, reason: 'el editor desaparece por completo');
      expect(
        ultimoBorrador!.horario,
        isNull,
        reason: 'el borrador notificado nunca debe llevar horario cuando la modalidad ya no es Personalizado — '
            'aunque el lunes siga "activado" en el estado interno del formulario, eso nunca debe llegar a persistirse',
      );
    },
  );
}
