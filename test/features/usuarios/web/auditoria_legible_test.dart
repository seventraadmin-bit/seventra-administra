import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' as apartados;
import 'package:riseg_one/features/usuarios/web/modelos/evento_de_auditoria.dart';
import 'package:riseg_one/features/usuarios/web/presentation/auditoria_legible.dart';

/// La auditoría dicha en español.
///
/// ## La prueba que de verdad protege esto es la ÚLTIMA
///
/// «El vocabulario cubre todas las entidades auditadas» recorre el inventario de
/// claves que el servidor escribe hoy y exige que **cada una tenga etiqueta propia**.
/// Si alguien añade un campo a un registro y no lo traduce, esa prueba falla con el
/// nombre del campo. Las demás comprueban que la traducción dice lo correcto; ésa
/// comprueba que no falta ninguna.
///
/// Su gemela vive en el backend —`AuditPayloadVocabularyTests`— y mide las claves
/// **reales** ejecutando las operaciones contra una base de verdad. Las dos juntas
/// cierran el círculo: el backend descubre una clave nueva, y aquí se exige su
/// etiqueta.
void main() {
  // Sin nombres ni catálogo: así se ve lo que la clase puede decir sola.
  const pelado = AuditoriaLegible(nombrePorIdentidad: {}, nombrePorPermiso: {});

  const conDatos = AuditoriaLegible(
    nombrePorIdentidad: {'01a15071-0001-7000-8000-000000000001': 'Juan Pérez'},
    nombrePorPermiso: {'personal.sueldo.ver': 'Ver sueldo'},
  );

  EventoDeAuditoria evento({
    required String entidad,
    required String accion,
    String? antes,
    String? despues,
    String? motivo,
    String tipoDeActor = 'identity',
    String? actor = '01a15071-0001-7000-8000-000000000001',
  }) => EventoDeAuditoria(
    id: 'ev-1',
    tipoDeActor: tipoDeActor,
    identidadDelActor: actor,
    tipoDeEntidad: entidad,
    entidadId: 'ent-1',
    accion: accion,
    antes: antes,
    despues: despues,
    motivo: motivo,
    cuando: DateTime.utc(2026, 10, 18, 19, 45),
  );

  group('El título nombra el objeto', () {
    test('«Creó el área MON · Monitoreo»: el CÓDIGO y el nombre, los dos', () {
      // ⚠️ ESTA PRUEBA AFIRMABA SÓLO EL NOMBRE, y se cambió el 20 de octubre de 2026
      // porque se vio en pantalla: el servidor ya mandaba los dos —se arregló para que
      // las transiciones de la sucursal dijeran cuál— y la pantalla seguía mostrando
      // sólo el nombre. La mitad del arreglo estaba hecha y la otra no.
      //
      // EL CÓDIGO ES LO QUE LA PERSONA BUSCA Y RECONOCE: es lo que ve en los listados
      // y en los documentos, y dos sucursales pueden llamarse parecido.
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"code":"MON","name":"Monitoreo","status":"activa"}',
      );

      expect(pelado.titulo(e), 'Creó el área MON · Monitoreo');
    });

    test('con sólo uno de los dos, no queda un « · » colgando', () {
      // LA EMPRESA TIENE NOMBRE Y NO TIENE CÓDIGO, así que un formato fijo dejaría
      // «Cambió la empresa · RISEG». Y al revés también: un registro con código y sin
      // nombre debe decir el código, no media frase.
      final soloNombre = evento(
        entidad: 'company',
        accion: 'updated',
        despues: '{"name":"RISEG"}',
      );

      final soloCodigo = evento(
        entidad: 'area',
        accion: 'deleted',
        antes: '{"code":"SOBRA"}',
      );

      expect(pelado.titulo(soloNombre), 'Cambió la empresa RISEG');
      expect(pelado.titulo(soloCodigo), contains('SOBRA'));
      expect(pelado.titulo(soloCodigo), isNot(contains('·')));
    });

    test('con el género correcto de cada objeto', () {
      // «el sucursal» es justo el detalle que hace que una pantalla parezca
      // traducida a máquina.
      final sucursal = evento(
        entidad: 'branch',
        accion: 'created',
        despues: '{"name":"Centro"}',
      );
      final puesto = evento(
        entidad: 'position',
        accion: 'updated',
        antes: '{"name":"Supervisor"}',
        despues: '{"name":"Supervisor general"}',
      );

      expect(pelado.titulo(sucursal), 'Creó la sucursal Centro');
      expect(pelado.titulo(puesto), 'Cambió el puesto Supervisor general');
    });

    test('un cambio de estado se dice «Desactivó», no «Cambió el estado»', () {
      // Quien lo lee quiere saber qué pasó, no qué columna se tocó.
      final apagada = evento(
        entidad: 'area',
        accion: 'status_changed',
        antes: '{"status":"activa"}',
        despues: '{"name":"Monitoreo","status":"inactiva"}',
      );

      expect(pelado.titulo(apagada), 'Desactivó el área Monitoreo');

      final encendida = evento(
        entidad: 'area',
        accion: 'status_changed',
        antes: '{"status":"inactiva"}',
        despues: '{"name":"Monitoreo","status":"activa"}',
      );

      expect(pelado.titulo(encendida), 'Activó el área Monitoreo');
    });

    test('un acceso se cuenta en PERSONAS y usa su nombre', () {
      final dado = evento(
        entidad: 'company_access',
        accion: 'granted',
        despues:
            '{"role":"user","subjectIdentityId":"01a15071-0001-7000-8000-000000000001"}',
      );

      expect(conDatos.titulo(dado), 'Dio acceso a Juan Pérez');

      final quitado = evento(
        entidad: 'company_access',
        accion: 'revoked',
        antes:
            '{"role":"user","status":"activa","subjectIdentityId":"01a15071-0001-7000-8000-000000000001"}',
        despues: '{"status":"revocada"}',
      );

      expect(conDatos.titulo(quitado), 'Quitó el acceso a Juan Pérez');
    });

    test('un permiso se nombra con el nombre del CATÁLOGO', () {
      final e = evento(
        entidad: 'company_access_permission',
        accion: 'granted',
        despues: '{"permission":"personal.sueldo.ver"}',
      );

      expect(conDatos.titulo(e), 'Concedió el permiso Ver sueldo');
    });

    test('un módulo se nombra con lo que manda el catálogo', () {
      // ⚠️ ANTES ESTA PRUEBA USABA `pelado`, porque el nombre salía de un mapa de
      // siete etiquetas escrito en la web. Desde el 19 de octubre de 2026 lo manda el
      // servidor, así que un traductor SIN catálogo ya no puede decir «Nómina» — y no
      // debe: inventarlo es lo que había que quitar.
      final e = evento(
        entidad: 'company_module',
        accion: 'enabled',
        despues: '{"module":"payroll","enabled":true}',
      );

      const conCatalogo = AuditoriaLegible(
        nombrePorIdentidad: {},
        nombrePorPermiso: {},
        nombrePorModulo: {'payroll': 'Nómina'},
      );

      expect(conCatalogo.titulo(e), 'Activó el módulo Nómina');

      // Y sin catálogo, el código humanizado: feo y honesto. El grupo del final
      // comprueba que en ese caso NO se cuela el nombre del apartado.
      expect(pelado.titulo(e), 'Activó el módulo Payroll');
    });

    test('sin nombre en el registro se dice «un área», que es la verdad', () {
      final e = evento(entidad: 'area', accion: 'deleted');

      expect(pelado.titulo(e), 'Borró un área');
    });

    test('una entidad SIN frase propia se dice legible, NUNCA con su código', () {
      // Es fea a propósito: es la señal visible de que falta traducirla. Lo que no
      // puede pasar es que salga el código crudo ni que se esconda la fila.
      //
      // ⚠️ ESTA PRUEBA USABA `subscription_extra`, Y DEJÓ DE VALER EL 26-nov-2026: ese
      // día se completó el catálogo de entidades y ahora dice «el adicional». Así que
      // el ejemplo es ahora una entidad que NO EXISTE en el servidor, y eso es lo
      // correcto: lo que se mide es el respaldo, no la falta de una traducción concreta
      // —si el ejemplo fuera una entidad real, traducirla rompería esta prueba y la
      // tentación sería dejarla sin traducir para que pase—.
      final e = evento(
        entidad: 'cosa_que_no_existe',
        accion: 'created',
        despues: '{"name":"Algo"}',
      );

      final titulo = pelado.titulo(e);

      expect(titulo, contains('Cosa que no existe'));
      expect(titulo, isNot(contains('cosa_que_no_existe')));
      expect(titulo, contains('registro de tipo'));
    });

    test('una ACCIÓN desconocida se dice legible, nunca cruda', () {
      final e = evento(entidad: 'area', accion: 'super_frobnicated');

      expect(pelado.titulo(e), isNot(contains('super_frobnicated')));
      expect(pelado.titulo(e), contains('Super frobnicated'));
    });
  });

  group('Quién lo hizo', () {
    test('con nombre cuando se conoce', () {
      expect(
        conDatos.actor(evento(entidad: 'area', accion: 'created')),
        'Juan Pérez',
      );
    });

    test('por su identidad abreviada cuando ya no tiene acceso', () {
      // NO se oculta la fila: una auditoría que esconde lo que no sabe nombrar deja
      // de servir justo para lo que existe.
      final texto = pelado.actor(evento(entidad: 'area', accion: 'created'));

      expect(texto, contains('01a15071'));
      expect(texto, contains('identidad'));
    });

    test('un hecho sin persona detrás lo dice con palabras', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        tipoDeActor: 'system',
        actor: null,
      );

      expect(pelado.actor(e), 'El sistema');
    });
  });

  group('El detalle', () {
    test('sólo los campos que CAMBIARON', () {
      // El código sigue igual y no aparece: repetir los que no se movieron esconde
      // el único que sí.
      final e = evento(
        entidad: 'area',
        accion: 'updated',
        antes: '{"code":"MON","name":"Monitoreo","status":"activa"}',
        despues: '{"code":"MON","name":"Monitoreo central","status":"activa"}',
      );

      final campos = pelado.campos(e);

      expect(campos.map((c) => c.etiqueta), ['Nombre']);
      expect(campos.single.esCambio, isTrue);
      expect(campos.single.antes!.texto, 'Monitoreo');
      expect(campos.single.despues!.texto, 'Monitoreo central');
    });

    test('un alta no tiene «antes», así que lista lo que trae', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"code":"MON","name":"Monitoreo","status":"activa"}',
      );

      final campos = pelado.campos(e);

      expect(campos.map((c) => c.etiqueta), ['Código', 'Nombre', 'Estado']);
      expect(campos.every((c) => !c.esCambio), isTrue);
    });

    test('los campos TÉCNICOS no se muestran', () {
      final e = evento(
        entidad: 'company',
        accion: 'created',
        despues:
            '{"name":"Demo","firstMaestroIdentityId":"01a15071-0001-7000-8000-000000000001","protectedPermissionsGranted":6}',
      );

      final etiquetas = pelado.campos(e).map((c) => c.etiqueta).toList();

      expect(etiquetas, contains('Nombre'));
      expect(etiquetas, contains('Permisos protegidos concedidos'));
      // El identificador del Maestro no le dice nada a nadie y empuja fuera lo que sí.
      expect(etiquetas.join(' '), isNot(contains('Identity')));
      expect(etiquetas.join(' '), isNot(contains('identity')));
    });

    test('«area_code» NO es un identificador y sí se muestra', () {
      // Es el código que el cliente escribió y reconoce. Un filtro que se comiera
      // todo lo que acaba en «code» perdería justamente eso.
      final e = evento(
        entidad: 'position',
        accion: 'created',
        despues: '{"code":"SUP","name":"Supervisor","area_code":"MON"}',
      );

      final campos = pelado.campos(e);

      expect(campos.map((c) => c.etiqueta), contains('Área'));
      expect(
        campos.firstWhere((c) => c.etiqueta == 'Área').despues!.texto,
        'MON',
      );
    });

    test('lo que ya está en el TÍTULO no se repite abajo', () {
      final e = evento(
        entidad: 'company_access_permission',
        accion: 'granted',
        despues: '{"permission":"personal.sueldo.ver"}',
      );

      expect(conDatos.titulo(e), contains('Ver sueldo'));
      expect(conDatos.campos(e), isEmpty);
    });

    test('el MOTIVO va primero, porque lo escribió una persona', () {
      final e = evento(
        entidad: 'area',
        accion: 'updated',
        antes: '{"status":"activa"}',
        despues: '{"status":"inactiva"}',
        motivo: 'cerró la sede',
      );

      final campos = pelado.campos(e);

      expect(campos.first.etiqueta, 'Motivo');
      expect(campos.first.despues!.texto, 'cerró la sede');
    });
  });

  group('Los valores se dicen en español', () {
    test('true y false son Sí y No', () {
      final e = evento(
        entidad: 'company_module',
        accion: 'enabled',
        antes: '{"enabled":false}',
        despues: '{"enabled":true}',
      );

      final campo = pelado.campos(e).single;

      expect(campo.etiqueta, 'Habilitado');
      expect(campo.antes!.texto, 'No');
      expect(campo.despues!.texto, 'Sí');
    });

    test('un estado es un chip, y conserva su código para el color', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"status":"activa"}',
      );

      final valor = pelado.campos(e).single.despues!;

      expect(valor.forma, FormaDeValor.estado);
      expect(valor.texto, 'Activa');
      // El color y el ícono se eligen por el código, no por la traducción.
      expect(valor.estadoCrudo, 'activa');
    });

    test('un rol se dice Maestro o Usuario', () {
      final e = evento(
        entidad: 'company_access',
        accion: 'role_changed',
        antes: '{"role":"user"}',
        despues: '{"role":"maestro"}',
      );

      final campo = pelado.campos(e).single;

      expect(campo.antes!.texto, 'Usuario');
      expect(campo.despues!.texto, 'Maestro');
    });

    test('una fecha se dice dd/mmm/aaaa, con el mes en letras', () {
      // `18/10/2026` y `10/18/2026` se confunden; `18/oct/2026` no se confunde con
      // nada. Aplica a los campos de fecha de los módulos que vengan después.
      final e = evento(
        entidad: 'employment_period',
        accion: 'created',
        despues: '{"started_on":"2026-10-18"}',
      );

      final valor = pelado.campos(e).single.despues!;

      expect(valor.forma, FormaDeValor.fecha);
      expect(valor.texto, '18/oct/2026');
    });

    test('un campo de fecha con un valor raro NO se interpreta', () {
      // Se detecta por la clave Y por la forma del valor. Sólo por la clave, esto
      // habría reventado al convertirlo.
      final e = evento(
        entidad: 'employment_period',
        accion: 'created',
        despues: '{"started_on":"pendiente"}',
      );

      final valor = pelado.campos(e).single.despues!;

      expect(valor.forma, FormaDeValor.texto);
      expect(valor.texto, 'pendiente');
    });

    test('una lista se cuenta, no se vuelca', () {
      final e = evento(
        entidad: 'service',
        accion: 'created',
        despues: '{"schedule_blocks":[1,2,3]}',
      );

      expect(pelado.campos(e).single.despues!.texto, '3 elementos');
    });
  });

  group('NUNCA sale JSON', () {
    test('un detalle ilegible se dice con palabras, y no se vuelca', () {
      const basura = 'esto no es json {{{';

      final e = evento(entidad: 'area', accion: 'created', despues: basura);

      final aviso = pelado.avisoDeFormato(e);

      expect(aviso, isNotNull);
      expect(aviso, isNot(contains(basura)));
      expect(aviso, contains('formato'));

      // Y no inventa campos a partir de lo que no entendió.
      expect(pelado.campos(e), isEmpty);
    });

    test('un detalle normal no levanta ningún aviso', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"name":"Monitoreo"}',
      );

      expect(pelado.avisoDeFormato(e), isNull);
    });

    test('ninguna etiqueta ni ningún valor sale con llaves o corchetes', () {
      // Una guarda de forma: si algún camino volcara el mapa, esto lo caza.
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"code":"MON","name":"Monitoreo","status":"activa"}',
      );

      final todo = [
        pelado.titulo(e),
        for (final c in pelado.campos(e))
          '${c.etiqueta} ${c.antes?.texto ?? ''} ${c.despues?.texto ?? ''}',
      ].join(' ');

      expect(todo, isNot(contains('{')));
      expect(todo, isNot(contains('"')));
    });
  });

  // =========================================================================
  // La prueba que protege todo lo anterior
  // =========================================================================

  group('El vocabulario cubre todas las entidades auditadas', () {
    /// Las claves que el servidor escribe **hoy** en los registros de empresa, por
    /// entidad.
    ///
    /// SALE DE LEER EL BACKEND, no de suponer: `TenancyRepository`,
    /// `AuthorizationRepository` y `StructureRepository` son los únicos que auditan lo
    /// que esta etapa produce. Su gemela —`AuditPayloadVocabularyTests`— mide las
    /// claves reales ejecutando las operaciones, así que si alguien añade una, allí
    /// falla con su nombre y aquí se le exige la etiqueta.
    ///
    /// **Se amplía cuando un módulo se muda**, igual que `modulos_mudados.dart`: no se
    /// inventa el texto oficial de un campo cuya pantalla no existe.
    const inventario = <String, List<String>>{
      // ⚠️ LAS SIETE DEL EXPEDIENTE SE COLARON A PANTALLA, y «Contact summary» salió
      // en inglés humanizado en una pantalla en español.
      //
      // Este par de pruebas existe justamente para impedirlo y NO LO CAZÓ. La razón
      // estaba en el backend: su escenario no ejercitaba las rutas del expediente que
      // añadió el esquema 50, así que estas claves nunca se escribían durante la
      // prueba y nunca se medían — y el círculo sólo se cierra para lo que el
      // escenario toca. Ya está corregido allí: el escenario guarda los dos
      // expedientes, y una mutación lo confirma diciendo
      // «company.contact_summary».
      'company': [
        'name',
        'firstMaestroIdentityId',
        'protectedPermissionsGranted',
        'legal_name',
        'tax_id',
        'legal_rep',
        'slogan',
        'fiscal_regime_code',
        'address_summary',
        'contact_summary',
        // La cuenta de las modalidades de turno con las que la empresa NACE (0066).
        'shiftModalitiesSeeded',
      ],
      'company_access': ['role', 'subjectIdentityId', 'status'],
      'company_access_permission': ['permission'],
      'company_module': ['module', 'enabled'],
      'area': ['code', 'name', 'status'],
      'position': ['code', 'name', 'kind', 'area_code', 'status'],
      // `operational_status` LO ESTRENÓ M3, con cerrar y reabrir. Y el borrado físico
      // escribe las mismas claves en `before`, así que no añade ninguna nueva.
      'branch': [
        'code',
        'name',
        'status',
        'operational_status',
        // ESQUEMA 50: el expediente de la sucursal. El domicilio va como UNA LÍNEA
        // —la auditoría «guarda qué cambió, no documentos»— y el horario como una
        // CUENTA, porque «ningún evento lleva una colección».
        'address_summary',
        'schedule_blocks',
      ],
      'branch_type': ['code', 'name', 'status', 'recommended', 'created_count'],

      // --- COMERCIAL, que llevaba mudado desde C1 y no estaba ----------------
      //
      // ⚠️ NINGUNA DE ESTAS ESTABA AQUÍ, y es el mismo hueco de las ocho del expediente:
      // la regla dice «se amplía cuando un módulo se muda» y nadie la aplicó al mudarse
      // Comercial. Por eso el dueño vio «Key name» y «Active → Terminated» en el ensayo.
      //
      // Y SALEN DE LEER EL CÓDIGO DEL SERVIDOR, no de suponer: su gemela del backend
      // barre los `.Set("…")` de `Clients`, `Services`, `Contracts` y `Files`, así que
      // una clave nueva de Comercial falla allí con su nombre y aquí se le exige nombre.
      'client': [
        'code',
        'commercial_name',
        'status',
        'started_on',
        'notes_length',
        'municipality',
        'state',
        'postal_code',
        'country',
      ],
      // EL CORREO Y EL TELÉFONO VAN ENMASCARADOS por el servidor; la clave sí viaja.
      'client_contact': [
        'name',
        'kind',
        'role',
        'is_primary',
        'status',
        'email_masked',
        'phone_masked',
      ],
      'client_address': ['municipality', 'state', 'postal_code', 'country'],
      'fiscal_entity': [
        'legal_name',
        'tax_id',
        'fiscal_regime_code',
        'status',
        'notes_length',
      ],
      // C4. `cipher_key_name` es TÉCNICA y se filtra; va en la lista a propósito, para
      // que la prueba de abajo compruebe que el filtro la agarra.
      'client_portal': ['name', 'kind', 'status', 'cipher_key_name'],
      'client_logo': ['original_file_name', 'content_type', 'size_bytes', 'purpose'],
      'client_document': ['title', 'original_file_name', 'content_type', 'size_bytes'],
      'service': [
        'code',
        'name',
        'status',
        'starts_on',
        'ends_on',
        'schedule_style',
        'shift_change_minute',
      ],
      'shift_modality': ['code', 'name', 'has_description', 'requires_period'],
      'service_commercial_line': [
        'status',
        'pricing_mode',
        'headcount',
        'shift_period',
        'shift_minutes',
        'requires_period',
        'tax_treatment',
        'currency',
      ],
      'commercial_line_term': [
        'starts_on',
        'ends_on',
        'new_ends_on',
        'stops_charging_on',
        'charges_until',
        'effective_on',
        'unit_price_minor',
        'monthly_amount_minor',
        'monthly_total_minor',
        'salary_minor',
        'bonus_minor',
        'term_version',
        'vigente_salida',
      ],
      'contract': [
        'code',
        'title',
        'status',
        'signed_on',
        'notice_days',
        'auto_renew',
        'terminated_on',
        'termination_reason',
        'linked_services',
        'linked_documents',
      ],
      'contract_amendment': ['sequence', 'title', 'effective_on'],
    };

    // ⚠️ LA LISTA DE VERBOS QUE VIVÍA AQUÍ SE RETIRÓ EL 26-nov-2026, y no por limpieza:
    // tenía los once de hasta M3 y le faltaban quince, cuatro de ellos los de C4. La
    // sustituye el espejo COMPLETO de `AuditAction`, en el grupo «Ningún catálogo cerrado
    // del servidor cae al inglés». Dejar las dos habría sido dejar dos listas de lo mismo
    // con distinto alcance, y la corta pasando en verde mientras la pantalla mostraba
    // «Secret updated» es exactamente cómo esto se colgó.

    test('cerrar y reabrir una sucursal se dicen sin confundirse con desactivar', () {
      // LAS DOS PREGUNTAS NO SE COLAPSAN, y el texto es donde se nota: si `closed`
      // dijera «Desactivó», la traza contaría que la sucursal se dio de baja cuando
      // sólo se cerró por obra, y quien audite un mes después no podría distinguirlo.
      final cerro = pelado.titulo(
        evento(
          entidad: 'branch',
          accion: 'closed',
          antes: '{"operational_status":"operando"}',
          despues: '{"operational_status":"cerrada_temporalmente"}',
        ),
      );

      expect(cerro, contains('Cerró temporalmente'));
      expect(cerro, isNot(contains('Desactivó')));

      final reabrio = pelado.titulo(
        evento(
          entidad: 'branch',
          accion: 'reopened',
          antes: '{"operational_status":"cerrada_temporalmente"}',
          despues: '{"operational_status":"operando"}',
        ),
      );

      expect(reabrio, contains('Reabrió'));
    });

    test('el estado operativo se dice en español y NO como chip de estado', () {
      // Un chip verde o gris lo haría parecer lo mismo que `status`, que es justo la
      // confusión que las dos columnas existen para evitar.
      final campos = pelado.campos(
        evento(
          entidad: 'branch',
          accion: 'closed',
          antes: '{"operational_status":"operando"}',
          despues: '{"operational_status":"cerrada_temporalmente"}',
        ),
      );

      final renglon = campos.single;

      expect(renglon.etiqueta, 'Estado operativo');
      expect(renglon.antes?.texto, 'Operando');
      expect(renglon.despues?.texto, 'Cerrada temporalmente');
    });

    test('el borrado físico dice qué desapareció y con qué motivo', () {
      // EL EVENTO ES LO ÚNICO QUE QUEDA DE LA FILA, así que tiene que leerse solo.
      const motivo = 'Se capturó por error, nunca se usó.';

      final e = evento(
        entidad: 'area',
        accion: 'deleted',
        antes: '{"code":"RH","name":"Recursos Humanos","status":"activa"}',
        motivo: motivo,
      );

      expect(pelado.titulo(e), contains('Borró'));
      expect(pelado.titulo(e), contains('Recursos Humanos'));

      // EL MOTIVO VA PRIMERO, porque lo escribió una persona.
      final campos = pelado.campos(e);
      expect(campos.first.etiqueta, 'Motivo');
      expect(campos.first.despues?.texto, motivo);
    });

    test('cada clave tiene etiqueta propia, o se dice cuál falta', () {
      final sinEtiqueta = <String>[];

      for (final entrada in inventario.entries) {
        for (final clave in entrada.value) {
          // Los técnicos no se muestran, así que no necesitan etiqueta. Se pregunta al
          // FILTRO DE VERDAD: aquí había una copia de su condición, y una copia es un
          // sitio más donde discrepar sin que nada falle.
          if (AuditoriaLegible.esTecnica(clave)) continue;

          if (!AuditoriaLegible.tieneEtiqueta(clave)) {
            sinEtiqueta.add('${entrada.key}.$clave');
          }
        }
      }

      expect(
        sinEtiqueta,
        isEmpty,
        reason:
            'Estos campos de la auditoría saldrían con un nombre inventado a partir '
            'de su clave en vez de en español. Añádeles su etiqueta en '
            '_etiquetas, en auditoria_legible.dart: ${sinEtiqueta.join(', ')}',
      );
    });

    test('cada entidad SE NOMBRA cuando el registro trae nombre', () {
      // ⚠️ LA PRUEBA QUE FALTABA, y se vio en pantalla: al desactivar una sucursal la
      // auditoría decía «Desactivó UNA sucursal». No era que a `branch` le faltara su
      // frase —la tenía— sino que el registro de un cambio de estado sólo llevaba
      // `status`, así que no había con qué nombrar la fila.
      //
      // El arreglo está en el servidor: `AuditarCambioAsync` manda el nombre SIEMPRE,
      // porque ahí no es un cambio sino la identificación del sujeto. Esta prueba fija
      // la mitad de acá: que con el nombre delante, NINGUNA entidad se quede en «un» o
      // «una».
      final sinNombrar = <String>[];

      for (final entidad in inventario.keys) {
        // Un registro realista de cambio de estado, con el nombre en los dos lados
        // como lo escribe el servidor.
        final e = evento(
          entidad: entidad,
          accion: 'status_changed',
          antes: '{"name":"Algo","status":"activa"}',
          despues: '{"name":"Algo","status":"inactiva"}',
        );

        if (!pelado.titulo(e).contains('Algo')) sinNombrar.add(entidad);
      }

      // `company_access`, `company_access_permission` y `company_module` se nombran por
      // OTRA clave —la identidad, el permiso, el módulo—, así que no usan `name` y es
      // correcto que no aparezcan aquí. Se nombran igual, con su propio dato.
      const porOtraClave = {
        'company_access',
        'company_access_permission',
        'company_module',
      };

      expect(
        sinNombrar.where((x) => !porOtraClave.contains(x)),
        isEmpty,
        reason:
            'Estas entidades saldrían como «un/una …» aunque el registro traiga el '
            'nombre: ${sinNombrar.join(', ')}',
      );
    });

    test('las tres que se nombran por otra clave TAMBIÉN se nombran', () {
      // No basta con exceptuarlas arriba: hay que comprobar que sí dicen de qué
      // hablan, cada una con su dato.
      final acceso = conDatos.titulo(
        evento(
          entidad: 'company_access',
          accion: 'status_changed',
          despues:
              '{"subjectIdentityId":"01a15071-0001-7000-8000-000000000001",'
              '"status":"inactiva"}',
        ),
      );

      expect(acceso, contains('Juan Pérez'));

      final permiso = conDatos.titulo(
        evento(
          entidad: 'company_access_permission',
          accion: 'granted',
          despues: '{"permission":"personal.sueldo.ver"}',
        ),
      );

      expect(permiso, contains('Ver sueldo'));

      final modulo = pelado.titulo(
        evento(
          entidad: 'company_module',
          accion: 'enabled',
          despues: '{"module":"personal","enabled":true}',
        ),
      );

      expect(modulo, contains('Personal'));
    });

    test('el nombre va al TÍTULO y no se repite en el detalle', () {
      // La otra mitad del arreglo del servidor: ahora el nombre viaja en los dos lados
      // de TODO cambio de estado. Si el detalle lo listara, cada desactivación tendría
      // un renglón «Nombre: Algo → Algo» que no dice nada.
      //
      // No hace falta tocar la pantalla para eso —«sólo lo que cambió» ya lo filtra—,
      // y esta prueba es la que lo garantiza al añadir el nombre al registro.
      final e = evento(
        entidad: 'branch',
        accion: 'status_changed',
        antes: '{"name":"AAA","status":"activa"}',
        despues: '{"name":"AAA","status":"inactiva"}',
      );

      expect(pelado.titulo(e), contains('AAA'));

      final etiquetas = pelado.campos(e).map((c) => c.etiqueta).toList();

      expect(etiquetas, ['Estado']);
      expect(etiquetas, isNot(contains('Nombre')));
    });

    test('cada entidad del inventario tiene su frase, con artículo', () {
      // Sin esto, una entidad auditada saldría como «el registro de tipo Company
      // access» — legible, pero no es español de verdad.
      for (final entidad in inventario.keys) {
        final e = evento(
          entidad: entidad,
          accion: 'created',
          despues: '{"name":"Algo"}',
        );

        final titulo = pelado.titulo(e);

        expect(
          titulo,
          isNot(contains('registro de tipo')),
          reason:
              'La entidad «$entidad» no tiene frase propia en _ObjetoDeAuditoria ni '
              'en _fraseEspecifica, así que sale con el respaldo genérico.',
        );
      }
    });

    test('y ninguna clave del inventario se muestra en crudo', () {
      // La guarda final: aunque faltara una etiqueta, lo que se pinta nunca es la
      // clave tal cual.
      for (final entrada in inventario.entries) {
        for (final clave in entrada.value) {
          if (AuditoriaLegible.esTecnica(clave)) continue;

          expect(
            AuditoriaLegible.etiquetaDe(clave),
            isNot(equals(clave)),
            reason: 'La clave «$clave» se mostraría cruda.',
          );
        }
      }
    });

    test('y la clave TÉCNICA del inventario la agarra el filtro, no una excepción', () {
      // `cipher_key_name` está en el inventario a propósito: es la clave que el servidor
      // escribe hoy en los eventos del secreto de un portal, y la prueba de arriba la
      // salta. Lo que se afirma aquí es POR QUÉ la salta — porque el filtro la reconoce
      // como técnica— y no porque alguien la dejara fuera de la lista.
      expect(AuditoriaLegible.esTecnica('cipher_key_name'), isTrue);
      expect(AuditoriaLegible.tieneEtiqueta('cipher_key_name'), isFalse);

      // Y LA VIEJA TAMBIÉN, que es la que está escrita en el ensayo y la única que
      // llevaba la dirección dentro.
      expect(AuditoriaLegible.esTecnica('key_name'), isTrue);
    });
  });

  // =========================================================================
  // LOS TRES CATÁLOGOS CERRADOS, COMPLETOS
  // =========================================================================

  /// ⚠️ **ESTE GRUPO NACE EL 26-nov-2026, de tres defectos vistos en PANTALLA** por el
  /// dueño mientras hacía la prueba de C4 en el ensayo: «Key name», «Active →
  /// Terminated» y «Vinculó un registro de tipo Client logo».
  ///
  /// ## Por qué las pruebas que ya existían no los cazaron
  ///
  /// Había una prueba por **clave** y una por **verbo**, las dos alimentadas por listas
  /// escritas a mano en este archivo, **y ninguna por entidad ni por valor de estado**.
  /// Y las dos listas a mano cubrían hasta M3: **Comercial llevaba mudado desde C1 y
  /// nadie las amplió**. Dos huecos distintos, y el segundo es el que se repite — es el
  /// mismo con el que «Contact summary» llegó a pantalla.
  ///
  /// ## Qué cambia aquí, que es lo que impide la tercera vez
  ///
  /// Los tres catálogos del servidor —acciones, tipos de entidad y códigos de estado—
  /// son **cerrados**, así que se espejan **enteros** y se exige traducción para
  /// **todos**, no para los que algún escenario toque. Una lista exacta es lo correcto
  /// justo aquí: romperse al añadir un miembro **es** la función.
  ///
  /// Su gemela del backend, `AuditPayloadVocabularyTests`, ya no depende sólo de su
  /// escenario: **lee el código del servidor** y saca las claves de ahí.
  group('Ningún catálogo cerrado del servidor cae al inglés', () {
    /// **Todas** las acciones de `AuditAction` (`src/Seventra.Data/Audit/AuditModels.cs`).
    const acciones = <String>[
      'created',
      'granted',
      'revoked',
      'role_changed',
      'enabled',
      'disabled',
      'initiated',
      'accepted',
      'cancelled',
      'activated',
      'status_changed',
      'replaced',
      'uploaded',
      'attached',
      'detached',
      'retired',
      'purged',
      'updated',
      'hired',
      'terminated',
      'rehired',
      'assignment_changed',
      'corrected',
      'viewed',
      'voided',
      'salary_changed',
      'invalidated',
      'issued',
      'deleted',
      // Los cuatro de C4.
      'secret_updated',
      'secret_cleared',
      'secret_revealed',
      'secret_copied',
      'closed',
      'reopened',
    ];

    /// **Todos** los tipos de `AuditEntityType`, en el mismo orden que el servidor.
    const entidades = <String>[
      'organization',
      'organization_membership',
      'organization_membership_permission',
      'organization_ownership_transfer',
      'company',
      'company_access',
      'company_module',
      'company_access_permission',
      'subscription',
      'subscription_extra',
      'subscription_line_activation',
      'subscription_discount',
      'platform_invitation',
      'file',
      'company_file_slot',
      'area',
      'position',
      'branch',
      'person',
      'person_address',
      'employee',
      'employee_assignment',
      'assignment_salary_term',
      'branch_type',
      'employment_period',
      'employee_photo',
      'employee_document',
      'employee_professional_profile',
      'employee_evaluation',
      'employee_evaluation_file',
      'employee_banking',
      'employee_technical_sheet',
      'client',
      'client_address',
      'client_contact',
      'fiscal_entity',
      'fiscal_entity_address',
      'client_portal',
      'client_logo',
      'client_document',
      'fiscal_entity_document',
      'service',
      'service_address',
      'service_type',
      'shift_modality',
      'service_commercial_line',
      'commercial_line_term',
      'commercial_line_salary_reference',
      'contract',
      'contract_service',
      'contract_amendment',
      'contract_document',
      'contract_amendment_document',
    ];

    /// **Todos** los códigos que el servidor escribe en `status`, de los ocho
    /// vocabularios que existen. Son dos idiomas en una sola columna: la estructura
    /// nació con códigos en español y Comercial en inglés.
    const estados = <String>[
      // Estructura, accesos, módulos y catálogo de tipos de servicio.
      'activa',
      'inactiva',
      'revocada',
      // Cliente y servicio.
      'active',
      'suspended',
      'terminated',
      // Contrato.
      'draft',
      // Entidad fiscal y portal.
      'archived',
      // Línea comercial.
      'retired',
      // Vínculos de archivo y de servicio con su contrato.
      'vigente',
      'sustituido',
      'desvinculado',
    ];

    test('cada ACCIÓN del catálogo se dice en español', () {
      final sinTraducir = acciones
          .where((a) => !AuditoriaLegible.tieneVerbo(a))
          .toList();

      expect(
        sinTraducir,
        isEmpty,
        reason:
            'Estas acciones saldrían en inglés humanizado —«Secret updated»—. '
            'Añádelas a _verbos, en auditoria_legible.dart: ${sinTraducir.join(', ')}',
      );
    });

    test('cada ENTIDAD del catálogo tiene su sustantivo, con artículo', () {
      // 🚫 NO BASTA CON `tieneFraseDeEntidad`: lo que se comprueba es lo que SALE. Una
      // entidad con frase en `_fraseEspecifica` y sin entrada en `_conocidos` también
      // está bien, y al revés —entrada sin artículo— saldría mal sin que nada fallara.
      final sinFrase = <String>[];

      for (final entidad in entidades) {
        final titulo = pelado.titulo(
          evento(entidad: entidad, accion: 'created', despues: '{"name":"Algo"}'),
        );

        if (titulo.contains('registro de tipo')) sinFrase.add(entidad);
      }

      expect(
        sinFrase,
        isEmpty,
        reason:
            'Estas entidades saldrían como «un registro de tipo Client logo», medio '
            'en inglés. Añádelas a _ObjetoDeAuditoria._conocidos: ${sinFrase.join(', ')}',
      );
    });

    test('cada CÓDIGO DE ESTADO se dice en español', () {
      final sinTraducir = estados
          .where((e) => !AuditoriaLegible.tieneEstado(e))
          .toList();

      expect(
        sinTraducir,
        isEmpty,
        reason:
            'Estos estados saldrían en inglés —«Active → Terminated»—. Añádelos a '
            'ValorLegible._estados, en auditoria_legible.dart: ${sinTraducir.join(', ')}',
      );
    });

    test('y lo que se PINTA de un cambio de estatus es español, no el código', () {
      // La medida de verdad: el caso exacto que el dueño vio.
      final campos = pelado.campos(
        evento(
          entidad: 'client',
          accion: 'status_changed',
          antes: '{"status":"active"}',
          despues: '{"status":"terminated"}',
        ),
      );

      final renglon = campos.single;

      expect(renglon.etiqueta, 'Estado');
      expect(renglon.antes?.texto, 'Activo');
      expect(renglon.despues?.texto, 'Terminado');

      // Y SIGUE SIENDO UN CHIP, con su código crudo para que el color lo elija el
      // widget: traducirlo no puede costarle el color.
      expect(renglon.despues?.forma, FormaDeValor.estado);
      expect(renglon.despues?.estadoCrudo, 'terminated');
    });

    test('el TIPO de un portal se dice en español, y no con el mapa de los puestos', () {
      // `kind` significa otra cosa en cada entidad, y antes había un solo mapa: un
      // portal de facturación salía «Billing».
      for (final tipo in ['billing', 'suppliers', 'payments', 'other']) {
        expect(
          AuditoriaLegible.tieneTipo('client_portal', tipo),
          isTrue,
          reason: 'El tipo de portal «$tipo» saldría en inglés.',
        );
      }

      final campos = pelado.campos(
        evento(
          entidad: 'client_portal',
          accion: 'created',
          despues: '{"name":"SAT","kind":"billing"}',
        ),
      );

      final tipo = campos.firstWhere((c) => c.etiqueta == 'Tipo');
      expect(tipo.despues?.texto, 'Facturación');

      // 🚫 Y UN CÓDIGO DE OTRA ENTIDAD NO SE CRUZA: «operativo» es un tipo de puesto y
      // de contacto, y en un portal no significa nada. Decir «Operativo» ahí sería
      // mentir, que es peor que humanizar.
      expect(AuditoriaLegible.tieneTipo('client_portal', 'operativo'), isFalse);
      expect(AuditoriaLegible.tieneTipo('position', 'billing'), isFalse);
    });
  });

  // =========================================================================
  // C4: los cuatro actos de la contraseña de un portal
  // =========================================================================

  group('Los actos de la contraseña de un portal', () {
    test('los cuatro se leen distintos, y dicen de qué portal', () {
      // MOSTRAR Y COPIAR SON DOS ACTOS, y la bitácora es lo único que queda de un acto
      // que no cambia nada: si los dos dijeran lo mismo, el registro no serviría.
      const esperado = {
        'secret_updated': 'Guardó la contraseña del portal SAT',
        'secret_cleared': 'Borró la contraseña del portal SAT',
        'secret_revealed': 'Mostró la contraseña del portal SAT',
        'secret_copied': 'Copió la contraseña del portal SAT',
      };

      for (final entrada in esperado.entries) {
        expect(
          pelado.titulo(
            evento(
              entidad: 'client_portal',
              accion: entrada.key,
              despues: '{"name":"SAT"}',
            ),
          ),
          entrada.value,
        );
      }

      // Y LOS CUATRO SON DISTINTOS ENTRE SÍ, dicho como propiedad y no caso por caso.
      expect(esperado.values.toSet(), hasLength(4));
    });

    test('sin nombre en el registro dice «de un portal», que es la verdad', () {
      // Los eventos escritos ANTES del 26-nov-2026 no traen el nombre: el servidor lo
      // añadió ese día. La pantalla tiene que seguir leyéndose con los viejos.
      expect(
        pelado.titulo(evento(entidad: 'client_portal', accion: 'secret_revealed')),
        'Mostró la contraseña de un portal',
      );
    });

    test('🚫 la LLAVE DE CIFRADO no se pinta nunca, ni traducida', () {
      // ⚠️ EL DEFECTO QUE EL DUEÑO ENCONTRÓ, en su forma exacta: el nombre de recurso de
      // Cloud KMS —con el id del proyecto de SEVENTRA dentro— en una pantalla que lee el
      // cliente del SaaS.
      //
      // El servidor ya escribe una etiqueta corta, pero esta prueba usa el payload VIEJO
      // a propósito: `audit_event` es append-only con disparador, así que las filas que
      // ya se escribieron en el ensayo conservan el nombre completo para siempre y
      // ninguna migración las puede limpiar. Esta mitad del arreglo es la que las cubre.
      const viejo =
          '{"client_id":"01a15071-0002-7000-8000-000000000002",'
          '"key_name":"projects/un-proyecto-de-seventra/locations/'
          'northamerica-south1/keyRings/seventra/cryptoKeys/portales-de-cliente"}';

      final campos = pelado.campos(
        evento(entidad: 'client_portal', accion: 'secret_revealed', despues: viejo),
      );

      expect(campos, isEmpty);

      // Y LA ETIQUETA NUEVA TAMPOCO SE PINTA: no filtra nada, y con qué llave se selló
      // una contraseña no le dice nada a quien administra una empresa.
      final conEtiqueta = pelado.campos(
        evento(
          entidad: 'client_portal',
          accion: 'secret_revealed',
          despues: '{"name":"SAT","cipher_key_name":"kms:portales-de-cliente"}',
        ),
      );

      expect(conEtiqueta.map((c) => c.etiqueta), isNot(contains('Cipher key')));
      expect(
        conEtiqueta.every((c) => c.despues?.texto != 'kms:portales-de-cliente'),
        isTrue,
      );
    });
  });

  // =========================================================================
  // EL NOMBRE DEL MÓDULO, que lo manda el servidor y NO es el del apartado
  // =========================================================================

  group('El nombre del MÓDULO no es el del apartado', () {
    // ⚠️ ESTE GRUPO SE MUDÓ DESDE `apartados_web_test.dart` el 19 de octubre de 2026,
    // cuando el catálogo del servidor empezó a mandar `moduleName` y las siete
    // etiquetas que la web tenía a mano se retiraron.
    //
    // POR QUÉ VIVE AQUÍ AHORA: la propiedad a vigilar cruza la frontera —el nombre
    // del módulo lo manda el SERVIDOR, el del apartado lo decide la WEB—, y este es
    // el único sitio donde las dos se encuentran, porque es donde se inyecta.
    //
    // Y POR QUÉ IMPORTA: al unificar los nombres en un solo archivo, la auditoría
    // empezó a decir «Activó el módulo Personal» cuando el hecho registrado era
    // `module: payroll`. Eso es FALSO: lo que se encendió fue Nómina.

    /// Los nombres tal como los manda `app.platform_module`. Es un FIXTURE, no una
    /// fuente: existe para poder comparar contra los apartados, y su exactitud la
    /// vigila `El_catalogo_manda_el_NOMBRE_del_modulo_y_no_sólo_su_codigo` en el
    /// backend, que los compara contra la tabla.
    const delServidor = {
      'personal': 'Personal',
      'payroll': 'Nómina',
      'finance': 'Finanzas',
      'collections': 'Cobranza',
      'purchases_inventory': 'Compras e Inventario',
      'assets': 'Activos',
      'clients_services': 'Clientes y Servicios',
    };

    const conModulos = AuditoriaLegible(
      nombrePorIdentidad: {},
      nombrePorPermiso: {},
      nombrePorModulo: delServidor,
    );

    EventoDeAuditoria eventoDeModulo(String codigo) => evento(
      entidad: 'company_module',
      accion: 'company.module.enabled',
      despues: '{"module":"$codigo","enabled":true}',
    );

    test('la auditoría nombra el MÓDULO, no su apartado', () {
      expect(conModulos.titulo(eventoDeModulo('payroll')), contains('Nómina'));
      expect(conModulos.titulo(eventoDeModulo('collections')), contains('Cobranza'));

      // Y NO dice el apartado, que es el fallo que se vio.
      expect(
        conModulos.titulo(eventoDeModulo('payroll')),
        isNot(contains('Personal')),
        reason: 'Diría «activó Personal» cuando lo que se encendió fue Nómina.',
      );
    });

    test('y los dos DISCREPAN en los módulos que comparten apartado', () {
      // Si alguna vez coincidieran, sería la señal de que alguien volvió a unificarlos
      // y la auditoría volvió a mentir.
      for (final codigo in ['payroll', 'collections', 'clients_services']) {
        expect(
          delServidor[codigo],
          isNot(equals(apartados.nombreDelGrupoDePermisos(codigo))),
          reason:
              'El módulo «$codigo» y su apartado tendrían el mismo nombre, así que '
              'la auditoría diría el del apartado y no el del módulo.',
        );
      }
    });

    test('SIN catálogo humaniza el código, y NO inventa el apartado', () {
      // Es el camino cuando el catálogo no cargó. «Payroll» se ve claramente sin
      // curar —y por eso es honesto—, pero lo que importa es que no diga «Personal».
      const sinCatalogo = AuditoriaLegible(
        nombrePorIdentidad: {},
        nombrePorPermiso: {},
      );

      final titulo = sinCatalogo.titulo(eventoDeModulo('payroll'));

      expect(titulo, contains('Payroll'));
      expect(
        titulo,
        isNot(contains('Personal')),
        reason:
            'Sin catálogo preferimos un nombre feo a uno falso: «Personal» sería '
            'una afirmación que los datos no sostienen.',
      );
    });
  });
}
