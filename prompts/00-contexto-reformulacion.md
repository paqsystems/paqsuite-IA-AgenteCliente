# 00 — Contexto de reformulación

| Campo | Valor |
|-------|--------|
| Fecha | 2026-09-03 |
| Autor | Pablo / PaqSystems |
| Estado | Vigente |
| Alcance | Producto Agente + Gateway. No es un parche del código actual. |

---

## 1. Objetivo del proyecto (una frase)

Poner un **agente en el servidor SQL del cliente** y un **gateway en Amazon**, de modo que la app PaqSuite en AWS consulte Tango **sin VPN, sin puertos entrantes en el cliente y sin conocer la IP pública del cliente**.

`empresas_conexion` guarda las **credenciales de ruteo** para que Laravel sepa *a qué agente* pedirle datos. El SQL se habla **en el servidor del cliente**, no desde AWS.

---

## 2. Por qué se reformula

El desarrollo actual (junio–septiembre 2026) produjo mucho código (agente, gateway, instalador, ~46 operaciones, 20 releases) pero **no cerró el objetivo**.

Lo que se observó:

1. No hay SPEC de producto cerrado ni circuito HU → TR. El trabajo se orientó por features (informes, acopios) sobre un caño de red incompleto.
2. Laravel sigue exigiendo `host` (IP) en `empresas_conexion` porque se dejó un **fallback SQL directo** por Tailscale. Ese fallback se volvió el camino real.
3. Por eso “solo funciona con Tailscale” y falla al poner la IP pública: se está midiendo el camino viejo (AWS abre 1433 hacia el cliente), no el agente.
4. El Gateway productivo en AWS quedó pendiente. El runbook más detallado levanta el Gateway en una PC de desarrollo vía Tailscale.
5. El instalador no pide `AgentToken` (escribe `dev-agent-token`). No hay un paquete de instalación para el cliente final.

No es falta de trabajo. Es falta de **objetivo cerrado y método**.

---

## 3. Qué se conserva como aprendizaje (no como base)

Se puede consultar, no copiar a ciegas:

- El diagrama de conexión saliente (arquitectura de junio) es correcto.
- SignalR + Windows Service + lista blanca de operaciones es el modelo adecuado.
- Las migraciones SQL `PAQ_*` ya escritas se podrán **reutilizar después del MVP**, cuando el caño esté verde.
- El instalador WinForms demostró que hace falta un .exe, no un script para desarrolladores.

Se descarta para el MVP paralelo:

- Fallback SQL directo / Tailscale como red de seguridad.
- `host` obligatorio en `empresas_conexion`.
- Porte masivo de operaciones antes de tener un cliente online por Internet.
- Gateway “en la notebook del programador” como entorno de verdad.

---

## 4. Cómo se trabaja en paralelo

1. Rama nueva en este repo (sugerida: `sdd-reformulacion`) o carpeta de implementación limpia según decida el SPEC técnico. El `main` actual no se pisa hasta el corte.
2. Contrato Laravel se especifica aquí y se implementa en `PaqSuite-IA-TANGO` en una HU dedicada.
3. Una HU a la vez. Criterios de aceptación verificables. Sin “mientras tanto agrego acopios”.
4. Tailscale puede existir en la red de PaqSystems para **acceso de soporte humano** a servidores. **No forma parte del producto.** No aparece en `empresas_conexion`, ni en el Gateway, ni en el instalador.

---

## 5. Pregunta que este paquete ya responde

> “Si el agente abre la conexión, ¿por qué Laravel necesita la IP del cliente?”

No la necesita. Si un diseño la pide, el diseño está mal. Ver SPEC sección 4 y decisiones técnicas.
