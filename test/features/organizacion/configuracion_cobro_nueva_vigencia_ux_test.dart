// Etapa MORGAN ATLACOMULCO — la mitad de UX del bug: al fallar el
// guardado, el diálogo se CERRABA y tiraba toda la captura, dejando solo
// "No se pudo registrar la nueva vigencia. Intenta de nuevo.".
//
// Regla que fijan estas pruebas (la misma establecida en "Crear
// usuario"): nada que el usuario pueda corregir dentro del formulario
// cierra el diálogo; el error se muestra DENTRO, con la captura intacta.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/decision_cierre_nueva_vigencia_cobro.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_cobro_section.dart';

const _mensajeReglas = 'Revisa las reglas de las etapas.';

void main() {
  group('Decisión de cierre del diálogo', () {
    test('REGRESIÓN: un fallo al persistir NO cierra el diálogo, y muestra el motivo real', () {
      final decision = decidirCierreNuevaVigenciaCobro(
        CambiarVigenciaConfiguracionCobroErrorInesperado(
          'SqliteException(1555): UNIQUE constraint failed: configuracion_cobro_etapa.id',
        ),
        mensajeReglasEtapas: _mensajeReglas,
      );

      expect(decision.cierraElDialogo, isFalse, reason: 'cerrarlo tira toda la captura del usuario');
      expect(decision.errorGeneral, contains('UNIQUE constraint failed'));
    });

    test('los errores de campo mantienen el diálogo abierto y viajan a sus controles', () {
      final decision = decidirCierreNuevaVigenciaCobro(
        CambiarVigenciaConfiguracionCobroErroresValidacion(
          const [
            ErrorConfiguracionCobro(
              campo: CampoConfiguracionCobro.fechaInicioVigencia,
              codigo: CodigoErrorConfiguracionCobro.fechaDuplicada,
            ),
          ],
        ),
        mensajeReglasEtapas: _mensajeReglas,
      );

      expect(decision.cierraElDialogo, isFalse);
      expect(decision.errores, hasLength(1));
      expect(decision.errores.single.campo, CampoConfiguracionCobro.fechaInicioVigencia);
      expect(decision.errorGeneral, isNull, reason: 'ese error tiene campo propio: no va al banner general');
    });

    test('las reglas de etapas van al error general, no a un snackbar que se va con el diálogo', () {
      final decision = decidirCierreNuevaVigenciaCobro(
        CambiarVigenciaConfiguracionCobroErroresValidacion(
          const [],
          const [ErrorEtapaCobro(etapaId: 'x', campo: null, codigo: CodigoErrorEtapaCobro.referenciaNoExiste)],
        ),
        mensajeReglasEtapas: _mensajeReglas,
      );

      expect(decision.cierraElDialogo, isFalse);
      expect(decision.errorGeneral, _mensajeReglas);
    });

    test('solo cierran el éxito y los dos casos irrecuperables desde el formulario', () {
      expect(
        decidirCierreNuevaVigenciaCobro(
          CambiarVigenciaConfiguracionCobroExitoso(_vigenciaCualquiera()),
          mensajeReglasEtapas: _mensajeReglas,
        ).cierraElDialogo,
        isTrue,
      );
      // Servicio terminado y configuración inexistente: insistir en el
      // formulario no puede llevar a nada.
      expect(
        decidirCierreNuevaVigenciaCobro(
          CambiarVigenciaConfiguracionCobroServicioNoDisponible(),
          mensajeReglasEtapas: _mensajeReglas,
        ).cierraElDialogo,
        isTrue,
      );
      expect(
        decidirCierreNuevaVigenciaCobro(
          CambiarVigenciaConfiguracionCobroNoExiste(),
          mensajeReglasEtapas: _mensajeReglas,
        ).cierraElDialogo,
        isTrue,
      );
    });

    test('cancelar (resultado nulo) tampoco fuerza ningún error', () {
      final decision = decidirCierreNuevaVigenciaCobro(null, mensajeReglasEtapas: _mensajeReglas);
      expect(decision.cierraElDialogo, isFalse);
      expect(decision.errores, isEmpty);
      expect(decision.errorGeneral, isNull);
    });
  });

  group('El formulario conserva la captura y muestra el error dentro', () {
    testWidgets('un intento fallido deja el diálogo abierto, con los datos escritos y el error visible',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const mensajeDelFallo = 'UNIQUE constraint failed: configuracion_cobro_etapa.id';
      var intentos = 0;
      String? errorGeneral;
      ConfiguracionCobroBorrador? ultimoBorrador;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => RisegDialog.showForm<bool>(
                    context: context,
                    title: 'Nueva vigencia',
                    confirmLabel: 'Guardar',
                    cancelLabel: 'Cancelar',
                    contentBuilder: (_) => ServicioConfiguracionCobroForm(
                      frecuencias: const [],
                      entidadesFiscales: const [],
                      contactos: const [],
                      portales: const [],
                      errorGeneral: errorGeneral,
                      onCambio: (b, _) => ultimoBorrador = b,
                    ),
                    onConfirm: () async {
                      intentos++;
                      // Primer intento: el guardado falla, igual que en
                      // el caso real.
                      final decision = decidirCierreNuevaVigenciaCobro(
                        intentos == 1
                            ? CambiarVigenciaConfiguracionCobroErrorInesperado(mensajeDelFallo)
                            : CambiarVigenciaConfiguracionCobroExitoso(_vigenciaCualquiera()),
                        mensajeReglasEtapas: _mensajeReglas,
                      );
                      errorGeneral = decision.errorGeneral;
                      return decision.cierraElDialogo ? true : null;
                    },
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Captura: el día de inicio del periodo, que es un campo de texto
      // simple y verificable.
      final campoDia = find.byType(RisegTextField).first;
      await tester.enterText(campoDia, '1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();

      // 1. El diálogo SIGUE ABIERTO.
      expect(find.text('Nueva vigencia'), findsOneWidget, reason: 'un fallo al guardar nunca tira la captura');
      // 2. El error se ve DENTRO del formulario.
      expect(find.byKey(const Key('configuracion_cobro_error_general')), findsOneWidget);
      expect(find.textContaining('UNIQUE constraint failed'), findsOneWidget);
      // 3. Lo capturado sigue ahí.
      expect(
        tester.widget<TextField>(find.descendant(of: campoDia, matching: find.byType(TextField))).controller?.text,
        '1',
      );
      expect(ultimoBorrador?.diaInicioPeriodo, 1);

      // 4. Reintentar desde el mismo formulario funciona: la captura no
      //    hubo que volver a escribirla.
      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();
      expect(find.text('Nueva vigencia'), findsNothing, reason: 'al tener éxito sí cierra');
      expect(intentos, 2);
      expect(tester.takeException(), isNull);
    });
  });
}

ConfiguracionCobroVigenciaData _vigenciaCualquiera() => ConfiguracionCobroVigenciaData(
      id: 'v1',
      configuracionCobroId: 'c1',
      tipoDocumento: 'reciboDePago',
      frecuenciaId: 'f1',
      diaInicioPeriodo: 1,
      agrupacion: 'porServicio',
      metodo: 'noAplica',
      requiereComplemento: false,
      fechaInicioVigencia: DateTime(2026, 9, 1),
      cicloVidaRegistro: 'activo',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
