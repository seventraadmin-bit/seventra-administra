import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/puesto_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../../data/tables/nomina_table.dart';
import '../repositories/nomina_repository.dart';
import 'calcular_dias_pagables_empleado.dart';
import 'fila_nomina_generada.dart';
import 'generar_nomina_usecase.dart' show EmpleadoExcluidoNomina;
import 'resolver_sueldo_empleado_nomina.dart';

sealed class ActualizarNominaDesdePersonalResultado {}

class ActualizarNominaDesdePersonalExitoso extends ActualizarNominaDesdePersonalResultado {
  ActualizarNominaDesdePersonalExitoso({
    required this.renglonesActualizados,
    required this.renglonesNuevos,
    required this.renglonesEliminados,
    required this.renglonesConservadosSinDias,
    required this.renglonesConDistribucionPendiente,
    required this.empleadosExcluidos,
  });

  final int renglonesActualizados;
  final int renglonesNuevos;
  final int renglonesEliminados;

  /// Empleados que perdieron todos sus días pagables pero conservaban
  /// movimientos manuales/distribución ya capturados — nunca
  /// desaparecen en silencio (Resolución explícita de Marlon), se dejan
  /// tal cual con `diasPagables == 0` como señal de "requiere revisión".
  final int renglonesConservadosSinDias;

  final int renglonesConDistribucionPendiente;
  final List<EmpleadoExcluidoNomina> empleadosExcluidos;
}

class ActualizarNominaDesdePersonalNoExiste extends ActualizarNominaDesdePersonalResultado {}

class ActualizarNominaDesdePersonalNominaCerrada extends ActualizarNominaDesdePersonalResultado {}

class ActualizarNominaDesdePersonalErrorInesperado extends ActualizarNominaDesdePersonalResultado {
  ActualizarNominaDesdePersonalErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Re-analiza una Nómina en Borrador contra el estado actual de
/// Personal (Etapa 6C) — altas/bajas/reingresos/cambios de Servicio o
/// sueldo desde que se generó o se actualizó por última vez. Nunca
/// automático, siempre una acción explícita del usuario.
///
/// **Qué se preserva siempre** (nunca se recalculan): préstamo, tiempo
/// extra, faltas, otros descuentos, observaciones — son movimientos
/// manuales puros, la actualización nunca los toca.
///
/// **Bono**: se vuelve a proponer automáticamente (según el tipo de
/// periodo) solo si el usuario nunca lo tocó a mano
/// (`bonoModificadoManualmente == false`); si ya lo modificó, se
/// conserva tal cual.
///
/// **Fiscal/No fiscal**: si nunca se modificó a mano, se reinicia al
/// default (Fiscal = nuevo total, No fiscal = `$0`). Si ya se modificó
/// a mano, se conserva **siempre** — pero si el nuevo total ya no
/// coincide con esa distribución conservada, se marca
/// `distribucionPendienteRevision` (bloquea el cierre) en vez de
/// ajustarla en silencio.
///
/// **Un renglón que pierde todos sus días pagables**: si nunca tuvo
/// movimientos manuales ni distribución modificada, se elimina sin
/// aviso (ya no representa nada pendiente de pagar). Si sí los tenía,
/// se conserva **exactamente como estaba** — nunca se recalcula ni se
/// borra un renglón con datos manuales — y el propio `diasPagables ==
/// 0` en un renglón ya existente es la señal de que necesita revisión
/// manual (préstamo pendiente, ajuste de otros descuentos, etc.).
class ActualizarNominaDesdePersonalUseCase {
  ActualizarNominaDesdePersonalUseCase(
    this._nominaRepository,
    this._empleadoRepository,
    this._puestoRepository,
    this._catalogoRepository,
    this._resolverSueldo,
  );

  final NominaRepository _nominaRepository;
  final EmpleadoRepository _empleadoRepository;
  final PuestoRepository _puestoRepository;
  final CatalogoRepository _catalogoRepository;
  final ResolverSueldoEmpleadoNomina _resolverSueldo;

  Future<ActualizarNominaDesdePersonalResultado> ejecutar({required String nominaId, String? actor}) async {
    final nomina = await _nominaRepository.obtenerPorId(nominaId);
    if (nomina == null) return ActualizarNominaDesdePersonalNoExiste();
    if (nomina.estatus != 'borrador') return ActualizarNominaDesdePersonalNominaCerrada();

    final tipo = TipoPeriodoNomina.values.byName(nomina.tipoPeriodo);

    try {
      final renglonesExistentes = await _nominaRepository.listarEmpleados(nominaId);
      final renglonesPorEmpleado = {for (final r in renglonesExistentes) r.empleadoId: r};

      final candidatos = await _empleadoRepository.listar();
      final bancos = await _catalogoRepository.listarBancos();

      var actualizados = 0;
      var nuevos = 0;
      var eliminados = 0;
      var conservadosSinDias = 0;
      var conDistribucionPendiente = 0;
      final excluidos = <EmpleadoExcluidoNomina>[];

      for (final empleado in candidatos) {
        final existente = renglonesPorEmpleado[empleado.id];

        final segmentos = await _resolverSueldo.segmentosLaborales(empleado);
        final intervalos = await _resolverSueldo.intervalosSueldo(
          empleado: empleado,
          periodoInicio: nomina.fechaInicioPeriodo,
          periodoFin: nomina.fechaFinPeriodo,
        );

        CalculoDiasPagablesEmpleado? calculo;
        try {
          String? puestoNombre;
          if (empleado.puestoId != null) {
            puestoNombre = (await _puestoRepository.obtenerPorId(empleado.puestoId!))?.nombre;
          }
          calculo = calcularDiasPagablesEmpleado(
            segmentosLaborales: segmentos,
            intervalosSueldo: intervalos,
            periodoInicio: nomina.fechaInicioPeriodo,
            periodoFin: nomina.fechaFinPeriodo,
            puestoNombre: puestoNombre,
          );
        } on SueldoNoDisponibleException {
          if (existente == null) {
            excluidos.add(
              EmpleadoExcluidoNomina(
                empleadoId: empleado.id,
                nombreCompleto: _nombreCompleto(empleado),
                motivo: 'Sin fuente de sueldo configurada (ni Servicio ni administrativo) para parte del periodo.',
              ),
            );
          }
          calculo = null;
        }

        final tieneDias = calculo != null && calculo.diasPagables > 0 && calculo.tramos.isNotEmpty;

        if (!tieneDias) {
          if (existente == null) continue;
          final tieneDatosManuales = existente.prestamo != 0 ||
              existente.tiempoExtra != 0 ||
              existente.faltas != 0 ||
              existente.otrosDescuentos != 0 ||
              (existente.observaciones != null && existente.observaciones!.trim().isNotEmpty) ||
              existente.bonoModificadoManualmente ||
              existente.distribucionModificadaManualmente;
          if (tieneDatosManuales) {
            conservadosSinDias++;
          } else {
            await _nominaRepository.eliminarRenglon(existente.id);
            eliminados++;
          }
          continue;
        }

        final ultimoTramo = calculo.tramos.last;
        String? bancoNombre;
        if (empleado.bancoId != null) {
          for (final b in bancos) {
            if (b.id == empleado.bancoId) bancoNombre = b.nombre;
          }
        }

        final int bono;
        final bool bonoModificadoManualmente;
        if (existente != null && existente.bonoModificadoManualmente) {
          bono = existente.bono;
          bonoModificadoManualmente = true;
        } else {
          bono = tipo == TipoPeriodoNomina.segunda ? calculo.bonoDisponible : 0;
          bonoModificadoManualmente = false;
        }

        final prestamo = existente?.prestamo ?? 0;
        final tiempoExtra = existente?.tiempoExtra ?? 0;
        final faltas = existente?.faltas ?? 0;
        final otrosDescuentos = existente?.otrosDescuentos ?? 0;
        final observaciones = existente?.observaciones;

        final pagoPorDia = (calculo.sueldoMensualUtilizado / 30).round();
        final descuentoPorFaltas = faltas * pagoPorDia;
        final nuevoTotal = calculo.importeBase + bono + tiempoExtra - prestamo - descuentoPorFaltas - otrosDescuentos;

        final int montoFiscal;
        final int montoNoFiscal;
        final bool distribucionModificadaManualmente;
        var distribucionPendienteRevision = false;

        if (existente == null || !existente.distribucionModificadaManualmente) {
          montoFiscal = nuevoTotal;
          montoNoFiscal = 0;
          distribucionModificadaManualmente = false;
        } else {
          distribucionModificadaManualmente = true;
          if (existente.montoFiscal + existente.montoNoFiscal == nuevoTotal) {
            montoFiscal = existente.montoFiscal;
            montoNoFiscal = existente.montoNoFiscal;
          } else {
            montoFiscal = existente.montoFiscal;
            montoNoFiscal = existente.montoNoFiscal;
            distribucionPendienteRevision = true;
            conDistribucionPendiente++;
          }
        }

        final fila = FilaNominaGenerada(
          empleadoId: empleado.id,
          numeroEmpleado: empleado.numeroEmpleado,
          nombreCompleto: _nombreCompleto(empleado),
          puestoNombre: calculo.puestoNombre,
          servicioId: ultimoTramo.servicioId,
          servicioNombre: ultimoTramo.servicioNombre,
          turnoNombre: ultimoTramo.turnoNombre,
          bancoNombre: bancoNombre,
          numeroCuentaTarjeta: empleado.numeroCuentaTarjeta,
          clabe: empleado.clabe,
          fuenteSueldoUtilizada: ultimoTramo.fuente,
          diasPagables: calculo.diasPagables,
          sueldoMensualUtilizado: calculo.sueldoMensualUtilizado,
          importeBase: calculo.importeBase,
          bonoPropuesto: bono,
          tramos: calculo.tramos,
        );

        await _nominaRepository.guardarRenglon(
          nominaId: nominaId,
          datos: fila,
          prestamo: prestamo,
          tiempoExtra: tiempoExtra,
          bono: bono,
          bonoModificadoManualmente: bonoModificadoManualmente,
          faltas: faltas,
          otrosDescuentos: otrosDescuentos,
          observaciones: observaciones,
          montoFiscal: montoFiscal,
          montoNoFiscal: montoNoFiscal,
          distribucionModificadaManualmente: distribucionModificadaManualmente,
          distribucionPendienteRevision: distribucionPendienteRevision,
        );

        if (existente == null) {
          nuevos++;
        } else {
          actualizados++;
        }
      }

      await _nominaRepository.registrarEvento(
        nominaId: nominaId,
        tipoEvento: 'actualizadaDesdePersonal',
        actor: actor,
        observacion: '$actualizados actualizados, $nuevos nuevos, $eliminados eliminados, '
            '$conservadosSinDias conservados sin días, $conDistribucionPendiente con distribución pendiente.',
      );

      return ActualizarNominaDesdePersonalExitoso(
        renglonesActualizados: actualizados,
        renglonesNuevos: nuevos,
        renglonesEliminados: eliminados,
        renglonesConservadosSinDias: conservadosSinDias,
        renglonesConDistribucionPendiente: conDistribucionPendiente,
        empleadosExcluidos: excluidos,
      );
    } catch (e) {
      return ActualizarNominaDesdePersonalErrorInesperado(e.toString());
    }
  }

  String _nombreCompleto(EmpleadoData empleado) {
    final partes = [empleado.nombres, empleado.apellidoPaterno, if (empleado.apellidoMaterno != null) empleado.apellidoMaterno!];
    return partes.join(' ');
  }
}
