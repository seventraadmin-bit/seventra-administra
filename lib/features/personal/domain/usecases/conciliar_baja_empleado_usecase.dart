import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/vehiculos/data/tables/asignacion_vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/asignacion_vehiculo_repository.dart';

import '../../data/tables/conciliacion_baja_table.dart';
import '../../data/tables/empleado_table.dart';
import '../repositories/conciliacion_baja_repository.dart';
import '../repositories/empleado_repository.dart';
import 'registrar_baja_laboral_usecase.dart';

/// Lo que el usuario decidió para UN bien, tal como lo capturó el
/// formulario de baja. Objeto plano de entrada: ninguna decisión se
/// infiere y ninguna se rellena sola.
class ResolucionResguardo {
  const ResolucionResguardo({
    this.asignacionId,
    this.asignacionVehiculoId,
    required this.resolucion,
    this.condicion,
    this.destino,
    this.motivoNoEntrega,
    this.motivoNoEntregaOtro,
    this.fechaCompromiso,
    this.autorizadorEmpleadoId,
    this.receptorEmpleadoId,
    this.nuevoResponsableEmpleadoId,
    this.costoLimpieza,
    this.responsableCostoLimpieza,
    this.generaDescuento = false,
    this.importeDescuento,
    this.conceptoDescuento,
    this.numeroCuotasDescuento = 1,
    this.motivoNoCobro,
    this.lugarEntrega,
    this.combustible,
    this.kilometraje,
    this.danos,
    this.observaciones,
  });

  final String? asignacionId;
  final String? asignacionVehiculoId;
  final ResolucionResguardoBaja resolucion;
  final CondicionDevolucionResguardo? condicion;
  final DestinoDevolucionResguardo? destino;
  final MotivoNoEntregaResguardo? motivoNoEntrega;
  final String? motivoNoEntregaOtro;
  final DateTime? fechaCompromiso;
  final String? autorizadorEmpleadoId;
  final String? receptorEmpleadoId;
  final String? nuevoResponsableEmpleadoId;
  final int? costoLimpieza;
  final ResponsableCostoResguardo? responsableCostoLimpieza;

  /// Decisión explícita de cobrar o no. `false` con un costo real
  /// exige [motivoNoCobro] + [autorizadorEmpleadoId] — no existe un
  /// "No" barato que haga desaparecer la responsabilidad.
  final bool generaDescuento;

  /// Puede diferir del valor del artículo: la dirección decide cuánto
  /// recuperar (§21).
  final int? importeDescuento;
  final String? conceptoDescuento;
  final int numeroCuotasDescuento;
  final String? motivoNoCobro;

  final String? lugarEntrega;
  final String? combustible;
  final int? kilometraje;
  final String? danos;
  final String? observaciones;

  bool get esVehiculo => asignacionVehiculoId != null;
}

sealed class ConciliarBajaEmpleadoResultado {}

class ConciliarBajaEmpleadoExitoso extends ConciliarBajaEmpleadoResultado {
  ConciliarBajaEmpleadoExitoso({required this.empleado, required this.conciliacionId, required this.descuentosCreados});
  final EmpleadoData empleado;
  final String conciliacionId;

  /// Ids de `DescuentoProgramadoEmpleado` creados — obligaciones reales,
  /// consumibles por Nómina como cualquier otra.
  final List<String> descuentosCreados;
}

class ConciliarBajaEmpleadoBajaRechazada extends ConciliarBajaEmpleadoResultado {
  ConciliarBajaEmpleadoBajaRechazada(this.resultado);
  final RegistrarBajaLaboralResultado resultado;
}

/// Quedó al menos un bien vigente sin resolución — la baja NO se ejecuta.
class ConciliarBajaEmpleadoResguardosSinResolver extends ConciliarBajaEmpleadoResultado {
  ConciliarBajaEmpleadoResguardosSinResolver(this.asignacionIds, this.asignacionVehiculoIds);
  final List<String> asignacionIds;
  final List<String> asignacionVehiculoIds;
}

class ConciliarBajaEmpleadoResolucionInvalida extends ConciliarBajaEmpleadoResultado {
  ConciliarBajaEmpleadoResolucionInvalida(this.detalle);
  final String detalle;
}

class ConciliarBajaEmpleadoAutorizadorInvalido extends ConciliarBajaEmpleadoResultado {
  ConciliarBajaEmpleadoAutorizadorInvalido(this.empleadoId);
  final String empleadoId;
}

class ConciliarBajaEmpleadoErrorInesperado extends ConciliarBajaEmpleadoResultado {
  ConciliarBajaEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Baja laboral CON conciliación obligatoria de resguardos
/// (schemaVersion 83).
///
/// **Qué cambió respecto de la v82.** Antes, dar de baja marcaba todos
/// los bienes como pendientes automáticamente. Protegía la integridad
/// pero creaba un limbo: nadie documentaba qué había pasado. Ahora cada
/// bien vigente exige una resolución explícita, y
/// `pendienteRecuperacionDesde` se marca **solo** cuando alguien declara
/// que el bien sigue con la persona.
///
/// **Lo obligatorio es saber qué pasó, no haber recuperado todo** (§16):
/// la baja se confirma con bienes perdidos, no entregados o pendientes —
/// lo que no se permite es dejar uno sin explicar.
///
/// **Una sola operación de negocio** (§17): baja laboral + cierre de
/// Servicio + cierre de Línea + resoluciones físicas + movimientos de
/// Inventario + resolución de Vehículo + creación de descuentos, todo
/// dentro de la transacción que ya abre `registrarBajaLaboral`. Si algo
/// falla, no queda empleado de baja con inventario a medias.
///
/// **Reutiliza los mecanismos existentes, no los reescribe**: el cierre
/// de asignaciones es el de Inventario/Vehículos con sus propios
/// movimientos; las obligaciones son `DescuentoProgramadoEmpleado` vía
/// su use case oficial; la transferencia usa `cambiarResponsable`, que
/// ya existía justo para no fingir una devolución.
class ConciliarBajaEmpleadoUseCase {
  ConciliarBajaEmpleadoUseCase(
    this._empleadoRepository,
    this._registrarBaja,
    this._asignacionRepository,
    this._asignacionVehiculoRepository,
    this._conciliacionRepository,
    this._registrarDescuento,
  );

  final EmpleadoRepository _empleadoRepository;
  final RegistrarBajaLaboralUseCase _registrarBaja;
  final AsignacionRepository _asignacionRepository;
  final AsignacionVehiculoRepository _asignacionVehiculoRepository;
  final ConciliacionBajaRepository _conciliacionRepository;
  final RegistrarDescuentoProgramadoUseCase _registrarDescuento;

  Future<ConciliarBajaEmpleadoResultado> ejecutar({
    required String empleadoId,
    required DateTime fechaBaja,
    required MotivoBajaEmpleado motivo,
    String? observaciones,
    required List<ResolucionResguardo> resoluciones,
    String? actorUsuarioId,
  }) async {
    // 1. Lo que la persona tiene HOY, por FK — nunca se le pide al
    //    usuario recordarlo (§2).
    final asignaciones = await _asignacionRepository.listarActivasPorEmpleado(empleadoId);
    final vehiculos = await _asignacionVehiculoRepository.listarActivasPorEmpleado(empleadoId);

    // 2. Bloqueo condicional (§16): ni un bien sin resolución.
    final resueltasInventario = resoluciones.map((r) => r.asignacionId).whereType<String>().toSet();
    final resueltasVehiculo = resoluciones.map((r) => r.asignacionVehiculoId).whereType<String>().toSet();
    final faltanInventario = asignaciones.map((a) => a.id).where((id) => !resueltasInventario.contains(id)).toList();
    final faltanVehiculo = vehiculos.map((a) => a.id).where((id) => !resueltasVehiculo.contains(id)).toList();
    if (faltanInventario.isNotEmpty || faltanVehiculo.isNotEmpty) {
      return ConciliarBajaEmpleadoResguardosSinResolver(faltanInventario, faltanVehiculo);
    }

    // 3. Validación de cada resolución, ANTES de tocar nada.
    for (final r in resoluciones) {
      final invalida = _validar(r);
      if (invalida != null) return ConciliarBajaEmpleadoResolucionInvalida(invalida);
    }

    // 4. Los autorizadores/receptores deben ser personal ADMINISTRATIVO
    //    ACTIVO, resuelto por FK contra la clasificación real (§9/§14).
    for (final r in resoluciones) {
      for (final id in [r.autorizadorEmpleadoId, r.receptorEmpleadoId]) {
        if (id == null) continue;
        if (!await _esAdministrativoActivo(id)) return ConciliarBajaEmpleadoAutorizadorInvalido(id);
      }
    }

    // 5. TODO lo que sigue va en UNA transacción (§17): baja laboral,
    //    cierres, movimientos de inventario y descuentos. Si algo falla
    //    a la mitad, no queda el empleado de baja con el inventario a
    //    medias ni un descuento huérfano.
    try {
      return await _conciliacionRepository.enTransaccion(() async {
        return await _ejecutarConciliacion(
          empleadoId: empleadoId,
          fechaBaja: fechaBaja,
          motivo: motivo,
          observaciones: observaciones,
          resoluciones: resoluciones,
          actorUsuarioId: actorUsuarioId,
        );
      });
    } on _BajaRechazada catch (e) {
      // La baja la rechazó su propio dominio (fecha inválida, ya de
      // baja). Se propaga como excepción a propósito: es la única
      // forma de abortar la transacción y dejar CERO rastro de las
      // resoluciones que ya se habían aplicado.
      return ConciliarBajaEmpleadoBajaRechazada(e.resultado);
    } catch (e) {
      return ConciliarBajaEmpleadoErrorInesperado(e.toString());
    }
  }

  Future<ConciliarBajaEmpleadoResultado> _ejecutarConciliacion({
    required String empleadoId,
    required DateTime fechaBaja,
    required MotivoBajaEmpleado motivo,
    String? observaciones,
    required List<ResolucionResguardo> resoluciones,
    String? actorUsuarioId,
  }) async {
    final conciliacionId = await _conciliacionRepository.crear(
      empleadoId: empleadoId,
      fechaBaja: fechaBaja,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );

    // Las resoluciones y sus obligaciones van ANTES de marcar la baja,
    // dentro de la misma transacción. No es un detalle cosmético:
    // RegistrarDescuentoProgramadoUseCase rechaza —con razón— crear
    // una obligación para un empleado que ya figura de baja. Como todo
    // ocurre en una sola transacción, el orden interno no cambia el
    // estado final observable, y así se respeta esa regla del dominio
    // de Descuentos en vez de relajarla.
    final descuentosCreados = <String>[];
    for (final r in resoluciones) {
      final descuentoId = await _aplicar(
        resolucion: r,
        empleadoId: empleadoId,
        fechaBaja: fechaBaja,
        actorUsuarioId: actorUsuarioId,
      );
      if (descuentoId != null) descuentosCreados.add(descuentoId);

      await _conciliacionRepository.agregarRenglon(
        conciliacionBajaId: conciliacionId,
        resolucion: r,
        descuentoProgramadoId: descuentoId,
      );
    }

    final baja = await _registrarBaja.ejecutar(
      empleadoId: empleadoId,
      fechaBaja: fechaBaja,
      motivo: motivo,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
    if (baja is! RegistrarBajaLaboralExitoso) throw _BajaRechazada(baja);

    return ConciliarBajaEmpleadoExitoso(
      empleado: baja.empleado,
      conciliacionId: conciliacionId,
      descuentosCreados: descuentosCreados,
    );
  }

  /// Reglas de captura — cada una existe porque su ausencia dejaría un
  /// hecho sin explicar.
  String? _validar(ResolucionResguardo r) {
    if ((r.asignacionId == null) == (r.asignacionVehiculoId == null)) {
      return 'Cada resolución apunta exactamente a una asignación.';
    }
    if (r.esVehiculo && !r.resolucion.aplicaAVehiculo) {
      return 'La resolución ${r.resolucion.name} no aplica a un vehículo.';
    }

    if (r.resolucion.exigeCondicionYDestino && (r.condicion == null || r.destino == null)) {
      // Un vehículo entregado no pasa por el catálogo de destinos de
      // Inventario: su "destino" es volver a la flotilla.
      if (!r.esVehiculo) return 'Un bien devuelto exige condición y destino.';
      if (r.condicion == null) return 'Un vehículo entregado exige condición.';
    }
    if (r.resolucion.exigeMotivoNoEntrega && r.motivoNoEntrega == null) {
      return 'Un bien no entregado exige motivo.';
    }
    if (r.motivoNoEntrega != null) {
      final motivo = r.motivoNoEntrega!;
      if (motivo.requiereTexto && (r.motivoNoEntregaOtro?.trim().isEmpty ?? true)) {
        return 'El motivo "otro" exige explicación.';
      }
      if (motivo.exigeAutorizacion && r.autorizadorEmpleadoId == null) {
        return 'Renunciar a recuperar un bien exige un autorizador administrativo.';
      }
    }
    if (r.resolucion.exigeNuevoResponsable && r.nuevoResponsableEmpleadoId == null) {
      return 'Una transferencia exige el nuevo responsable.';
    }

    // §6 — limpieza a cargo del trabajador.
    if (r.costoLimpieza != null && r.responsableCostoLimpieza == null) {
      return 'Un costo de limpieza exige decir quién lo absorbe.';
    }

    // §10/§11 — la decisión económica nunca queda muda.
    if (r.generaDescuento) {
      if (r.importeDescuento == null || r.importeDescuento! <= 0) return 'Un descuento exige importe.';
      if (r.numeroCuotasDescuento < 1) return 'Un descuento exige al menos una cuota.';
    } else if (_generaCosto(r)) {
      if (r.motivoNoCobro?.trim().isEmpty ?? true) {
        return 'Decidir no cobrar un bien o costo recuperable exige motivo.';
      }
      if (r.autorizadorEmpleadoId == null) {
        return 'Decidir no cobrar exige un autorizador administrativo.';
      }
    }
    return null;
  }

  /// ¿Esta resolución implica un costo que RISEG podría recuperar? Si
  /// sí y se decide no cobrar, hace falta justificación + autorizador.
  bool _generaCosto(ResolucionResguardo r) {
    if (r.costoLimpieza != null && r.responsableCostoLimpieza == ResponsableCostoResguardo.trabajador) return true;
    if (r.resolucion == ResolucionResguardoBaja.perdido) return true;
    if (r.condicion == CondicionDevolucionResguardo.danado) return true;
    if (r.resolucion == ResolucionResguardoBaja.noEntregado) {
      final motivo = r.motivoNoEntrega;
      // Si RISEG autorizó explícitamente no recuperarlo, la decisión ya
      // quedó justificada y con firma: no se exige dos veces.
      return motivo != null && !motivo.exigeAutorizacion;
    }
    return false;
  }

  Future<bool> _esAdministrativoActivo(String empleadoId) async {
    final empleado = await _empleadoRepository.obtenerPorId(empleadoId);
    if (empleado == null) return false;
    if (EstatusEmpleado.values.byName(empleado.estatus) != EstatusEmpleado.activo) return false;
    final clasificacion = await _empleadoRepository.clasificar(empleadoId);
    return clasificacion?.esAdministrativo ?? false;
  }

  /// Traduce una resolución a las operaciones REALES de cada dominio.
  /// Devuelve el id del descuento creado, si lo hubo.
  Future<String?> _aplicar({
    required ResolucionResguardo resolucion,
    required String empleadoId,
    required DateTime fechaBaja,
    String? actorUsuarioId,
  }) async {
    final r = resolucion;

    if (r.esVehiculo) {
      switch (r.resolucion) {
        case ResolucionResguardoBaja.devuelto:
          // Entrega real: el ciclo que ya existe deja el vehículo
          // disponible y registra el kilometraje de devolución.
          await _asignacionVehiculoRepository.cerrar(
            asignacionVehiculoId: r.asignacionVehiculoId!,
            fechaTermino: fechaBaja,
            motivoTermino: MotivoTerminoAsignacionVehiculo.liberacion.name,
            observacionesTermino: r.observaciones,
            kilometrajeDevolucion: r.kilometraje,
            actorUsuarioId: actorUsuarioId,
          );
        case ResolucionResguardoBaja.noEntregado:
        case ResolucionResguardoBaja.perdido:
          // NO se cierra: el vehículo sigue con la persona, así que no
          // puede quedar disponible ni reasignarse.
          if (r.motivoNoEntrega?.dejaPendiente ?? true) {
            await _asignacionVehiculoRepository.marcarPendientesPorBajaEmpleado(
              empleadoId: empleadoId,
              fecha: fechaBaja,
              actorUsuarioId: actorUsuarioId,
            );
          }
        case ResolucionResguardoBaja.transferido:
          await _asignacionVehiculoRepository.cambiarResponsable(
            asignacionVehiculoActualId: r.asignacionVehiculoId!,
            fecha: fechaBaja,
            nuevoEmpleadoId: r.nuevoResponsableEmpleadoId,
            observacionesNueva: r.observaciones,
            actorUsuarioId: actorUsuarioId,
          );
        case ResolucionResguardoBaja.desecho:
          break;
      }
      return _crearDescuentoSiAplica(r, empleadoId, fechaBaja, actorUsuarioId, null);
    }

    switch (r.resolucion) {
      case ResolucionResguardoBaja.devuelto:
        // El bien SÍ volvió a RISEG — siempre se cierra como devolución
        // y entra al ledger con su `entradaDevolucion`. Lo que el
        // destino decide es DÓNDE queda: en el anaquel, en la
        // tintorería, en el taller o esperando desecho.
        //
        // Esto es lo que antes estaba mal: una prenda enviada a
        // lavandería quedaba `disponible`, ofrecida para reasignar
        // mientras seguía fuera.
        await _asignacionRepository.cerrar(
          asignacionId: r.asignacionId!,
          motivo: MotivoCierreAsignacion.bajaEmpleado.name,
          fechaCierre: fechaBaja,
          ubicacionUnidad: r.destino?.ubicacion,
          observacionesCierre: r.observaciones,
          actorUsuarioId: actorUsuarioId,
        );
      case ResolucionResguardoBaja.desecho:
        // Volvió, pero inservible: sale de disponibilidad y espera que
        // Inventario ejecute su baja real.
        await _asignacionRepository.cerrar(
          asignacionId: r.asignacionId!,
          motivo: MotivoCierreAsignacion.bajaEmpleado.name,
          fechaCierre: fechaBaja,
          ubicacionUnidad: EstatusArticuloUnidad.pendienteDesecho,
          observacionesCierre: r.observaciones,
          actorUsuarioId: actorUsuarioId,
        );
      case ResolucionResguardoBaja.perdido:
        await _asignacionRepository.cerrar(
          asignacionId: r.asignacionId!,
          motivo: MotivoCierreAsignacion.perdida.name,
          fechaCierre: fechaBaja,
          observacionesCierre: r.observaciones,
          atribuibleAlEmpleado: r.generaDescuento,
          actorUsuarioId: actorUsuarioId,
        );
      case ResolucionResguardoBaja.transferido:
        // `cambiarResponsable` existe justo para esto: el bien nunca
        // vuelve al almacén, solo cambia de custodio
        // (`EstatusAsignacion.reasignada`).
        await _asignacionRepository.cambiarResponsable(
          asignacionId: r.asignacionId!,
          nuevoEmpleadoId: r.nuevoResponsableEmpleadoId,
          fecha: fechaBaja,
          observaciones: r.observaciones,
          actorUsuarioId: actorUsuarioId,
        );
      case ResolucionResguardoBaja.noEntregado:
        final motivo = r.motivoNoEntrega!;
        if (motivo.dejaPendiente) {
          // Sigue con la persona: se marca, no se cierra. Aquí
          // `pendienteRecuperacionDesde` deja de ser automático y pasa
          // a ser una decisión documentada.
          await _asignacionRepository.marcarPendienteRecuperacion(
            asignacionId: r.asignacionId!,
            fecha: fechaBaja,
            actorUsuarioId: actorUsuarioId,
          );
        } else {
          // Extraviado, robado, o RISEG renunció a recuperarlo: para
          // Inventario el bien salió del patrimonio recuperable. Nunca
          // se cierra como "devuelta", que afirmaría que volvió.
          await _asignacionRepository.cerrar(
            asignacionId: r.asignacionId!,
            motivo: MotivoCierreAsignacion.perdida.name,
            fechaCierre: fechaBaja,
            observacionesCierre: r.observaciones ?? r.motivoNoEntregaOtro,
            atribuibleAlEmpleado: r.generaDescuento,
            actorUsuarioId: actorUsuarioId,
          );
        }
    }

    return _crearDescuentoSiAplica(r, empleadoId, fechaBaja, actorUsuarioId, r.asignacionId);
  }

  Future<String?> _crearDescuentoSiAplica(
    ResolucionResguardo r,
    String empleadoId,
    DateTime fechaBaja,
    String? actorUsuarioId,
    String? asignacionOrigenId,
  ) async {
    if (!r.generaDescuento) return null;

    // Obligación REAL, con cuotas, vía el use case oficial de
    // Descuentos — nunca una escritura directa desde Personal, y nunca
    // un importe informativo desconectado de Nómina.
    final resultado = await _registrarDescuento.ejecutar(
      empleadoId: empleadoId,
      tipo: 'resguardo',
      fechaRegistro: fechaBaja,
      importeOriginal: r.importeDescuento!,
      numeroCuotas: r.numeroCuotasDescuento,
      fechaPrimeraCuota: fechaBaja,
      descripcion: r.conceptoDescuento,
      asignacionOrigenId: asignacionOrigenId,
      observaciones: r.observaciones,
      actorUsuarioId: actorUsuarioId,
    );
    if (resultado is! RegistrarDescuentoProgramadoExitoso) {
      throw StateError('No se pudo crear la obligación del resguardo: ${resultado.runtimeType}');
    }
    return resultado.descuento.id;
  }
}

/// Señal interna para abortar la transacción cuando la baja laboral es
/// rechazada por su propio dominio — nunca escapa del use case.
class _BajaRechazada implements Exception {
  _BajaRechazada(this.resultado);
  final RegistrarBajaLaboralResultado resultado;
}
