import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/puesto_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../../data/tables/nomina_table.dart';
import '../repositories/nomina_repository.dart';
import 'calcular_dias_pagables_empleado.dart';
import 'calcular_periodo_nomina.dart';
import 'fila_nomina_generada.dart';
import 'resolver_sueldo_empleado_nomina.dart';

/// Un Empleado con días pagables potenciales que se excluyó de la
/// generación porque ningún tramo de su periodo tiene una fuente de
/// sueldo configurada (ni Servicio ni administrativo) — nunca se
/// incluye con un importe en `$0` en silencio.
class EmpleadoExcluidoNomina {
  const EmpleadoExcluidoNomina({required this.empleadoId, required this.nombreCompleto, required this.motivo});
  final String empleadoId;
  final String nombreCompleto;
  final String motivo;
}

sealed class GenerarNominaResultado {}

class GenerarNominaExitoso extends GenerarNominaResultado {
  GenerarNominaExitoso({required this.nomina, required this.empleadosIncluidos, required this.empleadosExcluidos});
  final NominaData nomina;
  final int empleadosIncluidos;
  final List<EmpleadoExcluidoNomina> empleadosExcluidos;
}

class GenerarNominaYaExiste extends GenerarNominaResultado {}

class GenerarNominaSinEmpleados extends GenerarNominaResultado {}

class GenerarNominaErrorInesperado extends GenerarNominaResultado {
  GenerarNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Genera explícitamente una Nómina para un periodo (Etapa 6C) — nunca
/// automática/en segundo plano (Resolución explícita de Marlon). Incluye
/// a cualquier Empleado con al menos un día pagable dentro del periodo,
/// **incluso si ya está de baja** — una baja nunca hace desaparecer
/// dinero pendiente de pagar (Resolución explícita de Marlon).
///
/// El bono solo se propone automáticamente en la Nómina de la segunda
/// quincena (pago del día 5); en la primera siempre arranca en `$0` —
/// editable como excepción manual en cualquiera de las dos.
class GenerarNominaUseCase {
  GenerarNominaUseCase(
    this._nominaRepository,
    this._empleadoRepository,
    this._puestoRepository,
    this._catalogoRepository,
    this._resolverSueldo,
    this._generarCodigo,
  );

  final NominaRepository _nominaRepository;
  final EmpleadoRepository _empleadoRepository;
  final PuestoRepository _puestoRepository;
  final CatalogoRepository _catalogoRepository;
  final ResolverSueldoEmpleadoNomina _resolverSueldo;
  final GenerarCodigoUseCase _generarCodigo;

  Future<GenerarNominaResultado> ejecutar({
    required int anio,
    required int mes,
    required TipoPeriodoNomina tipo,
    String? actor,
  }) async {
    final existente = await _nominaRepository.obtenerPorPeriodo(anio: anio, mes: mes, tipo: tipo);
    if (existente != null) return GenerarNominaYaExiste();

    final periodo = calcularPeriodoNomina(anio: anio, mes: mes, tipo: tipo);

    try {
      final candidatos = await _empleadoRepository.listar();
      final bancos = await _catalogoRepository.listarBancos();

      final filas = <FilaNominaGenerada>[];
      final excluidos = <EmpleadoExcluidoNomina>[];

      for (final empleado in candidatos) {
        final segmentos = await _resolverSueldo.segmentosLaborales(empleado);
        final intervalos = await _resolverSueldo.intervalosSueldo(
          empleado: empleado,
          periodoInicio: periodo.fechaInicio,
          periodoFin: periodo.fechaFin,
        );

        CalculoDiasPagablesEmpleado calculo;
        try {
          String? puestoNombre;
          if (empleado.puestoId != null) {
            puestoNombre = (await _puestoRepository.obtenerPorId(empleado.puestoId!))?.nombre;
          }
          calculo = calcularDiasPagablesEmpleado(
            segmentosLaborales: segmentos,
            intervalosSueldo: intervalos,
            periodoInicio: periodo.fechaInicio,
            periodoFin: periodo.fechaFin,
            puestoNombre: puestoNombre,
          );
        } on SueldoNoDisponibleException {
          excluidos.add(
            EmpleadoExcluidoNomina(
              empleadoId: empleado.id,
              nombreCompleto: _nombreCompleto(empleado),
              motivo: 'Sin fuente de sueldo configurada (ni Servicio ni administrativo) para parte del periodo.',
            ),
          );
          continue;
        }

        if (calculo.diasPagables <= 0 || calculo.tramos.isEmpty) continue;

        final ultimoTramo = calculo.tramos.last;
        String? bancoNombre;
        if (empleado.bancoId != null) {
          for (final b in bancos) {
            if (b.id == empleado.bancoId) bancoNombre = b.nombre;
          }
        }

        final bonoPropuesto = tipo == TipoPeriodoNomina.segunda ? calculo.bonoDisponible : 0;

        filas.add(
          FilaNominaGenerada(
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
            bonoPropuesto: bonoPropuesto,
            tramos: calculo.tramos,
          ),
        );
      }

      if (filas.isEmpty) return GenerarNominaSinEmpleados();

      final folioResultado = await _generarCodigo.ejecutar('nomina');
      final String folio;
      switch (folioResultado) {
        case Ok<String>(value: final v):
          folio = v;
        case Err<String>(failure: final f):
          return GenerarNominaErrorInesperado(f.message);
      }

      final nomina = await _nominaRepository.generar(folio: folio, periodo: periodo, filas: filas, actor: actor);
      return GenerarNominaExitoso(nomina: nomina, empleadosIncluidos: filas.length, empleadosExcluidos: excluidos);
    } catch (e) {
      return GenerarNominaErrorInesperado(e.toString());
    }
  }

  String _nombreCompleto(EmpleadoData empleado) {
    final partes = [empleado.nombres, empleado.apellidoPaterno, if (empleado.apellidoMaterno != null) empleado.apellidoMaterno!];
    return partes.join(' ');
  }
}
