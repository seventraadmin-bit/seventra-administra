import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';

import '../repositories/catalogo_repository.dart';
import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/puesto_repository.dart';
import '../repositories/servicio_repository.dart';
import '../shared/horario_input.dart';
import 'linea_comercial_con_vigencia.dart';
import 'linea_comercial_errors.dart';

/// Condiciones de una línea comercial tal como llegan del formulario de
/// alta o de nueva vigencia — sin validar. `fechaFinVigencia`/
/// `descripcion`/`observaciones` son siempre opcionales; el resto es
/// obligatorio para poder calcular un subtotal con sentido.
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
    this.sueldoMensualReferenciaPersonal,
    this.bonoMensualReferenciaPersonal,
    this.horario,
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

  /// Condiciones de personal de referencia de este perfil (Etapa 15,
  /// rediseño de "Condiciones de Personal") — opcionales, igual que lo
  /// eran como columnas globales de `Servicio`: una línea puede
  /// capturarse antes de tener condición salarial definida. En
  /// centavos.
  final int? sueldoMensualReferenciaPersonal;
  final int? bonoMensualReferenciaPersonal;

  /// Horario personalizado (Etapa 15, "Modalidad de turno:
  /// Personalizado") — solo relevante cuando `modalidadTurnoId` es la
  /// modalidad Personalizado; se ignora (nunca se persiste) si la
  /// modalidad es cualquier otra, aunque el formulario todavía tenga
  /// datos capturados de un cambio de modalidad previo.
  final HorarioSemanalBorrador? horario;
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
    this.sueldoMensualReferenciaPersonal,
    this.bonoMensualReferenciaPersonal,
    this.horario,
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
  final int? sueldoMensualReferenciaPersonal;
  final int? bonoMensualReferenciaPersonal;

  /// `null` salvo cuando `modalidadTurnoId` es la modalidad
  /// Personalizado — ya validado y normalizado, listo para persistir.
  final HorarioSemanalInput? horario;
}

/// Validación compartida de una condición comercial — usada tanto por
/// el alta (Etapa 4G.1) como por la nueva vigencia (Etapa 4G.2), nunca
/// duplicada (mismo motivo que `ServicioValidator`/`PuestoValidator`).
class LineaComercialValidator {
  LineaComercialValidator(
    this._puestoRepository,
    this._catalogoRepository,
    this._servicioRepository,
    this._configuracionCobroRepository,
  );

  final PuestoRepository _puestoRepository;
  final CatalogoRepository _catalogoRepository;
  final ServicioRepository _servicioRepository;
  final ConfiguracionCobroRepository _configuracionCobroRepository;

  /// Validación cruzada contra la Configuración de cobro vigente del
  /// Servicio (Etapa 4H.1, Resoluciones D y G) — la misma pareja de
  /// reglas vive en `ConfiguracionCobroValidator`, aplicada en sentido
  /// inverso; cualquier cambio a una debe revisar la otra.
  Future<List<ErrorLineaComercial>> _validarCompatibilidadConfiguracionCobro({
    required String servicioId,
    required TratamientoIva? tratamientoIva,
  }) async {
    if (tratamientoIva == null) return const [];

    final configuracion = await _configuracionCobroRepository.obtenerConfiguracion(servicioId);
    final vigente = configuracion?.vigenciaActual;
    if (vigente == null) return const [];

    final tipoDocumento = TipoDocumentoCobro.values.byName(vigente.tipoDocumento);
    final incompatible = (tipoDocumento == TipoDocumentoCobro.cfdi && tratamientoIva == TratamientoIva.noAplica) ||
        (tipoDocumento == TipoDocumentoCobro.reciboDePago && tratamientoIva != TratamientoIva.noAplica);

    if (!incompatible) return const [];
    return const [
      ErrorLineaComercial(
        campo: CampoLineaComercial.tratamientoIva,
        codigo: CodigoErrorLineaComercial.ivaIncompatibleConfiguracionCobro,
      ),
    ];
  }

  /// Puesto/modalidad/cantidad/precio/IVA — idénticos entre alta y
  /// nueva vigencia. Las reglas de fecha difieren (nueva vigencia
  /// también debe evitar fechas duplicadas y solapamientos con
  /// vigencias ya registradas), así que viven en cada método público.
  Future<List<ErrorLineaComercial>> _validarCondicionesBase(LineaComercialBorrador borrador) async {
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

    // Sueldo/bono de referencia (Etapa 15) — opcionales, igual que lo
    // eran a nivel de Servicio: solo se validan cuando sí se capturan.
    final sueldo = borrador.sueldoMensualReferenciaPersonal;
    if (sueldo != null && sueldo <= 0) {
      errores.add(
        const ErrorLineaComercial(
          campo: CampoLineaComercial.sueldoMensualReferenciaPersonal,
          codigo: CodigoErrorLineaComercial.invalido,
        ),
      );
    }
    final bono = borrador.bonoMensualReferenciaPersonal;
    if (bono != null && bono < 0) {
      errores.add(
        const ErrorLineaComercial(
          campo: CampoLineaComercial.bonoMensualReferenciaPersonal,
          codigo: CodigoErrorLineaComercial.invalido,
        ),
      );
    }

    return errores;
  }

  /// Horario personalizado (Etapa 15) — solo se valida/persiste cuando
  /// `modalidadTurnoId` es la modalidad Personalizado; para cualquier
  /// otra modalidad se ignora sin error, aunque el formulario todavía
  /// traiga datos capturados de un cambio de modalidad previo (evita
  /// "basura inválida" al cambiar de Personalizado a otra modalidad).
  ({HorarioSemanalInput? resultado, List<ErrorLineaComercial> errores}) _validarHorarioSiAplica(
    LineaComercialBorrador borrador,
  ) {
    if (borrador.modalidadTurnoId.trim() != SeedIds.modalidadTurnoPersonalizado) {
      return (resultado: null, errores: const []);
    }
    final horarioBorrador = borrador.horario;
    if (horarioBorrador == null) {
      return (
        resultado: null,
        errores: const [
          ErrorLineaComercial(campo: CampoLineaComercial.horario, codigo: CodigoErrorLineaComercial.requerido),
        ],
      );
    }

    final validacion = validarHorarioSemanal(horarioBorrador);
    return (
      resultado: validacion.resultado,
      errores: [
        for (final e in validacion.errores)
          ErrorLineaComercial(
            campo: CampoLineaComercial.horario,
            codigo: switch (e.codigo) {
              CodigoErrorHorario.horaInicioRequerida => CodigoErrorLineaComercial.horarioHoraInicioRequerida,
              CodigoErrorHorario.horaFinRequerida => CodigoErrorLineaComercial.horarioHoraFinRequerida,
              CodigoErrorHorario.horasIguales => CodigoErrorLineaComercial.horarioHorasIguales,
            },
            diaSemana: e.dia.index,
          ),
      ],
    );
  }

  String? _vacioANull(String? valor) {
    final recortado = valor?.trim();
    return (recortado == null || recortado.isEmpty) ? null : recortado;
  }

  LineaComercialValidada _normalizar(LineaComercialBorrador borrador, HorarioSemanalInput? horario) {
    return LineaComercialValidada(
      puestoId: borrador.puestoId.trim(),
      modalidadTurnoId: borrador.modalidadTurnoId.trim(),
      cantidadElementos: borrador.cantidadElementos!,
      precioUnitario: borrador.precioUnitario!,
      tratamientoIva: borrador.tratamientoIva!,
      fechaInicioVigencia: borrador.fechaInicioVigencia!,
      descripcion: _vacioANull(borrador.descripcion),
      fechaFinVigencia: borrador.fechaFinVigencia,
      observaciones: _vacioANull(borrador.observaciones),
      sueldoMensualReferenciaPersonal: borrador.sueldoMensualReferenciaPersonal,
      bonoMensualReferenciaPersonal: borrador.bonoMensualReferenciaPersonal,
      horario: horario,
    );
  }

  Future<({LineaComercialValidada? resultado, List<ErrorLineaComercial> errores})> validar({
    required String servicioId,
    required LineaComercialBorrador borrador,
  }) async {
    final errores = await _validarCondicionesBase(borrador);
    errores.addAll(
      await _validarCompatibilidadConfiguracionCobro(servicioId: servicioId, tratamientoIva: borrador.tratamientoIva),
    );
    final horario = _validarHorarioSiAplica(borrador);
    errores.addAll(horario.errores);

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
    return (resultado: _normalizar(borrador, horario.resultado), errores: const <ErrorLineaComercial>[]);
  }

  /// Validación de una nueva vigencia sobre una línea ya existente
  /// (Etapa 4G.2) — mismas condiciones base que el alta, más las reglas
  /// de encadenamiento: sin fecha retroactiva sin confirmar (esa
  /// confirmación vive en la UI, no aquí — ver Resolución H), sin fecha
  /// de inicio duplicada, y sin que una fecha de fin capturada a mano
  /// se solape con una vigencia posterior ya registrada.
  ///
  /// Recibe `vigenciasExistentes` ya resueltas por el llamador (todas
  /// las vigencias `activo` de la línea) para no acoplar este validador
  /// a `ServicioComercialRepository` — el caso de uso ya las necesita de
  /// todas formas para calcular la predecesora/sucesora.
  Future<({LineaComercialValidada? resultado, List<ErrorLineaComercial> errores})> validarNuevaVigencia({
    required String servicioId,
    required LineaComercialBorrador borrador,
    required List<ServicioLineaComercialVigenciaData> vigenciasExistentes,
  }) async {
    final errores = await _validarCondicionesBase(borrador);
    errores.addAll(
      await _validarCompatibilidadConfiguracionCobro(servicioId: servicioId, tratamientoIva: borrador.tratamientoIva),
    );
    final horario = _validarHorarioSiAplica(borrador);
    errores.addAll(horario.errores);

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
      } else if (vigenciasExistentes.any((v) => soloFecha(v.fechaInicioVigencia) == soloFecha(fechaInicioVigencia))) {
        errores.add(
          const ErrorLineaComercial(
            campo: CampoLineaComercial.fechaInicioVigencia,
            codigo: CodigoErrorLineaComercial.fechaDuplicada,
          ),
        );
      }

      final fechaFinVigencia = borrador.fechaFinVigencia;
      if (fechaFinVigencia != null) {
        final inicioSinHora = soloFecha(fechaInicioVigencia);
        final sucesoraMasProxima = vigenciasExistentes
            .where((v) => soloFecha(v.fechaInicioVigencia).isAfter(inicioSinHora))
            .fold<ServicioLineaComercialVigenciaData?>(
              null,
              (masProxima, v) => masProxima == null || v.fechaInicioVigencia.isBefore(masProxima.fechaInicioVigencia)
                  ? v
                  : masProxima,
            );
        if (sucesoraMasProxima != null &&
            !soloFecha(fechaFinVigencia).isBefore(soloFecha(sucesoraMasProxima.fechaInicioVigencia))) {
          errores.add(
            const ErrorLineaComercial(
              campo: CampoLineaComercial.fechaFinVigencia,
              codigo: CodigoErrorLineaComercial.solapamiento,
            ),
          );
        }
      }
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }
    return (resultado: _normalizar(borrador, horario.resultado), errores: const <ErrorLineaComercial>[]);
  }
}
