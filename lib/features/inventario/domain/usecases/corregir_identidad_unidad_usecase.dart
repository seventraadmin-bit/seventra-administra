import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/inventario_repository.dart';

sealed class CorregirIdentidadUnidadResultado {}

class CorregirIdentidadUnidadExitoso extends CorregirIdentidadUnidadResultado {
  CorregirIdentidadUnidadExitoso(this.unidad);
  final ArticuloUnidadData unidad;
}

class CorregirIdentidadUnidadNoExiste extends CorregirIdentidadUnidadResultado {}

class CorregirIdentidadUnidadMotivoRequerido extends CorregirIdentidadUnidadResultado {}

class CorregirIdentidadUnidadNumeroSerieRequerido extends CorregirIdentidadUnidadResultado {}

/// Mismo texto exacto sin importar si el duplicado viene de aquí o de
/// `RegistrarCompraUseCase` — "El número de serie/IMEI ya está
/// registrado en otra unidad."
class CorregirIdentidadUnidadNumeroSerieDuplicado extends CorregirIdentidadUnidadResultado {
  CorregirIdentidadUnidadNumeroSerieDuplicado(this.detalle);
  final String detalle;
}

class CorregirIdentidadUnidadImeiDuplicado extends CorregirIdentidadUnidadResultado {
  CorregirIdentidadUnidadImeiDuplicado(this.detalle);
  final String detalle;
}

class CorregirIdentidadUnidadErrorInesperado extends CorregirIdentidadUnidadResultado {
  CorregirIdentidadUnidadErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Distingue, para un campo de texto opcional, entre "no lo toques"
/// (el parámetro nunca se pasó) y "bórralo"/"ponlo en este valor" (sí
/// se pasó, ya limpio de espacios). Evita el ternario anidado que
/// mezclaba ambos casos en la versión anterior de este archivo.
class _CampoResuelto {
  const _CampoResuelto({required this.tocar, required this.valor});
  final bool tocar;
  final String? valor;

  static _CampoResuelto sinTocar() => const _CampoResuelto(tocar: false, valor: null);
  static _CampoResuelto resolver(String? entrada) {
    if (entrada == null) return sinTocar();
    final limpio = entrada.trim();
    return _CampoResuelto(tocar: true, valor: limpio.isEmpty ? null : limpio);
  }
}

/// Corrección de identidad de una `ArticuloUnidad` ya existente (Etapa
/// 9D, tercer ajuste posterior) — número de serie, marca, modelo, IMEI
/// 1/IMEI 2, cuando se capturaron mal al dar de alta la unidad (vía
/// Compra o entrada manual). Deliberadamente separado de
/// `ConfigurarEquipoTelefonicoUseCase` (alta/edición rápida de IMEI sin
/// motivo, uso operativo diario): esta es una corrección sensible —
/// exige [motivo] y dispara un `ArticuloUnidadEvento` por cada campo
/// que realmente cambió, con valor anterior y nuevo.
///
/// Nunca cambia `cantidad`/`costo`/existencia, nunca crea
/// `MovimientoInventario`, nunca toca la `Compra`/`Egreso` original,
/// nunca borra historial — misma `ArticuloUnidad.id`/`codigo`; todas
/// las asignaciones/línea telefónica/credencial/historial de la unidad
/// se conservan intactas porque `InventarioRepository.corregirIdentidadUnidad`
/// nunca toca esas tablas.
///
/// La validación de duplicados vive aquí (no en el repositorio, mismo
/// criterio de siempre): número de serie vía
/// `InventarioRepository.obtenerUnidadPorNumeroSerie`, IMEI vía
/// `listarTelefonosPorImei` (idéntico patrón ya usado por
/// `ConfigurarEquipoTelefonicoUseCase`) — si el valor nuevo coincide
/// con el que la propia unidad ya tenía, no hay falso duplicado
/// (`existente.id`/`unidadId != unidadId` es la condición real).
class CorregirIdentidadUnidadUseCase {
  CorregirIdentidadUnidadUseCase(this._inventarioRepository);

  final InventarioRepository _inventarioRepository;

  Future<CorregirIdentidadUnidadResultado> ejecutar({
    required String unidadId,
    required String motivo,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? imei,
    String? imei2,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CorregirIdentidadUnidadMotivoRequerido();

    final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return CorregirIdentidadUnidadNoExiste();

    final serie = _CampoResuelto.resolver(numeroSerie);
    // numeroSerie nunca es nullable en el esquema: "tocarlo y dejarlo
    // vacío" es un error de captura, no "bórralo" (a diferencia de
    // marca/modelo/IMEI, que sí admiten quedar en null).
    if (serie.tocar && serie.valor == null) return CorregirIdentidadUnidadNumeroSerieRequerido();

    final campoMarca = _CampoResuelto.resolver(marca);
    final campoModelo = _CampoResuelto.resolver(modelo);
    if (serie.tocar && serie.valor != unidad.numeroSerie) {
      final existente = await _inventarioRepository.obtenerUnidadPorNumeroSerie(serie.valor!);
      if (existente != null && existente.id != unidadId) {
        return CorregirIdentidadUnidadNumeroSerieDuplicado('El número de serie/IMEI ya está registrado en otra unidad.');
      }
    }

    final campoImei = _CampoResuelto.resolver(imei);
    final campoImei2 = _CampoResuelto.resolver(imei2);

    if (campoImei.tocar && campoImei.valor != null) {
      final coincidencias = await _inventarioRepository.listarTelefonosPorImei(campoImei.valor!);
      if (coincidencias.any((t) => t.unidadId != unidadId)) {
        return CorregirIdentidadUnidadImeiDuplicado('El IMEI 1 ya está registrado en otro equipo.');
      }
    }

    if (campoImei2.tocar && campoImei2.valor != null) {
      // Valor efectivo de IMEI 1 tras esta corrección: el nuevo si se
      // está tocando en esta misma llamada, si no el que la unidad ya
      // tenía — nunca los dos IMEI iguales al terminar.
      final telefonoActual = campoImei.tocar ? null : await _inventarioRepository.obtenerTelefono(unidadId);
      final imei1Efectivo = campoImei.tocar ? campoImei.valor : telefonoActual?.imei;
      if (campoImei2.valor == imei1Efectivo) {
        return CorregirIdentidadUnidadImeiDuplicado('IMEI 1 e IMEI 2 no pueden ser el mismo valor.');
      }

      final coincidencias = await _inventarioRepository.listarTelefonosPorImei(campoImei2.valor!);
      if (coincidencias.any((t) => t.unidadId != unidadId)) {
        return CorregirIdentidadUnidadImeiDuplicado('El IMEI 2 ya está registrado en otro equipo.');
      }
    }

    try {
      final actualizada = await _inventarioRepository.corregirIdentidadUnidad(
        unidadId: unidadId,
        motivo: motivoLimpio,
        numeroSerie: serie.tocar ? serie.valor : null,
        marca: campoMarca.tocar ? campoMarca.valor : null,
        limpiarMarca: campoMarca.tocar && campoMarca.valor == null,
        modelo: campoModelo.tocar ? campoModelo.valor : null,
        limpiarModelo: campoModelo.tocar && campoModelo.valor == null,
        imei: campoImei.tocar ? campoImei.valor : null,
        limpiarImei: campoImei.tocar && campoImei.valor == null,
        imei2: campoImei2.tocar ? campoImei2.valor : null,
        limpiarImei2: campoImei2.tocar && campoImei2.valor == null,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirIdentidadUnidadExitoso(actualizada);
    } catch (e) {
      return CorregirIdentidadUnidadErrorInesperado(e.toString());
    }
  }
}
