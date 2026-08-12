// Etapa 14D (Bóveda de Accesos del Maestro) — pruebas de los 6 casos
// de uso de dominio, con `AppDatabase` en memoria y un
// `AlmacenClaveCifrado` en memoria para `CredentialCipher` (mismo
// patrón que `test/features/telefonia/equipo_telefonico_test.dart`,
// Etapa 9D — el almacén real usa canales de plataforma que no
// responden bajo `flutter test`).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/boveda/data/repositories/boveda_credencial_repository_impl.dart';
import 'package:riseg_one/features/boveda/domain/repositories/boveda_credencial_repository.dart';
import 'package:riseg_one/features/boveda/domain/usecases/actualizar_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/cambiar_secreto_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/crear_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/dar_de_baja_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/reactivar_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/revelar_secreto_credencial_boveda_usecase.dart';

class _AlmacenClaveCifradoEnMemoria implements AlmacenClaveCifrado {
  String? _clave;

  @override
  Future<String?> leer() async => _clave;

  @override
  Future<void> escribir(String valor) async => _clave = valor;
}

void main() {
  late AppDatabase db;
  late BovedaCredencialRepository repo;
  late CredentialCipher cipher;
  late CrearCredencialBovedaUseCase crear;
  late ActualizarCredencialBovedaUseCase actualizar;
  late CambiarSecretoCredencialBovedaUseCase cambiarSecreto;
  late RevelarSecretoCredencialBovedaUseCase revelar;
  late DarDeBajaCredencialBovedaUseCase darDeBaja;
  late ReactivarCredencialBovedaUseCase reactivar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = BovedaCredencialRepositoryImpl(db);
    cipher = CredentialCipher(almacen: _AlmacenClaveCifradoEnMemoria());
    crear = CrearCredencialBovedaUseCase(repo, cipher);
    actualizar = ActualizarCredencialBovedaUseCase(repo);
    cambiarSecreto = CambiarSecretoCredencialBovedaUseCase(repo, cipher);
    revelar = RevelarSecretoCredencialBovedaUseCase(repo, cipher);
    darDeBaja = DarDeBajaCredencialBovedaUseCase(repo);
    reactivar = ReactivarCredencialBovedaUseCase(repo);
  });

  tearDown(() => db.close());

  group('CrearCredencialBovedaUseCase', () {
    test('nombre vacío se rechaza', () async {
      final resultado = await crear.ejecutar(nombre: '   ', tipo: 'otro');
      expect(resultado, isA<CrearCredencialBovedaNombreRequerido>());
    });

    test('alta exitosa sin secreto no cifra nada y registra evento "creada"', () async {
      final resultado = await crear.ejecutar(nombre: 'PCR RISEG', tipo: 'pcr', actorUsuarioId: null);
      expect(resultado, isA<CrearCredencialBovedaExitoso>());
      final credencial = (resultado as CrearCredencialBovedaExitoso).credencial;
      expect(credencial.secretoCifrado, isNull);
      expect(credencial.fechaActualizacionSecreto, isNull);

      final eventos = await repo.listarEventos(credencial.id);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, 'creada');
    });

    test('alta con secreto lo cifra (nunca lo guarda en texto plano)', () async {
      final resultado = await crear.ejecutar(nombre: 'Portal proveedor', tipo: 'portal', secreto: 'clave-secreta-123');
      final credencial = (resultado as CrearCredencialBovedaExitoso).credencial;
      expect(credencial.secretoCifrado, isNotNull);
      expect(credencial.secretoCifrado, isNot(contains('clave-secreta-123')));
      expect(credencial.fechaActualizacionSecreto, isNotNull);

      final descifrado = await cipher.descifrar(credencial.secretoCifrado!);
      expect(descifrado, 'clave-secreta-123');
    });
  });

  group('ActualizarCredencialBovedaUseCase', () {
    test('credencial inexistente', () async {
      final resultado = await actualizar.ejecutar(id: 'no-existe', nombre: 'X', tipo: 'otro');
      expect(resultado, isA<ActualizarCredencialBovedaNoExiste>());
    });

    test('edita campos sin tocar el secreto', () async {
      final creado = (await crear.ejecutar(nombre: 'Original', tipo: 'software', secreto: 'no-debe-cambiar'))
          as CrearCredencialBovedaExitoso;

      final resultado = await actualizar.ejecutar(
        id: creado.credencial.id,
        nombre: 'Editado',
        tipo: 'software',
        correo: 'nuevo@riseg.mx',
      );
      expect(resultado, isA<ActualizarCredencialBovedaExitoso>());
      final actualizado = (resultado as ActualizarCredencialBovedaExitoso).credencial;
      expect(actualizado.nombre, 'Editado');
      expect(actualizado.correo, 'nuevo@riseg.mx');
      expect(actualizado.secretoCifrado, creado.credencial.secretoCifrado, reason: 'editar nunca toca el secreto');

      final eventos = await repo.listarEventos(creado.credencial.id);
      expect(eventos.map((e) => e.tipoEvento), containsAll(['creada', 'editada']));
    });
  });

  group('CambiarSecretoCredencialBovedaUseCase', () {
    test('sobrescribe el secreto vigente, nunca conserva el anterior', () async {
      final creado =
          (await crear.ejecutar(nombre: 'Correo RISEG', tipo: 'correo', secreto: 'clave-vieja')) as CrearCredencialBovedaExitoso;

      final resultado = await cambiarSecreto.ejecutar(id: creado.credencial.id, secreto: 'clave-nueva');
      expect(resultado, isA<CambiarSecretoCredencialBovedaExitoso>());
      final actualizado = (resultado as CambiarSecretoCredencialBovedaExitoso).credencial;
      expect(await cipher.descifrar(actualizado.secretoCifrado!), 'clave-nueva');

      final eventos = await repo.listarEventos(creado.credencial.id);
      expect(eventos.map((e) => e.tipoEvento), containsAll(['creada', 'secretoCambiado']));
      for (final evento in eventos) {
        expect(evento.observacion ?? '', isNot(contains('clave-vieja')));
        expect(evento.observacion ?? '', isNot(contains('clave-nueva')));
      }
    });

    test('secreto vacío limpia el campo', () async {
      final creado =
          (await crear.ejecutar(nombre: 'Software X', tipo: 'software', secreto: 'algo')) as CrearCredencialBovedaExitoso;
      final resultado = await cambiarSecreto.ejecutar(id: creado.credencial.id, secreto: '');
      final actualizado = (resultado as CambiarSecretoCredencialBovedaExitoso).credencial;
      expect(actualizado.secretoCifrado, isNull);
    });
  });

  group('RevelarSecretoCredencialBovedaUseCase', () {
    test('sin secreto configurado', () async {
      final creado = (await crear.ejecutar(nombre: 'Sin secreto', tipo: 'otro')) as CrearCredencialBovedaExitoso;
      final resultado = await revelar.ejecutar(credencialId: creado.credencial.id, accion: AccionRevelacionSecreto.mostrar);
      expect(resultado, isA<RevelarSecretoCredencialBovedaSinSecreto>());
    });

    test('mostrar y copiar descifran correctamente y registran eventos separados', () async {
      final creado =
          (await crear.ejecutar(nombre: 'Con secreto', tipo: 'pagina', secreto: 'shhh')) as CrearCredencialBovedaExitoso;

      final mostrar = await revelar.ejecutar(credencialId: creado.credencial.id, accion: AccionRevelacionSecreto.mostrar);
      expect(mostrar, isA<RevelarSecretoCredencialBovedaExitoso>());
      expect((mostrar as RevelarSecretoCredencialBovedaExitoso).secreto, 'shhh');

      final copiar = await revelar.ejecutar(credencialId: creado.credencial.id, accion: AccionRevelacionSecreto.copiar);
      expect((copiar as RevelarSecretoCredencialBovedaExitoso).secreto, 'shhh');

      final eventos = await repo.listarEventos(creado.credencial.id);
      expect(eventos.map((e) => e.tipoEvento), containsAll(['secretoRevelado', 'secretoCopiado']));
    });
  });

  group('DarDeBajaCredencialBovedaUseCase / ReactivarCredencialBovedaUseCase', () {
    test('da de baja y reactiva, sin bloqueo por dependencias', () async {
      final creado = (await crear.ejecutar(nombre: 'Reversible', tipo: 'otro')) as CrearCredencialBovedaExitoso;
      expect(creado.credencial.cicloVidaRegistro, 'activo');

      final baja = await darDeBaja.ejecutar(id: creado.credencial.id);
      expect((baja as DarDeBajaCredencialBovedaExitoso).credencial.cicloVidaRegistro, 'baja');

      final reactivada = await reactivar.ejecutar(id: creado.credencial.id);
      expect((reactivada as ReactivarCredencialBovedaExitoso).credencial.cicloVidaRegistro, 'activo');

      final eventos = await repo.listarEventos(creado.credencial.id);
      expect(eventos.map((e) => e.tipoEvento), containsAll(['dadaDeBaja', 'reactivada']));
    });

    test('listar(soloActivos: true) excluye credenciales dadas de baja', () async {
      final activa = (await crear.ejecutar(nombre: 'Activa', tipo: 'otro')) as CrearCredencialBovedaExitoso;
      final baja = (await crear.ejecutar(nombre: 'De baja', tipo: 'otro')) as CrearCredencialBovedaExitoso;
      await darDeBaja.ejecutar(id: baja.credencial.id);

      final soloActivas = await repo.listar(soloActivos: true);
      expect(soloActivas.map((c) => c.id), contains(activa.credencial.id));
      expect(soloActivas.map((c) => c.id), isNot(contains(baja.credencial.id)));
    });
  });
}
