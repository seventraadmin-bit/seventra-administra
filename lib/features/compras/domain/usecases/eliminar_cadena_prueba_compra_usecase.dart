import '../repositories/compra_repository.dart';

/// Motivo estructurado de "Eliminar cadena de prueba" (Etapa 15,
/// limpieza segura de datos de prueba, Maestro-only) — distinto de
/// [MotivoEliminacionFisicaCompra]: esta acción existe específicamente
/// para reconocer y limpiar cadenas COMPLETAS generadas durante
/// pruebas (Compra → Inventario → Asignación → devolución/daño/pérdida
/// → descuento), nunca para historia real de producción. Se persiste
/// el nombre estable del enum en `EliminacionFisicaEvento.motivoCodigo`,
/// nunca la etiqueta. `otro` es el único valor que exige `detalle`.
enum MotivoCadenaPruebaCompra {
  pruebaFuncional,
  pruebaDeIntegracion,
  registroCreadoParaDemostracion,
  errorDeCaptura,
  registroDuplicado,
  registroCreadoPorEquivocacion,
  otro,
}

extension MotivoCadenaPruebaCompraLabel on MotivoCadenaPruebaCompra {
  String get etiqueta => switch (this) {
        MotivoCadenaPruebaCompra.pruebaFuncional => 'Prueba funcional',
        MotivoCadenaPruebaCompra.pruebaDeIntegracion => 'Prueba de integración',
        MotivoCadenaPruebaCompra.registroCreadoParaDemostracion => 'Registro creado para demostración',
        MotivoCadenaPruebaCompra.errorDeCaptura => 'Error de captura',
        MotivoCadenaPruebaCompra.registroDuplicado => 'Registro duplicado',
        MotivoCadenaPruebaCompra.registroCreadoPorEquivocacion => 'Registro creado por equivocación',
        MotivoCadenaPruebaCompra.otro => 'Otro',
      };
}

/// Vista previa de solo lectura de "Eliminar cadena de prueba" (Etapa
/// 15) — muestra exactamente qué se borraría, ANTES de confirmar.
/// `detalleBloqueo` no nulo significa que algo en la cadena cruzó un
/// punto irreversible (ver el doc comment de
/// `CompraRepositoryImpl.eliminarCadenaPrueba`) — en ese caso NADA se
/// elimina, ni siquiera lo que sí sería seguro.
class ResumenCadenaPruebaCompra {
  const ResumenCadenaPruebaCompra({
    required this.existe,
    this.folioCompra,
    this.folioEgreso,
    this.montoEgreso,
    this.entradasInventario = 0,
    this.asignaciones = const [],
    this.movimientosDerivados = 0,
    this.descuentosPendientes = 0,
    this.totalDescuentosPendientes = 0,
    this.detalleBloqueo,
  });

  final bool existe;
  final String? folioCompra;
  final String? folioEgreso;
  final int? montoEgreso;
  final int entradasInventario;

  /// Una línea descriptiva por cada `Asignacion` que se eliminaría
  /// (ej. "PANTALON NEGRO COMANDO — SN-0001"), nunca solo un conteo.
  final List<String> asignaciones;

  /// Movimientos de devolución/daño/pérdida derivados de esas
  /// Asignaciones que también se eliminarían.
  final int movimientosDerivados;

  final int descuentosPendientes;
  final int totalDescuentosPendientes;

  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;

  int get totalRegistrosRelacionados =>
      entradasInventario + asignaciones.length + movimientosDerivados + descuentosPendientes;
}

sealed class EliminarCadenaPruebaCompraResultado {}

class EliminarCadenaPruebaCompraExitoso extends EliminarCadenaPruebaCompraResultado {}

class EliminarCadenaPruebaCompraNoExiste extends EliminarCadenaPruebaCompraResultado {}

/// `motivo == MotivoCadenaPruebaCompra.otro` sin `detalle` capturado.
class EliminarCadenaPruebaCompraDetalleRequerido extends EliminarCadenaPruebaCompraResultado {}

/// Algo en la cadena cruzó un punto irreversible — `detalle` siempre
/// nombra la razón real exacta, nunca un mensaje genérico. Nada se
/// elimina cuando ocurre esto (todo o nada).
class EliminarCadenaPruebaCompraTieneDependencias extends EliminarCadenaPruebaCompraResultado {
  EliminarCadenaPruebaCompraTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarCadenaPruebaCompraErrorInesperado extends EliminarCadenaPruebaCompraResultado {
  EliminarCadenaPruebaCompraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// "Eliminar cadena de prueba" (Etapa 15, limpieza segura de datos de
/// prueba) — exclusiva del Usuario Maestro (`exigirMaestro`, nunca
/// aquí). A diferencia de [EliminarCompraFisicamenteUseCase] (que
/// bloquea ante CUALQUIER historia posterior), esta acción SÍ elimina
/// las `Asignacion`/movimientos/`DescuentoInventario` derivados de la
/// Compra — pero únicamente cuando son atribuibles con exactitud (por
/// relación de IDs, nunca por artículo/empleado/fecha/importe) y
/// ninguno cruzó un punto irreversible. Ver el doc comment completo de
/// `CompraRepositoryImpl.eliminarCadenaPrueba` para los puntos
/// irreversibles exactos.
class EliminarCadenaPruebaCompraUseCase {
  EliminarCadenaPruebaCompraUseCase(this._repository);

  final CompraRepository _repository;

  Future<ResumenCadenaPruebaCompra> obtenerResumen(String compraId) {
    return _repository.obtenerResumenCadenaPrueba(compraId);
  }

  Future<EliminarCadenaPruebaCompraResultado> ejecutar({
    required String compraId,
    required MotivoCadenaPruebaCompra motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final detalleLimpio = detalle?.trim();
    if (motivo == MotivoCadenaPruebaCompra.otro && (detalleLimpio == null || detalleLimpio.isEmpty)) {
      return EliminarCadenaPruebaCompraDetalleRequerido();
    }

    try {
      return await _repository.eliminarCadenaPrueba(
        compraId: compraId,
        motivo: motivo.name,
        detalle: detalleLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarCadenaPruebaCompraErrorInesperado(e.toString());
    }
  }
}
