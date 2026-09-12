# 03 — Historias de usuario (MVP)

Origen: [01-SPEC-producto.md](01-SPEC-producto.md).  
Una HU = una capacidad observable. No se implementa la siguiente si la anterior no está aceptada.

Prioridad: el orden numérico **es** el orden de construcción.

---

## HU-001 — Alta de cliente agente sin IP

| Campo | Valor |
|-------|--------|
| Identificador | HU-001 |
| Épica | MVP conectividad |
| Prioridad | MUST |
| Roles | Operador PaqSystems |
| Dependencias | Ninguna de producto; contrato Laravel |
| Clasificación | HU SIMPLE (Laravel) |

### Narrativa

Como **operador de PaqSystems** quiero **dar de alta un cliente en `empresas_conexion` con `agent_id`, `client_id` y token, sin cargar IP ni puerto SQL**, para que Laravel sepa a qué agente pedir datos cuando el agente esté online.

### Criterios de aceptación

1. Formulario o comando de alta pide: `cliente`, `nombre`, genera `agent_id`, `client_id`, `agentToken`.
2. No exige `host` ni `port` ni password SQL.
3. Muestra el token **una vez** (para pasárselo al instalador).
4. El registro queda `activo=true` con `agent_id` poblado y `host` null.
5. Un tenant sin `agent_id` no entra al camino agente (fuera de este MVP: no se define SQL directo).

```gherkin
Feature: Alta de cliente modo agente
  Scenario: Alta sin host
    Given un operador autenticado en PaqSuite
    When da de alta el cliente "Tecmetal" en modo agente
    Then empresas_conexion tiene agent_id y client_id
    And host es null
    And se muestra un AgentToken una sola vez
```

---

## HU-002 — Gateway publicado en AWS

| Campo | Valor |
|-------|--------|
| Identificador | HU-002 |
| Épica | MVP conectividad |
| Prioridad | MUST |
| Roles | Operador de infraestructura PaqSystems |
| Dependencias | D1, D2, D8 |
| Clasificación | HU COMPLEJA (infra + servicio) |

### Narrativa

Como **operador de infraestructura** quiero **un PaqGateway en Amazon, en la misma VPC que Laravel, con HTTPS/WSS en gateway.paqsuite.com**, para que los agentes de los clientes se conecten por el puerto 443 saliente y Laravel les mande jobs por red interna.

### Criterios de aceptación

1. Instancia (EC2 o equivalente) con .NET 8, systemd, reverse proxy TLS.
2. `https://gateway.paqsuite.com/agent-hub` acepta handshake SignalR.
3. Security Group: 443 público; SQL 1433 **no** abierto a Internet; Laravel alcanza `/internal/*` por red privada.
4. Secretos por entorno, no `change-me-in-production` en el servidor.
5. Existe un instructivo paso a paso en este repo (`docs/` se genera con la HU, no antes de implementarla).
6. Health: proceso up + Laravel puede llamar `GET /internal/agents/{id}/status` con API key.

```gherkin
Feature: Gateway en AWS
  Scenario: Hub público
    When un agente válido se conecta a https://gateway.paqsuite.com/agent-hub
    Then el handshake WSS completa
    And el gateway registra el agentId como online
  Scenario: API interna no es pública
    When un cliente anónimo llama POST /internal/jobs/send sin API key
    Then responde 401 o 403
```

---

## HU-003 — Auto-instalador con credenciales esenciales

| Campo | Valor |
|-------|--------|
| Identificador | HU-003 |
| Épica | MVP conectividad |
| Prioridad | MUST |
| Roles | Administrador del servidor del cliente |
| Dependencias | HU-001 (valores para pegar), binarios del agente |
| Clasificación | HU COMPLEJA |

### Narrativa

Como **administrador del servidor SQL del cliente** quiero **un instalador Windows que me pida las credenciales esenciales, pruebe SQL y deje el agente como servicio**, para no editar archivos a mano ni instalar Visual Studio.

### Criterios de aceptación

1. UI pide exactamente los campos del SPEC sección 5 (incluye **AgentToken**, sin default).
2. Gateway URL prellenada con `https://gateway.paqsuite.com/agent-hub`, editable.
3. Botón “Probar conexión” contra SQL local; si falla, **no** instala.
4. Si AgentId, ClientId o AgentToken están vacíos, **no** instala.
5. Tras éxito: servicio Windows `PaqAgent` (nombre estable) `Running`, `start= auto`, `appsettings.local.json` escrito junto al binario.
6. No pide IP pública ni Tailscale.
7. Se distribuye como zip con el .exe (release GitHub). Documentar prerrequisito: .NET 8 Desktop Runtime x64.

```gherkin
Feature: Instalador
  Scenario: Rechaza sin token
    Given el formulario con SQL ok y AgentToken vacío
    When pulsa Instalar
    Then no crea el servicio
    And muestra error de token obligatorio
  Scenario: Instalación feliz
    Given credenciales de identidad y SQL válidas
    When pulsa Instalar
    Then el servicio PaqAgent queda Running
    And appsettings.local.json contiene el token informado
```

---

## HU-004 — Agente conectado, autenticado y con heartbeat

| Campo | Valor |
|-------|--------|
| Identificador | HU-004 |
| Épica | MVP conectividad |
| Prioridad | MUST |
| Roles | Sistema |
| Dependencias | HU-002, HU-003 |
| Clasificación | HU SIMPLE |

### Narrativa

Como **sistema** quiero que **el agente, al iniciar el servicio, abra WSS saliente al Gateway, se autentique y envíe heartbeat**, para que PaqSuite lo vea online sin que AWS inicie ninguna conexión hacia el cliente.

### Criterios de aceptación

1. Al start: conecta a `GatewayUrl`, Bearer token, `RegisterAgent` con agentId, clientId, machineName, sqlServerName, version.
2. Heartbeat periódico (default 30 s).
3. Si cae la red: reconecta con backoff (5, 10, 20, 30, 60 s) sin intervención.
4. Token inválido: no queda “online”; log de error claro, sin imprimir el token.
5. Laravel `GET` status via Gateway = `online` cuando el servicio corre.

```gherkin
Feature: Conexión saliente
  Scenario: Online
    Given el servicio PaqAgent running con token válido
    Then el Gateway lista ese agentId como online
    And Laravel consulta status online
  Scenario: Token inválido
    Given AgentToken incorrecto
    Then el agente no queda registrado
    And Laravel no lo muestra online
```

---

## HU-005 — Diagnóstico de punta a punta

| Campo | Valor |
|-------|--------|
| Identificador | HU-005 |
| Épica | MVP conectividad |
| Prioridad | MUST |
| Roles | Operador PaqSystems / soporte |
| Dependencias | HU-004 |
| Clasificación | HU SIMPLE |

### Narrativa

Como **soporte** quiero **ejecutar `diagnostics.run` desde PaqSuite (o un endpoint interno)** para saber si el agente está vivo y si SQL local responde, sin ir al servidor del cliente.

### Criterios de aceptación

1. Laravel (o un cliente interno autorizado) envía job `diagnostics.run` al `agentId` del tenant.
2. Respuesta `success` incluye al menos: versión, sqlConnectionOk, agentId.
3. Si el agente está caído: `offline`, sin intentar SQL remoto.
4. Timeout configurable (default 30 s) → `timeout`.

```gherkin
Feature: diagnostics.run
  Scenario: Agente sano
    When se envía diagnostics.run al agentId piloto
    Then status es success
    And sqlConnectionOk es true
  Scenario: Servicio detenido
    Given el servicio PaqAgent está Stopped
    When se envía diagnostics.run
    Then status es offline
```

---

## HU-006 — Operación piloto live

| Campo | Valor |
|-------|--------|
| Identificador | HU-006 |
| Épica | MVP conectividad |
| Prioridad | MUST |
| Roles | Usuario de PaqSuite |
| Dependencias | HU-005, SP `PAQ_Auth_Login` o `PAQ_Clientes_Buscar` en el diccionario/empresa |
| Clasificación | HU SIMPLE |

### Narrativa

Como **usuario de PaqSuite** quiero **completar un login (o una búsqueda de clientes) con datos reales de Tango vía agente**, para comprobar que el producto sirve y no solo que “el socket está abierto”.

### Criterios de aceptación

1. Una sola operación de negocio en el MVP: `auth.login` (preferida) o `clientes.buscar`.
2. Lista blanca: cualquier otra operación → `OPERATION_NOT_ALLOWED`.
3. SQL parametrizado; cero SQL enviado desde AWS.
4. Resultado usable por Laravel (mismo contrato JSON camelCase).
5. El usuario no configura IP.

```gherkin
Feature: Operación piloto
  Scenario: Login vía agente
    Given tenant con agent_id y agente online
    When el usuario se loguea con un código Tango válido
    Then Laravel obtiene el resultado vía Gateway
    And no abre conexión SQL hacia el cliente
```

---

## HU-007 — Agente offline: error claro, sin SQL directo

| Campo | Valor |
|-------|--------|
| Identificador | HU-007 |
| Épica | MVP conectividad |
| Prioridad | MUST |
| Roles | Usuario de PaqSuite |
| Dependencias | HU-006 |
| Clasificación | HU SIMPLE |

### Narrativa

Como **usuario** quiero **un mensaje claro si el servidor del cliente no está conectado**, para no esperar timeouts de SQL ni “caídas misteriosas”. Como **producto**, **no** queremos que AWS intente SQL por IP.

### Criterios de aceptación

1. Agente detenido → API Laravel error `AGENT_OFFLINE` (HTTP 503, no 401).
2. No se lee `host` de `empresas_conexion` para reintentar.
3. Log Laravel: warning con agentId, sin secretos.
4. Test automatizado (unitario Laravel o de contrato) que falle si alguien reintroduce el fallback.

```gherkin
Feature: Sin fallback
  Scenario: Offline
    Given agent_id configurado y agente offline
    When el usuario dispara la operación piloto
    Then la API responde AGENT_OFFLINE
    And no hay intento de conexión TDS desde Laravel
```

---

## HU-008 — Documentación de instalación (cliente y AWS)

| Campo | Valor |
|-------|--------|
| Identificador | HU-008 |
| Épica | MVP conectividad |
| Prioridad | MUST |
| Roles | Operador PaqSystems, administrador del cliente |
| Dependencias | HU-002, HU-003 (para no documentar vapor) |
| Clasificación | HU SIMPLE |

### Narrativa

Como **quien instala** quiero **un instructivo paso a paso, con URLs reales de descarga y checklist de AWS**, para repetir el piloto en el siguiente cliente sin preguntarle al programador.

### Criterios de aceptación

Documento único de operación (puede ser `docs/instalacion.md`) que incluya:

1. Dónde descargar el instalador (`releases/latest`).
2. Prerrequisito .NET 8 Desktop Runtime (link Microsoft).
3. Qué datos pide el instalador y de dónde sale cada uno (alta Laravel vs SQL local).
4. Cómo verificar servicio + logs + online en PaqSuite.
5. Gateway AWS: VPC, SG, DNS, certificado, systemd, env vars, prueba `diagnostics.run`.
6. Qué **no** configurar: Tailscale, IP pública, puerto 1433 a Internet.
7. Troubleshooting mínimo: servicio no parte, SQL test fail, agente no online (443 saliente).

Sin este documento el MVP no se acepta, aunque el código funcione en el laboratorio.

---

## Fuera del MVP (backlog, no se estiman aquí)

- HU-010+ Portar operaciones existentes (clientes, stock, informes, acopios…) **una épica por módulo**, solo cuando HU-001–008 estén aceptadas.
- Auto-update del agente.
- Botón de descarga dentro de la UI PaqSuite.
- Escalado horizontal del Gateway.
