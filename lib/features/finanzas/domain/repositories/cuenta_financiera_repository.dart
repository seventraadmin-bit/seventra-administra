import 'package:riseg_one/core/database/app_database.dart';

/// Un movimiento (Ingreso o Egreso) ya vinculado a una `CuentaFinanciera`
/// — vista de solo lectura para el historial del expediente (Etapa
/// 19C). `saldoAcumulado` se calcula siempre en memoria, ordenando por
/// fecha desde `saldoInicial` — nunca se persiste un saldo intermedio.
typedef MovimientoCuentaFinanciera = ({
  DateTime fecha,
  String concepto,
  String referencia,
  int entrada,
  int salida,
  bool esIngreso,
  String origenId,
});

/// Resumen de solo lectura para el mensaje de confirmación dinámico de
/// "Eliminar físicamente" — mismo criterio que `ResumenEliminacionDeuda`.
/// A diferencia de Deuda, una `CuentaFinanciera` SÍ puede tener un
/// bloqueo real: cualquier `Ingreso`/`Egreso` ya vinculado (pedido
/// explícito: "una Cuenta Financiera con movimientos históricos no debe
/// eliminarse físicamente de forma normal").
class ResumenEliminacionCuentaFinanciera {
  const ResumenEliminacionCuentaFinanciera({required this.existe, this.detalleBloqueo});

  final bool existe;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarCuentaFinancieraFisicamenteResultado {}

class EliminarCuentaFinancieraFisicamenteExitoso extends EliminarCuentaFinancieraFisicamenteResultado {}

class EliminarCuentaFinancieraFisicamenteNoExiste extends EliminarCuentaFinancieraFisicamenteResultado {}

class EliminarCuentaFinancieraFisicamenteTieneDependencias extends EliminarCuentaFinancieraFisicamenteResultado {
  EliminarCuentaFinancieraFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarCuentaFinancieraFisicamenteErrorInesperado extends EliminarCuentaFinancieraFisicamenteResultado {
  EliminarCuentaFinancieraFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Fuente real de dinero de la empresa (Etapa 19C) — ver el doc
/// comment de la tabla `CuentaFinanciera` para el criterio completo de
/// diseño (saldo siempre derivado, nunca persistido).
abstract interface class CuentaFinancieraRepository {
  Future<CuentaFinancieraData?> obtenerPorId(String id);

  /// `soloActivas` filtra por `cicloVidaRegistro == activo` — el
  /// selector de los formularios de captura (Parte C del pedido) usa
  /// esto exclusivamente, nunca lista cuentas desactivadas ahí.
  Future<List<CuentaFinancieraData>> listar({bool soloActivas = false});

  /// Saldo derivado de una sola cuenta: `saldoInicial + SUM(Ingreso) -
  /// SUM(Egreso)`, solo movimientos con `fecha >= fechaSaldoInicial`.
  Future<int> calcularSaldo(String cuentaId);

  /// Igual que [calcularSaldo], resuelto para varias cuentas a la vez
  /// en dos consultas agregadas (una para Ingreso, una para Egreso) —
  /// evita N+1 en "Posición por cuenta".
  Future<Map<String, int>> calcularSaldos(Iterable<String> cuentaIds);

  /// Ingreso + Egreso vinculados a esta cuenta, unificados y
  /// ordenados por fecha ascendente — el saldo acumulado se calcula en
  /// el llamador (presentación), nunca aquí, para no acoplar la
  /// consulta a un orden de presentación fijo.
  Future<List<MovimientoCuentaFinanciera>> listarMovimientos(String cuentaId);

  /// [codigo] se genera antes de llamar aquí (mismo criterio que
  /// `CompraRepository.crear` recibe `folioCompra` ya generado) —
  /// nunca capturado a mano por el usuario.
  Future<CuentaFinancieraData> crear({
    required String codigo,
    required String nombre,
    required String tipo,
    String? institucionId,
    String? ultimosDigitos,
    required int saldoInicial,
    required DateTime fechaSaldoInicial,
    String? observaciones,
  });

  /// Metadata pura — nunca `tipo`/`saldoInicial`/`fechaSaldoInicial`
  /// una vez que la cuenta ya tiene movimientos reales asociados (el
  /// use case valida esto antes de llamar aquí, mismo criterio que
  /// `Deuda.importeOriginal`).
  Future<CuentaFinancieraData> corregir({
    required String cuentaId,
    String? nombre,
    String? institucionId,
    bool limpiarInstitucionId = false,
    String? ultimosDigitos,
    bool limpiarUltimosDigitos = false,
    String? observaciones,
  });

  Future<CuentaFinancieraData> activar(String cuentaId);

  Future<CuentaFinancieraData> desactivar(String cuentaId);

  Future<ResumenEliminacionCuentaFinanciera> obtenerResumenEliminacionFisica(String cuentaId);

  Future<EliminarCuentaFinancieraFisicamenteResultado> eliminarFisicamente({
    required String cuentaId,
    required String motivo,
    String? actorUsuarioId,
  });
}
