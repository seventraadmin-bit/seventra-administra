# Compilar RISEG ONE para Windows

> **Por qué existe este documento.** El 6 de noviembre de 2026, al arreglar un defecto de
> Reportes, hizo falta responder «¿la versión que uso en operación lo tiene, y necesita
> compilación nueva?» — y **no había ningún procedimiento escrito**: ni guion, ni documento,
> ni nota. Los comandos de abajo se derivaron de la evidencia de la propia máquina (la
> carpeta `build\windows\x64\runner\Release\` sólo la produce `flutter build windows`), no de
> la memoria de nadie. La regla de la casa es que **los comandos locales se copian**, y para
> copiarlos tienen que estar escritos.

## Antes de nada: ¿hace falta?

Un arreglo de la web **no** llega al escritorio: son el mismo repositorio pero dos
artefactos. El escritorio es un ejecutable compilado, así que **cualquier cambio en `lib/`
que toque el escritorio exige recompilar**, y hasta entonces la máquina sigue corriendo el
binario viejo.

**Cómo saber qué binario estás usando y de cuándo es:**

```powershell
Get-ChildItem C:\ -Filter riseg_one.exe -Recurse -ErrorAction SilentlyContinue -Force |
  Select-Object FullName, LastWriteTime
```

Medido el 6-nov-2026: en esta máquina **no hay instalación** —ni en `Program Files`, ni en
`LocalAppData\Programs`, ni acceso directo en el menú—, sólo las dos carpetas de compilación
del repositorio (`Release` y `Debug`). O sea que **el ejecutable que se usa es el de
`build\windows\x64\runner\Release\`**, y su fecha dice qué código tiene dentro.

## ⚠️ Lo que hay que saber antes de compilar

1. **Compilar SOBREESCRIBE la carpeta que usas hoy.** Si el build falla a medias te quedas
   sin el ejecutable que funcionaba. **Copia la carpeta antes**, y así puedes volver:

   ```powershell
   Copy-Item -Recurse `
     C:\Users\segur\riseg_control_activos\build\windows\x64\runner\Release `
     "C:\Users\segur\riseg-one-release-$(Get-Date -Format yyyyMMdd)"
   ```

2. **Cierra la aplicación antes.** Mientras corre, el `.exe` está bloqueado y el build falla
   con un error de escritura que no dice que la culpa es eso.

3. **Tus datos NO están en la carpeta de compilación**, así que reemplazar el ejecutable no
   los toca. Viven en `C:\Users\segur\AppData\Roaming\RISEG\RISEG ONE\`.

4. **Y mira si el cambio sube `schemaVersion`.** Si lo sube, al abrir migra la base local y
   eso **no se revierte**: ahí sí conviene respaldar los datos además del ejecutable. Un
   arreglo que sólo toca presentación —como el del rango de Reportes— no sube nada y no
   migra nada.

## El paso a paso

```powershell
# 1 · El repositorio, y en la rama que lleva el arreglo.
cd C:\Users\segur\riseg_control_activos
git log --oneline -3

# 2 · Dependencias. Rápido si no cambiaron, y obligatorio si cambió `pubspec.yaml`.
flutter pub get

# 3 · El build. Varios minutos la primera vez.
#
# ⚠️ EL `--dart-define` NO ES OPCIONAL. Sin él la aplicación ARRANCA Y NO ABRE VENTANA.
flutter build windows --release `
  --dart-define=SEVENTRA_API_BASE_URL=http://localhost:5080
```

**Qué tiene que decir al terminar:** `√ Built build\windows\x64\runner\Release\riseg_one.exe`.
Si en vez de eso habla de Visual Studio, falta el conjunto de herramientas de C++ — estaba
instalado el 17-oct-2026, que es cuando se produjo el binario actual.

### ⚠️ Por qué el `--dart-define` y qué pasa si falta

**La primera versión de este documento lo omitía, y el resultado fue un ejecutable que no
abre ninguna ventana** — diagnosticado el 6-nov-2026, y lo mismo le pasaba al binario del
17-oct, que tampoco lo llevaba.

`ApiConfig` lee la dirección con `String.fromEnvironment('SEVENTRA_API_BASE_URL'), que es
**de tiempo de compilación**, y `bootstrap()` la valida **antes de abrir nada** y **lanza**
si falta —a propósito: «fallar al arrancar y no en la primera petición es deliberado»—. Pero
la excepción ocurre **antes de `runApp`**, y el runner de Flutter muestra la ventana cuando
se dibuja el primer fotograma. Así que:

- la ventana **se crea y nunca se muestra** (`FLUTTER_RUNNER_WIN32_WINDOW`, `Visible=False`);
- el proceso **queda vivo con ~0 s de CPU** y `MainWindowHandle = 0`;
- **no hay nada que leer en ningún sitio**: el registro es `AppLogger.console()` y una
  aplicación de ventana no tiene consola, así que ni stdout, ni archivo, ni Visor de eventos.

**Cómo confirmar que a un ejecutable le falta la URL**, sin ejecutarlo:

```powershell
$so = "C:\Users\segur\riseg_control_activos\build\windows\x64\runner\Release\data\app.so"
$txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($so))
([regex]'https?://[A-Za-z0-9\.\-]{4,60}').Matches($txt) |
  ForEach-Object { $_.Value } | Sort-Object -Unique |
  Where-Object { $_ -match 'seventra|localhost' }
```

Si no imprime nada, el `--dart-define` no se pasó. Es la misma clase de fallo silencioso que
**D-66** ya tenía anotada para la web: *«un `--dart-define` mal escrito no da ningún error,
se ignora en silencio»*.

**Qué URL poner.** El escritorio es el producto LOCAL: sus datos están en SQLite y **no
llama a ningún backend** para nada de lo que se usa hoy. `http://localhost:5080` satisface
la validación —`http` sólo se admite para máquinas locales— y deja constancia de que ese
binario no habla con ninguna nube. Si algún día el escritorio consumiera la API, ahí va la
dirección real.

**La carpeta entera es el producto, no sólo el `.exe`:** junto a él van las DLL del motor y
`data\` con los recursos. Si copias el ejecutable solo a otro sitio, no arranca.

## Comprobar que el arreglo está dentro

El build nuevo se verifica **en pantalla**, y eso no se automatiza ni se da por hecho:

1. Abre la aplicación y entra a **Reportes › Finanzas**.
2. Captura un egreso **con la fecha de hoy**.
3. El KPI de **«Salidas de efectivo»** y la suma de la tabla de **«Egresos por categoría»**
   tienen que coincidir. Antes del arreglo del 6-nov-2026 no coincidían: el movimiento de hoy
   salía en el KPI y faltaba en la tabla y en el detalle que se abre en Excel, porque el
   preset «Este mes» termina hoy **a medianoche** y la tabla usaba ese extremo crudo.
4. Lo mismo en el detalle exportado a Excel.
