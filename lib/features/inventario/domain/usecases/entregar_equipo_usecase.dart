import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/asignacion_repository.dart';
import '../repositories/inventario_repository.dart';
import 'validar_linea_asignacion.dart';

sealed class EntregarEquipoResultado {}

class EntregarEquipoExitoso extends EntregarEquipoResultado {
  EntregarEquipoExitoso(this.entrega, this.asignaciones);
  final EntregaData entrega;
  final List<AsignacionData> asignaciones;
}

class EntregarEquipoSinLineas extends EntregarEquipoResultado {}

/// Ni `empleadoId` ni `servicioId` (o ambos) — exactamente uno de los
/// dos, mismo criterio que `CrearAsignacionDestinoInvalido`.
class EntregarEquipoDestinoInvalido extends EntregarEquipoResultado {}

/// Motivo por el que una línea puntual del carrito no pasó la
/// validación — mapea 1:1 a `ValidacionLineaAsignacion`
/// (`validar_linea_asignacion.dart`), con [sobrepasaDisponible]
/// llevando también la cantidad disponible real.
enum EntregarEquipoMotivoLinea {
  articuloNoExiste,
  cantidadInvalida,
  varianteInvalida,
  unidadInvalida,
  unidadNoDisponible,
  sobrepasaDisponible,
  unidadDuplicadaEnElCarrito,
}

/// Falla de una línea puntual del carrito — [indice] es 0-based, en el
/// mismo orden que [EntregarEquipoUseCase.ejecutar] recibió `lineas`.
/// Nunca un mensaje genérico: el operador necesita saber CUÁL de las N
/// líneas falló y por qué para poder corregirla sin adivinar.
class EntregarEquipoLineaInvalida extends EntregarEquipoResultado {
  EntregarEquipoLineaInvalida(this.indice, this.motivo, {this.disponible});
  final int indice;
  final EntregarEquipoMotivoLinea motivo;
  final int? disponible;
}

class EntregarEquipoErrorInesperado extends EntregarEquipoResultado {
  EntregarEquipoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Entrega múltiple de Inventario a un Empleado o Servicio en un solo
/// acto ("Entregar equipo") — genera una `Entrega` (cabecera
/// documental) más una `Asignacion` independiente por cada línea del
/// carrito, todo o nada. Reutiliza `validarLineaAsignacion` (mismas
/// reglas que `CrearAsignacionUseCase`, un solo lugar donde viven).
///
/// Toda la validación ocurre ANTES de abrir cualquier transacción — la
/// única forma en que "todo o nada" depende de un rollback real es una
/// condición de carrera genuina (p. ej. una unidad serializada que deja
/// de estar disponible entre esta validación y la escritura, o el
/// índice único `idx_asignacion_unidad_activa`); en ese caso
/// `AsignacionRepository.crearEntrega` revierte TODA la transacción
/// (Entrega incluida) por las garantías propias de Drift.
class EntregarEquipoUseCase {
  EntregarEquipoUseCase(
    this._asignacionRepository,
    this._articuloRepository,
    this._inventarioRepository,
    this._generarCodigo,
  );

  final AsignacionRepository _asignacionRepository;
  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;
  final GenerarCodigoUseCase _generarCodigo;

  /// [condicionEntrega]/[observaciones] son datos GENERALES de la
  /// Entrega (pedido: "puede heredarse el valor general a cada nueva
  /// Asignación") — se escriben tal cual en cada línea del lote, nunca
  /// se leen de [AsignacionLineaInput] (ese campo por-línea no se usa
  /// aquí; existe en el tipo solo porque lo comparte `crear`/`crearVarias`
  /// individuales).
  Future<EntregarEquipoResultado> ejecutar({
    required List<AsignacionLineaInput> lineas,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaEntrega,
    required String condicionEntrega,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    if (lineas.isEmpty) return EntregarEquipoSinLineas();

    final unoSoloDestino = (empleadoId != null) != (servicioId != null);
    if (!unoSoloDestino) return EntregarEquipoDestinoInvalido();

    // Ninguna unidad serializada repetida dentro del mismo carrito —
    // nunca confiar solo en que el diálogo ya la haya excluido de su
    // selector.
    final unidadesVistas = <String>{};
    for (var i = 0; i < lineas.length; i++) {
      final unidadId = lineas[i].unidadId;
      if (unidadId == null) continue;
      if (!unidadesVistas.add(unidadId)) {
        return EntregarEquipoLineaInvalida(i, EntregarEquipoMotivoLinea.unidadDuplicadaEnElCarrito);
      }
    }

    // Suma agregada por artículo+variante (líneas fungibles) antes de
    // comparar contra Disponible — dos líneas que individualmente
    // caben pero juntas exceden deben rechazarse.
    final comprometidoPorClave = <String, int>{};
    for (var i = 0; i < lineas.length; i++) {
      final linea = lineas[i];
      final esFungible = linea.unidadId == null;
      final clave = '${linea.articuloId}::${linea.varianteId}';
      final yaComprometido = esFungible ? (comprometidoPorClave[clave] ?? 0) : 0;

      final validacion = await validarLineaAsignacion(
        articuloRepository: _articuloRepository,
        inventarioRepository: _inventarioRepository,
        articuloId: linea.articuloId,
        varianteId: linea.varianteId,
        unidadId: linea.unidadId,
        cantidad: linea.cantidad,
        cantidadYaComprometidaEnLote: yaComprometido,
      );
      switch (validacion) {
        case LineaAsignacionValida():
          if (esFungible) comprometidoPorClave[clave] = yaComprometido + linea.cantidad;
        case LineaAsignacionArticuloNoExiste():
          return EntregarEquipoLineaInvalida(i, EntregarEquipoMotivoLinea.articuloNoExiste);
        case LineaAsignacionCantidadInvalida():
          return EntregarEquipoLineaInvalida(i, EntregarEquipoMotivoLinea.cantidadInvalida);
        case LineaAsignacionVarianteInvalida():
          return EntregarEquipoLineaInvalida(i, EntregarEquipoMotivoLinea.varianteInvalida);
        case LineaAsignacionUnidadInvalida():
          return EntregarEquipoLineaInvalida(i, EntregarEquipoMotivoLinea.unidadInvalida);
        case LineaAsignacionUnidadNoDisponible():
          return EntregarEquipoLineaInvalida(i, EntregarEquipoMotivoLinea.unidadNoDisponible);
        case LineaAsignacionSobrepasaDisponible(:final disponible):
          return EntregarEquipoLineaInvalida(i, EntregarEquipoMotivoLinea.sobrepasaDisponible, disponible: disponible);
      }
    }

    try {
      final folioResultado = await _generarCodigo.ejecutar('entrega');
      final String folio;
      switch (folioResultado) {
        case Ok<String>(value: final v):
          folio = v;
        case Err<String>(failure: final f):
          return EntregarEquipoErrorInesperado(f.message);
      }

      final lineasConCondicionGeneral = [
        for (final linea in lineas)
          AsignacionLineaInput(
            articuloId: linea.articuloId,
            varianteId: linea.varianteId,
            unidadId: linea.unidadId,
            cantidad: linea.cantidad,
            condicionEntrega: condicionEntrega,
            observaciones: observaciones,
          ),
      ];
      final creada = await _asignacionRepository.crearEntrega(
        folio: folio,
        lineas: lineasConCondicionGeneral,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaEntrega: fechaEntrega,
        actorUsuarioId: actorUsuarioId,
      );
      return EntregarEquipoExitoso(creada.entrega, creada.asignaciones);
    } catch (e) {
      return EntregarEquipoErrorInesperado(e.toString());
    }
  }
}
