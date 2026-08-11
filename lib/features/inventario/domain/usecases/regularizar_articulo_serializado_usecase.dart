import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/inventario_repository.dart';

/// Datos capturados por el usuario para cada unidad nueva — nunca un
/// número de serie inventado, siempre el real del dispositivo (mismo
/// requisito que `RegistrarEntradaUnidadUseCase`).
class DatosUnidadRegularizacionInput {
  const DatosUnidadRegularizacionInput({
    required this.numeroSerie,
    this.marca,
    this.modelo,
    this.imei,
    this.imei2,
  });

  final String numeroSerie;
  final String? marca;
  final String? modelo;
  final String? imei;
  final String? imei2;
}

sealed class RegularizarArticuloSerializadoResultado {}

class RegularizarArticuloSerializadoExitoso extends RegularizarArticuloSerializadoResultado {
  RegularizarArticuloSerializadoExitoso(this.unidades);
  final List<ArticuloUnidadData> unidades;
}

class RegularizarArticuloSerializadoArticuloNoExiste extends RegularizarArticuloSerializadoResultado {}

/// El Artículo ya está correctamente configurado — no aplica
/// regularización (esto no es un error de datos, es que no hay nada
/// que corregir).
class RegularizarArticuloSerializadoArticuloYaManejaSerie extends RegularizarArticuloSerializadoResultado {}

/// Fuera de alcance deliberado (Etapa 9D, punto 3.5 del plan aprobado)
/// — un Artículo con variante complica la regularización sin un caso
/// real que lo requiera todavía.
class RegularizarArticuloSerializadoArticuloManejaVariante extends RegularizarArticuloSerializadoResultado {}

class RegularizarArticuloSerializadoMovimientoNoExiste extends RegularizarArticuloSerializadoResultado {}

/// El movimiento elegido no es un `entrada` por cantidad de este
/// Artículo (ya es de una unidad, o es de otro tipo, o es de otro
/// Artículo).
class RegularizarArticuloSerializadoMovimientoNoElegible extends RegularizarArticuloSerializadoResultado {}

class RegularizarArticuloSerializadoCantidadNoCoincide extends RegularizarArticuloSerializadoResultado {}

class RegularizarArticuloSerializadoNumeroSerieRequerido extends RegularizarArticuloSerializadoResultado {}

class RegularizarArticuloSerializadoNumeroSerieDuplicado extends RegularizarArticuloSerializadoResultado {}

class RegularizarArticuloSerializadoErrorInesperado extends RegularizarArticuloSerializadoResultado {
  RegularizarArticuloSerializadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Regularización de existencia legacy (Etapa 9D, ajuste posterior) —
/// única vía controlada para corregir un Artículo que se dio de alta
/// sin marcar `manejaSerie` por error y ya tiene existencia real por
/// cantidad (caso real: "SMARTPHONE" comprado como COM-000001). Única
/// excepción a "`manejaSerie` nunca cambia después de creado" (7A) —
/// por eso es Maestro-only (ver el provider en `inventario_providers`),
/// no una operación operativa de uso diario.
///
/// Compone `ArticuloRepository` (flip de `manejaSerie`) e
/// `InventarioRepository` (división de unidades) — ambos dentro de la
/// misma transacción, incluyendo el re-ligado de `CompraPartidaMovimiento`
/// si el movimiento original venía de una Compra (ver el doc comment de
/// `InventarioRepository.regularizarUnidadesDesdeMovimiento`: el FK
/// `ON DELETE RESTRICT` de esa tabla hacia `MovimientoInventario` obliga
/// a que ambas escrituras ocurran atómicamente, no en dos pasos).
class RegularizarArticuloSerializadoUseCase {
  RegularizarArticuloSerializadoUseCase(
    this._articuloRepository,
    this._inventarioRepository,
    this._generarCodigo,
  );

  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegularizarArticuloSerializadoResultado> ejecutar({
    required String articuloId,
    required String movimientoInventarioId,
    required List<DatosUnidadRegularizacionInput> unidades,
  }) async {
    final articulo = await _articuloRepository.obtenerPorId(articuloId);
    if (articulo == null) return RegularizarArticuloSerializadoArticuloNoExiste();
    if (articulo.manejaSerie) return RegularizarArticuloSerializadoArticuloYaManejaSerie();
    if (articulo.manejaVariante) return RegularizarArticuloSerializadoArticuloManejaVariante();

    final movimiento = await _inventarioRepository.obtenerMovimientoPorId(movimientoInventarioId);
    if (movimiento == null) return RegularizarArticuloSerializadoMovimientoNoExiste();
    if (movimiento.articuloId != articuloId ||
        movimiento.tipoMovimiento != 'entrada' ||
        movimiento.unidadId != null ||
        movimiento.varianteId != null) {
      return RegularizarArticuloSerializadoMovimientoNoElegible();
    }

    if (unidades.length != movimiento.cantidad) {
      return RegularizarArticuloSerializadoCantidadNoCoincide();
    }

    final seriesVistas = <String>{};
    for (final datos in unidades) {
      final serie = datos.numeroSerie.trim();
      if (serie.isEmpty) return RegularizarArticuloSerializadoNumeroSerieRequerido();
      if (!seriesVistas.add(serie)) return RegularizarArticuloSerializadoNumeroSerieDuplicado();
    }

    try {
      final datosConCodigo = <DatosUnidadRegularizada>[];
      for (final datos in unidades) {
        final codigoResultado = await _generarCodigo.ejecutar('articulo_unidad');
        final String codigo;
        switch (codigoResultado) {
          case Ok<String>(value: final v):
            codigo = v;
          case Err<String>(failure: final f):
            return RegularizarArticuloSerializadoErrorInesperado(f.message);
        }
        datosConCodigo.add(DatosUnidadRegularizada(
          codigo: codigo,
          numeroSerie: datos.numeroSerie.trim(),
          marca: datos.marca?.trim().isEmpty ?? true ? null : datos.marca!.trim(),
          modelo: datos.modelo?.trim().isEmpty ?? true ? null : datos.modelo!.trim(),
          imei: datos.imei?.trim().isEmpty ?? true ? null : datos.imei!.trim(),
          imei2: datos.imei2?.trim().isEmpty ?? true ? null : datos.imei2!.trim(),
        ));
      }

      final unidadesCreadas = await _inventarioRepository.regularizarUnidadesDesdeMovimiento(
        articuloId: articuloId,
        movimientoInventarioId: movimientoInventarioId,
        unidades: datosConCodigo,
      );

      return RegularizarArticuloSerializadoExitoso(unidadesCreadas);
    } catch (e) {
      return RegularizarArticuloSerializadoErrorInesperado(e.toString());
    }
  }
}
