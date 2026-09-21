// Etapa 16 — previsualización de la Tarjeta fiscal. Cubre: datos
// incompletos bloquean con mensaje claro y ofrecen "Editar empresa";
// con datos completos, la previsualización muestra los datos reales
// (razón social/RFC/domicilio/contacto); "Copiar datos" copia el texto
// esperado al portapapeles; responsive sin overflow; tema oscuro.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_data.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/widgets/tarjeta_fiscal_dialog.dart';

EmpresaData _empresa({String? razonSocial, String? rfc}) {
  final ahora = DateTime(2026, 1, 1);
  return EmpresaData(
    id: 'empresa-1',
    codigo: 'RSG-01',
    razonSocial: razonSocial,
    nombreComercial: 'Seguridad Privada RISEG',
    rfc: rfc,
    representanteLegal: null,
    eslogan: null,
    logoAttachmentId: null,
    cicloVidaRegistro: 'activo',
    createdAt: ahora,
    updatedAt: ahora,
  );
}

DireccionData _direccion() {
  final ahora = DateTime(2026, 1, 1);
  return DireccionData(
    id: 'direccion-1',
    empresaId: 'empresa-1',
    sucursalId: null,
    clienteId: null,
    servicioId: null,
    entidadFiscalId: null,
    empleadoId: null,
    tipoDireccion: 'fiscal',
    esPrincipal: true,
    calle: 'Valle de los Reyes',
    numeroExterior: '2',
    numeroInterior: '9',
    colonia: 'Valle del Nevado',
    municipioAlcaldia: 'Calimaya',
    ciudadLocalidad: null,
    estado: 'Estado de México',
    codigoPostal: '52224',
    pais: 'México',
    referencias: null,
    cicloVidaRegistro: 'activo',
    createdAt: ahora,
    updatedAt: ahora,
  );
}

MedioContactoData _contacto() {
  final ahora = DateTime(2026, 1, 1);
  return MedioContactoData(
    id: 'contacto-1',
    empresaId: 'empresa-1',
    sucursalId: null,
    telefono: '5555555555',
    correo: 'facturacion@riseg.mx',
    sitioWeb: null,
    etiqueta: 'principal',
    cicloVidaRegistro: 'activo',
    createdAt: ahora,
    updatedAt: ahora,
  );
}

final _datosCompletos = EmpresaExpedienteData(
  empresa: _empresa(razonSocial: 'CORPORATIVO DE SEGURIDAD PRIVADA RIZEG SAS DE CV', rfc: 'CSP123456AB1'),
  direccionFiscal: _direccion(),
  medioContacto: _contacto(),
);

Future<void> _pump(WidgetTester tester, EmpresaExpedienteData datos, {Size tamano = const Size(700, 900), ThemeData? tema}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: tema ?? AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => mostrarDialogoTarjetaFiscal(context, datos),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  // Sin `pumpAndSettle()`: la previsualización incluye `Image.asset` del
  // logotipo institucional, cuya decodificación real puede dejar un
  // frame pendiente indefinidamente para `pumpAndSettle` (mismo hallazgo
  // ya documentado con `FileImage` en `personal_bajas_responsive_widget_test.dart`).
  // Un número acotado de `pump()` es suficiente para asentar la UI.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Datos incompletos — bloqueo claro', () {
    testWidgets('faltan razón social, RFC y domicilio: se listan los 3, sin previsualización', (tester) async {
      final sinDatos = EmpresaExpedienteData(empresa: _empresa());
      await _pump(tester, sinDatos);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Razón social'), findsOneWidget);
      expect(find.textContaining('RFC'), findsOneWidget);
      expect(find.textContaining('Dirección fiscal'), findsOneWidget);
      expect(find.text('DATOS PARA FACTURACIÓN'), findsNothing, reason: 'no debe mostrarse una previsualización luciendo completa');
    });

    testWidgets('"Editar empresa" cierra el diálogo devolviendo true', (tester) async {
      late bool resultado;
      final sinDatos = EmpresaExpedienteData(empresa: _empresa());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => resultado = await mostrarDialogoTarjetaFiscal(context, sinDatos),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();

      expect(resultado, isTrue);
    });

    testWidgets('"Cerrar" cierra el diálogo devolviendo false', (tester) async {
      late bool resultado;
      final sinDatos = EmpresaExpedienteData(empresa: _empresa());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => resultado = await mostrarDialogoTarjetaFiscal(context, sinDatos),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(resultado, isFalse);
    });
  });

  group('Previsualización — datos reales', () {
    testWidgets('muestra razón social, RFC, domicilio y contacto reales', (tester) async {
      await _pump(tester, _datosCompletos);

      expect(tester.takeException(), isNull);
      expect(find.text('CORPORATIVO DE SEGURIDAD PRIVADA RIZEG SAS DE CV'), findsOneWidget);
      expect(find.text('CSP123456AB1'), findsOneWidget);
      expect(find.text('Valle de los Reyes 2 INT. 9'), findsOneWidget);
      expect(find.text('C.P. 52224'), findsOneWidget);
      expect(find.text('facturacion@riseg.mx'), findsOneWidget);
      expect(find.text('5555555555'), findsOneWidget);
    });

    testWidgets('"Copiar datos" copia el texto esperado al portapapeles', (tester) async {
      // Se intercepta el canal de plataforma directamente en vez de usar
      // `Clipboard.getData` — ese round-trip esperaría una respuesta
      // real de plataforma que este entorno de pruebas no provee.
      final llamadas = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        llamadas.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(tester, _datosCompletos);

      await tester.tap(find.byKey(const Key('tarjeta_fiscal_boton_copiar')));
      await tester.pump();

      final llamadaCopiar = llamadas.singleWhere((c) => c.method == 'Clipboard.setData');
      final texto = (llamadaCopiar.arguments as Map)['text'] as String;
      expect(texto, contains('CORPORATIVO DE SEGURIDAD PRIVADA RIZEG SAS DE CV'));
      expect(texto, contains('CSP123456AB1'));
      expect(texto, contains('facturacion@riseg.mx'));
    });
  });

  group('Responsive y tema', () {
    for (final tamano in const [Size(1366, 900), Size(1024, 900), Size(500, 900)]) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()}: cero overflow (datos completos)', (tester) async {
        await _pump(tester, _datosCompletos, tamano: tamano);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('modo oscuro: cero overflow (datos completos)', (tester) async {
      await _pump(tester, _datosCompletos, tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });

    testWidgets('modo oscuro: cero overflow (datos incompletos, bloqueada)', (tester) async {
      await _pump(tester, EmpresaExpedienteData(empresa: _empresa()), tema: AppTheme.dark());
      expect(tester.takeException(), isNull);
    });
  });
}
