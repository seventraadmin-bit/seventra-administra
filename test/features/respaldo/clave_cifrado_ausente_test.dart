// Etapa 4B — "no tengo la llave" deja de confundirse con "la llave no
// abre".
//
// La auditoría 4A encontró que `descifrar()` llamaba a
// `_obtenerOCrearClave()`: abrir una credencial restaurada de otra
// computadora generaba en silencio una clave nueva, fallaba igual, y
// dejaba la base con textos cifrados bajo DOS claves distintas sin nada
// que los distinguiera. Cifrar puede crear la clave —está guardando algo
// nuevo—; descifrar jamás.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/boveda/data/repositories/boveda_credencial_repository_impl.dart';
import 'package:riseg_one/features/boveda/domain/usecases/revelar_secreto_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_portal_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_portal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_portal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_cliente_portal_resultado.dart';
import 'package:riseg_one/features/telefonia/data/repositories/equipo_telefonico_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/revelar_credencial_equipo_telefonico_usecase.dart';

/// Almacén que se puede vaciar — es lo que ocurre al restaurar en otra
/// computadora: la base llega, el Almacén de Credenciales está vacío.
class _AlmacenEnMemoria implements AlmacenClaveCifrado {
  String? valor;
  int escrituras = 0;

  @override
  Future<String?> leer() async => valor;

  @override
  Future<void> escribir(String v) async {
    valor = v;
    escrituras++;
  }
}

/// El validador de Portal sólo consulta `obtenerPorId`: se le da el
/// repositorio real sobre la base en memoria y nada más.
class _ClienteRepositorioReal implements ClienteRepository {
  _ClienteRepositorioReal(this._db);
  final AppDatabase _db;

  @override
  Future<ClienteData?> obtenerPorId(String id) {
    return (_db.select(_db.cliente)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _AlmacenEnMemoria almacen;

  setUp(() => almacen = _AlmacenEnMemoria());

  group('Semántica de la clave', () {
    test('42. cifrar sin clave la crea: es el momento correcto para hacerlo', () async {
      final cipher = CredentialCipher(almacen: almacen);

      final cifrado = await cipher.cifrar('contrasena-del-portal');

      expect(almacen.valor, isNotNull);
      expect(almacen.escrituras, 1);
      expect(cifrado, startsWith('aesgcm'));
    });

    test('43. descifrar con la clave correcta devuelve el original', () async {
      final cipher = CredentialCipher(almacen: almacen);
      final cifrado = await cipher.cifrar('secreto real');

      expect(await cipher.descifrar(cifrado), 'secreto real');
    });

    test('44-46. descifrar SIN clave falla con un error de dominio y NO crea ninguna', () async {
      // Se cifra en un "equipo" y se intenta leer en otro.
      final equipoA = CredentialCipher(almacen: almacen);
      final cifrado = await equipoA.cifrar('secreto real');

      final equipoB = CredentialCipher(almacen: _AlmacenEnMemoria());
      final almacenB = _AlmacenEnMemoria();
      final cipherB = CredentialCipher(almacen: almacenB);

      await expectLater(
        cipherB.descifrar(cifrado),
        throwsA(isA<ClaveCifradoNoDisponible>()),
        reason: 'no es un error inesperado: es "aquí no se puede recuperar"',
      );
      expect(almacenB.valor, isNull, reason: 'intentar leer no puede fabricar una llave');
      expect(almacenB.escrituras, 0);
      expect(equipoB, isNotNull);
    });

    test('tras el fallo, el texto cifrado sigue intacto y legible en su equipo', () async {
      final cipher = CredentialCipher(almacen: almacen);
      final cifrado = await cipher.cifrar('secreto real');

      final otro = CredentialCipher(almacen: _AlmacenEnMemoria());
      await expectLater(otro.descifrar(cifrado), throwsA(isA<ClaveCifradoNoDisponible>()));

      // El equipo original lo sigue abriendo: nada se corrompió.
      expect(await CredentialCipher(almacen: almacen).descifrar(cifrado), 'secreto real');
    });

    test('una clave presente pero distinta NO se confunde con clave ausente', () async {
      final cipher = CredentialCipher(almacen: almacen);
      final cifrado = await cipher.cifrar('secreto real');

      final ajeno = _AlmacenEnMemoria();
      await CredentialCipher(almacen: ajeno).cifrar('otra cosa'); // genera SU clave

      await expectLater(
        CredentialCipher(almacen: ajeno).descifrar(cifrado),
        throwsA(isNot(isA<ClaveCifradoNoDisponible>())),
        reason: 'hay llave, simplemente no abre: es corrupción o dato ajeno, no ausencia',
      );
    });
  });

  group('47. Bóveda lo presenta como un caso de negocio', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('revelar una credencial sin clave devuelve ClaveNoDisponible, no ErrorInesperado', () async {
      final repo = BovedaCredencialRepositoryImpl(db);
      final cifradoAjeno = await CredentialCipher(almacen: _AlmacenEnMemoria()).cifrar('contrasena');
      final credencial = await repo.crear(nombre: 'RISEG - Portal', tipo: 'portal', secretoCifrado: cifradoAjeno);

      // Este equipo no tiene ninguna clave.
      final resultado = await RevelarSecretoCredencialBovedaUseCase(
        repo,
        CredentialCipher(almacen: _AlmacenEnMemoria()),
      ).ejecutar(credencialId: credencial.id, accion: AccionRevelacionSecreto.mostrar);

      expect(
        resultado,
        isA<RevelarSecretoCredencialBovedaClaveNoDisponible>(),
        reason: 'la pantalla necesita poder explicar POR QUÉ, no mostrar una excepción',
      );
    });

    test('50. ningún secreto ni material de clave aparece en el evento registrado', () async {
      final repo = BovedaCredencialRepositoryImpl(db);
      final cipher = CredentialCipher(almacen: almacen);
      final credencial = await repo.crear(
        nombre: 'RISEG - Portal',
        tipo: 'portal',
        secretoCifrado: await cipher.cifrar('contrasena-secreta-1'),
      );

      await RevelarSecretoCredencialBovedaUseCase(
        repo,
        cipher,
      ).ejecutar(credencialId: credencial.id, accion: AccionRevelacionSecreto.mostrar);

      for (final evento in await db.select(db.bovedaCredencialEvento).get()) {
        final texto = '${evento.observacion ?? ''}${evento.tipoEvento}';
        expect(texto, isNot(contains('contrasena-secreta-1')));
        expect(texto, isNot(contains(almacen.valor!)), reason: 'la clave jamás se registra');
        expect(texto, isNot(contains('aesgcm')));
      }
    });
  });

  group('48-49. Los otros dos módulos que comparten la clave', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('48. Telefonía también devuelve ClaveNoDisponible, no un error técnico', () async {
      final categoria = await db
          .into(db.categoriaArticulo)
          .insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Telefonía'));
      final articulo = await db
          .into(db.articulo)
          .insertReturning(ArticuloCompanion.insert(folio: 'ART-001', categoriaId: categoria.id, nombre: 'Teléfono'));
      final unidad = await db
          .into(db.articuloUnidad)
          .insertReturning(
            ArticuloUnidadCompanion.insert(codigo: 'U-001', articuloId: articulo.id, numeroSerie: 'SN-001'),
          );
      // Cifrada en otro equipo: aquí no existe la clave.
      final ajena = await CredentialCipher(almacen: _AlmacenEnMemoria()).cifrar('contrasena-del-equipo');
      await db
          .into(db.equipoTelefonicoCredencial)
          .insert(EquipoTelefonicoCredencialCompanion.insert(unidadId: unidad.id, contrasenaCifrada: Value(ajena)));

      final resultado = await RevelarCredencialEquipoTelefonicoUseCase(
        InventarioRepositoryImpl(db),
        EquipoTelefonicoRepositoryImpl(db),
        CredentialCipher(almacen: _AlmacenEnMemoria()),
      ).ejecutar(unidadId: unidad.id, accion: AccionRevelacionCredencial.mostrar);

      expect(resultado, isA<RevelarCredencialEquipoTelefonicoClaveNoDisponible>());
    });

    test('49. el Portal sigue pudiendo GUARDAR una contraseña sin clave previa', () async {
      final almacenVacio = _AlmacenEnMemoria();
      final cliente = await db
          .into(db.cliente)
          .insertReturning(ClienteCompanion.insert(codigo: 'CLI-001', nombreComercial: 'MORGAN'));

      final resultado = await CrearClientePortalUseCase(
        ClientePortalRepositoryImpl(db),
        ClientePortalValidator(_ClienteRepositorioReal(db)),
        CredentialCipher(almacen: almacenVacio),
      ).ejecutar(
        clienteId: cliente.id,
        borrador: const ClientePortalBorrador(
          nombre: 'Portal MORGAN',
          tipo: TipoPortalCliente.facturacion,
          contrasenaNueva: 'nueva-contrasena',
        ),
      );

      expect(
        resultado,
        isA<GuardarClientePortalExitoso>(),
        reason: 'escribir algo nuevo no depende de poder leer lo viejo',
      );
      expect(almacenVacio.valor, isNotNull, reason: 'la clave se crea aquí, que es el momento correcto');
      final guardado = await db.select(db.clientePortal).getSingle();
      expect(guardado.contrasenaCifrada, isNot(contains('nueva-contrasena')));
    });
  });
}
