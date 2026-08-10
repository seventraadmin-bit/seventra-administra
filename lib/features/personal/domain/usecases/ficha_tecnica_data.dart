import 'package:riseg_one/core/database/app_database.dart';

import 'calcular_edad.dart';

/// Claves de las secciones **opcionales** de la Ficha técnica (Etapa
/// 5E) — mismo texto que se persiste, separado por comas, en
/// `FichaTecnicaEmpleado.camposExcluidos`. Los datos núcleo (nombre,
/// edad, puesto, experiencia) no tienen clave: nunca son excluibles.
abstract final class SeccionFichaTecnica {
  static const fotografia = 'fotografia';
  static const zonaResidencia = 'zonaResidencia';
  static const contacto = 'contacto';
  static const perfilPsicologico = 'perfilPsicologico';
  static const estudioSocioeconomico = 'estudioSocioeconomico';
  static const antidoping = 'antidoping';
  static const servicioTurno = 'servicioTurno';

  static const todas = [
    fotografia,
    zonaResidencia,
    contacto,
    perfilPsicologico,
    estudioSocioeconomico,
    antidoping,
    servicioTurno,
  ];
}

/// Un resultado de sustancia ya filtrado — `construirFichaTecnicaData`
/// nunca produce una entrada para una sustancia en `noAplica` (ver su
/// doc comment).
class AntidopingFichaTecnica {
  const AntidopingFichaTecnica({required this.sustancia, required this.resultado});

  /// Código de la sustancia (`AMP`/`BZD`/`COC`/`MET`/`OPI`).
  final String sustancia;

  /// `negativo` o `positivo` (nunca `noAplica` — ya filtrado).
  final String resultado;
}

/// Contenido íntegro de una Ficha técnica (Etapa 5E) — el subconjunto
/// reducido y curado del expediente que se comparte con un cliente.
/// Nunca contiene RFC/CURP/NSS/código postal fiscal/antigüedad/estatus
/// laboral/observaciones internas/documentos — ver el doc comment de
/// `construirFichaTecnicaData` para el criterio completo de qué se
/// incluye y qué no.
///
/// Cada campo opcional es `null` (o, para antidoping, una lista vacía)
/// tanto si el expediente no lo tiene capturado como si el usuario lo
/// excluyó explícitamente al generar — el renderizador nunca necesita
/// distinguir el motivo, solo "¿hay algo que mostrar aquí?".
class FichaTecnicaData {
  const FichaTecnicaData({
    required this.nombreCompleto,
    required this.edad,
    this.puestoNombre,
    required this.aniosExperiencia,
    this.mesesExperienciaAdicionales,
    this.ultimoPuestoDesempenado,
    this.resumenExperiencia,
    this.fotografiaAttachmentId,
    this.zonaResidencia,
    this.telefono,
    this.contactoEmergenciaNombre,
    this.telefonoEmergencia,
    this.parentescoEmergencia,
    this.resumenPsicologico,
    this.resumenEstudioSocioeconomico,
    this.antidoping = const [],
    this.servicioNombre,
    this.turnoNombre,
  });

  final String nombreCompleto;
  final int edad;
  final String? puestoNombre;

  final int aniosExperiencia;
  final int? mesesExperienciaAdicionales;
  final String? ultimoPuestoDesempenado;
  final String? resumenExperiencia;

  final String? fotografiaAttachmentId;
  final String? zonaResidencia;

  final String? telefono;
  final String? contactoEmergenciaNombre;
  final String? telefonoEmergencia;
  final String? parentescoEmergencia;

  final String? resumenPsicologico;
  final String? resumenEstudioSocioeconomico;
  final List<AntidopingFichaTecnica> antidoping;

  final String? servicioNombre;
  final String? turnoNombre;

  bool get tieneContacto =>
      telefono != null || contactoEmergenciaNombre != null || telefonoEmergencia != null || parentescoEmergencia != null;

  bool get tieneServicioOTurno => servicioNombre != null || turnoNombre != null;
}

String? _limpio(String? valor) {
  final v = valor?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// Arma el contenido de la Ficha técnica a partir de datos **ya
/// existentes** en el expediente — nunca captura nada nuevo. Cada
/// sección opcional se omite (queda `null`/vacía) si el dato no existe
/// en el expediente **o** si su clave (ver `SeccionFichaTecnica`) está
/// en [seccionesExcluidas].
///
/// Reglas fijas (nunca dependen de [seccionesExcluidas], Resoluciones
/// definitivas de Marlon para la Etapa 5E):
/// - Nunca incluye RFC, CURP, NSS, código postal fiscal, antigüedad,
///   fecha de ingreso, estatus laboral, observaciones internas
///   (`observacionesPsicologico`/`observacionesEstudioSocioeconomico`/
///   `observacionesAntidoping`) ni documentos del expediente.
/// - Antidoping: una sustancia en `noAplica` nunca aparece; si
///   `fechaAntidoping` es `null` (nunca capturado), la lista completa
///   queda vacía sin importar si `antidoping` está excluido o no.
/// - Zona de residencia = colonia + municipio/alcaldía + estado
///   únicamente — nunca calle/número (esos solo viven en el
///   expediente interno).
FichaTecnicaData construirFichaTecnicaData({
  required EmpleadoData empleado,
  DireccionData? domicilio,
  String? puestoNombre,
  String? servicioNombre,
  String? turnoNombre,
  required Set<String> seccionesExcluidas,
}) {
  final excluye = seccionesExcluidas.contains;

  final nombreCompleto = [
    empleado.nombres,
    empleado.apellidoPaterno,
    if (_limpio(empleado.apellidoMaterno) != null) empleado.apellidoMaterno,
  ].join(' ');

  String? zonaResidencia;
  if (domicilio != null && !excluye(SeccionFichaTecnica.zonaResidencia)) {
    zonaResidencia = '${domicilio.colonia}, ${domicilio.municipioAlcaldia}, ${domicilio.estado}';
  }

  final incluyeContacto = !excluye(SeccionFichaTecnica.contacto);

  final incluyePsicologico = !excluye(SeccionFichaTecnica.perfilPsicologico) && empleado.fechaEvaluacionPsicologica != null;
  final incluyeSocioeconomico =
      !excluye(SeccionFichaTecnica.estudioSocioeconomico) && empleado.fechaEstudioSocioeconomico != null;

  var antidoping = const <AntidopingFichaTecnica>[];
  if (!excluye(SeccionFichaTecnica.antidoping) && empleado.fechaAntidoping != null) {
    antidoping = [
      if (empleado.resultadoAmp != null && empleado.resultadoAmp != 'noAplica')
        AntidopingFichaTecnica(sustancia: 'AMP', resultado: empleado.resultadoAmp!),
      if (empleado.resultadoBzd != null && empleado.resultadoBzd != 'noAplica')
        AntidopingFichaTecnica(sustancia: 'BZD', resultado: empleado.resultadoBzd!),
      if (empleado.resultadoCoc != null && empleado.resultadoCoc != 'noAplica')
        AntidopingFichaTecnica(sustancia: 'COC', resultado: empleado.resultadoCoc!),
      if (empleado.resultadoMet != null && empleado.resultadoMet != 'noAplica')
        AntidopingFichaTecnica(sustancia: 'MET', resultado: empleado.resultadoMet!),
      if (empleado.resultadoOpi != null && empleado.resultadoOpi != 'noAplica')
        AntidopingFichaTecnica(sustancia: 'OPI', resultado: empleado.resultadoOpi!),
    ];
  }

  final incluyeServicioTurno = !excluye(SeccionFichaTecnica.servicioTurno);
  final incluyeFotografia = !excluye(SeccionFichaTecnica.fotografia) && empleado.fotografiaAttachmentId != null;

  return FichaTecnicaData(
    nombreCompleto: nombreCompleto,
    edad: calcularEdad(empleado.fechaNacimiento),
    puestoNombre: puestoNombre,
    aniosExperiencia: empleado.aniosExperienciaSeguridad,
    mesesExperienciaAdicionales: empleado.mesesExperienciaAdicionales,
    ultimoPuestoDesempenado: _limpio(empleado.ultimoPuestoDesempenado),
    resumenExperiencia: _limpio(empleado.resumenExperiencia),
    fotografiaAttachmentId: incluyeFotografia ? empleado.fotografiaAttachmentId : null,
    zonaResidencia: zonaResidencia,
    telefono: incluyeContacto ? _limpio(empleado.telefono) : null,
    contactoEmergenciaNombre: incluyeContacto ? _limpio(empleado.contactoEmergenciaNombre) : null,
    telefonoEmergencia: incluyeContacto ? _limpio(empleado.telefonoEmergencia) : null,
    parentescoEmergencia: incluyeContacto ? _limpio(empleado.parentescoEmergencia) : null,
    resumenPsicologico: incluyePsicologico ? _limpio(empleado.resumenPsicologico) : null,
    resumenEstudioSocioeconomico: incluyeSocioeconomico ? _limpio(empleado.resumenEstudioSocioeconomico) : null,
    antidoping: antidoping,
    servicioNombre: incluyeServicioTurno ? servicioNombre : null,
    turnoNombre: incluyeServicioTurno ? turnoNombre : null,
  );
}
