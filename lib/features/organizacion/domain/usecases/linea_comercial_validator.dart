import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';

import '../repositories/catalogo_repository.dart';
import '../repositories/puesto_repository.dart';
import '../repositories/servicio_repository.dart';
import 'linea_comercial_errors.dart';

/// Condiciones de una línea comercial tal como llegan del formulario de
/// alta — sin validar. `fechaFinVigencia`/`descripcion`/`observaciones`
/// son siempre opcionales; el resto es obligatorio para poder calcular
/// un subtotal con sentido.
class LineaComercialBorrador {
  const LineaComercialBorrador({
    required this.puestoId,
    required this.modalidadTurnoId,
    required this.cantidadElementos,
    required this.precioUnitario,
    required this.tratamientoIva,
    required this.fechaInicioVigencia,
    this.descripcion,
    this.fechaFinVigencia,
    this.observaciones,
  });

  final String puestoId;
  final String modalidadTurnoId;
  final int? cantidadElementos;
  final int? precioUnitario;
  final TratamientoIva? tratamientoIva;
  final DateTime? fechaInicioVigencia;
  final String? descripcion;
  final DateTime? fechaFinVigencia;
  final String? observaciones;
}

/// Condiciones ya validadas y normalizadas — listas para persistir.
class LineaComercialValidada {
  const LineaComercialValidada({
    required this.puestoId,
    required this.modalidadTurnoId,
    required this.cantidadElementos,
    required this.precioUnitario,
    required this.tratamientoIva,
    required this.fechaInicioVigencia,
    this.descripcion,
    this.fechaFinVigencia,
    this.observaciones,
  });

  final String puestoId;
  final String modalidadTurnoId;
  final int cantidadElementos;
  final int precioUnitario;
  final TratamientoIva tratamientoIva;
  final DateTime fechaInicioVigencia;
  final String? descripcion;
  final DateTime? fechaFinVigencia;
  final String? observaciones;
}

/// Validación compartida de una condición comercial (alta hoy;
/// nueva-vigencia en la Etapa 4G.2 reutilizará esta misma clase, mismo
/// motivo que `ServicioValidator`/`PuestoValidator`).
class LineaComercialValidator {
  LineaComercialValidator(this._puestoRepository, this._catalogoRepository, this._servicioRepository);

  final PuestoRepository _puestoRepository;
  final CatalogoRepository _catalogoRepository;
  final ServicioRepository _servicioRepository;

  Future<({LineaComercialValidada? resultado, List<ErrorLineaComercial> errores})> validar({
    required String servicioId,
    required LineaComercialBorrador borrador,
  }) async {
    final errores = <ErrorLineaComercial>[];

    final puestoId = borrador.puestoId.trim();
    if (puestoId.isEmpty) {
      errores.add(const ErrorLineaComercial(campo: CampoLineaComercial.puesto, codigo: CodigoErrorLineaComercial.requerido));
    } else {
      final puesto = await _puestoRepository.obtenerPorId(puestoId);
      if (puesto == null) {
        errores.add(const ErrorLineaComercial(campo: CampoLineaComercial.puesto, codigo: CodigoErrorLineaComercial.noExiste));
      } else if (puesto.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
        errores.add(const ErrorLineaComercial(campo: CampoLineaComercial.puesto, codigo: CodigoErrorLineaComercial.inactivo));
      }
    }

    final modalidadTurnoId = borrador.modalidadTurnoId.trim();
    if (modalidadTurnoId.isEmpty) {
      errores.add(
        const ErrorLineaComercial(campo: CampoLineaComercial.modalidadTurno, codigo: CodigoErrorLineaComercial.requerido),
      );
    } else {
      final modalidades = await _catalogoRepository.listarModalidadesTurno();
      if (!modalidades.any((m) => m.id == modalidadTurnoId)) {
        errores.add(
          const ErrorLineaComercial(campo: CampoLineaComercial.modalidadTurno, codigo: CodigoErrorLineaComercial.noExiste),
        );
      }
    }

    final cantidad = borrador.cantidadElementos;
    if (cantidad == null || cantidad <= 0) {
      errores.add(
        const ErrorLineaComercial(campo: CampoLineaComercial.cantidadElementos, codigo: CodigoErrorLineaComercial.requerido),
      );
    }

    final precio = borrador.precioUnitario;
    if (precio == null || precio <= 0) {
      errores.add(
        const ErrorLineaComercial(campo: CampoLineaComercial.precioUnitario, codigo: CodigoErrorLineaComercial.requerido),
      );
    }

    if (borrador.tratamientoIva == null) {
      errores.add(
        const ErrorLineaComercial(campo: CampoLineaComercial.tratamientoIva, codigo: CodigoErrorLineaComercial.requerido),
      );
    }

    final fechaInicioVigencia = borrador.fechaInicioVigencia;
    if (fechaInicioVigencia == null) {
      errores.add(
        const ErrorLineaComercial(
          campo: CampoLineaComercial.fechaInicioVigencia,
          codigo: CodigoErrorLineaComercial.requerido,
        ),
      );
    } else {
      final servicio = await _servicioRepository.obtenerPorId(servicioId);
      if (servicio != null && fechaInicioVigencia.isBefore(servicio.fechaInicio)) {
        errores.add(
          const ErrorLineaComercial(
            campo: CampoLineaComercial.fechaInicioVigencia,
            codigo: CodigoErrorLineaComercial.fechaAnteriorInicioServicio,
          ),
        );
      }
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }

    String? vacioANull(String? valor) {
      final recortado = valor?.trim();
      return (recortado == null || recortado.isEmpty) ? null : recortado;
    }

    return (
      resultado: LineaComercialValidada(
        puestoId: puestoId,
        modalidadTurnoId: modalidadTurnoId,
        cantidadElementos: cantidad!,
        precioUnitario: precio!,
        tratamientoIva: borrador.tratamientoIva!,
        fechaInicioVigencia: fechaInicioVigencia!,
        descripcion: vacioANull(borrador.descripcion),
        fechaFinVigencia: borrador.fechaFinVigencia,
        observaciones: vacioANull(borrador.observaciones),
      ),
      errores: const <ErrorLineaComercial>[],
    );
  }
}
