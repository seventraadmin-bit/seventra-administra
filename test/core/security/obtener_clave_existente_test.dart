// Etapa 4D — leer la clave para meterla en un respaldo portable NO
// puede crearla.
//
// El camino de `cifrar()` sí la crea cuando falta, y hace bien: está
// guardando algo nuevo. Reutilizarlo aquí produciría el peor resultado
// posible — un paquete portable que viaja con una clave recién
// inventada, incapaz de abrir un solo secreto de los que acompaña, y
// que no se descubriría hasta el día de la emergencia en otra PC.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/security/credential_cipher.dart';

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

void main() {
  late _AlmacenEnMemoria almacen;

  setUp(() => almacen = _AlmacenEnMemoria());

  test('A. con clave existente devuelve exactamente esa clave', () async {
    final cipher = CredentialCipher(almacen: almacen);
    await cipher.cifrar('algo'); // crea la clave, que es su papel
    final guardada = base64.decode(almacen.valor!);

    final leida = await CredentialCipher(almacen: almacen).obtenerClaveExistente();

    expect(leida, equals(guardada));
    expect(leida.length, 32);
  });

  test('B. sin clave lanza ClaveCifradoNoDisponible', () async {
    await expectLater(
      CredentialCipher(almacen: almacen).obtenerClaveExistente(),
      throwsA(isA<ClaveCifradoNoDisponible>()),
      reason: 'no es un error inesperado: es "aquí no hay clave que llevarse"',
    );
  });

  test('C. después de fallar, la clave SIGUE ausente', () async {
    final cipher = CredentialCipher(almacen: almacen);

    await expectLater(cipher.obtenerClaveExistente(), throwsA(isA<ClaveCifradoNoDisponible>()));

    expect(almacen.valor, isNull, reason: 'intentar leer no puede fabricar una clave');
    expect(almacen.escrituras, 0, reason: 'no se escribió en el Almacén de Credenciales');
  });

  test('D. leer no cambia ni rota la clave', () async {
    final cipher = CredentialCipher(almacen: almacen);
    await cipher.cifrar('algo');
    final antes = almacen.valor;
    final escriturasAntes = almacen.escrituras;

    final primera = await cipher.obtenerClaveExistente();
    final segunda = await cipher.obtenerClaveExistente();
    final tercera = await CredentialCipher(almacen: almacen).obtenerClaveExistente();

    expect(primera, equals(segunda));
    expect(segunda, equals(tercera));
    expect(almacen.valor, antes, reason: 'el material guardado es el mismo');
    expect(almacen.escrituras, escriturasAntes, reason: 'ninguna escritura nueva');
  });

  test('la clave leída es la que descifra lo ya cifrado en este equipo', () async {
    final cipher = CredentialCipher(almacen: almacen);
    final cifrado = await cipher.cifrar('secreto del portal');

    final clave = await cipher.obtenerClaveExistente();

    // Se reconstruye un cipher con exactamente ese material y se
    // comprueba que abre lo de antes: es lo que tendrá que ocurrir en
    // PC B después de restaurar.
    final otroEquipo = _AlmacenEnMemoria()..valor = base64.encode(clave);
    expect(await CredentialCipher(almacen: otroEquipo).descifrar(cifrado), 'secreto del portal');
  });

  test('devuelve una copia: modificarla no toca la clave cacheada', () async {
    final cipher = CredentialCipher(almacen: almacen);
    await cipher.cifrar('algo');

    final copia = await cipher.obtenerClaveExistente();
    final original = Uint8List.fromList(copia);
    copia[0] ^= 0xFF;

    expect(await cipher.obtenerClaveExistente(), equals(original));
  });

  test('las tres ranuras tienen nombres distintos y estables', () {
    final nombres = {NombresRanuraClave.principal, NombresRanuraClave.pendiente, NombresRanuraClave.anterior};

    expect(nombres, hasLength(3));
    expect(NombresRanuraClave.principal, 'riseg_one_credencial_cifrado_clave_v1', reason: 'no puede cambiar nunca');
  });
}
