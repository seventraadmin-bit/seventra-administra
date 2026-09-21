/// Representación segura de un identificador sensible para auditoría —
/// número telefónico, ICCID, IMEI.
///
/// El problema real que resuelve: un auditor necesita poder verificar
/// QUE un identificador cambió y distinguir un valor de otro, pero la
/// pantalla de Auditoría no debe convertirse en un directorio de SIMs
/// consultable por cualquiera con `auditoria.ver`. Guardar el valor
/// completo en el diff haría exactamente eso — y a diferencia de la
/// entidad viva, un evento es append-only: lo que entra ahí no se
/// vuelve a sacar.
///
/// Se conservan los últimos [visibles] caracteres, que es la convención
/// que el propio proyecto ya usa para tarjetas
/// (`Deuda.tarjetaUltimosDigitos`). Un valor corto se enmascara entero
/// en vez de quedar casi completo.
///
/// `null` se conserva como `null`: "no tenía valor" es un dato real y
/// distinto de "tenía uno que no muestro".
String? enmascararIdentificador(String? valor, {int visibles = 4}) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (limpio.length <= visibles) return '·' * limpio.length;
  return '····${limpio.substring(limpio.length - visibles)}';
}

/// Representación segura de un CORREO para auditoría.
///
/// Mismo problema que [enmascararIdentificador], distinta forma: en un
/// correo lo que hay que poder distinguir es la persona dentro de un
/// mismo dominio, así que se conservan las primeras letras de la cuenta
/// y el dominio completo — `mariana@empresa.com` → `ma···@empresa.com`.
///
/// El dominio no se oculta a propósito: no identifica a nadie por sí
/// solo y es justo lo que permite reconocer de qué empresa se trata.
/// Una cuenta muy corta se enmascara entera: dejarla casi completa
/// derrotaría el propósito.
String? enmascararCorreo(String? valor, {int visibles = 2}) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;

  final arroba = limpio.lastIndexOf('@');
  // Sin `@` no es un correo reconocible: se trata como identificador
  // cualquiera en vez de inventarle una estructura.
  if (arroba <= 0) return enmascararIdentificador(limpio);

  final cuenta = limpio.substring(0, arroba);
  final dominio = limpio.substring(arroba);
  if (cuenta.length <= visibles) return '${'·' * cuenta.length}$dominio';
  return '${cuenta.substring(0, visibles)}···$dominio';
}
