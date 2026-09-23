import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

/// Identidad efectiva de una cuenta (Etapa 3B) — el **único** lugar del
/// proyecto que decide de dónde sale el nombre y el puesto que se
/// muestran de un `Usuario`.
///
/// El modelo es híbrido a propósito:
///
///  * **Cuenta independiente** (`empleadoId == null`): su identidad es
///    la suya. `Usuario.nombre` y `Usuario.puestoId` son la verdad.
///    Es un estado legítimo y frecuente — el Maestro del bootstrap, un
///    administrador sin expediente laboral — y nunca es un error ni
///    merece una advertencia.
///
///  * **Cuenta vinculada** (`empleadoId != null`): declara pertenecer a
///    una persona registrada en Personal, y entonces la identidad
///    personal viene de Personal. `Usuario.nombre`/`Usuario.puestoId`
///    quedan como snapshot técnico y NO se presentan.
///
/// Por qué una clase y no un puñado de `if` repartidos: porque la regla
/// que se repite en cada pantalla es exactamente la regla que se olvida
/// en una de ellas. La auditoría 3A encontró la versión anterior de
/// este problema — el vínculo existía en la base y **nada** lo leía, así
/// que el listado seguía pintando la identidad propia de una cuenta
/// vinculada.
///
/// **Nunca sincroniza copiando.** No hay ningún punto donde
/// `Empleado.nombres` se escriba sobre `Usuario.nombre`: eso volvería a
/// crear las dos fuentes de verdad que esta etapa cierra. El nombre del
/// Empleado se resuelve al leer, siempre en lote (ver
/// `UsuarioRepository.listarConIdentidad`), nunca con una consulta por
/// fila.
class IdentidadUsuario {
  const IdentidadUsuario({required this.usuario, this.empleado, this.puesto});

  final UsuarioData usuario;

  /// El Empleado detrás de la cuenta, ya resuelto. `null` cuando la
  /// cuenta es independiente.
  final EmpleadoData? empleado;

  /// El Puesto **efectivo** ya resuelto: el del Empleado si la cuenta
  /// está vinculada, el propio si es independiente. `null` si no hay
  /// puesto, que es un estado permitido en ambos casos.
  ///
  /// Se resuelve contra el catálogo COMPLETO de puestos, no sólo los
  /// activos: un puesto que se desactivó después sigue siendo el que
  /// esta cuenta tiene, y mostrar "—" en su lugar sería borrar un dato
  /// que sí existe (bug encontrado en la auditoría 3A).
  final PuestoData? puesto;

  bool get estaVinculado => usuario.empleadoId != null;

  /// Lo que se muestra como nombre de esta cuenta, en cualquier
  /// pantalla, sin excepción.
  ///
  /// Si el vínculo apunta a un Empleado que no se pudo resolver, cae al
  /// nombre propio en vez de quedarse en blanco: una cuenta siempre
  /// tiene que poder nombrarse. No debería ocurrir (la FK es
  /// `restrict`), pero una ficha rota es peor que un nombre viejo.
  String get nombreEfectivo {
    final e = empleado;
    return e == null ? usuario.nombre : empleadoNombreCompleto(e);
  }

  String? get puestoEfectivoId => estaVinculado ? empleado?.puestoId : usuario.puestoId;

  /// `null` cuando no hay puesto — la UI decide cómo decirlo ("Sin
  /// puesto asignado"), el dominio no inventa una etiqueta.
  String? get nombrePuestoEfectivo => puesto?.nombre;

  /// La persona está laboralmente dada de baja. Sólo tiene sentido para
  /// una cuenta vinculada; una cuenta independiente nunca lo está.
  bool get empleadoDeBaja {
    final e = empleado;
    return e != null && EstatusEmpleado.values.byName(e.estatus) == EstatusEmpleado.baja;
  }

  bool get cuentaActiva => usuario.cicloVidaRegistro == 'activo';
}
