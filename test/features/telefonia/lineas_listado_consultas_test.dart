// §22 de la Rebanada 3 — el listado de Líneas muestra, por fila,
// destino, equipo y última recarga. Eso NO puede costar una consulta por
// línea.
//
// Antes de esta rebanada el ensamblado del equipo hacía DOS consultas
// por fila (`obtenerActualPorLinea` + `obtenerUnidadPorId`): 100 líneas
// eran 200 viajes a la base. La medición es real, no una promesa en un
// comentario: se cuentan las sentencias que drift envía mientras se
// arma la pantalla.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/presentation/lineas_telefonicas_list_screen.dart';
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

/// Cuántas sentencias envía drift mientras se arma el listado con
/// [lineas] filas. `logStatements` imprime cada una; se cuentan
/// interceptando `print` en una zona.
Future<int> _consultasParaListado(WidgetTester tester, int lineas) async {
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
  for (var i = 0; i < lineas; i++) {
    await db.into(db.lineaTelefonica).insert(
          LineaTelefonicaCompanion.insert(
            codigo: 'LIN-${i.toString().padLeft(6, '0')}',
            numero: Value('722${i.toString().padLeft(7, '0')}'),
            operador: OperadorTelefonico.telcel.name,
            modalidadSim: ModalidadSim.fisica.name,
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
        home: const Scaffold(body: LineasTelefonicasListScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return consultas;
}

/// Cada medición monta su propio árbol de widgets: pumpear cuatro en
/// una sola prueba deja temporizadores vivos y el framework lo rechaza.
/// Los resultados se comparan en la última prueba del archivo.
final _medidas = <int, int>{};

void main() {
  for (final n in [0, 1, 10, 100]) {
    testWidgets('mide el listado con $n líneas', (tester) async {
      tester.view.physicalSize = const Size(1536, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      _medidas[n] = await _consultasParaListado(tester, n);
      expect(_medidas[n], greaterThan(0), reason: 'si no se cuenta nada, la medición no vale');
    });
  }

  test('el coste del listado no crece con el número de líneas', () {
    // ignore: avoid_print
    print(
      'Consultas del listado de Líneas — 0 líneas: ${_medidas[0]}'
      ' | 1: ${_medidas[1]} | 10: ${_medidas[10]} | 100: ${_medidas[100]}',
    );

    expect(_medidas[10], lessThanOrEqualTo(_medidas[1]!), reason: 'de 1 a 10 líneas el coste no cambia');
    expect(_medidas[100], lessThanOrEqualTo(_medidas[1]!), reason: 'de 1 a 100 tampoco: resolución en lote, nunca N+1');
    expect(_medidas[100], lessThan(20), reason: 'un puñado de consultas, no doscientas');
  });
}
