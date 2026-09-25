import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../../core/security/almacen_ranuras_clave.dart';
import '../usecases/aplicar_restauracion_pendiente_usecase.dart';
import '../usecases/preparar_restauracion_usecase.dart';
import 'verificar_respaldo_portable_usecase.dart';

/// Claves del marcador que pertenecen a la restauración portable.
abstract final class CamposRestauracionPortable {
  static const operacion = 'restoreOperationId';
  static const keyIdEsperado = 'keyIdEsperado';
  static const clavePendiente = 'clavePendienteGuardada';
}

sealed class ResultadoPrepararPortable {}

class RestauracionPortablePreparada extends ResultadoPrepararPortable {
  RestauracionPortablePreparada({required this.restoreOperationId, required this.keyId});
  final String restoreOperationId;
  final String keyId;
}

/// El paquete no pasó la verificación completa. **No se tocó nada** de la
/// instalación actual: validar antes de destruir no es una preferencia
/// de estilo, es la única forma de que un paquete corrupto no cueste los
/// datos que ya había.
class RestauracionPortableRechazada extends ResultadoPrepararPortable {
  RestauracionPortableRechazada(this.verificacion);
  final ResultadoVerificarPortable verificacion;
}

/// El motor de 4B no pudo dejar el paquete en espera.
/// La preparación no se intentó porque quien la pidió no podía pedirla.
///
/// Vive aquí, y no junto a la compuerta que la produce, sólo porque
/// [ResultadoPrepararPortable] es sellado: fuera de esta librería no se
/// puede extender. La razón de ser de este caso está en
/// `autorizar_restauracion_portable.dart`.
class RestauracionPortableNoAutorizada extends ResultadoPrepararPortable {
  RestauracionPortableNoAutorizada(this.mensaje);
  final String mensaje;
}

class RestauracionPortablePreparacionFallida extends ResultadoPrepararPortable {
  RestauracionPortablePreparacionFallida(this.resultado);
  final ResultadoPrepararRestauracion resultado;
}

/// Por qué una restauración portable no llegó a confirmarse.
enum MotivoRestauracionPortableAbortada {
  aplicacionFallida,
  baseNoSana,
  claveNoAbreLoRestaurado,
  promocionDeClaveFallida,
  confirmacionFallida,
  estadoAmbiguo,
}

sealed class ResultadoAplicarPortable {}

class RestauracionPortableConfirmada extends ResultadoAplicarPortable {
  RestauracionPortableConfirmada({required this.restoreOperationId, required this.keyId});
  final String restoreOperationId;
  final String keyId;
}

class RestauracionPortableRevertida extends ResultadoAplicarPortable {
  RestauracionPortableRevertida({required this.motivo, required this.estadoAnteriorRepuesto});
  final MotivoRestauracionPortableAbortada motivo;

  /// `false` es la situación grave: hay que decírselo a alguien, nunca
  /// seguir como si nada.
  final bool estadoAnteriorRepuesto;
}

/// El estado en disco no permite decidir sin riesgo. **No se toca nada**
/// y no se borra evidencia: ni la base, ni `restore_old`, ni el
/// preventivo, ni las ranuras de clave, ni el marcador.
class RestauracionPortableEstadoAmbiguo extends ResultadoAplicarPortable {
  RestauracionPortableEstadoAmbiguo(this.detalle);
  final String detalle;
}

class SinRestauracionPortablePendiente extends ResultadoAplicarPortable {}

/// Coordina una restauración portable entre dos mundos que **no
/// comparten transacción**: el sistema de archivos y el Almacén de
/// Credenciales de Windows (Etapa 4D).
///
/// ## La invariante que lo justifica todo
///
/// En ningún punto observable puede quedar **la base de A con la clave
/// de B**, ni al revés. Un estado así no es un error recuperable: son
/// datos que existen y no se pueden leer, y nadie sabría por qué.
///
/// ## Cómo se consigue
///
/// Compromiso en dos fases, con tres ranuras de clave y un identificador
/// propio de la operación:
///
/// ```
/// preparar()                        principal  pendiente  anterior
///   verificar el paquete COMPLETO      K_B         —         —
///   guardar la clave del paquete       K_B        K_A        —
///   4B: preventivo + staging + marca   K_B        K_A        —
/// -- reinicio --
/// aplicarYConfirmar()
///   4B: apartar (no borrar)            K_B        K_A        —
///   abrir, migrar, PRAGMAs             K_B        K_A        —
///   ¿la clave abre lo restaurado?      K_B        K_A        —
///   promover                           K_A         —        K_B
///   confirmar                          K_A         —        K_B
/// ```
///
/// Nada se borra antes de confirmar, la promoción ocurre **después** de
/// validar y **antes** de confirmar, y cada paso es idempotente: si el
/// equipo se apaga en cualquier punto, el siguiente arranque deduce
/// dónde quedó leyendo el marcador y las ranuras — nunca por marcas de
/// tiempo ni por suposiciones.
class CoordinadorRestauracionPortable {
  CoordinadorRestauracionPortable({
    required VerificarRespaldoPortableUseCase verificador,
    required PrepararRestauracionUseCase preparar,
    required AplicarRestauracionPendienteUseCase aplicar,
    required AlmacenRanurasClave ranuras,
    required String stagingDir,
    required Future<ResultadoSaludBaseRestaurada> Function() validarBaseRestaurada,
    required Future<bool> Function(Uint8List clave) claveAbreLoRestaurado,
    Random? aleatorio,
  }) : _verificador = verificador,
       _preparar = preparar,
       _aplicar = aplicar,
       _ranuras = ranuras,
       _stagingDir = stagingDir,
       _validarBaseRestaurada = validarBaseRestaurada,
       _claveAbreLoRestaurado = claveAbreLoRestaurado,
       _aleatorio = aleatorio ?? Random.secure();

  final VerificarRespaldoPortableUseCase _verificador;
  final PrepararRestauracionUseCase _preparar;
  final AplicarRestauracionPendienteUseCase _aplicar;
  final AlmacenRanurasClave _ranuras;
  final String _stagingDir;

  /// Abre la base ya instalada, corre sus migraciones y sus PRAGMAs. Se
  /// inyecta porque abrir la base de verdad es responsabilidad del
  /// arranque, no de este coordinador.
  final Future<ResultadoSaludBaseRestaurada> Function() _validarBaseRestaurada;

  /// Comprueba que la clave del paquete descifra de verdad una muestra
  /// de lo que se acaba de restaurar.
  final Future<bool> Function(Uint8List clave) _claveAbreLoRestaurado;

  final Random _aleatorio;

  /// Fase 1: valida el paquete de arriba abajo y deja todo listo, **sin
  /// haber alterado la instalación** hasta que el paquete ha demostrado
  /// que sirve.
  Future<ResultadoPrepararPortable> preparar({
    required String rutaPaquete,
    required int appSchemaVersionActual,
    String? frase,
    String? claveRecuperacionTexto,
  }) async {
    final operacion = _hexAleatorio(16);
    final staging = Directory(p.join(_stagingDir, 'restaurar_$operacion'))..createSync(recursive: true);
    final respaldoV2 = File(p.join(staging.path, 'respaldo_v2.zip'));

    try {
      // 1. Verificación COMPLETA antes de tocar nada: contenedor,
      //    credencial, payload entero, respaldo v2 con el validador
      //    canónico de 4B y registro de clave.
      final verificacion = await _verificador.ejecutar(
        rutaPaquete: rutaPaquete,
        appSchemaVersionActual: appSchemaVersionActual,
        frase: frase,
        claveRecuperacionTexto: claveRecuperacionTexto,
        respaldoDestino: respaldoV2,
      );
      if (verificacion is! PortableVerificado) {
        await _borrarSiSePuede(staging);
        return RestauracionPortableRechazada(verificacion);
      }

      // 2. La clave del paquete espera en su ranura. La principal sigue
      //    siendo la de este equipo y sigue funcionando: si esta
      //    restauración no llega a buen puerto, nadie se enterará.
      final clave = verificacion.claveAes;
      await _ranuras.escribir(RanuraClave.pendiente, clave.clave);

      // 3. El motor de 4B hace el trabajo de archivos: preventivo,
      //    staging y marcador. Se le añaden los campos de correlación.
      final preparado = await _preparar.ejecutar(
        rutaZip: respaldoV2.path,
        appSchemaVersionActual: appSchemaVersionActual,
        datosExtra: {
          CamposRestauracionPortable.operacion: operacion,
          CamposRestauracionPortable.keyIdEsperado: clave.keyId,
          CamposRestauracionPortable.clavePendiente: true,
        },
      );
      if (preparado is! RestauracionPreparada) {
        // Si no hay restauración pendiente, una clave esperando no
        // pertenece a nada: se retira.
        await _ranuras.borrar(RanuraClave.pendiente);
        await _borrarSiSePuede(staging);
        return RestauracionPortablePreparacionFallida(preparado);
      }

      return RestauracionPortablePreparada(restoreOperationId: operacion, keyId: clave.keyId);
    } finally {
      await _borrarSiSePuede(staging);
    }
  }

  /// Fase 2, en el arranque: aplica, valida y **sólo entonces** promueve
  /// la clave y confirma.
  Future<ResultadoAplicarPortable> aplicarYConfirmar() async {
    final marcador = await _aplicar.leerMarcador();

    if (marcador == null) {
      // Sin marcador no hay operación a la que pertenezca una clave
      // pendiente: es un huérfano de un intento que no llegó a empezar.
      if (await _ranuras.leer(RanuraClave.pendiente) != null) {
        await _ranuras.borrar(RanuraClave.pendiente);
      }
      return SinRestauracionPortablePendiente();
    }

    final operacion = marcador[CamposRestauracionPortable.operacion] as String?;
    final keyIdEsperado = marcador[CamposRestauracionPortable.keyIdEsperado] as String?;
    if (operacion == null || keyIdEsperado == null) {
      // Un marcador de 4B sin datos portables: lo atiende el arranque
      // normal, no este coordinador.
      return SinRestauracionPortablePendiente();
    }

    final pendiente = await _ranuras.leer(RanuraClave.pendiente);
    final anterior = await _ranuras.leer(RanuraClave.anterior);

    // Si no hay clave pendiente y tampoco hay constancia de haberla
    // promovido, no se puede saber qué clave corresponde a la base que
    // está instalada. No se adivina y no se borra nada.
    if (pendiente == null && anterior == null) {
      return RestauracionPortableEstadoAmbiguo(
        'el marcador anuncia una restauración portable pero no hay ni clave pendiente ni clave anterior',
      );
    }

    // 1. Archivos: apartar, nunca borrar (4B).
    final aplicado = await _aplicar.ejecutar();
    if (aplicado is! RestauracionAplicadaPendienteConfirmar) {
      return _revertir(MotivoRestauracionPortableAbortada.aplicacionFallida);
    }

    // 2. La base ya instalada: abre, migra, esquema, PRAGMAs, adjuntos.
    final salud = await _validarBaseRestaurada();
    if (!salud.sana) return _revertir(MotivoRestauracionPortableAbortada.baseNoSana);

    // 3. ¿La clave del paquete abre de verdad lo que acaba de
    //    restaurarse? Sin esto, "recuperación total" sería una promesa
    //    que nadie ha comprobado.
    final claveDelPaquete = pendiente ?? await _ranuras.leer(RanuraClave.principal);
    if (claveDelPaquete == null) {
      return RestauracionPortableEstadoAmbiguo('no hay clave con la que comprobar lo restaurado');
    }
    if (!await _claveAbreLoRestaurado(claveDelPaquete)) {
      return _revertir(MotivoRestauracionPortableAbortada.claveNoAbreLoRestaurado);
    }

    // 4. Promoción. Idempotente: si ya ocurrió —porque el equipo se
    //    apagó entre promover y confirmar— la pendiente ya no existe y
    //    se sigue adelante sin volver a moverla.
    if (pendiente != null) {
      try {
        final principalActual = await _ranuras.leer(RanuraClave.principal);
        if (principalActual != null && anterior == null) {
          await _ranuras.escribir(RanuraClave.anterior, principalActual);
        }
        await _ranuras.escribir(RanuraClave.principal, pendiente);
        await _ranuras.borrar(RanuraClave.pendiente);
      } catch (_) {
        return _revertir(MotivoRestauracionPortableAbortada.promocionDeClaveFallida);
      }
    }

    // 5. Recién ahora se suelta el estado anterior.
    try {
      await _aplicar.confirmar();
    } catch (_) {
      return _revertir(MotivoRestauracionPortableAbortada.confirmacionFallida);
    }

    return RestauracionPortableConfirmada(restoreOperationId: operacion, keyId: keyIdEsperado);
  }

  /// Vuelta atrás **conjunta**: archivos y clave. Que SQLite vuelva no es
  /// rollback si la Bóveda queda ilegible.
  ///
  /// Cada paso se intenta por separado a propósito. La primera versión
  /// los encadenaba en un solo `try`, y al probar el caso en que el
  /// Almacén de Credenciales rechaza toda escritura se vio el problema:
  /// el fallo al reponer la clave abortaba el resto y dejaba la clave
  /// pendiente ahí, apuntando a una operación que ya no existía. Una
  /// limpieza que se rinde a la primera no es una limpieza.
  Future<ResultadoAplicarPortable> _revertir(MotivoRestauracionPortableAbortada motivo) async {
    final archivosRepuestos = await _intentar(_aplicar.revertir) ?? false;

    // La clave anterior vuelve a principal sólo si la promoción ya había
    // ocurrido. Si no, principal nunca se tocó y no hay nada que reponer.
    var claveRepuesta = true;
    final anterior = await _intentar(() => _ranuras.leer(RanuraClave.anterior));
    if (anterior != null) {
      claveRepuesta =
          await _intentar(() async {
            await _ranuras.escribir(RanuraClave.principal, anterior);
            await _ranuras.borrar(RanuraClave.anterior);
            return true;
          }) ??
          false;
    }

    // Se intenta siempre, con independencia de lo anterior: una clave
    // pendiente huérfana confundiría al siguiente arranque.
    await _intentar(() async {
      await _ranuras.borrar(RanuraClave.pendiente);
      return true;
    });

    return RestauracionPortableRevertida(motivo: motivo, estadoAnteriorRepuesto: archivosRepuestos && claveRepuesta);
  }

  /// Ejecuta un paso de limpieza sin dejar que su fallo arrastre a los
  /// demás. Devuelve `null` si no salió.
  Future<T?> _intentar<T>(Future<T> Function() paso) async {
    try {
      return await paso();
    } catch (_) {
      return null;
    }
  }

  String _hexAleatorio(int bytes) {
    return List<int>.generate(
      bytes,
      (_) => _aleatorio.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _borrarSiSePuede(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Se limpiará al arrancar.
    }
  }
}

/// Lo que el arranque responde sobre la base ya instalada.
class ResultadoSaludBaseRestaurada {
  const ResultadoSaludBaseRestaurada({required this.sana, this.detalle});
  final bool sana;
  final String? detalle;
}
