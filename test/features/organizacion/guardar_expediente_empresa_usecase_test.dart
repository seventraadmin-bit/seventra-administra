import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_expediente_empresa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_expediente_empresa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_empresa_activa_usecase.dart';

const _datosGeneralesValidos = EmpresaDatosGeneralesInput(nombreComercial: 'Seguridad Privada RISEG');

const _direccionValida = DireccionFiscalBorrador(
  calle: 'Av. Insurgentes',
  numeroExterior: '123',
  colonia: 'Roma Norte',
  municipioAlcaldia: 'Cuauhtémoc',
  estado: 'Ciudad de México',
  codigoPostal: '06700',
);

const _contactoValido = MedioContactoBorrador(
  telefono: '55 1234 5678',
  correo: 'contacto@riseg.mx',
  sitioWeb: 'https://www.riseg.mx',
);

void main() {
  late AppDatabase db;
  late GuardarExpedienteEmpresaUseCase guardar;
  late ObtenerExpedienteEmpresaUseCase obtener;
  late String empresaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final repo = EmpresaRepositoryImpl(db);
    guardar = GuardarExpedienteEmpresaUseCase(repo);
    obtener = ObtenerExpedienteEmpresaUseCase(ObtenerEmpresaActivaUseCase(repo), repo);
    empresaId = (await repo.obtenerActiva()).id;
  });

  tearDown(() => db.close());

  test('guarda datos generales, dirección y contacto válidos en una sola operación', () async {
    final resultado = await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        direccionFiscal: _direccionValida,
        medioContacto: _contactoValido,
      ),
    );

    expect(resultado, isA<GuardarExpedienteExitoso>());
    final datos = (resultado as GuardarExpedienteExitoso).datos;
    expect(datos.direccionFiscal?.calle, 'Av. Insurgentes');
    expect(datos.medioContacto?.correo, 'contacto@riseg.mx');
  });

  test('dirección vacía no crea ninguna fila', () async {
    final resultado = await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(datosGenerales: _datosGeneralesValidos),
    );

    expect(resultado, isA<GuardarExpedienteExitoso>());
    final datos = (resultado as GuardarExpedienteExitoso).datos;
    expect(datos.direccionFiscal, isNull);
    expect(datos.medioContacto, isNull);
  });

  test('dirección parcial reporta todos los campos requeridos faltantes de una vez', () async {
    final resultado = await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        direccionFiscal: DireccionFiscalBorrador(calle: 'Av. Insurgentes'),
      ),
    );

    expect(resultado, isA<GuardarExpedienteErroresValidacion>());
    final errores = (resultado as GuardarExpedienteErroresValidacion).errores;
    final campos = errores.map((e) => e.campo).toSet();
    expect(
      campos,
      containsAll(<CampoExpediente>{
        CampoExpediente.numeroExterior,
        CampoExpediente.colonia,
        CampoExpediente.municipioAlcaldia,
        CampoExpediente.estado,
        CampoExpediente.codigoPostal,
      }),
    );
  });

  test('código postal mexicano debe tener exactamente 5 dígitos', () async {
    final resultado = await guardar.ejecutar(
      empresaId: empresaId,
      input: EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        direccionFiscal: _direccionValida.copyWithCp('123'),
      ),
    );

    expect(resultado, isA<GuardarExpedienteErroresValidacion>());
    final errores = (resultado as GuardarExpedienteErroresValidacion).errores;
    expect(
      errores.any(
        (e) => e.campo == CampoExpediente.codigoPostal && e.codigo == CodigoErrorCampo.formatoInvalido,
      ),
      isTrue,
    );
  });

  test('la regla de 5 dígitos no aplica si el país no es México', () async {
    final resultado = await guardar.ejecutar(
      empresaId: empresaId,
      input: EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        direccionFiscal: _direccionValida.copyWithPaisYCp('Estados Unidos', '90210'),
      ),
    );

    expect(resultado, isA<GuardarExpedienteExitoso>());
  });

  test('RFC con formato inválido se rechaza', () async {
    final resultado = await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(
        datosGenerales: EmpresaDatosGeneralesInput(nombreComercial: 'RISEG', rfc: 'CORTO'),
      ),
    );

    expect(resultado, isA<GuardarExpedienteErroresValidacion>());
    final errores = (resultado as GuardarExpedienteErroresValidacion).errores;
    expect(errores.any((e) => e.campo == CampoExpediente.rfc), isTrue);
  });

  test('correo con formato inválido se rechaza', () async {
    final resultado = await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        medioContacto: MedioContactoBorrador(correo: 'no-es-un-correo'),
      ),
    );

    expect(resultado, isA<GuardarExpedienteErroresValidacion>());
    final errores = (resultado as GuardarExpedienteErroresValidacion).errores;
    expect(errores.any((e) => e.campo == CampoExpediente.correo), isTrue);
  });

  test('sitio web acepta con o sin https://', () async {
    final r1 = await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        medioContacto: MedioContactoBorrador(sitioWeb: 'riseg.mx'),
      ),
    );
    expect(r1, isA<GuardarExpedienteExitoso>());

    final r2 = await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        medioContacto: MedioContactoBorrador(sitioWeb: 'https://www.riseg.mx/contacto'),
      ),
    );
    expect(r2, isA<GuardarExpedienteExitoso>());
  });

  test('teléfono se normaliza quitando espacios accidentales', () async {
    final resultado = await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        medioContacto: MedioContactoBorrador(telefono: '  55   1234    5678  '),
      ),
    );

    expect(resultado, isA<GuardarExpedienteExitoso>());
    final datos = (resultado as GuardarExpedienteExitoso).datos;
    expect(datos.medioContacto?.telefono, '55 1234 5678');
  });

  test('ObtenerExpedienteEmpresaUseCase refleja lo guardado', () async {
    await guardar.ejecutar(
      empresaId: empresaId,
      input: const EmpresaExpedienteInput(
        datosGenerales: _datosGeneralesValidos,
        direccionFiscal: _direccionValida,
        medioContacto: _contactoValido,
      ),
    );

    final resultado = await obtener.ejecutar();
    expect(resultado.isOk, isTrue);
    resultado.when(
      ok: (datos) {
        expect(datos.direccionFiscal?.colonia, 'Roma Norte');
        expect(datos.medioContacto?.telefono, '55 1234 5678');
      },
      failure: (_) => fail('no debería fallar'),
    );
  });
}

extension on DireccionFiscalBorrador {
  DireccionFiscalBorrador copyWithCp(String cp) => DireccionFiscalBorrador(
        calle: calle,
        numeroExterior: numeroExterior,
        numeroInterior: numeroInterior,
        colonia: colonia,
        municipioAlcaldia: municipioAlcaldia,
        ciudadLocalidad: ciudadLocalidad,
        estado: estado,
        codigoPostal: cp,
        pais: pais,
        referencias: referencias,
      );

  DireccionFiscalBorrador copyWithPaisYCp(String pais, String cp) => DireccionFiscalBorrador(
        calle: calle,
        numeroExterior: numeroExterior,
        numeroInterior: numeroInterior,
        colonia: colonia,
        municipioAlcaldia: municipioAlcaldia,
        ciudadLocalidad: ciudadLocalidad,
        estado: estado,
        codigoPostal: cp,
        pais: pais,
        referencias: referencias,
      );
}
