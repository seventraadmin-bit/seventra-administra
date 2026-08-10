import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../repositories/nomina_repository.dart';
import 'calcular_dias_pagables_empleado.dart';
import 'renglon_nomina_requiere_revision.dart';
import 'resolver_sueldo_empleado_nomina.dart';

/// Determina, contra el estado **actual** de Personal, qué renglones de
/// una Nómina requieren revisión manual (Etapa 6C, resolución explícita
/// de Marlon al cerrar la etapa): un renglón que ya no tiene cobertura
/// laboral/sueldo en el periodo (0 días pagables, o ninguna fuente de
/// sueldo) pero conserva movimientos manuales o una distribución ya
/// capturada a mano.
///
/// **Por qué no basta con leer `NominaEmpleado.diasPagables`**: ese es
/// exactamente el caso que `ActualizarNominaDesdePersonalUseCase` deja
/// intacto a propósito — nunca reescribe un renglón con datos
/// manuales, y el esquema tampoco lo permitiría
/// (`CHECK (sueldo_mensual_utilizado > 0)` en `NominaEmpleado` impide
/// persistir un renglón con 0 días/0 tramos). El valor guardado queda
/// congelado en su último estado real, así que la única forma correcta
/// de detectar la condición es re-resolver contra Personal en el
/// momento de preguntar — deliberadamente derivado, sin columna nueva.
///
/// Reutilizado por `CerrarNominaUseCase` (bloquea el cierre) y por la
/// UI (`NominaDetalleScreen`, banner y badge por renglón) — misma
/// fuente de verdad en ambos lados.
class EvaluarRenglonesRequierenRevisionUseCase {
  EvaluarRenglonesRequierenRevisionUseCase(this._nominaRepository, this._empleadoRepository, this._resolverSueldo);

  final NominaRepository _nominaRepository;
  final EmpleadoRepository _empleadoRepository;
  final ResolverSueldoEmpleadoNomina _resolverSueldo;

  Future<List<NominaEmpleadoData>> ejecutar(String nominaId) async {
    final nomina = await _nominaRepository.obtenerPorId(nominaId);
    if (nomina == null) return const [];

    final renglones = await _nominaRepository.listarEmpleados(nominaId);
    // Filtro barato primero: solo vale la pena re-resolver contra
    // Personal a los renglones que sí tienen algo que perder.
    final candidatos = renglones.where(renglonNominaTieneMovimientosManuales).toList();
    if (candidatos.isEmpty) return const [];

    final resultado = <NominaEmpleadoData>[];
    for (final renglon in candidatos) {
      final empleado = await _empleadoRepository.obtenerPorId(renglon.empleadoId);
      if (empleado == null) {
        resultado.add(renglon);
        continue;
      }

      final segmentos = await _resolverSueldo.segmentosLaborales(empleado);
      final intervalos = await _resolverSueldo.intervalosSueldo(
        empleado: empleado,
        periodoInicio: nomina.fechaInicioPeriodo,
        periodoFin: nomina.fechaFinPeriodo,
      );

      try {
        final calculo = calcularDiasPagablesEmpleado(
          segmentosLaborales: segmentos,
          intervalosSueldo: intervalos,
          periodoInicio: nomina.fechaInicioPeriodo,
          periodoFin: nomina.fechaFinPeriodo,
        );
        if (calculo.diasPagables <= 0 || calculo.tramos.isEmpty) resultado.add(renglon);
      } on SueldoNoDisponibleException {
        resultado.add(renglon);
      }
    }
    return resultado;
  }
}
