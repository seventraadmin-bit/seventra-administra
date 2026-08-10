import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../../data/tables/nomina_empleado_table.dart';
import 'calcular_dias_pagables_empleado.dart';

DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Arma, contra la base de datos, los `SegmentoLaboral`/`IntervaloSueldo`
/// que necesita `calcularDiasPagablesEmpleado` para un Empleado y un
/// periodo de Nómina concretos (Etapa 6C) — la única pieza de esta
/// etapa que sí toca repositorios; el cálculo en sí sigue siendo puro.
///
/// **Segmentos laborales**: el periodo vigente de `Empleado`
/// (`fechaIngreso`/`fechaBaja`) más todos los periodos archivados en
/// `EmpleadoPeriodoLaboral` — cubre tanto una baja/reingreso simple como
/// un reingreso dentro de la misma quincena (dos segmentos).
///
/// **Intervalos de sueldo**: recorre todas las `AsignacionServicio` del
/// Empleado (vigentes y cerradas) que se traslapan con el periodo, y
/// dentro de cada una sus `AsignacionServicioSueldoVigencia` — cada
/// vigencia se recorta contra el fin de su propia asignación (`ver el
/// doc comment de AsignacionServicioSueldoVigencia`: una asignación
/// cerrada nunca deja leer su vigencia de sueldo más allá de su propio
/// `fechaTermino`). Cualquier hueco dentro del periodo que ninguna
/// `AsignacionServicio` cubra se rellena con la fuente administrativa
/// (`Empleado.sueldoMensualAdministrativo`/`bonoMensualAdministrativo`)
/// — solo si está configurada; si no lo está, el hueco queda sin cubrir
/// y `calcularDiasPagablesEmpleado` lo señala con
/// `SueldoNoDisponibleException`, nunca con un tramo en `$0`.
class ResolverSueldoEmpleadoNomina {
  ResolverSueldoEmpleadoNomina(
    this._empleadoRepository,
    this._asignacionServicioRepository,
    this._servicioRepository,
    this._catalogoRepository,
  );

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionServicioRepository;
  final ServicioRepository _servicioRepository;
  final CatalogoRepository _catalogoRepository;

  Future<List<SegmentoLaboral>> segmentosLaborales(EmpleadoData empleado) async {
    final segmentos = <SegmentoLaboral>[
      SegmentoLaboral(
        inicio: empleado.fechaIngreso,
        fin: EstatusEmpleado.values.byName(empleado.estatus) == EstatusEmpleado.baja ? empleado.fechaBaja : null,
      ),
    ];
    final archivados = await _empleadoRepository.listarPeriodosLaboralesArchivados(empleado.id);
    for (final periodo in archivados) {
      segmentos.add(SegmentoLaboral(inicio: periodo.fechaIngreso, fin: periodo.fechaBaja));
    }
    return segmentos;
  }

  Future<List<IntervaloSueldo>> intervalosSueldo({
    required EmpleadoData empleado,
    required DateTime periodoInicio,
    required DateTime periodoFin,
  }) async {
    final inicioPeriodo = _soloFecha(periodoInicio);
    final finPeriodo = _soloFecha(periodoFin);

    final modalidadesTurno = await _catalogoRepository.listarModalidadesTurno();
    String? nombreTurno(String? turnoId) {
      if (turnoId == null) return null;
      for (final m in modalidadesTurno) {
        if (m.id == turnoId) return m.nombre;
      }
      return null;
    }

    final asignaciones = await _asignacionServicioRepository.listarPorEmpleado(empleado.id);
    final intervalosServicio = <IntervaloSueldo>[];

    for (final asignacion in asignaciones) {
      final asignacionFin = asignacion.fechaTermino;
      if (asignacionFin != null && _soloFecha(asignacionFin).isBefore(inicioPeriodo)) continue;
      if (_soloFecha(asignacion.fechaInicio).isAfter(finPeriodo)) continue;

      final servicio = await _servicioRepository.obtenerPorId(asignacion.servicioId);
      final turnoNombre = nombreTurno(asignacion.turnoId);
      final vigencias = await _asignacionServicioRepository.listarHistorialSueldo(asignacion.id);

      for (final vigencia in vigencias) {
        if (vigencia.cicloVidaRegistro == CicloVidaRegistro.archivado.name) continue;

        DateTime? finVigencia = vigencia.fechaFinVigencia;
        if (asignacionFin != null) {
          finVigencia = finVigencia == null || asignacionFin.isBefore(finVigencia) ? asignacionFin : finVigencia;
        }
        if (finVigencia != null && _soloFecha(finVigencia).isBefore(inicioPeriodo)) continue;
        if (_soloFecha(vigencia.fechaInicioVigencia).isAfter(finPeriodo)) continue;

        intervalosServicio.add(
          IntervaloSueldo(
            inicio: vigencia.fechaInicioVigencia,
            fin: finVigencia,
            fuente: FuenteSueldoNomina.servicio,
            servicioId: asignacion.servicioId,
            servicioNombre: servicio?.nombre,
            turnoNombre: turnoNombre,
            sueldoMensual: vigencia.sueldoMensual,
            bonoMensual: vigencia.bonoMensual,
          ),
        );
      }
    }

    return _rellenarConAdministrativo(intervalosServicio, empleado, inicioPeriodo, finPeriodo);
  }

  /// Recorre `intervalosServicio` (pueden venir en cualquier orden, sin
  /// traslape entre sí) y rellena cualquier hueco dentro de
  /// `[inicio, fin]` con la fuente administrativa, si está configurada.
  List<IntervaloSueldo> _rellenarConAdministrativo(
    List<IntervaloSueldo> intervalosServicio,
    EmpleadoData empleado,
    DateTime inicio,
    DateTime fin,
  ) {
    final sueldoAdmin = empleado.sueldoMensualAdministrativo;
    final bonoAdmin = empleado.bonoMensualAdministrativo ?? 0;

    final ordenados = [...intervalosServicio]..sort((a, b) => a.inicio.compareTo(b.inicio));
    final resultado = <IntervaloSueldo>[];
    var cursor = inicio;

    IntervaloSueldo? tramoAdministrativo(DateTime desde, DateTime hasta) {
      if (sueldoAdmin == null) return null;
      return IntervaloSueldo(
        inicio: desde,
        fin: hasta,
        fuente: FuenteSueldoNomina.administrativo,
        sueldoMensual: sueldoAdmin,
        bonoMensual: bonoAdmin,
      );
    }

    for (final intervalo in ordenados) {
      final intInicio = _soloFecha(intervalo.inicio);
      final intFin = intervalo.fin == null ? fin : _soloFecha(intervalo.fin!);
      if (intFin.isBefore(cursor)) continue;
      if (intInicio.isAfter(fin)) break;

      if (intInicio.isAfter(cursor)) {
        final relleno = tramoAdministrativo(cursor, intInicio.subtract(const Duration(days: 1)));
        if (relleno != null) resultado.add(relleno);
      }

      final trozoInicio = intInicio.isAfter(cursor) ? intInicio : cursor;
      final trozoFin = intFin.isBefore(fin) ? intFin : fin;
      if (!trozoFin.isBefore(trozoInicio)) {
        resultado.add(
          IntervaloSueldo(
            inicio: trozoInicio,
            fin: trozoFin,
            fuente: intervalo.fuente,
            servicioId: intervalo.servicioId,
            servicioNombre: intervalo.servicioNombre,
            turnoNombre: intervalo.turnoNombre,
            sueldoMensual: intervalo.sueldoMensual,
            bonoMensual: intervalo.bonoMensual,
          ),
        );
      }
      cursor = trozoFin.add(const Duration(days: 1));
      if (cursor.isAfter(fin)) break;
    }

    if (!cursor.isAfter(fin)) {
      final relleno = tramoAdministrativo(cursor, fin);
      if (relleno != null) resultado.add(relleno);
    }

    return resultado;
  }
}
