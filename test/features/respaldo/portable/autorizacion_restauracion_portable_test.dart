// Etapa 4D — la única compuerta del proyecto que puede abrirse sin
// sesión. Aquí se prueba justamente eso: que se abre cuando debe y, sobre
// todo, que NO se abre cuando no debe.
//
// El coordinador se sustituye por un doble que se niega a ser invocado:
// así una prueba de autorización falla si la operación llega a empezar,
// no sólo si devuelve el resultado equivocado.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'dart:io';

import 'package:riseg_one/features/respaldo/data/repositories/configuracion_recuperacion_repository_impl.dart';
import 'package:riseg_one/features/respaldo/domain/portable/autorizar_restauracion_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/configuracion_recuperacion.dart';
import 'package:riseg_one/features/respaldo/domain/portable/resultado_recuperacion.dart';
import 'package:riseg_one/features/respaldo/domain/portable/coordinador_restauracion_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/evaluador_instalacion.dart';
import 'package:riseg_one/features/respaldo/portable_providers.dart';
import 'package:riseg_one/features/respaldo/respaldo_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../../support/sesion_en_base.dart';

class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;
  @override
  SesionUsuario? build() => _sesion;
}

/// Doble que registra si se le llamó. Devuelve un resultado cualquiera:
/// lo que se mide aquí es la compuerta, no la restauración.
class _CoordinadorEspia implements CoordinadorRestauracionPortable {
  bool invocado = false;
  bool aplicado = false;

  @override
  Future<ResultadoPrepararPortable> preparar({
    required String rutaPaquete,
    required int appSchemaVersionActual,
    String? frase,
    String? claveRecuperacionTexto,
  }) async {
    invocado = true;
    return RestauracionPortablePreparada(restoreOperationId: 'op-1', keyId: 'key-1');
  }

  @override
  Future<ResultadoAplicarPortable> aplicarYConfirmar() async {
    aplicado = true;
    return SinRestauracionPortablePendiente();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Evaluador de mentira: devuelve el estado que la prueba quiera, o
/// revienta cuando la prueba quiera comprobar qué se hace entonces.
class _EvaluadorFijo implements EvaluadorInstalacion {
  _EvaluadorFijo(this._estado);
  final EstadoInstalacion? _estado;

  @override
  Future<EstadoInstalacion> evaluar() async {
    final estado = _estado;
    if (estado == null) throw StateError('el disco no se puede leer');
    return estado;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Repositorio que se niega a guardar. Simula el disco lleno o la base
/// tomada por otro proceso.
class _RepositorioQueFalla implements ConfiguracionRecuperacionRepositoryImpl {
  @override
  Future<ConfiguracionRecuperacion?> obtener() async => null;

  @override
  Future<void> guardar(ConfiguracionRecuperacion configuracion) async {
    throw const FileSystemException('no se puede escribir en la base');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _sesionMaestro = SesionUsuario(
  usuarioId: 'usuario-maestro',
  nombre: 'Maestro',
  nombreUsuario: 'maestro',
  esMaestro: true,
  permisos: {},
);

const _sesionNoMaestro = SesionUsuario(
  usuarioId: 'usuario-normal',
  nombre: 'Usuario normal',
  nombreUsuario: 'normal',
  esMaestro: false,
  // Ni el permiso más alto del catálogo alcanza: esto no es un permiso
  // dinámico, es una facultad del Maestro.
  permisos: {'usuarios.administrar', 'respaldo.administrar'},
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<({ProviderContainer container, _CoordinadorEspia espia})> montar({
    required SesionUsuario? sesion,
    required EstadoInstalacion? estado,
  }) async {
    if (sesion != null) await sembrarSesionEnBase(db, sesion);
    final espia = _CoordinadorEspia();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
        coordinadorRestauracionPortableProvider.overrideWithValue(espia),
        evaluadorInstalacionProvider.overrideWithValue(_EvaluadorFijo(estado)),
        appSchemaVersionProvider.overrideWithValue(93),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, espia: espia);
  }

  Future<ResultadoPrepararPortable> restaurar(ProviderContainer c) => c.read(
    prepararRestauracionPortableAutorizadoProvider,
  )(rutaPaquete: 'C:/usb/respaldo.risegbkp', frase: 'la frase');

  group('La puerta según el estado de la instalación', () {
    test('sólo VACIA_SEGURA se abre sin credencial', () {
      expect(puertaSegunInstalacion(EstadoInstalacion.vaciaSegura), PuertaRestauracionPortable.sinCredencial);
      expect(puertaSegunInstalacion(EstadoInstalacion.existente), PuertaRestauracionPortable.exigeMaestro);
      expect(puertaSegunInstalacion(EstadoInstalacion.indeterminada), PuertaRestauracionPortable.exigeMaestro);
    });
  });

  group('Instalación vacía: hay que poder recuperar sin nadie que autorice', () {
    test('SIN NINGUNA SESIÓN se restaura — es el caso de "la computadora se destruyó"', () async {
      final m = await montar(sesion: null, estado: EstadoInstalacion.vaciaSegura);
      expect(await restaurar(m.container), isA<RestauracionPortablePreparada>());
      expect(m.espia.invocado, isTrue);
    });
  });

  group('Instalación con datos: restaurar los reemplaza', () {
    test('SIN SESIÓN no se restaura, y la restauración NI SE INTENTA', () async {
      final m = await montar(sesion: null, estado: EstadoInstalacion.existente);
      expect(await restaurar(m.container), isA<RestauracionPortableNoAutorizada>());
      expect(m.espia.invocado, isFalse, reason: 'una negativa que ya tocó el disco no es una negativa');
    });

    test('con sesión que NO es Maestro tampoco, por mucho permiso que tenga', () async {
      final m = await montar(sesion: _sesionNoMaestro, estado: EstadoInstalacion.existente);
      expect(await restaurar(m.container), isA<RestauracionPortableNoAutorizada>());
      expect(m.espia.invocado, isFalse);
    });

    test('con el Usuario Maestro sí', () async {
      final m = await montar(sesion: _sesionMaestro, estado: EstadoInstalacion.existente);
      expect(await restaurar(m.container), isA<RestauracionPortablePreparada>());
      expect(m.espia.invocado, isTrue);
    });
  });

  group('Estado indeterminado: nunca es una puerta abierta', () {
    test('INDETERMINADA sin sesión NO restaura', () async {
      final m = await montar(sesion: null, estado: EstadoInstalacion.indeterminada);
      expect(await restaurar(m.container), isA<RestauracionPortableNoAutorizada>());
      expect(m.espia.invocado, isFalse);
    });

    test('INDETERMINADA con Maestro sí: la duda pide credencial, no prohíbe', () async {
      final m = await montar(sesion: _sesionMaestro, estado: EstadoInstalacion.indeterminada);
      expect(await restaurar(m.container), isA<RestauracionPortablePreparada>());
    });

    test('si el evaluador REVIENTA se trata como instalación con datos, no como vacía', () async {
      // El fallo cómodo sería asumir "no encontré nada, luego no hay
      // nada". Eso convertiría un disco ilegible en una puerta abierta.
      final m = await montar(sesion: null, estado: null);
      expect(await restaurar(m.container), isA<RestauracionPortableNoAutorizada>());
      expect(m.espia.invocado, isFalse);
    });
  });

  group('Aplicar (fase 2) no tiene compuerta, y su protección es el marcador', () {
    test('la vía existe sin sesión: se ejecuta en el arranque', () async {
      final m = await montar(sesion: null, estado: EstadoInstalacion.existente);
      // Sin sesión y sobre una instalación con datos: aun así llega al
      // coordinador. Tiene que ser así — en el arranque no hay nadie
      // conectado, y la decisión ya la tomó un Maestro al dejar el
      // marcador. Sin marcador esto no hace nada, y eso es lo que lo
      // protege.
      final resultado = await m.container.read(aplicarRestauracionPortableProvider)();
      expect(m.espia.aplicado, isTrue);
      expect(resultado, isA<SinRestauracionPortablePendiente>());
    });
  });
  group('Un fallo al guardar NO sale como excepción', () {
    test('configurar con la base inservible devuelve un resultado, no revienta', () async {
      // Sin esto, quien estuviera configurando su recuperación vería la
      // aplicación romperse en mitad de la operación en vez de un mensaje.
      await sembrarSesionEnBase(db, _sesionMaestro);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(() => _SesionFija(_sesionMaestro)),
          configuracionRecuperacionRepositoryProvider.overrideWithValue(_RepositorioQueFalla()),
          appSchemaVersionProvider.overrideWithValue(93),
        ],
      );
      addTearDown(container.dispose);

      final resultado = await container.read(configurarRecuperacionAutorizadoProvider)(
        frase: 'una frase suficientemente larga',
      );
      expect(resultado, isA<RecuperacionErrorInesperado>());
    });
  });
}
