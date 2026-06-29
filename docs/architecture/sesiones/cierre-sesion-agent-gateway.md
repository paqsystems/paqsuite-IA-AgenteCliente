# Cierre de sesión — Integración Agent Gateway en PaqSuite-IA-TANGO

> Fecha: 26/06/2026
> Repos involucrados: `PaqSuite-IA-TANGO` (rama `deplyunificado`), `paqsuite-IA-AgenteCliente`
> Autor: Klaus, con asistencia de Cursor

---

## 1. Objetivo de la sesión

Reemplazar el esquema de conexión SQL directa (Laravel → VPN/Tailscale → SQL
Server del cliente) por un esquema de agente local + gateway, que evita
exponer puertos en la red del cliente y resuelve el problema de latencia
detectado en consultas vía Tailscale — manteniendo, como red de seguridad,
un **fallback automático** al camino SQL directo existente si el Gateway o
el agente no están disponibles.

## 2. Qué se logró (de cero a funcionando end-to-end)

### 2.1 — PaqAgent (repo `paqsuite-IA-AgenteCliente`)

- Worker Service .NET 8 ya implementado de sesiones anteriores.
- **Nuevo:** soporte de múltiples result sets en `SqlExecutor`
  (`ExecuteStoredProcedureMultiResultAsync`), sin romper el método simple
  existente usado por `clientes.buscar` y demás operaciones.
- **Nuevo:** operación `auth.login`, con su propio handler
  (`AuthLoginOperation.cs`) y rama dedicada en `JobDispatcher` — no pasa
  por el flujo genérico de `StoredProcedureOperation`.
- **Nuevo:** Stored Procedure `PAQ_Auth_Login` (en
  `PaqAgent/sql/migrations/2026_06_24_000001_create_paq_auth_login.sql`), con **detección dinámica de esquema**
  de columnas (legacy PascalCase vs snake_case moderno), replicando la
  misma lógica que `Schema::hasColumn()` ya usa en el backend PHP.
- Bug encontrado y corregido en el SP: el fallback de `@ColRolPK` y
  `@ColEmpresaPK` apuntaba mal a `id_rol`/`id_empresa` (columnas de
  `pq_permiso`, no de `pq_rol`/`pq_empresa`) — corregido a `id`.
- Validado end-to-end contra `diccionario_klaus` (esquema híbrido) y contra
  el SQL real accesible desde `srv-pq`.

### 2.2 — Agent Gateway (nuevo, `paqsuite-IA-AgenteCliente/PaqGateway/`)

- Proyecto ASP.NET Core + SignalR Hub creado de cero esta sesión.
- Librería compartida `PaqContracts/` con los modelos (`AgentJobResult`,
  `AgentIdentity`, `AgentHeartbeat`) para no duplicar contratos entre
  Gateway y Agente.
- `AgentHub` (`/agent-hub`): recibe `RegisterAgent`, `SendHeartbeat`,
  `SendJobResult` del agente; invoca `ExecuteJob` (string JSON) y
  `RunDiagnostics` hacia el agente.
- `AgentConnectionRegistry`: mapa en memoria `agentId → connectionId` +
  estado online/offline.
- `JobCorrelationService`: correlaciona `jobId → TaskCompletionSource`
  para que el endpoint HTTP "espere" la respuesta asíncrona del agente.
- `InternalJobsController`: `POST /internal/jobs/send`,
  `GET /internal/agents/{id}/status`, `POST /internal/agents/{id}/disconnect`,
  protegidos por `X-Internal-Api-Key`.
- Validado end-to-end entre máquinas reales (PC de desarrollo + `srv-pq`),
  a través de Tailscale.

### 2.3 — Integración Laravel (`PaqSuite-IA-TANGO`, rama `deplyunificado`)

- Nuevos campos `agent_id` / `client_id` en `empresas_conexion`
  (migración `2026_06_25_120000_add_agent_gateway_ids_to_empresas_conexion_table.php`),
  nullable — solo poblados hoy para el tenant `tecser`
  (`tecser-agent-01` / `000205_012`). `tecmetal` y `quento` quedan en
  `NULL` a propósito: son clientes reales sin agente instalado todavía.
- `config/agent_gateway.php` + variables `AGENT_GATEWAY_*` en `.env`.
- `app/Services/Agents/AgentGatewayClient.php` +
  `AgentGatewayException.php`: cliente HTTP dedicado, sin loguear
  payloads sensibles.
- `AuthService::login()` reescrito con lógica **Gateway-primero +
  fallback automático**:
  - Si el tenant no tiene `agent_id`/`client_id` → camino SQL directo
    sin tocar (comportamiento idéntico al de antes de esta sesión).
  - Si los tiene → intenta `auth.login` vía Gateway; ante
    `AgentGatewayException`, `status=offline` o `status=timeout` →
    fallback a SQL directo con `Log::warning`.
  - Rechazos de negocio (`NOT_FOUND`, `INACTIVE`, `NO_EMPRESAS`,
    `SQL_ERROR`) **no** disparan fallback — se propagan como error real.
  - Nueva constante `ERROR_AUTH_PROVIDER = 3205`, mapeada a HTTP 503 en
    `AuthController` (en vez de 401, para no confundir "credenciales
    inválidas" con "proveedor de auth no disponible").
  - Validación explícita de `data.status === 'OK'` como capa extra de
    robustez (con `Log::error` si el Gateway devolviera algo anómalo).
- `AuthServiceTest.php` actualizado para mockear `AgentGatewayClient`
  (con helper `createAuthService()` para tests futuros de Gateway).

## 3. Pruebas realizadas y resultado

| Prueba | Resultado |
|---|---|
| Cableado Gateway ↔ Agente (mismo equipo) | ✅ `diagnostics.run` exitoso |
| Cableado Gateway ↔ Agente (máquinas distintas, Tailscale) | ✅ tras resolver firewall + identidad Tailscale duplicada |
| Conexión SQL real desde el agente (Tec-Metal) | ✅ `sqlConnectionOk: true` |
| `PAQ_Auth_Login` contra `diccionario_klaus` (esquema híbrido) | ✅ tras corregir el bug de `@ColRolPK`/`@ColEmpresaPK` |
| `auth.login` end-to-end vía Gateway (Postman directo) | ✅ |
| Login real Laravel, tenant `tecser`, Gateway+agente online | ✅ HTTP 200, ~6.4s |
| Login real Laravel, tenant `tecser`, Gateway caído | ✅ fallback automático, HTTP 200, ~3.1s |
| Login real Laravel, tenant `tecser`, agente offline (Gateway online) | ✅ fallback automático, HTTP 200, ~4.8s |
| Login real Laravel, tenant `tecmetal` (sin `agent_id`) | ✅ usa SQL directo sin intentar Gateway (falla por esquema legacy, problema preexistente no relacionado) |
| Persistencia de `AGENT_GATEWAY_*` en `.env` | ✅ |

## 4. Problemas encontrados y resueltos durante la sesión

- **`appsettings.Development.json` equivocado**: se editó el archivo de
  `PaqGateway` en lugar de `PaqAgent` (y viceversa) más de una vez — son
  proyectos distintos con secciones de configuración distintas
  (`Gateway` vs `Agent`).
- **Variable de entorno equivocada**: el Gateway (ASP.NET Core) usa
  `ASPNETCORE_ENVIRONMENT`; el Agente (Worker Service puro) usa
  `DOTNET_ENVIRONMENT`. Confundirlas hace que el `Development` no se
  aplique y se sigan usando los valores de producción del `appsettings.json`
  base.
- **Binding del Gateway a `localhost` en vez de `0.0.0.0`**: bloqueaba
  conexiones entrantes desde otra máquina. Solución: editar
  `launchSettings.json` directamente (`applicationUrl`), no depender de
  `ASPNETCORE_URLS` por variable de entorno (no siempre tiene prioridad).
- **Typo `https://` en lugar de `http://`** en el `applicationUrl` —
  forzaba el certificado de desarrollo no confiable.
- **Reglas de firewall `Block` generadas automáticamente por Windows**:
  cada vez que el Gateway arranca en una sesión nueva y el cartel de
  "permitir acceso a redes" se cierra sin confirmar, Windows crea reglas
  de bloqueo que tapan a la regla `Allow` ya creada. Documentado en el
  runbook (sección 8) con diagnóstico y solución repetible.
- **Identidad de Tailscale duplicada en `srv-pq`**: la misma máquina
  física aparecía con dos nombres/IPs distintos (`tec-ser` / `srv-pq`)
  según qué cuenta de Tailscale estuviera logueada en esa sesión de
  Windows. Resuelto re-logueando con la cuenta organizacional compartida
  (`tailscale@paqsystems.com.ar`).
- **Operación de Gateway mal diseñada inicialmente**: se había propuesto
  una operación nueva (`auth.getUserPasswordHash`) que no existía y que
  hubiera desperdiciado el trabajo que el SP ya hace (`es_admin`,
  `empresas`, `redirectTo`). Corregido a tiempo, antes de implementar,
  usando la operación real ya validada (`auth.login`).
- **Estructura real de `AgentJobResult` distinta a la asumida**: los
  rechazos de negocio (`NOT_FOUND`, etc.) llegan con `status: "failed"`
  en la raíz y `data: null` — no dentro de `data.status` como se había
  asumido en un primer diseño. Confirmado con código fuente real antes
  de escribir `AuthService.php`, evitando un bug silencioso.
- **Esquema de columnas mixto en `diccionario_klaus`**: confirmado que no
  es una inconsistencia accidental, sino el perfil real de "instalación
  limpia" de TANGO (documentado en la auditoría de migraciones).

## 5. Pendientes para la próxima sesión

- [ ] Validar `PAQ_Auth_Login` también contra un esquema 100% legacy real
      (Tec-Metal) — hoy solo se validó la rama snake_case del fallback.
- [ ] Resolver el problema de esquema legacy de `tecmetal` en el camino
      SQL directo (columna `codigo` vs `name`) — preexistente, no
      introducido por esta sesión.
- [ ] Escribir `AuthServiceGatewayTest` con cobertura específica de
      `shouldUseGateway()`, mapeo de `status`, y los distintos caminos de
      fallback (offline/timeout/excepción).
- [ ] Poblar `agent_id`/`client_id` reales para `tecmetal` y `quento`
      cuando tengan su propio agente instalado (hoy solo `tecser`, que es
      el servidor de pruebas propio del equipo, los tiene).
- [ ] Deploy real del Agent Gateway al EC2 de AWS (hoy todo corrió en
      una PC de desarrollo + `srv-pq`, conectados por Tailscale).
- [ ] Evaluar si conviene fijar la cuenta de Tailscale compartida como
      `--operator` o equivalente en todas las máquinas del equipo, para
      evitar el problema de identidad duplicada a futuro.
- [ ] Documentación formal (CC/HU/TR) de este trabajo, siguiendo el
      proceso Open-SPEC ya usado para la Etapa 1 de multitenancy.

## 6. Documentos de referencia generados en esta sesión

- `runbook-gateway-agente-dev.md` — cómo levantar Gateway + Agente en
  desarrollo local, troubleshooting de firewall, checklist rápido.
- Este documento de cierre.

## 7. Decisiones de diseño clave (para no tener que redescubrirlas)

| Decisión | Razón |
|---|---|
| Gateway en AWS junto a Laravel, NO en el servidor del cliente | El agente es quien abre la conexión saliente una sola vez; si el Gateway estuviera en el cliente, Laravel seguiría necesitando atravesar la misma distancia de red en cada consulta — no resolvería la latencia |
| Reemplazo total del login (no convivencia con SQL directo "siempre") | Decisión inicial de Klaus, luego refinada con fallback automático |
| Fallback automático Gateway → SQL directo | El objetivo de cerrar puertos en el cliente hace que SQL directo "puro" no sea una alternativa real en producción final, pero hoy (con Tailscale) sigue siendo una red de seguridad válida durante la migración |
| `SQL_ERROR` del SP NO dispara fallback | Es un error real de la base del cliente; SQL directo fallaría igual, reintentar solo agrega latencia sin beneficio |
| SP con detección dinámica de esquema (no fijo a un solo perfil) | TANGO tiene 2 perfiles válidos y documentados (legacy puro en clientes reales, híbrido en instalaciones limpias) — el SP debe comportarse igual que el PHP existente |
| `tenants_catalog` (la tabla `empresas_conexion`) se mantiene como única fuente de verdad para identificar cliente, sin importar si usa Gateway o SQL directo | Evita lógica de resolución de tenant duplicada |
