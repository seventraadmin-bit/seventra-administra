import '../repositories/compra_repository.dart';

/// Un cambio real sobre una `CompraPartida` ya existente, o una
/// operación de alta/baja de partida completa — la forma que recibe
/// `CompraRepository.corregir` (Etapa 15, ampliación de "Corregir
/// datos"). Nunca reescribe una partida a ciegas: cada variante
/// describe exactamente qué cambió, para que el repositorio pueda
/// reconciliar Inventario solo por lo que realmente cambió, nunca
/// recreando movimientos completos.
sealed class CorreccionPartida {}

/// Corrige cantidad y/o costo unitario de una partida existente, sin
/// cambiar artículo/variante. Para partidas serializadas, la cantidad
/// se ajusta explícitamente con [numerosSerieNuevos] (aumentar) y/o
/// [unidadesIdAEliminar] (disminuir) — nunca un delta implícito, porque
/// cada unidad serializada es una entidad real distinta.
class CorreccionPartidaCantidadCosto extends CorreccionPartida {
  CorreccionPartidaCantidadCosto({
    required this.compraPartidaId,
    this.nuevaCantidad,
    this.nuevoCostoUnitario,
    this.numerosSerieNuevos = const [],
    this.unidadesIdAEliminar = const [],
  });

  final String compraPartidaId;
  final int? nuevaCantidad;
  final int? nuevoCostoUnitario;
  final List<String> numerosSerieNuevos;
  final List<String> unidadesIdAEliminar;
}

/// Cambia el artículo y/o variante de una partida existente (ej.
/// CAMISOLA talla G → CH, o sustituir un artículo por otro
/// completamente distinto). Para partidas fungibles, revierte toda la
/// cantidad del artículo/variante anterior y registra la misma
/// cantidad en el nuevo. Para partidas serializadas, da de baja las
/// unidades existentes de la partida y da de alta unidades nuevas bajo
/// el artículo nuevo con [numerosSerieNuevos] — es la operación B
/// ("sustituir la unidad"), nunca una edición de la misma unidad.
class CorreccionPartidaVariante extends CorreccionPartida {
  CorreccionPartidaVariante({
    required this.compraPartidaId,
    required this.nuevoArticuloId,
    this.nuevaVarianteId,
    this.numerosSerieNuevos = const [],
    this.nuevaCantidad,
    this.nuevoCostoUnitario,
  });

  final String compraPartidaId;
  final String nuevoArticuloId;
  final String? nuevaVarianteId;
  final List<String> numerosSerieNuevos;

  /// Solo aplica a partidas fungibles (sin serie) — para serializadas,
  /// la cantidad final la determina `numerosSerieNuevos.length`.
  final int? nuevaCantidad;
  final int? nuevoCostoUnitario;
}

/// Agrega una partida omitida en el Alta original — mismo `PartidaCompraInput`
/// que usa `RegistrarCompraUseCase`, tratada exactamente igual (nueva
/// entrada de Inventario si aplica).
class CorreccionPartidaAgregar extends CorreccionPartida {
  CorreccionPartidaAgregar({required this.input});
  final PartidaCompraInput input;
}

/// Quita una partida capturada por error — bloqueada si tiene
/// dependencias reales (mismo criterio que la eliminación física).
class CorreccionPartidaQuitar extends CorreccionPartida {
  CorreccionPartidaQuitar({required this.compraPartidaId});
  final String compraPartidaId;
}

/// Resumen de solo lectura antes de aplicar una corrección de partidas
/// — la UI lo usa para mostrar el impacto real (nunca inventado) antes
/// de pedir confirmación. `detalleBloqueo` no nulo significa que al
/// menos uno de los cambios propuestos toca existencia ya consumida
/// (asignada, vinculada a telefonía, o con movimientos ajenos) — en ese
/// caso NINGÚN cambio se aplica (todo o nada).
class ResumenCorreccionCompra {
  const ResumenCorreccionCompra({
    required this.existe,
    this.detalleBloqueo,
    this.totalAnterior,
    this.totalNuevo,
  });

  final bool existe;
  final String? detalleBloqueo;
  final int? totalAnterior;
  final int? totalNuevo;

  bool get bloqueado => detalleBloqueo != null;
}
