import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;

import '../repositories/compra_repository.dart';

sealed class CancelarCompraResultado {}

class CancelarCompraExitosa extends CancelarCompraResultado {
  CancelarCompraExitosa(this.compra);
  final CompraData compra;
}

class CancelarCompraNoExiste extends CancelarCompraResultado {}

class CancelarCompraYaCancelada extends CancelarCompraResultado {}

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

class CancelarCompraErrorInesperado extends CancelarCompraResultado {
  CancelarCompraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela una Compra completa (Etapa 10) — reversión estructurada,
/// nunca borrado: revierte cada entrada de Inventario que generó (una
/// `MovimientoInventario` nueva tipo `baja`/`registrarBajaUnidad` por
/// cada una, el `entrada` original queda intacto) y cancela su Egreso.
/// Antes de tocar nada, verifica que ninguna `ArticuloUnidad` generada
/// haya dejado de estar `disponible` — mismo template de chequeo que
/// `DesactivarAreaUseCase` (contar/listar dependientes activos antes
/// de mutar, no después).
class CancelarCompraUseCase {
  CancelarCompraUseCase(this._compraRepository);

  final CompraRepository _compraRepository;

  Future<CancelarCompraResultado> ejecutar({
    required String compraId,
    required String motivo,
    String? actor,
  }) async {
    final compra = await _compraRepository.obtenerPorId(compraId);
    if (compra == null) return CancelarCompraNoExiste();
    if (compra.estatus == 'cancelada') return CancelarCompraYaCancelada();

    final unidades = await _compraRepository.listarUnidadesGeneradas(compraId);
    final noDisponibles = unidades.where((u) => u.estatus != EstatusArticuloUnidad.disponible.name).toList();
    if (noDisponibles.isNotEmpty) {
      return CancelarCompraBloqueadaPorUnidadesNoDisponibles(noDisponibles);
    }

    try {
      final cancelada = await _compraRepository.cancelar(compraId: compraId, motivo: motivo, actor: actor);
      return CancelarCompraExitosa(cancelada);
    } catch (e) {
      return CancelarCompraErrorInesperado(e.toString());
    }
  }
}
