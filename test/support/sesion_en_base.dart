import 'package:drift/drift.dart' show Value;

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';

/// Persiste en la base el estado que un fixture declara en su
/// `SesionUsuario`.
///
/// Desde la Etapa 3B, autorizar una operación revalida la sesión contra
/// la base: una sesión que dice ser `U1` con el permiso `P` no autoriza
/// nada si `U1` no existe o no tiene `P`. Eso vuelve mentirosa a
/// cualquier fixture que inyectara una sesión sintética sin respaldo —
/// describía un estado que el sistema real no puede producir.
///
/// **No es una segunda implementación de autorización.** No decide
/// permisos, no los deduce por módulo, no convierte nada en Maestro y
/// no simula `vigente()`. Copia a la base, literalmente, lo que el
/// fixture ya declaraba; quien lee la llamada ve qué identidad y qué
/// permisos se están creando, porque son los del propio literal.
///
/// Tres decisiones que importan para no falsear pruebas:
///
///  1. **Los permisos se sincronizan EXACTAMENTE**, no se añaden. Si el
///     fixture declara `{'compras.ver'}`, la cuenta termina con ese
///     permiso y con ninguno más. Añadir sobre lo que ya hubiera
///     convertiría una prueba negativa —"sin `compras.corregir` no
///     puede"— en una positiva sin que nadie lo notara.
///  2. **Nunca reactiva una cuenta.** Si el fixture creó a propósito un
///     Usuario inactivo, sigue inactivo: esa inconsistencia puede ser
///     justamente el objeto de la prueba.
///  3. **Un Maestro se queda sin filas de permiso**, igual que en
///     producción: su acceso se calcula del catálogo.
Future<void> sembrarSesionEnBase(AppDatabase db, SesionUsuario sesion) async {
  final existente = await (db.select(db.usuario)..where((t) => t.id.equals(sesion.usuarioId))).getSingleOrNull();

  if (existente == null) {
    await db
        .into(db.usuario)
        .insert(
          UsuarioCompanion.insert(
            id: Value(sesion.usuarioId),
            nombre: sesion.nombre,
            // `nombreUsuario` es único: si el fixture reutiliza uno que
            // ya existe con otro id, se desambigua. Estas cuentas nunca
            // inician sesión, así que el valor exacto da igual; lo que
            // importa es no romper el fixture con un choque de unicidad.
            nombreUsuario: await _nombreLibre(db, sesion),
            passwordHash: 'sin-contrasena-en-pruebas',
            esMaestro: Value(sesion.esMaestro),
            debeCambiarPassword: Value(sesion.debeCambiarPassword),
          ),
        );
  } else {
    // La fila ya existía (la creó el propio fixture). Se alinea sólo en
    // lo que decide la autorización — nunca el ciclo de vida, ver (2).
    await (db.update(db.usuario)..where((t) => t.id.equals(sesion.usuarioId))).write(
      UsuarioCompanion(
        esMaestro: Value(sesion.esMaestro),
        debeCambiarPassword: Value(sesion.debeCambiarPassword),
      ),
    );
  }

  await (db.delete(db.permisoUsuario)..where((t) => t.usuarioId.equals(sesion.usuarioId))).go();
  if (sesion.esMaestro) return;
  for (final codigo in sesion.permisos) {
    await db.into(db.permisoUsuario).insert(
      PermisoUsuarioCompanion.insert(usuarioId: sesion.usuarioId, codigo: codigo),
    );
  }
}

Future<String> _nombreLibre(AppDatabase db, SesionUsuario sesion) async {
  final ocupado = await (db.select(db.usuario)..where((t) => t.nombreUsuario.equals(sesion.nombreUsuario)))
      .getSingleOrNull();
  return ocupado == null ? sesion.nombreUsuario : '${sesion.nombreUsuario}-${sesion.usuarioId}';
}
