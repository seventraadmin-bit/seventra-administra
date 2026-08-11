// Pruebas de autorización del expediente de Equipos telefónicos (Etapa
// 9D) — mismo patrón que `test/features/usuarios/authorization_service_test.dart`
// (`_SesionFija`/`_container`/`_sesionCon`/`_sesionMaestro`), enfocado en
// el punto 4 del plan de Marlon: "ver Telefonía" y "revelar/copiar
// contraseñas" son permisos independientes (`telefonia.ver` vs
// `telefonia.verCredenciales`), y las lecturas (historia del equipo) no
// pasan por ningún gate de autorización en absoluto — ese control vive
// en la ruta/sidebar, no en el caso de uso.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/revelar_credencial_equipo_telefonico_usecase.dart';
import 'package:riseg_one/features/telefonia/telefonia_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// Implementación en memoria de `AlmacenClaveCifrado` — la real usa
/// canales de plataforma que no responden bajo `flutter test`. Se
/// inyecta vía override de `credentialCipherProvider` para que las
/// pruebas "con permiso" que sí descifran puedan ejecutarse.
class _AlmacenClaveCifradoEnMemoria implements AlmacenClaveCifrado {
  String? _clave;

  @override
  Future<String?> leer() async => _clave;

  @override
  Future<void> escribir(String valor) async => _clave = valor;
}

class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;
  @override
  SesionUsuario? build() => _sesion;
}

const _mensajePermiso = 'No tiene permiso para realizar esta acción.';

/// [almacen] se comparte entre los `ProviderContainer` de una misma
/// prueba (nunca uno nuevo por container) — en producción la clave
/// maestra vive una sola vez por máquina (Almacén de Credenciales de
/// Windows); si cada container generara la suya, "escribir con un
/// container y leer con otro" (el patrón real de estas pruebas: una
/// sesión configura la contraseña, otra distinta la revela) fallaría al
/// descifrar por una clave distinta, no por el permiso que se está
/// probando.
ProviderContainer _container(AppDatabase db, SesionUsuario? sesion, {AlmacenClaveCifrado? almacen}) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
      credentialCipherProvider.overrideWithValue(CredentialCipher(almacen: almacen ?? _AlmacenClaveCifradoEnMemoria())),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

SesionUsuario _sesionCon(Set<String> permisos) => SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: false,
      permisos: permisos,
    );

const _sesionMaestro = SesionUsuario(
  usuarioId: 'maestro-prueba',
  nombre: 'Maestro de prueba',
  nombreUsuario: 'maestro',
  esMaestro: true,
  permisos: {},
);

/// Mismo gotcha que en `authorization_service_test.dart` (Etapa 11D):
/// `actorUsuarioId` es una FK real hacia `Usuario`, así que los ids de
/// `_sesionCon`/`_sesionMaestro` deben existir como filas reales.
Future<void> _sembrarUsuariosDePrueba(AppDatabase db) async {
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('usuario-prueba'),
          nombre: 'Usuario de prueba',
          nombreUsuario: 'usuario-prueba',
          passwordHash: 'x',
        ),
      );
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('maestro-prueba'),
          nombre: 'Maestro de prueba',
          nombreUsuario: 'maestro-prueba',
          passwordHash: 'x',
        ),
      );
}

/// Crea directamente (sin pasar por ningún gate de autorización, esta
/// suite no está probando Inventario) una `ArticuloUnidad` real de un
/// Artículo serializado — la fixture mínima que
/// `RevelarCredencialEquipoTelefonicoUseCase`/`ObtenerHistoriaEquipoTelefonicoUseCase`
/// necesitan para no fallar por "unidad no existe".
Future<String> _crearUnidadDePrueba(AppDatabase db) async {
  final articuloRepo = ArticuloRepositoryImpl(db);
  final inventarioRepo = InventarioRepositoryImpl(db);
  final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
  final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

  final categoria =
      (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso).categoria;
  final articulo = (await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo)
          .ejecutar(categoriaId: categoria.id, nombre: 'Smartphone', manejaSerie: true) as CrearArticuloExitoso)
      .articulo;
  final unidad = (await RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo).ejecutar(
    articuloId: articulo.id,
    numeroSerie: 'SN-PERMISOS-0001',
    fecha: DateTime(2026, 1, 1),
  ) as RegistrarEntradaUnidadExitoso)
      .unidad;
  return unidad.id;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _sembrarUsuariosDePrueba(db);
  });

  tearDown(() => db.close());

  group('Lectura del expediente — sin gate de autorización', () {
    test('ObtenerHistoriaEquipoTelefonicoUseCase devuelve datos con una sesión sin ningún permiso', () async {
      final unidadId = await _crearUnidadDePrueba(db);

      // Configura el equipo con una sesión que sí tiene permiso, para
      // tener algo real que leer después.
      final containerEscritura = _container(db, _sesionCon({'telefonia.ver', 'telefonia.modificar'}));
      await containerEscritura.read(configurarEquipoTelefonicoAutorizadoProvider)(unidadId: unidadId, imei: '351234567890123');

      // La lectura se hace con una sesión SIN ningún permiso — la
      // consulta no está gateada por `autorizarUseCase` en absoluto.
      final containerLectura = _container(db, _sesionCon({}));
      final historia = await containerLectura.read(obtenerHistoriaEquipoTelefonicoUseCaseProvider).ejecutar(unidadId);

      expect(historia.movimientoAdquisicion, isNotNull, reason: 'la lectura funcionó, no fue rechazada por permisos');
    });

    test('ObtenerHistoriaEquipoTelefonicoUseCase también funciona sin ninguna sesión activa', () async {
      final unidadId = await _crearUnidadDePrueba(db);
      final container = _container(db, null);

      final historia = await container.read(obtenerHistoriaEquipoTelefonicoUseCaseProvider).ejecutar(unidadId);

      expect(historia, isNotNull);
    });
  });

  group('revelarCredencialEquipoTelefonicoAutorizadoProvider — gateado por telefonia.verCredenciales', () {
    test('sesión con telefonia.ver + telefonia.modificar pero SIN telefonia.verCredenciales: rechazada', () async {
      final unidadId = await _crearUnidadDePrueba(db);
      final containerEscritura = _container(db, _sesionCon({'telefonia.ver', 'telefonia.modificar'}));
      await containerEscritura.read(cambiarContrasenaEquipoTelefonicoAutorizadoProvider)(
        unidadId: unidadId,
        contrasena: 'ClaveDePrueba123',
      );

      final containerLectura = _container(db, _sesionCon({'telefonia.ver', 'telefonia.modificar'}));
      final resultado = await containerLectura.read(revelarCredencialEquipoTelefonicoAutorizadoProvider)(
        unidadId: unidadId,
        accion: AccionRevelacionCredencial.mostrar,
      );

      expect(resultado, isA<RevelarCredencialEquipoTelefonicoErrorInesperado>());
      expect((resultado as RevelarCredencialEquipoTelefonicoErrorInesperado).mensaje, _mensajePermiso);
    });

    test('sesión con SOLO telefonia.ver (sin .modificar ni .verCredenciales): también rechazada', () async {
      final unidadId = await _crearUnidadDePrueba(db);
      final container = _container(db, _sesionCon({'telefonia.ver'}));

      final resultado = await container.read(revelarCredencialEquipoTelefonicoAutorizadoProvider)(
        unidadId: unidadId,
        accion: AccionRevelacionCredencial.mostrar,
      );

      expect(resultado, isA<RevelarCredencialEquipoTelefonicoErrorInesperado>());
      expect(
        (resultado as RevelarCredencialEquipoTelefonicoErrorInesperado).mensaje,
        _mensajePermiso,
        reason: 'el código de permiso exacto es telefonia.verCredenciales, no telefonia.ver',
      );
    });

    test('sesión CON telefonia.verCredenciales: sí puede revelar la contraseña vigente', () async {
      final unidadId = await _crearUnidadDePrueba(db);
      final almacen = _AlmacenClaveCifradoEnMemoria();
      final containerEscritura = _container(db, _sesionCon({'telefonia.ver', 'telefonia.modificar'}), almacen: almacen);
      await containerEscritura.read(cambiarContrasenaEquipoTelefonicoAutorizadoProvider)(
        unidadId: unidadId,
        contrasena: 'ClaveDePrueba123',
      );

      final containerLectura = _container(db, _sesionCon({'telefonia.ver', 'telefonia.verCredenciales'}), almacen: almacen);
      final resultado = await containerLectura.read(revelarCredencialEquipoTelefonicoAutorizadoProvider)(
        unidadId: unidadId,
        accion: AccionRevelacionCredencial.mostrar,
      );

      expect(resultado, isA<RevelarCredencialEquipoTelefonicoExitoso>());
      expect((resultado as RevelarCredencialEquipoTelefonicoExitoso).contrasena, 'ClaveDePrueba123');
    });

    test('un Maestro siempre puede revelarla, sin ninguna fila de PermisoUsuario', () async {
      final unidadId = await _crearUnidadDePrueba(db);
      final almacen = _AlmacenClaveCifradoEnMemoria();
      final containerEscritura = _container(db, _sesionMaestro, almacen: almacen);
      await containerEscritura.read(cambiarContrasenaEquipoTelefonicoAutorizadoProvider)(
        unidadId: unidadId,
        contrasena: 'ClaveDeMaestro456',
      );

      final containerLectura = _container(db, _sesionMaestro, almacen: almacen);
      final resultado = await containerLectura.read(revelarCredencialEquipoTelefonicoAutorizadoProvider)(
        unidadId: unidadId,
        accion: AccionRevelacionCredencial.mostrar,
      );

      expect(resultado, isA<RevelarCredencialEquipoTelefonicoExitoso>());
      expect((resultado as RevelarCredencialEquipoTelefonicoExitoso).contrasena, 'ClaveDeMaestro456');
    });
  });
}
