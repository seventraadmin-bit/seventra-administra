import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';

/// EL PUENTE, Y SÓLO EL PUENTE: proyecta la Identity del SaaS en la fila
/// `Usuario` local que las FKs heredadas todavía necesitan.
///
/// ## Por qué existe
///
/// El producto atribuye CADA operación a un `actorUsuarioId`: mil setecientos
/// noventa lugares lo pasan y quince tablas lo referencian con clave foránea. Esa
/// atribución es auditoría real —quién canceló aquel pago, quién cerró aquella
/// nómina— y no se tira a la basura porque cambie de dónde sale la sesión.
///
/// ## Por qué NO es una segunda identidad
///
/// **`Usuario.id` ES el `identityId` del SaaS**, carácter por carácter. No hay
/// columna puente, no hay tabla de correspondencia y no hay id alternativo: la
/// fila local *es* la sombra de la Identity, no su pareja. Por eso una prueba de
/// arquitectura de IF-2 —«no existe columna ni tabla puente Usuario↔Identity»—
/// sigue pasando después de esto: no se añadió ninguna.
///
/// Lo que esta clase NO hace, y cada punto es deliberado:
///
/// · **No empareja por correo ni por nombre.** Si el `identityId` no estaba, la
///   fila se crea; si estaba, se actualiza. Nunca se busca «una parecida».
/// · **No genera identificadores.** El único id posible es el que trae el SaaS.
/// · **No guarda contraseña utilizable.** Escribe un centinela que
///   `PasswordHasher.verify` rechaza siempre —no empieza por `pbkdf2`—, así que
///   autenticar contra esta fila es imposible por construcción, no por promesa.
/// · **No decide si alguien es Maestro.** Ese hecho vive en el `CompanyContext`
///   del servidor. Aquí se escribe como DATO PROYECTADO para que la interfaz
///   heredada que lee la columna siga mostrando lo mismo que el servidor dice;
///   jamás se consulta como autoridad.
///
/// `nombre` y `nombreUsuario` son igualmente datos proyectados: se refrescan en
/// cada inicio de sesión porque el SaaS manda, y no son claves de nada.
///
/// ## Cuándo desaparece
///
/// Cuando ninguna tabla local referencie ya `Usuario.id` —es decir, cuando los
/// módulos que aún viven en SQLite hayan migrado y su auditoría viva en
/// PostgreSQL—, **este archivo se borra entero y no hay que tocar nada más**.
/// Está aislado a propósito: nadie lo llama salvo el arranque de sesión, no
/// exporta tipos que otros usen y no tiene estado. Ésa es la prueba de que es un
/// puente y no una pieza del modelo.
class ProyeccionIdentityUsuario {
  const ProyeccionIdentityUsuario(this._db);

  final AppDatabase _db;

  /// El valor que ocupa `passwordHash` en una cuenta proyectada.
  ///
  /// NO ES UNA CONTRASEÑA, ni siquiera una imposible de adivinar: es una cadena
  /// que el verificador descarta antes de calcular nada, porque su primer
  /// segmento no es `pbkdf2`. Dejar aquí un hash real de una contraseña
  /// aleatoria habría sido peor: existiría una contraseña que abre la cuenta,
  /// aunque nadie la conozca.
  static const centinelaSinContrasena = r'saas$sin-contrasena-local';

  /// Crea o actualiza la fila, y devuelve el id —que es el `identityId`—.
  ///
  /// **Idempotente**: llamarla mil veces con los mismos datos deja la base
  /// exactamente igual. Se ejecuta en cada inicio de sesión y en cada
  /// restauración, así que tenía que serlo.
  Future<String> proyectar({
    required String identityId,
    required String nombre,
    required String correo,
    required bool esMaestro,
  }) async {
    final ahora = DateTime.now();

    // `nombreUsuario` es único en la tabla. Se usa el correo porque es lo que el
    // SaaS da y lo que la persona reconoce; si otra fila ya lo tuviera —una
    // cuenta legacy con ese mismo texto— la restricción única saltaría, y eso es
    // lo correcto: preferimos fallar a ADOPTAR una fila ajena, que sería
    // emparejar por correo por la puerta de atrás.
    final existente = await (_db.select(
      _db.usuario,
    )..where((t) => t.id.equals(identityId))).getSingleOrNull();

    if (existente == null) {
      await _db
          .into(_db.usuario)
          .insert(
            UsuarioCompanion.insert(
              id: Value(identityId),
              nombre: nombre,
              nombreUsuario: correo,
              passwordHash: centinelaSinContrasena,
              esMaestro: Value(esMaestro),
              // La cuenta proyectada NUNCA arrastra el cambio obligatorio de
              // contraseña: ese mecanismo se retiró con el cutover y aquí no hay
              // contraseña local que cambiar.
              debeCambiarPassword: const Value(false),
              createdAt: Value(ahora),
              updatedAt: Value(ahora),
              cicloVidaRegistro: const Value('activo'),
            ),
          );

      return identityId;
    }

    // Se reescriben SÓLO los datos proyectados. `empleadoId`, `puestoId` y todo
    // lo que el producto haya vinculado a esta cuenta se conserva intacto: el
    // SaaS no sabe nada de eso y sobrescribirlo con nulos destruiría el vínculo
    // laboral en cada inicio de sesión.
    await (_db.update(_db.usuario)..where((t) => t.id.equals(identityId))).write(
      UsuarioCompanion(
        nombre: Value(nombre),
        nombreUsuario: Value(correo),
        esMaestro: Value(esMaestro),
        passwordHash: const Value(centinelaSinContrasena),
        debeCambiarPassword: const Value(false),
        cicloVidaRegistro: const Value('activo'),
        ultimoAccesoAt: Value(ahora),
        updatedAt: Value(ahora),
      ),
    );

    return identityId;
  }
}
