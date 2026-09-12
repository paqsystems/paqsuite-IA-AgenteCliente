# 02 — Decisiones técnicas

| Campo | Valor |
|-------|--------|
| Fecha | 2026-09-03 |
| Estado | Vigente para el MVP |
| Relacionado | [01-SPEC-producto.md](01-SPEC-producto.md) |

Toda implementación que viole una decisión de este archivo se rechaza. Si hay que cambiarla, se actualiza **este** documento primero.

---

## D1 — Lenguaje de programación

### Decisión

| Pieza | Lenguaje | Runtime |
|-------|----------|---------|
| PaqAgent (servicio en el cliente) | **C#** | .NET 8 Worker Service, Windows Service |
| PaqGateway (Amazon) | **C#** | .NET 8 ASP.NET Core + SignalR |
| Auto-instalador | **C#** | .NET 8 WinForms (o WPF), Windows x64 |
| Contratos compartidos Agent ↔ Gateway | **C#** | proyecto `PaqContracts` |
| App PaqSuite (ya existe) | **PHP** | Laravel (repo `PaqSuite-IA-TANGO`) |
| Consultas Tango | **T-SQL** | stored procedures `PAQ_*` en SQL Server del cliente |

### Por qué C# (y no otro)

1. El agente corre en **Windows Server** al lado de SQL Server Tango. Windows Service es ciudadano de primera en .NET.
2. **SignalR** es nativo en ASP.NET y en el cliente .NET: reconexión, keep-alive y hub ya resueltos. Rehacerlo en Node/Go/Python es costo puro.
3. **Microsoft.Data.SqlClient** es el driver oficial de SQL Server (instancias con nombre, puertos no estándar, TLS).
4. El instalador es UI de escritorio Windows: WinForms en .NET es el camino corto y soportable.
5. Agent y Gateway en el **mismo lenguaje** = un solo contrato (`PaqContracts`), menos bugs de serialización.
6. El equipo y el código de referencia ya están en C#. Reformular no significa cambiar de ecosistema; significa cerrar el SPEC y no arrastrar Tailscale.

### Qué no se elige

| Alternativa | Por qué no |
|-------------|------------|
| Node / TypeScript en el agente | Servicio Windows y SQL Server son de segunda. Instalador pobre. |
| Python | Mismo problema. Empaquetado en cliente final peor. |
| Go | Buen Gateway, mal instalador Windows y peor historia SQL Server + SignalR. |
| Reescribir Laravel en .NET | Fuera de alcance. Laravel se queda. El Gateway es el puente. |

### Dependencias .NET permitidas (MVP)

- `Microsoft.Extensions.Hosting.WindowsServices`
- `Microsoft.AspNetCore.SignalR` / `SignalR.Client`
- `Microsoft.Data.SqlClient`
- `Serilog` + sink de archivo
- `Polly` (reconexión)
- WinForms + `System.Text.Json` en el instalador

Nada más en el MVP sin actualizar este archivo.

---

## D2 — Tailscale no es parte del producto

Tailscale apareció porque el camino **viejo** era Laravel → VPN → SQL 1433. El agente existe para **eliminar** ese camino.

Permitido:

- Que un técnico de PaqSystems use Tailscale para **entrar a administrar** un servidor (RDP/SSH de soporte), igual que cualquier otra herramienta de acceso remoto.

Prohibido:

- Poner IPs Tailscale en `empresas_conexion.host`.
- Levantar el Gateway de producción detrás de Tailscale.
- Documentar Tailscale como requisito del cliente.
- Fallback “si el agente no está, conecto SQL por Tailscale”.
- Medir rendimiento usando `host` = IP pública o IP Tailscale.

El runbook de desarrollo, si existe, usa `localhost` o la VPC. No Tailscale.

---

## D3 — Dónde vive cada secreto

| Secreto | Dónde | Quién lo carga |
|---------|--------|----------------|
| Usuario/password SQL Tango | Solo el servidor del cliente (`appsettings.local.json`) | Instalador |
| AgentToken (valor) | Cliente: `appsettings.local.json`. AWS: hash o secreto en catálogo | Alta Laravel + instalador |
| API key Laravel ↔ Gateway | AWS (Forge / env del Gateway) | Operador PaqSystems |
| Connection string SQL en Laravel | **No existe** en modo agente | — |

---

## D4 — Token del agente en Laravel

Decisión MVP:

- Tabla `empresas_conexion` (o tabla hija `agents` 1:1 con el tenant) guarda `agent_id`, `client_id` y el **hash** del token (o el token cifrado con `APP_KEY`, igual que hoy `password` SQL).
- Al dar de alta, Laravel **muestra el token una vez** (pantalla o descarga de ficha de instalación).
- El Gateway valida el token llamando a Laravel (`POST /api/internal/gateway/authenticate`) o leyendo el mismo catálogo. Una sola fuente de verdad.

No se hardcodea la lista de agentes en `appsettings` del Gateway en producción.

---

## D5 — `host` en `empresas_conexion`

- En modo agente: **nullable y no consultado**.
- Migración Laravel: `host` y `port` pasan a nullable; validación de alta de cliente agente no los exige.
- Cualquier código Laravel que abra SQL con `host` del tenant queda **fuera del camino de producción** (se puede dejar muerto o detrás de un flag `AGENT_SQL_DIRECT_FALLBACK=false` por defecto, y en producción el flag no se prende).

---

## D6 — Repos y ramas

| Repo | Rama sugerida | Contenido |
|------|----------------|-----------|
| `paqsuite-IA-AgenteCliente` | `sdd-reformulacion` | Agente, Gateway, instalador, docs de deploy |
| `PaqSuite-IA-TANGO` | rama equivalente | Contrato `empresas_conexion` + `AgentGatewayClient` + quitar fallback |

El `main` actual del agente se conserva como referencia hasta el corte. No se “limpia” main reescribiendo encima sin piloto verde.

Convención de código en C#: **camelCase** en variables, propiedades, métodos y funciones (regla de casa). Tipos y archivos: convención .NET habitual (`PascalCase` en tipos públicos si el linter del repo lo exige — **excepción documentada**: el usuario pidió camelCase en miembros; el SPEC de implementación de cada TR lo respeta en lógica nueva).

Aclaración práctica para el agente de IA: en C# los tipos públicos siguen PascalCase (`class AgentWorker`); campos, parámetros, variables locales y nombres JSON: camelCase. Propiedades públicas de DTOs que serializan a JSON: camelCase en JSON (`JsonNamingPolicy.CamelCase`).

---

## D7 — Operaciones: genéricas, no una clase por SP

El registro de operaciones es **configuración** (nombre → stored procedure → parámetros permitidos → connection `dictionary` | `company`).

Se escribe un handler genérico. Solo se hace clase específica si hay lógica que el genérico no cubre (hoy: `auth.login` multi result set, `diagnostics.run`).

Está prohibido copiar 40 clases casi idénticas. Eso fue síntoma del desvío anterior.

El MVP registra únicamente:

- `diagnostics.run`
- `auth.login` **o** `clientes.buscar` (una piloto, no las dos obligatorias; recomendada `diagnostics.run` + `auth.login` porque el login ya es el cuello que el usuario siente)

Fase 2: ir portando SPs existentes como **datos de configuración**, no como features nuevas de arquitectura.

---

## D8 — Entornos

| Entorno | Gateway | Agente |
|---------|---------|--------|
| Desarrollo | `http://127.0.0.1:5100` en la misma máquina o VPC de dev | `GatewayUrl` a ese hub |
| Staging | Gateway en AWS staging | Un agente de laboratorio |
| Producción | `https://gateway.paqsuite.com/agent-hub` | Instalador con esa URL por defecto |

No hay entorno “PC del programador + Tailscale + SQL de cliente real” como camino oficial.

---

## D9 — Descarga del instalador (MVP)

El repo de GitHub es público. El MVP usa:

```text
https://github.com/paqsystems/paqsuite-IA-AgenteCliente/releases/latest
```

Assets: `PaqAgentInstaller.zip` (el .exe que el cliente corre) y, si aplica, runtime .NET 8 Desktop documentado.

Fase 2: botón “Descargar agente” dentro de PaqSuite que apunte a ese release o a un bucket propio. No bloquea el MVP.

---

## D10 — Qué se puede reutilizar del código actual

Permitido reutilizar **después de leer el SPEC**, no copiar el híbrido:

- Contratos JSON de job/result.
- `SqlExecutor` parametrizado.
- Migraciones `PAQ_*` (fase 2).
- Idea del instalador WinForms (rehacer la UI para incluir token y quitar defaults inseguros).

Prohibido reutilizar:

- Fallback SQL en Laravel.
- `InternalUrl` pensado para IP Tailscale como diseño de producción.
- `GITHUB_TOKEN = "CONFIGURAR-TOKEN-AQUI"` embebido; el repo es público, no hace falta token para bajar releases.
- `dev-agent-token` como default de instalación.
