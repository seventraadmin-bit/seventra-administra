import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/auth/password_hasher.dart';

void main() {
  // Iteraciones bajas en pruebas — la seguridad real (100000) se prueba
  // aparte con un solo caso, el resto no necesita pagar ese costo.
  const hasher = PasswordHasher(iteraciones: 1000);

  test('hash nunca contiene la contraseña en texto plano', () {
    final stored = hasher.hash('Sup3rSecreta!');
    expect(stored.contains('Sup3rSecreta'), isFalse);
  });

  test('verify acepta la contraseña correcta', () {
    final stored = hasher.hash('Sup3rSecreta!');
    expect(hasher.verify('Sup3rSecreta!', stored), isTrue);
  });

  test('verify rechaza una contraseña incorrecta', () {
    final stored = hasher.hash('Sup3rSecreta!');
    expect(hasher.verify('otra-cosa', stored), isFalse);
  });

  test('dos hashes de la misma contraseña son distintos (salt aleatorio)', () {
    final a = hasher.hash('misma-clave');
    final b = hasher.hash('misma-clave');
    expect(a, isNot(equals(b)));
    expect(hasher.verify('misma-clave', a), isTrue);
    expect(hasher.verify('misma-clave', b), isTrue);
  });

  test('formato almacenado trae algoritmo e iteraciones legibles', () {
    final stored = hasher.hash('x');
    final partes = stored.split(r'$');
    expect(partes[0], 'pbkdf2');
    expect(partes[1], '1000');
  });

  test('verify rechaza una cadena almacenada corrupta o de otro formato', () {
    expect(hasher.verify('cualquiera', 'no-es-un-hash-valido'), isFalse);
    expect(hasher.verify('cualquiera', 'otroAlgoritmo\$1000\$AA==\$BB=='), isFalse);
  });

  test('iteraciones por defecto son 100000 y siguen verificando correctamente', () {
    const hasherDefault = PasswordHasher();
    final stored = hasherDefault.hash('clave-real');
    expect(stored.split(r'$')[1], '100000');
    expect(hasherDefault.verify('clave-real', stored), isTrue);
  });
}
