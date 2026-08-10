import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/domain/usecases/ficha_tecnica_data.dart';

EmpleadoData _empleado({
  String nombres = 'Juan',
  String apellidoPaterno = 'Pérez',
  String? apellidoMaterno,
  DateTime? fechaNacimiento,
  int aniosExperienciaSeguridad = 5,
  int? mesesExperienciaAdicionales,
  String? ultimoPuestoDesempenado,
  String? resumenExperiencia,
  String? fotografiaAttachmentId,
  String? telefono,
  String? contactoEmergenciaNombre,
  String? telefonoEmergencia,
  String? parentescoEmergencia,
  DateTime? fechaEvaluacionPsicologica,
  String? resumenPsicologico,
  DateTime? fechaEstudioSocioeconomico,
  String? resumenEstudioSocioeconomico,
  DateTime? fechaAntidoping,
  String? resultadoAmp,
  String? resultadoBzd,
  String? resultadoCoc,
  String? resultadoMet,
  String? resultadoOpi,
}) {
  final ahora = DateTime(2026, 1, 1);
  return EmpleadoData(
    id: 'empleado-1',
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    numeroEmpleado: 1,
    fotografiaAttachmentId: fotografiaAttachmentId,
    nombres: nombres,
    apellidoPaterno: apellidoPaterno,
    apellidoMaterno: apellidoMaterno,
    sexo: 'masculino',
    fechaNacimiento: fechaNacimiento ?? DateTime(1990, 1, 1),
    curp: 'PEXJ900101HDFXXX01',
    rfc: 'PEXJ900101AB1',
    nss: '12345678901',
    estadoCivil: 'soltero',
    nacionalidad: 'Mexicana',
    telefono: telefono,
    contactoEmergenciaNombre: contactoEmergenciaNombre,
    telefonoEmergencia: telefonoEmergencia,
    parentescoEmergencia: parentescoEmergencia,
    fechaIngreso: DateTime(2020, 1, 1),
    estatus: 'activo',
    aniosExperienciaSeguridad: aniosExperienciaSeguridad,
    mesesExperienciaAdicionales: mesesExperienciaAdicionales,
    ultimoPuestoDesempenado: ultimoPuestoDesempenado,
    resumenExperiencia: resumenExperiencia,
    fechaEvaluacionPsicologica: fechaEvaluacionPsicologica,
    resumenPsicologico: resumenPsicologico,
    fechaEstudioSocioeconomico: fechaEstudioSocioeconomico,
    resumenEstudioSocioeconomico: resumenEstudioSocioeconomico,
    fechaAntidoping: fechaAntidoping,
    resultadoAmp: resultadoAmp,
    resultadoBzd: resultadoBzd,
    resultadoCoc: resultadoCoc,
    resultadoMet: resultadoMet,
    resultadoOpi: resultadoOpi,
  );
}

DireccionData _domicilio({String colonia = 'Del Valle', String municipio = 'Toluca', String estado = 'Estado de México'}) {
  final ahora = DateTime(2026, 1, 1);
  return DireccionData(
    id: 'direccion-1',
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    tipoDireccion: 'domicilio',
    esPrincipal: true,
    calle: 'Calle Real',
    numeroExterior: '123',
    colonia: colonia,
    municipioAlcaldia: municipio,
    estado: estado,
    codigoPostal: '50000',
    pais: 'México',
  );
}

void main() {
  group('construirFichaTecnicaData — núcleo', () {
    test('arma nombre completo con apellido materno cuando existe', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(nombres: 'Ana', apellidoPaterno: 'García', apellidoMaterno: 'López'),
        seccionesExcluidas: const {},
      );
      expect(data.nombreCompleto, 'Ana García López');
    });

    test('omite el apellido materno cuando no existe', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(nombres: 'Ana', apellidoPaterno: 'García'),
        seccionesExcluidas: const {},
      );
      expect(data.nombreCompleto, 'Ana García');
    });

    test('calcula la edad a partir de la fecha de nacimiento', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(fechaNacimiento: DateTime(1990, 6, 15)),
        seccionesExcluidas: const {},
      );
      expect(data.edad, greaterThan(0));
    });

    test('nunca incluye antigüedad, RFC, CURP, NSS ni datos administrativos (no existen como campos)', () {
      final data = construirFichaTecnicaData(empleado: _empleado(), seccionesExcluidas: const {});
      // La aserción real es de compilación: `FichaTecnicaData` no declara
      // esos campos. Esto solo confirma que el resto del contenido sigue
      // armándose con normalidad.
      expect(data.nombreCompleto, isNotEmpty);
    });
  });

  group('construirFichaTecnicaData — experiencia', () {
    test('incluye último puesto y resumen cuando existen', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(ultimoPuestoDesempenado: 'Guardia', resumenExperiencia: 'Experiencia en centros comerciales'),
        seccionesExcluidas: const {},
      );
      expect(data.ultimoPuestoDesempenado, 'Guardia');
      expect(data.resumenExperiencia, 'Experiencia en centros comerciales');
    });

    test('omite último puesto y resumen cuando no existen', () {
      final data = construirFichaTecnicaData(empleado: _empleado(), seccionesExcluidas: const {});
      expect(data.ultimoPuestoDesempenado, isNull);
      expect(data.resumenExperiencia, isNull);
    });
  });

  group('construirFichaTecnicaData — fotografía', () {
    test('incluye el id del Attachment cuando existe y no está excluida', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(fotografiaAttachmentId: 'attachment-foto'),
        seccionesExcluidas: const {},
      );
      expect(data.fotografiaAttachmentId, 'attachment-foto');
    });

    test('se omite si el Empleado no tiene fotografía capturada', () {
      final data = construirFichaTecnicaData(empleado: _empleado(), seccionesExcluidas: const {});
      expect(data.fotografiaAttachmentId, isNull);
    });

    test('se omite si está excluida aunque exista', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(fotografiaAttachmentId: 'attachment-foto'),
        seccionesExcluidas: {SeccionFichaTecnica.fotografia},
      );
      expect(data.fotografiaAttachmentId, isNull);
    });
  });

  group('construirFichaTecnicaData — zona de residencia', () {
    test('arma colonia, municipio y estado únicamente (nunca calle/número)', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(),
        domicilio: _domicilio(colonia: 'Roma Norte', municipio: 'Cuauhtémoc', estado: 'Ciudad de México'),
        seccionesExcluidas: const {},
      );
      expect(data.zonaResidencia, 'Roma Norte, Cuauhtémoc, Ciudad de México');
      expect(data.zonaResidencia, isNot(contains('Calle Real')));
      expect(data.zonaResidencia, isNot(contains('123')));
    });

    test('se omite si no hay domicilio capturado', () {
      final data = construirFichaTecnicaData(empleado: _empleado(), seccionesExcluidas: const {});
      expect(data.zonaResidencia, isNull);
    });

    test('se omite si está excluida aunque exista domicilio', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(),
        domicilio: _domicilio(),
        seccionesExcluidas: {SeccionFichaTecnica.zonaResidencia},
      );
      expect(data.zonaResidencia, isNull);
    });
  });

  group('construirFichaTecnicaData — contacto', () {
    test('incluye teléfono y contacto de emergencia juntos cuando existen', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(
          telefono: '5555555555',
          contactoEmergenciaNombre: 'María Pérez',
          telefonoEmergencia: '5555555556',
          parentescoEmergencia: 'Madre',
        ),
        seccionesExcluidas: const {},
      );
      expect(data.telefono, '5555555555');
      expect(data.contactoEmergenciaNombre, 'María Pérez');
      expect(data.tieneContacto, isTrue);
    });

    test('excluir "contacto" oculta teléfono y datos de emergencia juntos', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(telefono: '5555555555', contactoEmergenciaNombre: 'María Pérez'),
        seccionesExcluidas: {SeccionFichaTecnica.contacto},
      );
      expect(data.telefono, isNull);
      expect(data.contactoEmergenciaNombre, isNull);
      expect(data.tieneContacto, isFalse);
    });

    test('tieneContacto es falso cuando nada está capturado', () {
      final data = construirFichaTecnicaData(empleado: _empleado(), seccionesExcluidas: const {});
      expect(data.tieneContacto, isFalse);
    });
  });

  group('construirFichaTecnicaData — evaluaciones', () {
    test('incluye resumen psicológico solo si tiene fecha de evaluación y resumen', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(fechaEvaluacionPsicologica: DateTime(2025, 1, 1), resumenPsicologico: 'Perfil estable'),
        seccionesExcluidas: const {},
      );
      expect(data.resumenPsicologico, 'Perfil estable');
    });

    test('omite resumen psicológico si nunca se capturó la evaluación', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(resumenPsicologico: 'Perfil estable'),
        seccionesExcluidas: const {},
      );
      expect(data.resumenPsicologico, isNull);
    });

    test('excluir "perfilPsicologico" lo oculta aunque exista', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(fechaEvaluacionPsicologica: DateTime(2025, 1, 1), resumenPsicologico: 'Perfil estable'),
        seccionesExcluidas: {SeccionFichaTecnica.perfilPsicologico},
      );
      expect(data.resumenPsicologico, isNull);
    });

    test('estudio socioeconómico sigue la misma regla que perfil psicológico', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(fechaEstudioSocioeconomico: DateTime(2025, 1, 1), resumenEstudioSocioeconomico: 'Entorno estable'),
        seccionesExcluidas: const {},
      );
      expect(data.resumenEstudioSocioeconomico, 'Entorno estable');
    });
  });

  group('construirFichaTecnicaData — antidoping', () {
    test('lista vacía si nunca se capturó el antidoping', () {
      final data = construirFichaTecnicaData(empleado: _empleado(), seccionesExcluidas: const {});
      expect(data.antidoping, isEmpty);
    });

    test('excluye sustancias en noAplica pero conserva las demás', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(
          fechaAntidoping: DateTime(2025, 1, 1),
          resultadoAmp: 'negativo',
          resultadoBzd: 'noAplica',
          resultadoCoc: 'positivo',
          resultadoMet: 'noAplica',
          resultadoOpi: 'noAplica',
        ),
        seccionesExcluidas: const {},
      );
      expect(data.antidoping.map((r) => r.sustancia), ['AMP', 'COC']);
      expect(data.antidoping.map((r) => r.resultado), ['negativo', 'positivo']);
    });

    test('lista vacía si todas las sustancias evaluadas son noAplica', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(
          fechaAntidoping: DateTime(2025, 1, 1),
          resultadoAmp: 'noAplica',
          resultadoBzd: 'noAplica',
        ),
        seccionesExcluidas: const {},
      );
      expect(data.antidoping, isEmpty);
    });

    test('excluir "antidoping" vacía la lista aunque haya resultados', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(fechaAntidoping: DateTime(2025, 1, 1), resultadoAmp: 'negativo'),
        seccionesExcluidas: {SeccionFichaTecnica.antidoping},
      );
      expect(data.antidoping, isEmpty);
    });
  });

  group('construirFichaTecnicaData — servicio y turno', () {
    test('incluye servicio y turno cuando se proveen y no están excluidos', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(),
        servicioNombre: 'Vigilancia Sportium',
        turnoNombre: '24×24',
        seccionesExcluidas: const {},
      );
      expect(data.servicioNombre, 'Vigilancia Sportium');
      expect(data.turnoNombre, '24×24');
      expect(data.tieneServicioOTurno, isTrue);
    });

    test('excluir "servicioTurno" oculta ambos aunque se provean', () {
      final data = construirFichaTecnicaData(
        empleado: _empleado(),
        servicioNombre: 'Vigilancia Sportium',
        turnoNombre: '24×24',
        seccionesExcluidas: {SeccionFichaTecnica.servicioTurno},
      );
      expect(data.servicioNombre, isNull);
      expect(data.turnoNombre, isNull);
      expect(data.tieneServicioOTurno, isFalse);
    });

    test('tieneServicioOTurno es falso sin asignación vigente', () {
      final data = construirFichaTecnicaData(empleado: _empleado(), seccionesExcluidas: const {});
      expect(data.tieneServicioOTurno, isFalse);
    });
  });
}
