// §26 — el listado de Eventuales muestra, por fila, el nombre del
// solicitante, los totales de coberturas y costos Y —desde la
// schemaVersion 88— el cobrado y el pendiente de su Cuenta por cobrar.
// Nada de eso puede costar una consulta por evento.
//
// La medición es real, no una promesa en un comentario: se cuentan las
// sentencias que drift envía mientras se arma la pantalla, con 0, 1, 10
// y 100 eventuales, cada uno con participante, cobertura, costo y
// Cuenta por cobrar propios.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/servicios_eventuales_list_screen.dart';
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

Future<int> _consultasParaListado(WidgetTester tester, int eventuales) async {
  final db = AppDatabase(NativeDatabase.memory(logStatements: true));
  addTearDown(db.close);

  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('maestro'),
          nombre: 'Maestro de prueba',
          nombreUsuario: 'maestro',
          passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
          esMaestro: const Value(true),
        ),
      );

  // La mitad de los eventuales son de un Cliente registrado: así la
  // medición también cubre la resolución en lote de nombres.
  final cliente = await db.into(db.cliente).insertReturning(
        ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Corporativo Sur'),
      );

  for (var i = 0; i < eventuales; i++) {
    final esCliente = i.isEven;
    final eventual = await db.into(db.servicioEventual).insertReturning(
          ServicioEventualCompanion.insert(
            folio: 'EVT-${i.toString().padLeft(6, '0')}',
            nombre: 'Evento $i',
            fechaHoraInicio: DateTime(2026, 5, 1, 8),
            fechaHoraFin: DateTime(2026, 5, 1, 20),
            importeAcordado: 1000000,
            tipoSolicitante: esCliente
                ? TipoSolicitanteServicioEventual.cliente.name
                : TipoSolicitanteServicioEventual.eventual.name,
            clienteId: Value(esCliente ? cliente.id : null),
            solicitanteNombre: Value(esCliente ? null : 'Promotora $i'),
          ),
        );
    final participante = await db.into(db.servicioEventualParticipante).insertReturning(
          ServicioEventualParticipanteCompanion.insert(
            servicioEventualId: eventual.id,
            nombreExterno: Value('Refuerzo $i'),
          ),
        );
    await db.into(db.servicioEventualCobertura).insert(
          ServicioEventualCoberturaCompanion.insert(
            servicioEventualId: eventual.id,
            participanteId: participante.id,
            fecha: DateTime(2026, 5, 1),
            horaInicioMinutos: 8 * 60,
            horaFinMinutos: 20 * 60,
            importeAcordado: 200000,
          ),
        );
    await db.into(db.servicioEventualCosto).insert(
          ServicioEventualCostoCompanion.insert(
            servicioEventualId: eventual.id,
            concepto: 'Traslado',
            monto: 50000,
            fecha: DateTime(2026, 5, 1),
          ),
        );
    // schemaVersion 88 — su Cuenta por cobrar, parcialmente cobrada:
    // así la medición cubre de verdad las columnas de cobranza.
    await db.into(db.cuentaPorCobrar).insert(
          CuentaPorCobrarCompanion.insert(
            servicioEventualId: Value(eventual.id),
            clienteId: Value(esCliente ? cliente.id : null),
            tipoDocumento: 'reciboDePago',
            metodo: 'noAplica',
            fechaEmisionReal: DateTime(2026, 5, 1),
            importeEmitido: 1000000,
            saldoOriginal: 1000000,
            saldoPendiente: 400000,
            estatus: const Value('parcial'),
          ),
        );
  }

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestro.new),
    ],
  );
  addTearDown(container.dispose);

  // El conteo empieza AQUÍ: la siembra de arriba no cuenta.
  var consultas = 0;
  final anterior = driftRuntimeOptions.debugPrint;
  driftRuntimeOptions.debugPrint = (mensaje) {
    if (mensaje.contains('SELECT')) consultas++;
  };
  addTearDown(() => driftRuntimeOptions.debugPrint = anterior);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ServiciosEventualesListScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return consultas;
}

/// Cada medición monta su propio árbol de widgets; los resultados se
/// comparan en la última prueba del archivo.
final _medidas = <int, int>{};

void main() {
  for (final n in [0, 1, 10, 100]) {
    testWidgets('mide el listado con $n eventuales', (tester) async {
      tester.view.physicalSize = const Size(1536, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      _medidas[n] = await _consultasParaListado(tester, n);
      expect(_medidas[n], greaterThan(0), reason: 'si no se cuenta nada, la medición no vale');
    });
  }

  test('el coste del listado no crece con el número de eventuales', () {
    // ignore: avoid_print
    print('Consultas del listado de Eventuales — 0: ${_medidas[0]} | 1: ${_medidas[1]} '
        '| 10: ${_medidas[10]} | 100: ${_medidas[100]}');

    expect(_medidas[10], lessThanOrEqualTo(_medidas[1]!), reason: 'de 1 a 10 eventuales el coste no cambia');
    expect(_medidas[100], lessThanOrEqualTo(_medidas[1]!),
        reason: 'de 1 a 100 tampoco: SUM ... GROUP BY y nombres en lote, nunca N+1');
    expect(_medidas[100], lessThan(15), reason: 'un puñado de consultas, no doscientas');
  });
}
