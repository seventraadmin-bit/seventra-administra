import 'package:flutter/material.dart';

import '../../../core/company/company_remota.dart';
import '../../../core/company/gestor_de_company.dart';
import 'marca_seventra.dart';
import 'mensajes_humanos.dart';

/// Elegir con qué empresa entrar.
///
/// 🚫 **ESTA PANTALLA NO SE VE CUANDO HAY UNA SOLA EMPRESA**, y no porque aquí se
/// compruebe: `GestorDeCompany` ya resuelve ese caso antes de publicar un estado
/// —con una, la abre; con varias, pide elegir si no hay una recordada válida—. Si
/// además se comprobara aquí, habría dos sitios decidiendo lo mismo y podrían
/// discrepar. Esta pantalla sólo existe para el estado
/// [SeleccionDeCompanyRequerida], y el portón es quien la monta.
///
/// **El orden de la lista es el del servidor**, que la entrega por Organization y
/// luego por nombre. No se reordena: sería duplicar una decisión ya tomada, y
/// divergiría el día que el backend la cambie.
///
/// LA ORGANIZATION SE MUESTRA, y hace falta: una misma persona puede tener acceso a
/// «Administración» en dos clientes distintos, y el nombre de la empresa solo no los
/// distingue. Lo que **no** se muestra es el rol —`maestro` o `user`—: es
/// vocabulario del modelo de permisos, no algo que ayude a elegir.
class SelectorDeEmpresaScreen extends StatefulWidget {
  const SelectorDeEmpresaScreen({
    required this.gestor,
    required this.disponibles,
    required this.alCerrarSesion,
    super.key,
  });

  final GestorDeCompany gestor;

  /// Las empresas a elegir, **tal como llegaron en el estado**.
  ///
  /// Se reciben en vez de leerse de `gestor.disponibles` para que lo que se pinta
  /// sea exactamente lo que el estado dijo. Leerlas del gestor abriría la ventana
  /// de pintar una lista que otra resolución ya cambió.
  final List<CompanyDisponible> disponibles;

  /// Para salir de una cuenta que no es la que se quería. Sin esto, quien entra con
  /// el correo equivocado se queda mirando empresas ajenas sin ninguna salida.
  final Future<void> Function() alCerrarSesion;

  @override
  State<SelectorDeEmpresaScreen> createState() =>
      _SelectorDeEmpresaScreenState();
}

class _SelectorDeEmpresaScreenState extends State<SelectorDeEmpresaScreen> {
  /// Cuál se está abriendo. Es el id y no un `bool` porque hay que señalar **esa**
  /// fila mientras las demás se deshabilitan; un `bool` las haría parpadear todas.
  String? _abriendo;

  String? _error;

  Future<void> _abrir(CompanyDisponible empresa) async {
    setState(() {
      _abriendo = empresa.companyId;
      _error = null;
    });

    final resultado = await widget.gestor.cambiarA(empresa.companyId);

    if (!mounted) return;

    resultado.when(
      // NO SE NAVEGA DESDE AQUÍ, igual que en el login: el gestor publica
      // `CompanyActiva` y el portón decide. Esta pantalla sólo se queda esperando a
      // que la desmonten.
      ok: (_) => setState(() => _abriendo = null),
      failure: (fallo) => setState(() {
        _abriendo = null;
        _error = MensajesHumanos.deEmpresa(fallo);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final abriendo = _abriendo != null;

    return Scaffold(
      backgroundColor: MarcaSeventra.fondo,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: LogotipoSeventra(alto: 28)),
                const SizedBox(height: 28),
                const Text(
                  'Elige una empresa',
                  style: TextStyle(
                    color: MarcaSeventra.tinta,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tienes acceso a más de una. Podrás cambiar después.',
                  style: TextStyle(color: MarcaSeventra.suave, fontSize: 13.5),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  _Aviso(_error!),
                  const SizedBox(height: 16),
                ],
                for (final empresa in widget.disponibles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FilaDeEmpresa(
                      empresa: empresa,
                      abriendoEsta: _abriendo == empresa.companyId,
                      // Mientras una se abre, las demás se deshabilitan: dos
                      // selecciones a la vez dejarían a la segunda ganando la
                      // carrera, y el usuario entraría a la que no pulsó último.
                      habilitada: !abriendo,
                      alPulsar: () => _abrir(empresa),
                    ),
                  ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: abriendo ? null : widget.alCerrarSesion,
                    style: TextButton.styleFrom(
                      foregroundColor: MarcaSeventra.suave,
                    ),
                    child: const Text('Entrar con otra cuenta'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilaDeEmpresa extends StatelessWidget {
  const _FilaDeEmpresa({
    required this.empresa,
    required this.abriendoEsta,
    required this.habilitada,
    required this.alPulsar,
  });

  final CompanyDisponible empresa;
  final bool abriendoEsta;
  final bool habilitada;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: habilitada ? alPulsar : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: abriendoEsta ? MarcaSeventra.verde : MarcaSeventra.borde,
            width: abriendoEsta ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    empresa.companyName,
                    style: const TextStyle(
                      color: MarcaSeventra.tinta,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    empresa.organizationName,
                    style: const TextStyle(
                      color: MarcaSeventra.suave,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (abriendoEsta)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: MarcaSeventra.verde,
                ),
              )
            else
              const Icon(
                Icons.chevron_right,
                size: 22,
                color: MarcaSeventra.suave,
              ),
          ],
        ),
      ),
    ),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.mensaje);

  final String mensaje;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0x0F9A2B2B),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x339A2B2B)),
    ),
    child: Text(
      mensaje,
      style: const TextStyle(
        color: MarcaSeventra.rojo,
        fontSize: 13.5,
        height: 1.35,
      ),
    ),
  );
}
