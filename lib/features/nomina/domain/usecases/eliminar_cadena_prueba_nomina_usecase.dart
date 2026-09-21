import '../repositories/nomina_repository.dart';

/// Motivo estructurado de "Eliminar cadena de prueba" para Nómina
/// (Etapa 15, ampliación de la limpieza segura de datos de prueba —
/// mismo concepto ya construido para Compra) — distinto de
/// [MotivoEliminacionFisicaNomina]: esta acción SÍ alcanza una Nómina
/// `cerrada`/`pagada` con su `PagoNomina`/`Egreso`, algo que la
/// eliminación física normal bloquea siempre. Se persiste el nombre
/// estable del enum en `EliminacionFisicaEvento.motivoCodigo`, nunca la
/// etiqueta. `otro` es el único valor que exige `detalle`.
enum MotivoCadenaPruebaNomina {
  nominaDePrueba,
  pagoDePrueba,
  errorDeCaptura,
  nominaDuplicada,
  pruebasDeDesarrollo,
  registroCreadoPorEquivocacion,
  otro,
}

extension MotivoCadenaPruebaNominaLabel on MotivoCadenaPruebaNomina {
  String get etiqueta => switch (this) {
        MotivoCadenaPruebaNomina.nominaDePrueba => 'Nómina de prueba',
        MotivoCadenaPruebaNomina.pagoDePrueba => 'Pago de prueba',
        MotivoCadenaPruebaNomina.errorDeCaptura => 'Error de captura',
        MotivoCadenaPruebaNomina.nominaDuplicada => 'Nómina duplicada',
        MotivoCadenaPruebaNomina.pruebasDeDesarrollo => 'Pruebas de desarrollo',
        MotivoCadenaPruebaNomina.registroCreadoPorEquivocacion => 'Registro creado por equivocación',
        MotivoCadenaPruebaNomina.otro => 'Otro',
      };
}

/// Un `PagoNomina` dentro de la cadena — vista previa de solo lectura,
/// nunca el detalle completo de `AplicacionPagoNomina`.
class PagoEnCadenaPruebaNomina {
  const PagoEnCadenaPruebaNomina({required this.folioPagoNomina, required this.montoTotal, this.folioEgreso});

  final String folioPagoNomina;
  final int montoTotal;
  final String? folioEgreso;
}

/// Vista previa de solo lectura de "Eliminar cadena de prueba" (Etapa
/// 15) — muestra exactamente qué se borraría/revertiría, ANTES de
/// confirmar. `detalleBloqueo` no nulo significa que algo en la cadena
/// cruzó un punto irreversible real — en ese caso NADA se elimina.
class ResumenCadenaPruebaNomina {
  const ResumenCadenaPruebaNomina({
    required this.existe,
    this.folioNomina,
    this.estatus,
    this.totalEmpleados = 0,
    this.totalAPagar = 0,
    this.pagos = const [],
    this.descuentosInventarioAplicados = 0,
    this.totalDescuentosInventarioAplicados = 0,
    this.detalleBloqueo,
  });

  final bool existe;
  final String? folioNomina;
  final String? estatus;
  final int totalEmpleados;
  final int totalAPagar;
  final List<PagoEnCadenaPruebaNomina> pagos;

  /// `DescuentoInventario` que esta Nómina aplicó — se revierten a
  /// `pendiente` (NUNCA se eliminan) como parte de la limpieza.
  final int descuentosInventarioAplicados;
  final int totalDescuentosInventarioAplicados;

  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarCadenaPruebaNominaResultado {}

class EliminarCadenaPruebaNominaExitoso extends EliminarCadenaPruebaNominaResultado {}

class EliminarCadenaPruebaNominaNoExiste extends EliminarCadenaPruebaNominaResultado {}

/// `motivo == MotivoCadenaPruebaNomina.otro` sin `detalle` capturado.
class EliminarCadenaPruebaNominaDetalleRequerido extends EliminarCadenaPruebaNominaResultado {}

/// Algo en la cadena cruzó un punto irreversible — `detalle` siempre
/// nombra la razón real exacta. Nada se elimina cuando ocurre esto.
class EliminarCadenaPruebaNominaTieneDependencias extends EliminarCadenaPruebaNominaResultado {
  EliminarCadenaPruebaNominaTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarCadenaPruebaNominaErrorInesperado extends EliminarCadenaPruebaNominaResultado {
  EliminarCadenaPruebaNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// "Eliminar cadena de prueba" para Nómina (Etapa 15) — exclusiva del
/// Usuario Maestro (`exigirMaestro`, nunca aquí). A diferencia de
/// [EliminarNominaFisicamenteUseCase] (que bloquea ante CUALQUIER
/// Nómina que no sea Borrador o que ya tenga un `PagoNomina`), esta
/// acción SÍ elimina una Nómina `cerrada`/`pagada` junto con TODOS sus
/// `PagoNomina`/`Egreso` — pero únicamente por relación de IDs exacta
/// (nunca por coincidencia de empleado/fecha/importe/periodo) y solo
/// cuando nada cruzó un punto irreversible real. Ver el doc comment
/// completo de `NominaRepositoryImpl.eliminarCadenaPrueba` para los
/// puntos irreversibles exactos investigados.
class EliminarCadenaPruebaNominaUseCase {
  EliminarCadenaPruebaNominaUseCase(this._repository);

  final NominaRepository _repository;

  Future<ResumenCadenaPruebaNomina> obtenerResumen(String nominaId) {
    return _repository.obtenerResumenCadenaPrueba(nominaId);
  }

  Future<EliminarCadenaPruebaNominaResultado> ejecutar({
    required String nominaId,
    required MotivoCadenaPruebaNomina motivo,
    String? detalle,
    String? actorUsuarioId,
  }) async {
    final detalleLimpio = detalle?.trim();
    if (motivo == MotivoCadenaPruebaNomina.otro && (detalleLimpio == null || detalleLimpio.isEmpty)) {
      return EliminarCadenaPruebaNominaDetalleRequerido();
    }

    try {
      return await _repository.eliminarCadenaPrueba(
        nominaId: nominaId,
        motivo: motivo.name,
        detalle: detalleLimpio,
        actorUsuarioId: actorUsuarioId,
      );
    } catch (e) {
      return EliminarCadenaPruebaNominaErrorInesperado(e.toString());
    }
  }
}
