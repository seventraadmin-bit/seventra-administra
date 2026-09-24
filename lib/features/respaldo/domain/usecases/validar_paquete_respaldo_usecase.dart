import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../huella_archivo.dart';
import '../manifest_respaldo.dart';
import '../rutas_paquete.dart';
import '../salud_base_datos.dart';

sealed class ResultadoValidarPaqueteRespaldo {}

/// [staging] es la carpeta temporal ya extraída, con `riseg_one.sqlite`
/// y (si el respaldo tenía adjuntos) `attachments/` adentro — el
/// llamador (`PrepararRestauracionUseCase`) es responsable de moverla o
/// borrarla; este caso de uso nunca la borra en el caso exitoso.
class PaqueteRespaldoValido extends ResultadoValidarPaqueteRespaldo {
  PaqueteRespaldoValido({required this.staging, required this.manifiesto, required this.verificacionCompleta});

  final Directory staging;
  final ManifestRespaldo manifiesto;

  /// `false` para un paquete de formato 1: se comprobó que la base de
  /// datos abre y pasa sus PRAGMAs, pero **no** que los adjuntos hayan
  /// llegado íntegros — ese formato no registraba hashes. La pantalla
  /// tiene que decirlo con esas palabras; nunca presentarlo como
  /// verificado.
  final bool verificacionCompleta;
}

/// `.zip` sin `manifest.json` válido, sin `riseg_one.sqlite`, o
/// cualquier otra forma inesperada del paquete.
class PaqueteRespaldoInvalido extends ResultadoValidarPaqueteRespaldo {
  PaqueteRespaldoInvalido(this.motivo);
  final MotivoPaqueteInvalido motivo;
}

/// Por qué un paquete no sirve — un valor cerrado, no una cadena
/// técnica: la pantalla traduce cada caso a una frase que una persona
/// entiende, sin rutas del sistema ni mensajes de excepción.
enum MotivoPaqueteInvalido {
  noEsUnZip,
  rutaInsegura,
  faltaManifiesto,
  manifiestoDanado,
  formatoNoSoportado,
  faltaBaseDatos,
  baseDatosAlterada,
  baseDatosIlegible,
  integridadBaseDatos,
  referenciasRotas,
  adjuntoFaltante,
  adjuntoAlterado,
  adjuntoNoDeclarado,
}

class PaqueteRespaldoIntegridadFallida extends ResultadoValidarPaqueteRespaldo {}

/// El paquete fue creado con una versión de esquema más nueva que la
/// que esta build de RISEG ONE conoce — restaurarlo sin protección
/// dejaría a la aplicación operando sobre una forma de base de datos
/// que no entiende. Se bloquea siempre, sin excepción.
class PaqueteRespaldoVersionMasNueva extends ResultadoValidarPaqueteRespaldo {
  PaqueteRespaldoVersionMasNueva({required this.versionPaquete, required this.versionApp});
  final int versionPaquete;
  final int versionApp;
}

class PaqueteRespaldoErrorInesperado extends ResultadoValidarPaqueteRespaldo {
  PaqueteRespaldoErrorInesperado(this.mensaje);

  /// Detalle técnico — para registro, nunca para mostrarse tal cual.
  final String mensaje;
}

/// Valida un `.zip` de respaldo candidato a restauración **antes** de
/// tocar cualquier archivo vivo de la aplicación — nunca abre la
/// conexión Drift, siempre trabaja sobre una copia extraída a una
/// carpeta temporal.
///
/// **Es el único juez de integridad del proyecto** (Etapa 4B): lo usa
/// Restaurar, lo usa Verificar desde la lista, y lo usa el propio
/// `CrearRespaldoUseCase` sobre el paquete que acaba de escribir. No
/// existe una segunda implementación que pueda opinar distinto.
class ValidarPaqueteRespaldoUseCase {
  Future<ResultadoValidarPaqueteRespaldo> ejecutar({
    required String rutaZip,
    required int appSchemaVersionActual,
  }) async {
    final staging = await Directory.systemTemp.createTemp('riseg_restauracion_');
    var stagingEntregada = false;
    try {
      final extraccion = await _extraerConRutasSeguras(rutaZip, staging);
      if (extraccion != null) return PaqueteRespaldoInvalido(extraccion);

      final manifestFile = File(p.join(staging.path, RutasPaquete.nombreManifiesto));
      final sqliteFile = File(p.join(staging.path, RutasPaquete.nombreBaseDatos));
      if (!manifestFile.existsSync()) return PaqueteRespaldoInvalido(MotivoPaqueteInvalido.faltaManifiesto);
      if (!sqliteFile.existsSync()) return PaqueteRespaldoInvalido(MotivoPaqueteInvalido.faltaBaseDatos);

      final ManifestRespaldo manifiesto;
      try {
        final json = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        final parseado = ManifestRespaldo.fromJson(json);
        if (parseado == null) return PaqueteRespaldoInvalido(MotivoPaqueteInvalido.manifiestoDanado);
        manifiesto = parseado;
      } catch (_) {
        return PaqueteRespaldoInvalido(MotivoPaqueteInvalido.manifiestoDanado);
      }

      if (manifiesto.formatVersion < 1 || manifiesto.formatVersion > ManifestRespaldo.versionActual) {
        return PaqueteRespaldoInvalido(MotivoPaqueteInvalido.formatoNoSoportado);
      }

      // Integridad por archivo — sólo un paquete que la declara.
      if (manifiesto.verificaIntegridad) {
        final fallo = await _verificarArchivos(staging, manifiesto, sqliteFile);
        if (fallo != null) return PaqueteRespaldoInvalido(fallo);
      }

      // Las mismas tres preguntas que el arranque le hace a la base ya
      // instalada (`revisarSaludBaseDatos`), para que no existan dos
      // definiciones de "sana" que puedan separarse con el tiempo.
      final SaludBaseDatos salud;
      try {
        final db = sqlite3.open(sqliteFile.path, mode: OpenMode.readOnly);
        try {
          salud = await revisarSaludBaseDatos((sql) async => db.select(sql).rows);
        } finally {
          db.dispose();
        }
      } catch (_) {
        return PaqueteRespaldoInvalido(MotivoPaqueteInvalido.baseDatosIlegible);
      }

      if (!salud.integridadOk) return PaqueteRespaldoIntegridadFallida();
      if (!salud.referenciasOk) return PaqueteRespaldoInvalido(MotivoPaqueteInvalido.referenciasRotas);

      // Política de versión propia de este momento: una base más vieja
      // es legítima y se migrará al restaurarla; una más nueva no puede
      // entenderse y se rechaza aquí.
      if (salud.userVersion > appSchemaVersionActual) {
        return PaqueteRespaldoVersionMasNueva(versionPaquete: salud.userVersion, versionApp: appSchemaVersionActual);
      }

      stagingEntregada = true;
      return PaqueteRespaldoValido(
        staging: staging,
        manifiesto: manifiesto,
        verificacionCompleta: manifiesto.verificaIntegridad,
      );
    } catch (e) {
      return PaqueteRespaldoErrorInesperado(e.toString());
    } finally {
      if (!stagingEntregada) {
        await staging.delete(recursive: true);
      }
    }
  }

  /// Extrae comprobando **cada** nombre de entrada antes de escribir.
  ///
  /// No se usa `extractFileToDisk`: esa función confía en los nombres
  /// que trae el archivo, y un `.zip` es contenido ajeno. Aquí una
  /// entrada que intente salir del staging aborta la validación entera,
  /// sin haber escrito ese archivo.
  Future<MotivoPaqueteInvalido?> _extraerConRutasSeguras(String rutaZip, Directory staging) async {
    final InputFileStream entrada;
    try {
      entrada = InputFileStream(rutaZip);
    } catch (_) {
      return MotivoPaqueteInvalido.noEsUnZip;
    }
    try {
      final Archive archivo;
      try {
        archivo = ZipDecoder().decodeBuffer(entrada);
      } catch (_) {
        return MotivoPaqueteInvalido.noEsUnZip;
      }

      for (final entry in archivo) {
        final nombre = entry.name.replaceAll(r'\', '/');
        if (!RutasPaquete.esSegura(nombre)) return MotivoPaqueteInvalido.rutaInsegura;
        if (!entry.isFile) continue;

        final destino = File(p.join(staging.path, p.joinAll(nombre.split('/'))));
        // Cinturón y tirantes: aunque `esSegura` ya lo garantiza, se
        // comprueba que la ruta final siga dentro del staging.
        if (!p.isWithin(staging.path, destino.path)) return MotivoPaqueteInvalido.rutaInsegura;

        destino.parent.createSync(recursive: true);
        final salida = OutputFileStream(destino.path);
        try {
          entry.writeContent(salida);
        } finally {
          await salida.close();
        }
      }
      return null;
    } finally {
      await entrada.close();
    }
  }

  /// Comprueba tamaño y SHA-256 de la base y de cada adjunto declarado,
  /// y que no haya adjuntos que el manifiesto no describa.
  ///
  /// Un adjunto no declarado invalida el paquete: el manifiesto debe
  /// describir EXACTAMENTE el conjunto que se va a restaurar. Si
  /// sobrara un archivo, restaurar dejaría en disco algo que nadie
  /// verificó y que la base no conoce.
  Future<MotivoPaqueteInvalido?> _verificarArchivos(
    Directory staging,
    ManifestRespaldo manifiesto,
    File sqliteFile,
  ) async {
    final base = manifiesto.baseDatos!;
    if (await sqliteFile.length() != base.bytes) return MotivoPaqueteInvalido.baseDatosAlterada;
    if (await sha256DeArchivo(sqliteFile) != base.sha256) return MotivoPaqueteInvalido.baseDatosAlterada;

    final declarados = {for (final a in manifiesto.adjuntos) a.rutaRelativa: a};
    for (final declarado in declarados.values) {
      if (!RutasPaquete.esSegura(declarado.rutaRelativa)) return MotivoPaqueteInvalido.rutaInsegura;
      final archivo = File(p.join(staging.path, 'attachments', p.joinAll(declarado.rutaRelativa.split('/'))));
      if (!archivo.existsSync()) return MotivoPaqueteInvalido.adjuntoFaltante;
      if (await archivo.length() != declarado.bytes) return MotivoPaqueteInvalido.adjuntoAlterado;
      if (await sha256DeArchivo(archivo) != declarado.sha256) return MotivoPaqueteInvalido.adjuntoAlterado;
    }

    final carpetaAdjuntos = Directory(p.join(staging.path, 'attachments'));
    if (carpetaAdjuntos.existsSync()) {
      for (final entidad in carpetaAdjuntos.listSync(recursive: true).whereType<File>()) {
        final relativa = p.relative(entidad.path, from: carpetaAdjuntos.path).replaceAll(r'\', '/');
        if (!declarados.containsKey(relativa)) return MotivoPaqueteInvalido.adjuntoNoDeclarado;
      }
    }

    return null;
  }
}
