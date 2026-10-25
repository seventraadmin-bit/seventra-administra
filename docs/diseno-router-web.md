# El router de la web — diseño de D-39

**Estado:** propuesto el 25 de octubre de 2026, **sin implementar**. Cambia la arquitectura de
navegación de Administra en la nube, así que se aprueba antes de escribir código.

**Qué deuda paga:** **D-39**, «la vía del `bool` en Sucursales, que el router haría innecesaria».

---

## 1. Qué está mal hoy, en concreto

La web no tiene router a propósito ([`main_web.dart`](../lib/main_web.dart) usa `MaterialApp` con
`home:`, no `MaterialApp.router`), y eso fue correcto mientras hubo **una** pantalla dentro. Con
cuatro pestañas en Organización, dos en Configuración y pantallas que abren cosas **dentro** de
una pestaña, el portón acabó guardando a mano tres cosas que son, literalmente, una dirección:

| En el portón | Qué es en realidad |
|---|---|
| `_rutaDeSeccion` | el primer segmento: `/organizacion` |
| `_pestanaPorApartado` | el segundo: `sucursales` |
| `_rastroDentro` | el tercero: `tipos` |

Y la tercera no se puede deducir desde arriba, porque vive dentro de la pantalla. De ahí salió
`alCambiarElRastro`: **la pantalla le avisa al portón** de lo que abrió, para que el rastro no
mienta. Dos pantallas publican hacia arriba por esa vía, y cada una tiene que acordarse de
avisar también al volver.

**Eso es la deuda.** No es que la vía esté mal escrita —está concentrada en un solo método,
`_verTipos`, justamente para que nadie cambie el estado sin avisar—: es que no debería existir.
Quien sabe dónde estás es la dirección, no un callback.

---

## 2. La regla que el router NO puede romper

> **Lo que se ve depende de la sesión y de la empresa, no de la URL.**

Está escrita en el portón y en `main_web.dart`, y es la razón por la que no hubo rutas hasta hoy.
El router **no la cambia**: la implementa con un `redirect` que pregunta a los dos gestores antes
de dejar entrar a cualquier ruta.

Tres consecuencias que no se negocian:

1. **Una dirección escrita a mano no concede nada.** Si no hay sesión, el `redirect` manda a
   entrar; si la empresa no está resuelta, al selector. La ruta pedida se recuerda y se recupera
   **sólo si la sesión acabó permitiéndola**.
2. **Los permisos siguen saliendo del servidor.** Una ruta visible no es un permiso: cada
   pantalla recibe sus capacidades del contexto que confirmó el servidor, igual que hoy. El
   router decide *dónde estás*, nunca *qué puedes*.
3. **La empresa NO va en la URL.** Ver §3.

---

## 3. La empresa no es parte de la dirección

**Decisión:** la URL dice dónde estás dentro de Administra; **con qué empresa es estado de la
sesión**, y no aparece en la dirección.

**Por qué**, y es E1-B: cambiar de empresa se hace **sólo desde la barra inferior**, y con varias
**se pregunta siempre al entrar**. Una URL con la empresa dentro sería un enlace que cambia de
empresa al abrirlo —exactamente lo que E1-B prohibió— y además convertiría «consultar» en
«cambiar», que es la distinción que esa etapa estableció.

**Lo que sí hace falta:** al cambiar de empresa, **la parte de dentro de la ruta se limpia**. Un
`/organizacion/sucursales/<id>/expediente` de la empresa A no sobrevive a la B —ese id allí no
existe, y la pantalla recibiría un 404 que nadie pidió—, así que el cambio te deja en el apartado,
no en lo que estabas mirando.

---

## 4. La forma de las rutas

Los apartados **ya tienen ruta** en [`apartados_web.dart`](../lib/app/shell/apartados_web.dart)
—`/organizacion`, `/configuracion`, `/comercial`…— y las pestañas ya tienen `id`. El router no
inventa nombres: los usa.

```
/entrar                                        ← login
/elegir-empresa                                ← selector (sólo si hay varias)

/organizacion                                  → redirige a la primera pestaña visible
/organizacion/empresa
/organizacion/sucursales
/organizacion/sucursales/tipos                 ← el `bool` de hoy, hecho ruta hija
/organizacion/sucursales/<id>/expediente       ← lo que hoy es otro estado interno
/organizacion/puestos
/organizacion/areas
/configuracion/usuarios
/configuracion/auditoria
```

Un apartado no mudado —`/personal`, `/finanzas`— sigue existiendo como ruta y sigue enseñando su
«Próximamente»: la pestaña atenuada **sí se abre**, y eso no cambia.

---

## 5. El rastro sale de la ruta

Con esto, `dentroDeLaPestana`, `_rastroDentro` y `alCambiarElRastro` **desaparecen**: el marco lee
los segmentos de la ruta activa y los traduce a nombres con el mismo registro de apartados. Las
dos pantallas que hoy publican hacia arriba dejan de hacerlo; navegan, y el rastro se entera
porque la dirección cambió.

«Organización › Sucursales › Tipos de sucursal» deja de depender de que alguien se acuerde de
avisar.

---

## 6. Lo que hay que conservar, y es lo que más cuida este diseño

| Hoy funciona así | Con router |
|---|---|
| **Se abre el primer apartado CON PANTALLA**, no el primero del menú (Dashboard no está mudado) | la ruta inicial sale del mismo registro, igual que hoy |
| **Se recuerda la pestaña de cada apartado**: vuelves a Configuración y sigues en Usuarios | hace falta memoria aparte, porque la URL sólo guarda **dónde estás ahora**. Se guarda la última ruta visitada por apartado, y el menú lateral navega a ella |
| **La pestaña se recuerda por `id`, no por posición** | igual: la ruta lleva el `id` |
| **Al cambiar de apartado se limpia lo de dentro** | lo hace la propia ruta |

La segunda fila es la única función que el router **no** regala y que un cambio descuidado
perdería. Es la que hay que probar.

---

## 7. Los cinco casos que prueban la frontera

1. **Dirección pedida sin sesión** → entra al login y, al autenticarse, aterriza en la pedida
   —si la sesión la permite—; si no, en la primera con pantalla.
2. **Dirección de una pestaña que esta sesión no ve** (una de Maestro, sin serlo) → el apartado,
   en su primera pestaña visible. **No un 404 ni una pantalla vacía.**
3. **Cambio de empresa estando dentro** → el apartado, con lo de dentro limpio (§3).
4. **Dirección de un apartado no mudado** → su «Próximamente», que es lo que hace hoy.
5. **Atrás del navegador** → vuelve a la pestaña anterior, no cierra la sesión. Es la función que
   hoy no existe y que el router añade; probarla es parte del precio.

---

## 8. La decisión abierta: `/ruta` o `/#/ruta`

| | URL con `#` | URL limpia |
|---|---|---|
| Se ve | `…/#/organizacion/sucursales` | `…/organizacion/sucursales` |
| Hace falta en el servidor | **nada** | que **toda** ruta devuelva `index.html` |
| Riesgo de despliegue | ninguno | si falta la regla, recargar en `/organizacion` da 404 |

**Recomiendo empezar con `#`** y pasar a la URL limpia cuando el hospedaje definitivo esté
decidido: el cambio es una línea, y así el router no arrastra una decisión de infraestructura.

---

## 9. Costo y cuándo

El cambio toca `main_web.dart`, el portón entero —es quien hoy decide qué se muestra—, las dos
pantallas que publican hacia arriba y el marco. Más las pruebas de los cinco casos de §7 y la de
la memoria por apartado de §6.

**Mi recomendación sobre el cuándo:** dentro de C1, pero **junto con las pantallas de Clientes y
servicios**, no antes. La razón es que C1 trae un apartado nuevo con pestañas y con cosas que se
abren dentro —un cliente, sus contactos, sus servicios—, y son esas rutas las que fijan la forma
definitiva. Hacerlo antes significa diseñar las rutas de un apartado que todavía no existe, y
volver a tocarlo cuando exista.
