import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;

import '../repositories/compra_repository.dart';

/// Motivo estructurado de cancelación de una Compra (Etapa 15) — nunca
/// texto libre obligatorio: el código se persiste tal cual (nombre del
/// enum) en `Compra.motivoCancelacionCodigo`, estable aunque cambie la
/// etiqueta traducida. `otro` es el único valor que exige `detalle`.
enum MotivoCancelacionCompra {
  errorDeCaptura,
  compraDePrueba,
  compraNoRealizada,
  compraDuplicada,
  compraDevueltaReembolsada,
  proveedorCancelo,
  cambioDeCompraOProveedor,
  otro,
}

/// Etiqueta traducida de cada [MotivoCancelacionCompra] — única fuente
/// de la conversión código→texto humano, usada tanto por la UI como
/// por `CompraRepositoryImpl.cancelar` (motivo del `Egreso` asociado,
/// que no tiene motivo estructurado propio).
extension MotivoCancelacionCompraLabel on MotivoCancelacionCompra {
  String get etiqueta => switch (this) {
        MotivoCancelacionCompra.errorDeCaptura => 'Error de captura',
        MotivoCancelacionCompra.compraDePrueba => 'Compra de prueba',
        MotivoCancelacionCompra.compraNoRealizada => 'Compra no realizada',
        MotivoCancelacionCompra.compraDuplicada => 'Compra duplicada',
        MotivoCancelacionCompra.compraDevueltaReembolsada => 'Compra devuelta / reembolsada',
        MotivoCancelacionCompra.proveedorCancelo => 'Proveedor canceló la operación',
        MotivoCancelacionCompra.cambioDeCompraOProveedor => 'Cambio de compra o proveedor',
        MotivoCancelacionCompra.otro => 'Otro',
      };
}

sealed class CancelarCompraResultado {}

class CancelarCompraExitosa extends CancelarCompraResultado {
  CancelarCompraExitosa(this.compra);
  final CompraData compra;
}

class CancelarCompraNoExiste extends CancelarCompraResultado {}

class CancelarCompraYaCancelada extends CancelarCompraResultado {}

/// `motivo == MotivoCancelacionCompra.otro` sin `detalle` capturado.
class CancelarCompraDetalleRequerido extends CancelarCompraResultado {}

/// Al menos una `ArticuloUnidad` generada por esta Compra ya no está
/// `disponible` (asignada/dañada/perdida/dada de baja) — revertir a
/// "nunca se compró esto" mezclaría ese hecho de negocio real con la
/// cancelación de la Compra, así que se bloquea. La UI debe listar
/// cada unidad conflictiva con su estatus, nunca un mensaje genérico
/// (mismo criterio que `DesactivarAreaBloqueadaPorPuestosActivos`,
/// llevado un paso más allá: aquí interesa el detalle, no solo el
/// conteo).
class CancelarCompraBloqueadaPorUnidadesNoDisponibles extends CancelarCompraResultado {
  CancelarCompraBloqueadaPorUnidadesNoDisponibles(this.unidades);
  final List<ArticuloUnidadData> unidades;
}

/// Equivalente a [CancelarCompraBloqueadaPorUnidadesNoDisponibles] para
/// partidas por CANTIDAD (artículo sin número de serie): al menos una
/// ya tiene alguna `Asignacion` registrada para su artículo/variante —
/// política conservadora, misma que ya usan `corregir()` y
/// `obtenerResumenEliminacionFisica` para el mismo caso (Resolución
/// explícita de Marlon, Etapa 15: nunca se adivina cuánta existencia
/// del conjunto fungible pertenece todavía a esta Compra específica;
/// cualquier asignación registrada bloquea, sin importar cuánta
/// existencia numérica quedaría disponible tras revertir). Antes de
/// este chequeo proactivo, este caso dejaba que
/// `InventarioRepository.registrarBaja` lanzara
/// `ExistenciaInsuficienteException` a medio camino de la reversión —
/// bug real reportado por Marlon (COM-000021).
class CancelarCompraBloqueadaPorArticulosConsumidos extends CancelarCompraResultado {
  CancelarCompraBloqueadaPorArticulosConsumidos(this.detalles);
  final List<String> detalles;
}

class CancelarCompraErrorInesperado extends CancelarCompraResultado {
  CancelarCompraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela una Compra completa (Etapa 10) — reversión estructurada,
/// nunca borrado: revierte cada entrada de Inventario que generó (una
/// `MovimientoInventario` nueva tipo `baja`/`registrarBajaUnidad` por
/// cada una, el `entrada` original queda intacto) y cancela su Egreso.
/// Antes de tocar nada, verifica que ninguna `ArticuloUnidad` generada
/// haya dejado de estar `disponible` **y** que ninguna partida por
/// cantidad tenga ya alguna `Asignacion` registrada para su
/// artículo/variante — mismo template de chequeo que `DesactivarAreaUseCase`
/// (contar/listar dependientes activos antes de mutar, no después):
/// con ambos chequeos pasados, la reversión real dentro de
/// `CompraRepositoryImpl.cancelar` nunca debería toparse con
/// existencia insuficiente; si aun así ocurriera (carrera real entre
/// dos operaciones concurrentes), la transacción de Drift revierte todo
/// automáticamente y el resultado sigue siendo `CancelarCompraErrorInesperado`
/// — nunca una cancelación a medias.
class CancelarCompraUseCase {
  CancelarCompraUseCase(this._compraRepository);

  final CompraRepository _compraRepository;

  Future<CancelarCompraResultado> ejecutar({
    required String compraId,
    required MotivoCancelacionCompra motivo,
    String? detalle,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final detalleLimpio = detalle?.trim();
    if (motivo == MotivoCancelacionCompra.otro && (detalleLimpio == null || detalleLimpio.isEmpty)) {
      return CancelarCompraDetalleRequerido();
    }

    final compra = await _compraRepository.obtenerPorId(compraId);
    if (compra == null) return CancelarCompraNoExiste();
    if (compra.estatus == 'cancelada') return CancelarCompraYaCancelada();

    final unidades = await _compraRepository.listarUnidadesGeneradas(compraId);
    final noDisponibles = unidades.where((u) => u.estatus != EstatusArticuloUnidad.disponible.name).toList();
    if (noDisponibles.isNotEmpty) {
      return CancelarCompraBloqueadaPorUnidadesNoDisponibles(noDisponibles);
    }

    final partidasConsumidas = await _compraRepository.listarDetalleBloqueoCancelacionPorCantidad(compraId);
    if (partidasConsumidas.isNotEmpty) {
      return CancelarCompraBloqueadaPorArticulosConsumidos(partidasConsumidas);
    }

    try {
      final cancelada = await _compraRepository.cancelar(
        compraId: compraId,
        motivo: motivo.name,
        detalle: detalleLimpio,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return CancelarCompraExitosa(cancelada);
    } catch (e) {
      return CancelarCompraErrorInesperado(e.toString());
    }
  }
}
