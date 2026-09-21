import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import '../repositories/descuento_programado_repository.dart';
import 'generar_plan_cuotas.dart';

sealed class RegistrarDescuentoProgramadoResultado {}

class RegistrarDescuentoProgramadoExitoso
    extends RegistrarDescuentoProgramadoResultado {
  RegistrarDescuentoProgramadoExitoso(this.descuento);
  final DescuentoProgramadoEmpleadoData descuento;
}

class RegistrarDescuentoProgramadoEmpleadoNoExiste
    extends RegistrarDescuentoProgramadoResultado {}

/// No se registra una obligación económica nueva sobre un Empleado ya
/// dado de baja — un saldo pendiente EXISTENTE se conserva y se sigue
/// cobrando (ver el doc comment de `EmpleadoRepository`), pero abrir
/// una obligación nueva sobre alguien que ya no labora no tiene
/// sentido operativo.
class RegistrarDescuentoProgramadoEmpleadoNoActivo
    extends RegistrarDescuentoProgramadoResultado {}

class RegistrarDescuentoProgramadoImporteInvalido
    extends RegistrarDescuentoProgramadoResultado {}

class RegistrarDescuentoProgramadoNumeroCuotasInvalido
    extends RegistrarDescuentoProgramadoResultado {}

/// [esEntregaDinero] declara que el registro representa un desembolso
/// real (típicamente un préstamo), pero no se seleccionó ninguna
/// `CuentaFinanciera` de origen — a diferencia de una "recuperación de
/// concepto" (ej. botas), donde no hace falta ninguna cuenta.
class RegistrarDescuentoProgramadoCuentaFinancieraRequerida
    extends RegistrarDescuentoProgramadoResultado {}

class RegistrarDescuentoProgramadoErrorInesperado
    extends RegistrarDescuentoProgramadoResultado {
  RegistrarDescuentoProgramadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una obligación económica programada — préstamo o costo de
/// botas (Etapa 15) — con su plan de recuperación completo ya resuelto
/// vía `generarPlanCuotas` (misma función que alimenta la
/// previsualización del diálogo, nunca un cálculo paralelo). Genera el
/// folio por tipo (`PRE-000012`/`DES-000015`) y delega la escritura
/// transaccional a `DescuentoProgramadoRepository.registrar`.
class RegistrarDescuentoProgramadoUseCase {
  RegistrarDescuentoProgramadoUseCase(
    this._repository,
    this._empleadoRepository,
    this._generarCodigo,
  );

  final DescuentoProgramadoRepository _repository;
  final EmpleadoRepository _empleadoRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarDescuentoProgramadoResultado> ejecutar({
    required String empleadoId,
    required String tipo,
    required DateTime fechaRegistro,
    required int importeOriginal,
    required int numeroCuotas,
    required DateTime fechaPrimeraCuota,
    String? descripcion,
    String? asignacionOrigenId,
    String? observaciones,
    bool esEntregaDinero = false,
    String? cuentaFinancieraId,
    String? formaPagoEgreso,
    String? actorUsuarioId,
  }) async {
    final empleado = await _empleadoRepository.obtenerPorId(empleadoId);
    if (empleado == null) return RegistrarDescuentoProgramadoEmpleadoNoExiste();
    if (empleado.estatus != 'activo')
      return RegistrarDescuentoProgramadoEmpleadoNoActivo();
    if (importeOriginal <= 0)
      return RegistrarDescuentoProgramadoImporteInvalido();
    if (numeroCuotas <= 0)
      return RegistrarDescuentoProgramadoNumeroCuotasInvalido();
    if (esEntregaDinero && cuentaFinancieraId == null) {
      return RegistrarDescuentoProgramadoCuentaFinancieraRequerida();
    }

    try {
      final entityType =
          tipo == 'botas'
              ? 'descuentoProgramadoBotas'
              : 'descuentoProgramadoPrestamo';
      final folioResultado = await _generarCodigo.ejecutar(entityType);
      final String folio;
      switch (folioResultado) {
        case Ok<String>(value: final v):
          folio = v;
        case Err<String>(failure: final f):
          return RegistrarDescuentoProgramadoErrorInesperado(f.message);
      }

      final plan = generarPlanCuotas(
        importeOriginal: importeOriginal,
        numeroCuotas: numeroCuotas,
        fechaPrimera: fechaPrimeraCuota,
      );

      final descuento = await _repository.registrar(
        folio: folio,
        empleadoId: empleadoId,
        tipo: tipo,
        fechaRegistro: fechaRegistro,
        importeOriginal: importeOriginal,
        descripcion: descripcion,
        asignacionOrigenId: asignacionOrigenId,
        observaciones: observaciones,
        cuotas: [
          for (final c in plan)
            (
              numeroCuota: c.numeroCuota,
              fechaProgramada: c.fechaProgramada,
              importe: c.importe,
            ),
        ],
        cuentaFinancieraId: esEntregaDinero ? cuentaFinancieraId : null,
        beneficiarioEgreso: esEntregaDinero ? empleadoNombreCompleto(empleado) : null,
        formaPagoEgreso: esEntregaDinero ? formaPagoEgreso : null,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarDescuentoProgramadoExitoso(descuento);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un
      // rechazo previsto y accionable. Se deja propagar para que la
      // pantalla muestre disponible/requerido/faltante en vez de un
      // mensaje genérico. La transacción ya quedó revertida entera.
      rethrow;
    } catch (e) {
      return RegistrarDescuentoProgramadoErrorInesperado(e.toString());
    }
  }
}
