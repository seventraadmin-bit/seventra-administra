import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import 'configuracion_cobro_con_vigencia.dart';
import 'linea_comercial_con_vigencia.dart';
import 'personal_asignado_servicio.dart';

/// Servicio junto con todo lo que su expediente necesita mostrar: el
/// Cliente propietario (solo lectura, relación inmutable), si ya tiene
/// una Dirección operativa activa (y la propia Dirección, si existe), y
/// sus 3 vinculaciones opcionales (Entidad fiscal, Responsable del
/// Cliente, Sucursal administrativa) — cada una acompañada de si el
/// registro relacionado sigue activo, para que el expediente pueda
/// mostrar una advertencia sin desvincular nada automáticamente (Etapa
/// 4F.2, "las relaciones no se desvinculan solas cuando lo asignado se
/// archiva después").
///
/// `tieneDireccionOperativaActiva` decide cómo se muestra "Activar"
/// (deshabilitado + indicación "Disponible al completar la Dirección
/// operativa", punto 3 de la aprobación de la Etapa 4F.1) — durante
/// toda la 4F.1 era siempre `false`; desde la 4F.2, con la captura de
/// Dirección ya construida, puede ser `true`.
class ServicioExpedienteData {
  const ServicioExpedienteData({
    required this.servicio,
    required this.cliente,
    required this.tieneDireccionOperativaActiva,
    required this.lineasComerciales,
    this.direccionOperativa,
    this.entidadFiscal,
    this.responsableCliente,
    this.sucursalAdministrativa,
    this.configuracionCobro,
    this.personalAsignado = const [],
  });

  final ServicioData servicio;
  final ClienteData cliente;
  final bool tieneDireccionOperativaActiva;
  final DireccionData? direccionOperativa;
  final EntidadFiscalData? entidadFiscal;
  final ContactoData? responsableCliente;
  final SucursalData? sucursalAdministrativa;

  /// Configuración comercial (Etapa 4G.1) — cada línea ya resuelta
  /// contra la fecha de hoy (vigente/programadas).
  final List<LineaComercialConVigencia> lineasComerciales;

  /// Configuración de cobro (Etapa 4H.1) — `null` si el Servicio todavía
  /// no tiene ninguna capturada.
  final ConfiguracionCobroConVigencia? configuracionCobro;

  /// Historial completo de personal asignado a este Servicio (Etapa
  /// 5D) — vigente + cerrado, orden descendente por fecha de inicio.
  /// Solo consulta: `Servicio` nunca escribe aquí, todas las acciones
  /// se disparan desde el expediente del Empleado.
  final List<PersonalAsignadoServicio> personalAsignado;

  /// Subconjunto vigente de `personalAsignado` — nunca una consulta
  /// aparte, se deriva de la misma lista (Resolución explícita de
  /// Marlon: "no duplicar información").
  List<PersonalAsignadoServicio> get personalVigente => personalAsignado.where((p) => p.vigente).toList();

  /// Suma de `cantidad × precio` de la vigencia vigente de cada línea —
  /// nunca mezcla tratamientos de IVA distintos (Etapa 4G.1, Resolución
  /// B): es un subtotal comercial, no un total financiero. El cálculo
  /// completo con IVA queda para la futura Configuración de cobro.
  int get subtotalComercial => lineasComerciales.fold(0, (acc, l) => acc + l.subtotal);

  /// `true` si las líneas comerciales usan más de un tratamiento de IVA
  /// distinto entre sí — la pantalla lo usa para mostrar que el IVA se
  /// calcula por línea, nunca de forma agregada.
  bool get ivaVariaPorLinea =>
      lineasComerciales.map((l) => l.vigenciaActual?.tratamientoIva).toSet().length > 1;

  /// Suma de `cantidadElementos` de la vigencia vigente de cada línea —
  /// "elementos comerciales vigentes hoy" (Etapa 4G.2), independiente de
  /// `Servicio.elementosAutorizados`.
  int get elementosComercialesVigentes =>
      lineasComerciales.fold(0, (acc, l) => acc + (l.vigenciaActual?.cantidadElementos ?? 0));

  /// `true` si los elementos según Configuración comercial no coinciden
  /// con `elementosAutorizados` — Etapa 4G.1, Resolución E: nunca se
  /// sincronizan automáticamente, solo se advierte la diferencia.
  bool get elementosDifierenDeAutorizados => elementosComercialesVigentes != servicio.elementosAutorizados;

  /// `true` si alguna línea tiene al menos una vigencia programada a
  /// futuro — aviso agregado a nivel de expediente (Etapa 4G.2).
  bool get tieneVigenciasProgramadas => lineasComerciales.any((l) => l.vigenciasProgramadas.isNotEmpty);

  /// La fecha de inicio más próxima entre todas las vigencias
  /// programadas de todas las líneas — `null` si no hay ninguna.
  DateTime? get proximaFechaProgramada {
    DateTime? proxima;
    for (final linea in lineasComerciales) {
      for (final v in linea.vigenciasProgramadas) {
        if (proxima == null || v.fechaInicioVigencia.isBefore(proxima)) {
          proxima = v.fechaInicioVigencia;
        }
      }
    }
    return proxima;
  }

  bool get entidadFiscalArchivada =>
      entidadFiscal != null && entidadFiscal!.cicloVidaRegistro != CicloVidaRegistro.activo.name;

  bool get responsableClienteArchivado =>
      responsableCliente != null && responsableCliente!.cicloVidaRegistro != CicloVidaRegistro.activo.name;

  bool get sucursalAdministrativaArchivada =>
      sucursalAdministrativa != null && sucursalAdministrativa!.cicloVidaRegistro != CicloVidaRegistro.activo.name;
}
