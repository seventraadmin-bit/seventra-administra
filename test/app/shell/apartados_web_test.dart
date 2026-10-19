import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/shell/apartados_web.dart';
import 'package:riseg_one/core/company/permiso_company.dart';

/// El registro único de la estructura de Administra en la nube.
///
/// ## Qué protege, que no es el orden del menú
///
/// Lo que de verdad se vigila son **dos propiedades**, y las dos producen fallos
/// silenciosos si se rompen:
///
///  1. **Cada módulo del servidor pertenece a exactamente un apartado.** Un módulo
///     huérfano haría que sus permisos salieran con su código crudo —«assets»— en
///     lugar de «Activos», y que nunca se mostraran porque ningún apartado dice si
///     está mudado.
///  2. **El grupo de permisos se llama como el apartado.** No por dos textos iguales
///     en dos archivos, sino porque **sale del mismo sitio**. Si alguien renombrara el
///     apartado y no el grupo, el menú diría una cosa y los permisos otra.
///
/// ## Lo que NO se fija
///
/// **No se exige la lista exacta de apartados.** Se acota el número, se afirma que los
/// nueve decididos están y en qué orden relativo, y se niega lo que la propiedad
/// prohíbe. Un décimo apartado es una decisión legítima y no tiene por qué romper
/// esto; lo que sí rompe es un módulo sin apartado.
void main() {
  group('Los apartados decididos están, y en orden', () {
    test('el número está acotado, no clavado', () {
      // Nueve hoy. La cota deja crecer sin que esta prueba se convierta en un
      // trámite, y sigue cazando una lista que se duplique por un mal `merge`.
      expect(apartados.length, greaterThanOrEqualTo(9));
      expect(apartados.length, lessThanOrEqualTo(12));
    });

    test('los nueve están, en el orden del menú', () {
      const decididos = [
        'Dashboard',
        'Organización',
        'Comercial',
        'Finanzas',
        'Personal',
        'Compras e inventario',
        'Activos',
        'Reportes',
        'Configuración',
      ];

      final nombres = apartados.map((a) => a.nombre).toList();

      // ORDEN RELATIVO, no posiciones absolutas: si mañana se intercala uno, lo que
      // importa es que Personal siga antes de Reportes, no que sea el quinto.
      var desde = 0;
      for (final nombre in decididos) {
        final donde = nombres.indexOf(nombre, desde);

        expect(
          donde,
          isNonNegative,
          reason: 'Falta el apartado «$nombre», o quedó fuera de orden.',
        );

        desde = donde + 1;
      }
    });

    test('ningún nombre se repite', () {
      final nombres = apartados.map((a) => a.nombre).toList();

      expect(nombres.toSet().length, nombres.length);
    });

    test('ninguna ruta se repite: es la clave de las Key de prueba', () {
      final rutas = apartados.map((a) => a.ruta).toList();

      expect(rutas.toSet().length, rutas.length);
    });
  });

  group('Cada módulo del servidor tiene exactamente un apartado', () {
    test('ninguno se queda huérfano', () {
      // ÉSTE ES EL FALLO SILENCIOSO QUE LA PRUEBA EXISTE PARA EVITAR: un módulo sin
      // apartado no tiene nombre legible ni forma de saber si está mudado, así que
      // sus permisos saldrían con el código crudo y nunca se mostrarían.
      final huerfanos = [
        for (final m in ModuloCompany.todos)
          if (apartadoDelModulo(m) == null) m,
      ];

      expect(
        huerfanos,
        isEmpty,
        reason:
            'Estos módulos del servidor no pertenecen a ningún apartado, así que sus '
            'permisos saldrían con su código: ${huerfanos.join(', ')}',
      );
    });

    test('ninguno pertenece a dos', () {
      final duenos = <String, List<String>>{};

      for (final a in apartados) {
        for (final m in a.modulos) {
          duenos.putIfAbsent(m, () => []).add(a.nombre);
        }
      }

      final compartidos = duenos.entries.where((e) => e.value.length > 1).toList();

      expect(
        compartidos,
        isEmpty,
        reason:
            'Un módulo con dos apartados haría que sus permisos se titularan de dos '
            'formas distintas según quién pregunte: '
            '${compartidos.map((e) => '${e.key} → ${e.value.join(" y ")}').join('; ')}',
      );
    });

    test('los apartados del NÚCLEO no reclaman ningún módulo', () {
      // Dashboard, Organización, Reportes y Configuración no dependen de nada
      // contratado. Si uno reclamara un módulo, apagarlo escondería la estructura o
      // la auditoría, que son core.
      for (final nombre in [
        'Dashboard',
        'Organización',
        'Reportes',
        'Configuración',
      ]) {
        final a = apartados.firstWhere((x) => x.nombre == nombre);

        expect(a.modulos, isEmpty, reason: '«$nombre» es del núcleo.');
      }
    });
  });

  group('El grupo de permisos se llama como el apartado', () {
    test('las dos uniones decididas para la nube', () {
      // No es que dos textos coincidan: es que el nombre SALE del apartado. Si
      // alguien renombrara el menú, esto cambiaría con él.
      expect(
        nombreDelGrupoDePermisos(ModuloCompany.purchasesInventory),
        'Compras e inventario',
      );
      expect(nombreDelGrupoDePermisos(ModuloCompany.assets), 'Activos');
    });

    test('nómina se agrupa bajo Personal, y cobranza bajo Finanzas', () {
      // El servidor tiene siete módulos y el menú nueve apartados: dos apartados
      // cubren dos módulos cada uno. Los permisos de nómina se buscan en Personal.
      expect(nombreDelGrupoDePermisos(ModuloCompany.payroll), 'Personal');
      expect(nombreDelGrupoDePermisos(ModuloCompany.collections), 'Finanzas');
    });

    test('el núcleo tiene su propio título', () {
      expect(nombreDelGrupoDePermisos(null), 'Núcleo de la empresa');
    });

    test('un módulo DESCONOCIDO se muestra con su código, no se oculta', () {
      // Si el servidor sembrara uno nuevo, aparecería feo —visible, corregible— en
      // vez de desaparecer con sus permisos dentro.
      expect(nombreDelGrupoDePermisos('modulo_nuevo'), 'modulo_nuevo');
    });
  });

  group('Qué permisos se muestran hoy', () {
    test('el NÚCLEO siempre, porque no depende de nada contratado', () {
      expect(permisosVisiblesDe(null), isTrue);
    });

    test('ningún módulo todavía, y eso es un hecho medido', () {
      // Lo único mudado es la estructura —áreas y sucursales— y Configuración, y sus
      // permisos son del núcleo. Cuando Personal se mude, su pestaña pasa a
      // `mudada: true` y esta prueba cambia con una línea.
      final visibles = [
        for (final m in ModuloCompany.todos)
          if (permisosVisiblesDe(m)) m,
      ];

      expect(
        visibles,
        isEmpty,
        reason:
            'Si un módulo se mudó, actualiza esta prueba. Si NO se mudó y aparece '
            'aquí, sus permisos se están mostrando sin pantalla que los use: '
            '${visibles.join(', ')}',
      );
    });

    test('un módulo DESCONOCIDO no se muestra', () {
      // Fail-closed: lo que no está declarado no se enseña.
      expect(permisosVisiblesDe('modulo_nuevo'), isFalse);
    });
  });

  group('Las pestañas', () {
    test('un apartado está mudado si y sólo si tiene una pestaña mudada', () {
      for (final a in apartados) {
        expect(
          a.mudado,
          a.pestanas.any((p) => p.mudada),
          reason: '«${a.nombre}» discrepa entre `mudado` y sus pestañas.',
        );
      }
    });

    test('Organización lleva las cuatro del escritorio, en su orden', () {
      // EL ORDEN ES EL DEL ESCRITORIO, y es lo que esta prueba fija: ahí Empresa va
      // primero aunque todavía no tenga pantalla. Reordenarlas «para que la mudada
      // quede al principio» rompería el parecido que la mudanza persigue.
      final org = apartados.firstWhere((a) => a.nombre == 'Organización');

      expect(org.pestanas.map((p) => p.nombre), [
        'Empresa',
        'Sucursales',
        'Puestos',
        'Áreas',
      ]);

      // ⚠️ ACTUALIZADA AL MUDAR PUESTOS. Antes afirmaba `['sucursales', 'areas']`, y
      // el número cambió porque el producto avanzó, no porque la prueba estuviera
      // mal. Lo que NO se hizo fue cambiar la lista y nada más: se afirma la
      // PROPIEDAD —las mudadas son las que tienen pantalla— y se niega lo que falta,
      // así que la próxima mudanza sólo mueve un nombre de un lado al otro.
      expect(
        org.pestanas.where((p) => p.mudada).map((p) => p.id),
        ['sucursales', 'puestos', 'areas'],
      );

      expect(org.pestanas.where((p) => !p.mudada).map((p) => p.id), ['empresa']);

      // Y las dos listas juntas son todas: ninguna pestaña se queda sin clasificar.
      expect(org.pestanasMudadas.length + 1, org.pestanas.length);
    });

    test('Configuración lleva Usuarios y Auditoría, con sus exigencias', () {
      final config = apartados.firstWhere((a) => a.nombre == 'Configuración');

      expect(config.pestanas.map((p) => p.nombre), ['Usuarios', 'Auditoría']);

      final usuarios = config.pestanas.firstWhere((p) => p.id == 'usuarios');
      final auditoria = config.pestanas.firstWhere((p) => p.id == 'auditoria');

      // USUARIOS ES DE MAESTRO: todas sus rutas lo exigen y a otro le responderían
      // 403, así que ofrecerla sería enseñar una puerta cerrada.
      expect(usuarios.soloMaestro, isTrue);
      expect(usuarios.permiso, isNull);

      // AUDITORÍA VA POR PERMISO, NO POR ROL, y la diferencia importa: se le puede
      // conceder a alguien que no administra el equipo.
      expect(auditoria.soloMaestro, isFalse);
      expect(auditoria.permiso, PermisoCompany.companyAuditRead);
    });

    test('Respaldo y Bóveda NO están, y no es un olvido', () {
      // El respaldo portable y la bóveda local son del producto de escritorio, donde
      // los datos viven en el disco de quien los usa. En la nube el respaldo es del
      // servidor.
      final config = apartados.firstWhere((a) => a.nombre == 'Configuración');
      final nombres = config.pestanas.map((p) => p.nombre).toList();

      expect(nombres, isNot(contains('Respaldo')));
      expect(nombres, isNot(contains('Bóveda')));
    });

    test('ninguna pestaña exige un permiso que no existe', () {
      // Un permiso mal tecleado no falla: simplemente no coincide nunca y la pestaña
      // no aparece — el peor fallo posible, porque parece una decisión.
      for (final a in apartados) {
        for (final p in a.pestanas) {
          if (p.permiso case final codigo?) {
            expect(
              PermisoCompany.todos,
              contains(codigo),
              reason:
                  'La pestaña «${p.nombre}» de «${a.nombre}» exige «$codigo», que no '
                  'está en el catálogo.',
            );
          }
        }
      }
    });

    test('ningún id de pestaña se repite dentro de su apartado', () {
      // El id es lo que se recuerda para volver a la pestaña elegida. Repetido,
      // volver abriría la otra.
      for (final a in apartados) {
        final ids = a.pestanas.map((p) => p.id).toList();

        expect(ids.toSet().length, ids.length, reason: 'En «${a.nombre}».');
      }
    });
  });

  group('Qué hacer con un apartado, según quién pregunta', () {
    final organizacion = apartados.firstWhere((a) => a.nombre == 'Organización');
    final configuracion = apartados.firstWhere((a) => a.nombre == 'Configuración');
    final personal = apartados.firstWhere((a) => a.nombre == 'Personal');

    test('un apartado SIN mudar es «Próximamente», para cualquiera', () {
      // Incluso para el Maestro con todos los permisos: no hay nada que abrir.
      expect(
        queHacerCon(
          personal,
          esMaestro: true,
          permisos: PermisoCompany.todos,
        ),
        QueHacerConElApartado.proximamente,
      );
    });

    test('Organización se abre con sólo tener acceso', () {
      // Sucursales y Áreas no exigen ni rol ni permiso: leer la estructura basta con
      // estar dentro de la empresa, y así lo expone el servidor.
      expect(
        queHacerCon(organizacion, esMaestro: false, permisos: const {}),
        QueHacerConElApartado.seAbre,
      );
    });

    test('Configuración NO APARECE para quien no es Maestro ni lee auditoría', () {
      // ÉSTE ES EL CASO QUE NO SE PUEDE CONFUNDIR CON «Próximamente». El apartado
      // está mudado; lo que pasa es que no es para esta persona.
      expect(
        queHacerCon(configuracion, esMaestro: false, permisos: const {}),
        QueHacerConElApartado.noAparece,
      );
    });

    test('Configuración se abre para un Maestro', () {
      expect(
        queHacerCon(configuracion, esMaestro: true, permisos: const {}),
        QueHacerConElApartado.seAbre,
      );

      // Y le ofrece las dos: Usuarios por su rol, Auditoría porque un Maestro hereda
      // los permisos core.
      expect(
        pestanasPara(
          configuracion,
          esMaestro: true,
          permisos: {PermisoCompany.companyAuditRead},
        ).map((p) => p.id),
        ['usuarios', 'auditoria'],
      );
    });

    test('con sólo el permiso de auditoría se abre, y con UNA sola pestaña', () {
      // Alguien de cumplimiento puede leer la auditoría sin administrar el equipo.
      // Entonces Configuración existe para él y Usuarios no está.
      final pestanas = pestanasPara(
        configuracion,
        esMaestro: false,
        permisos: {PermisoCompany.companyAuditRead},
      );

      expect(
        queHacerCon(
          configuracion,
          esMaestro: false,
          permisos: {PermisoCompany.companyAuditRead},
        ),
        QueHacerConElApartado.seAbre,
      );

      expect(pestanas.map((p) => p.id), ['auditoria']);
    });

    test('un Maestro SIN el permiso de auditoría no ve esa pestaña', () {
      // En la práctica un Maestro lo hereda, pero la pestaña no lo da por hecho: lee
      // los permisos EFECTIVOS que calculó el servidor, no una regla propia.
      expect(
        pestanasPara(
          configuracion,
          esMaestro: true,
          permisos: const {},
        ).map((p) => p.id),
        ['usuarios'],
      );
    });

    test('ningún apartado mudado se queda sin pestañas para un Maestro', () {
      // Si pasara, el Maestro vería un apartado que no puede abrir — y con la regla
      // de arriba, ni lo vería. Sería un apartado invisible para todos.
      for (final a in apartados) {
        if (!a.mudado) continue;

        expect(
          pestanasPara(a, esMaestro: true, permisos: PermisoCompany.todos),
          isNotEmpty,
          reason: '«${a.nombre}» está mudado y nadie podría abrirlo.',
        );
      }
    });
  });

  group('El nombre del MÓDULO no es el del apartado', () {
    // ⚠️ ESTA DIFERENCIA LA CAZÓ LA SUITE COMPLETA, y por eso tiene su propio grupo.
    //
    // Al unificar los nombres en un solo archivo, la auditoría empezó a decir «Activó
    // el módulo Personal» cuando el hecho registrado era `module: payroll`. Eso es
    // FALSO: lo que se encendió fue Nómina. Son dos preguntas y tienen dos respuestas.

    test('la auditoría nombra el hecho exacto', () {
      expect(nombreDelModulo(ModuloCompany.payroll), 'Nómina');
      expect(nombreDelModulo(ModuloCompany.collections), 'Cobranza');
      expect(nombreDelModulo(ModuloCompany.clientsServices), 'Clientes y servicios');
    });

    test('el panel de permisos agrupa por apartado', () {
      expect(nombreDelGrupoDePermisos(ModuloCompany.payroll), 'Personal');
      expect(nombreDelGrupoDePermisos(ModuloCompany.collections), 'Finanzas');
    });

    test('y los dos DISCREPAN en los módulos que comparten apartado', () {
      // Si alguna vez coincidieran para los cuatro, sería la señal de que alguien
      // volvió a unificarlos y la auditoría volvió a mentir.
      for (final m in [
        ModuloCompany.payroll,
        ModuloCompany.collections,
        ModuloCompany.clientsServices,
      ]) {
        expect(
          nombreDelModulo(m),
          isNot(equals(nombreDelGrupoDePermisos(m))),
          reason:
              'El módulo «$m» y su apartado tendrían el mismo nombre, así que la '
              'auditoría diría el del apartado y no el del módulo.',
        );
      }
    });

    test('los siete módulos tienen nombre propio', () {
      final sinNombre = [
        for (final m in ModuloCompany.todos)
          if (!nombresDeModulo.containsKey(m)) m,
      ];

      expect(
        sinNombre,
        isEmpty,
        reason:
            'Estos módulos saldrían con su código en la auditoría: '
            '${sinNombre.join(', ')}',
      );
    });

    test('un módulo DESCONOCIDO se devuelve tal cual, no se oculta', () {
      expect(nombreDelModulo('modulo_nuevo'), 'modulo_nuevo');
    });
  });

  group('Las pestañas se muestran TODAS, mudadas o no', () {
    final organizacion = apartados.firstWhere((a) => a.nombre == 'Organización');

    test('Organización enseña las cuatro, en el orden del escritorio', () {
      // Mostrar sólo las dos que tienen pantalla haría pensar que el producto perdió
      // Empresa y Puestos. Aparecen, y al abrirlas se explica.
      expect(
        pestanasPara(organizacion, esMaestro: false, permisos: const {})
            .map((p) => p.nombre),
        ['Empresa', 'Sucursales', 'Puestos', 'Áreas'],
      );
    });

    test('pero NO todas están mudadas, y eso es el punto', () {
      // Lo que esta prueba vigila no es CUÁNTAS están mudadas —eso cambia cada vez
      // que se muda una— sino que `pestanasPara` devuelva **las dos clases**: si
      // filtrara por `mudada`, Empresa desaparecería y el menú perdería una pestaña
      // del escritorio sin que nadie lo decidiera.
      final suyas = pestanasPara(
        organizacion,
        esMaestro: false,
        permisos: const {},
      );

      expect(suyas.any((p) => p.mudada), isTrue, reason: 'Ninguna tiene pantalla.');
      expect(
        suyas.any((p) => !p.mudada),
        isTrue,
        reason:
            'Si TODAS están mudadas, esta prueba ya no distingue nada: cambia el '
            'apartado de ejemplo por uno que tenga pestañas pendientes.',
      );
    });

    test('la que exige rol o permiso SÍ se filtra, y no es lo mismo', () {
      // Una pestaña sin mudar se enseña y se explica —va a llegar—. Una que no te
      // toca no se enseña: no tenerla no es algo que esté por llegar.
      final configuracion = apartados.firstWhere((a) => a.nombre == 'Configuración');

      expect(
        pestanasPara(configuracion, esMaestro: false, permisos: const {}),
        isEmpty,
      );
    });
  });

  group('Por dónde se empieza', () {
    final organizacion = apartados.firstWhere((a) => a.nombre == 'Organización');

    test('la primera DISPONIBLE, no la primera de la lista', () {
      // El orden del escritorio empieza por Empresa, que no tiene pantalla. Abrir ahí
      // recibiría a todo el mundo con un «Próximamente» teniendo Sucursales al lado.
      final suyas = pestanasPara(
        organizacion,
        esMaestro: true,
        permisos: PermisoCompany.todos,
      );

      expect(suyas.first.id, 'empresa');
      expect(primeraDisponible(suyas)?.id, 'sucursales');
    });

    test('sin ninguna mudada devuelve null, y no finge', () {
      // Quien llama no debería haber llegado ahí —`queHacerCon` ya lo dijo— y un
      // «primera de la lista» escondería ese error.
      const ninguna = [
        PestanaDeApartado(id: 'a', nombre: 'A', mudada: false),
        PestanaDeApartado(id: 'b', nombre: 'B', mudada: false),
      ];

      expect(primeraDisponible(ninguna), isNull);
    });

    test('la SESIÓN empieza en el primer apartado con pantalla, no en Dashboard', () {
      // Dashboard es el primero del menú y está en «Próximamente»: recibir ahí haría
      // pensar que no hay nada hecho. Y sale del MISMO registro, así que el día que
      // Dashboard se mude, la sesión empezará ahí sin tocar una línea de la pantalla.
      final primero = primerApartadoConPantalla(
        esMaestro: true,
        permisos: PermisoCompany.todos,
      );

      expect(primero?.nombre, 'Organización');
      expect(apartados.first.nombre, 'Dashboard');
      expect(apartados.first.mudado, isFalse);
    });

    test('quien no es Maestro también empieza en Organización', () {
      // Su estructura se lee con sólo tener acceso, así que no hay nadie con acceso
      // que entre a un «Próximamente».
      expect(
        primerApartadoConPantalla(esMaestro: false, permisos: const {})?.nombre,
        'Organización',
      );
    });
  });

  group('Las pestañas tienen ícono propio', () {
    // ⚠️ SIN ESTO TODAS SALÍAN CON EL ÍCONO DEL APARTADO, y Puestos enseñaba el mismo
    // edificio que Empresa: las dos parecían la misma cosa sin terminar. Lo cazó una
    // revisión en pantalla, no una prueba.
    test('ninguna pestaña de Organización repite el ícono de otra', () {
      final org = apartados.firstWhere((a) => a.nombre == 'Organización');
      final iconos = [for (final p in org.pestanas) p.icono];

      expect(iconos, everyElement(isNotNull));
      expect(
        iconos.toSet().length,
        iconos.length,
        reason: 'Dos pestañas con el mismo ícono se leen como la misma cosa.',
      );
    });

    test('y ninguna repite el del apartado que las contiene', () {
      for (final a in apartados) {
        for (final p in a.pestanas) {
          if (p.icono == null) continue;

          expect(
            p.icono,
            isNot(equals(a.icono)),
            reason:
                'La pestaña «${p.nombre}» usa el mismo ícono que «${a.nombre}», así '
                'que su aviso de «Próximamente» no se distingue del del apartado.',
          );
        }
      }
    });

    test('Puestos ya está mudado, así que Organización sólo espera Empresa', () {
      final org = apartados.firstWhere((a) => a.nombre == 'Organización');

      expect(
        org.pestanas.where((p) => !p.mudada).map((p) => p.id),
        ['empresa'],
      );
    });
  });
}
