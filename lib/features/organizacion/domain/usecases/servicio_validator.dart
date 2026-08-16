import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';

import '../repositories/catalogo_repository.dart';
import '../repositories/cliente_repository.dart';
import 'servicio_errors.dart';

/// Datos de Servicio tal como llegan del formulario de alta/edición —
/// sin validar. No incluye `clienteId`: en edición, la relación con el
/// Cliente es inmutable después de creada (ver `ActualizarServicioUseCase`),
/// así que solo `CrearServicioUseCase` la recibe por separado, nunca como
/// parte de este borrador editable. Tampoco incluye `fechaTermino`: esa
/// solo se captura vía la acción explícita de terminar
/// (`CambiarEstatusServicioUseCase`) — mantenerla fuera de este borrador
/// evita un segundo camino de escritura que pudiera asignarla sin la
/// confirmación que exige esa acción.
class ServicioBorrador {
  const ServicioBorrador({
    required this.nombre,
    required this.tipoServicioId,
    required this.fechaInicio,
    this.observaciones,
    this.referenciaComercial,
    this.referenciaContractual,
  });

  final String nombre;
  final String tipoServicioId;
  final DateTime? fechaInicio;
  final String? observaciones;
  final String? referenciaComercial;
  final String? referenciaContractual;
}

/// Servicio ya validado y normalizado — listo para persistir.
class ServicioValidado {
  const ServicioValidado({
    required this.nombre,
    required this.tipoServicioId,
    required this.fechaInicio,
    this.observaciones,
    this.referenciaComercial,
    this.referenciaContractual,
  });

  final String nombre;
  final String tipoServicioId;
  final DateTime fechaInicio;
  final String? observaciones;
  final String? referenciaComercial;
  final String? referenciaContractual;
}

/// Validación compartida entre alta y edición de Servicio — nunca
/// duplicada entre `CrearServicioUseCase` y `ActualizarServicioUseCase`
/// (mismo motivo que `PuestoValidator`/`EntidadFiscalValidator`).
///
/// El Cliente propietario se valida aquí (no solo en la creación) porque
/// una edición también debe rechazarse si, entre tanto, el Cliente pasó
/// a un estado que ya no admite nuevas relaciones — aunque en 4F.1 la
/// única operación que de verdad depende de esto es la creación, ya que
/// `ActualizarServicioUseCase` nunca cambia el Cliente.
class ServicioValidator {
  ServicioValidator(this._clienteRepository, this._catalogoRepository);

  final ClienteRepository _clienteRepository;
  final CatalogoRepository _catalogoRepository;

  /// Estatus comerciales bajo los cuales un Cliente puede recibir un
  /// Servicio nuevo. `suspendido`/`terminado`/`descartado` quedan fuera:
  /// una relación pausada, cerrada o que nunca prosperó no debe generar
  /// compromisos nuevos sin que el Cliente vuelva primero, de forma
  /// explícita, a `prospecto` o `activo`.
  static const _estatusClientePermitidos = {EstatusCliente.prospecto, EstatusCliente.activo};

  Future<({ServicioValidado? resultado, List<ErrorCampoServicio> errores})> validar({
    required String clienteId,
    required ServicioBorrador borrador,
  }) async {
    final errores = <ErrorCampoServicio>[];

    final cliente = await _clienteRepository.obtenerPorId(clienteId);
    if (cliente == null || cliente.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      errores.add(
        const ErrorCampoServicio(campo: CampoServicio.cliente, codigo: CodigoErrorServicio.noExiste),
      );
    } else if (!_estatusClientePermitidos.contains(EstatusCliente.values.byName(cliente.estatus))) {
      errores.add(
        const ErrorCampoServicio(campo: CampoServicio.cliente, codigo: CodigoErrorServicio.clienteNoDisponible),
      );
    }

    final nombre = borrador.nombre.trim();
    if (nombre.isEmpty) {
      errores.add(const ErrorCampoServicio(campo: CampoServicio.nombre, codigo: CodigoErrorServicio.requerido));
    }

    final tipoServicioId = borrador.tipoServicioId.trim();
    if (tipoServicioId.isEmpty) {
      errores.add(const ErrorCampoServicio(campo: CampoServicio.tipoServicio, codigo: CodigoErrorServicio.requerido));
    } else {
      final tipos = await _catalogoRepository.listarTiposServicio();
      if (!tipos.any((t) => t.id == tipoServicioId)) {
        errores.add(const ErrorCampoServicio(campo: CampoServicio.tipoServicio, codigo: CodigoErrorServicio.noExiste));
      }
    }

    final fechaInicio = borrador.fechaInicio;
    if (fechaInicio == null) {
      errores.add(const ErrorCampoServicio(campo: CampoServicio.fechaInicio, codigo: CodigoErrorServicio.requerido));
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }

    String? vacioANull(String? valor) {
      final recortado = valor?.trim();
      return (recortado == null || recortado.isEmpty) ? null : recortado;
    }

    return (
      resultado: ServicioValidado(
        nombre: nombre,
        tipoServicioId: tipoServicioId,
        fechaInicio: fechaInicio!,
        observaciones: vacioANull(borrador.observaciones),
        referenciaComercial: vacioANull(borrador.referenciaComercial),
        referenciaContractual: vacioANull(borrador.referenciaContractual),
      ),
      errores: const <ErrorCampoServicio>[],
    );
  }
}
