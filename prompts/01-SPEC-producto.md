# 01 — SPEC de producto: PaqAgent + PaqGateway

| Campo | Valor |
|-------|--------|
| Identificador | SPEC-AGW-001 |
| Producto | PAQSuite IA — Agente local Tango |
| Versión | 1.0 |
| Fecha | 2026-09-03 |
| Estado | Borrador para cierre (revisión de ambigüedad pendiente) |
| Repos | `paqsuite-IA-AgenteCliente`, contrato en `PaqSuite-IA-TANGO` |

Este documento es la **fuente de verdad**. Si una HU, un TR o un agente de IA contradicen este SPEC, manda el SPEC. Si falta algo, se actualiza el SPEC **antes** de codear.

---

## 1. Problema

PaqSuite (Laravel en AWS) necesita datos vivos de Tango Gestión, que vive en SQL Server **dentro de la red de cada cliente**.

Abrir SQL Server a Internet es inaceptable. Pedir VPN/Tailscale por cliente no escala: IPs no fijas, fricción de soporte, latencia, dependencia de un overlay que no es el producto.

---

## 2. Solución

Invertir el sentido de la conexión.

```text
Usuario  →  Laravel (AWS)  --HTTP interno-->  PaqGateway (AWS)
                                              ▲
                                              │ WSS 443 saliente
                                              │
                                    PaqAgent (Windows Service
                                    en el servidor SQL del cliente)
                                              │
                                              ▼ LAN
                                    SQL Server Tango
```

- El **agente** se instala en el servidor donde está SQL Server (o en un Windows de la misma LAN que alcance SQL).
- El **gateway** se instala en Amazon, junto a Laravel (misma VPC).
- Laravel **nunca** abre un socket SQL hacia el cliente.
- El cliente **nunca** abre puertos entrantes ni expone 1433.

---

## 3. Actores

| Actor | Rol |
|-------|-----|
| Operador PaqSystems | Da de alta el cliente en Laravel, genera `agentId` / `clientId` / `agentToken`, entrega el instalador |
| Administrador del servidor del cliente | Ejecuta el instalador, carga credenciales, deja el servicio corriendo |
| Usuario de PaqSuite | Usa la app con normalidad; no ve el agente |
| Laravel | Valida usuario/permisos, resuelve tenant, manda job al Gateway por `agentId` |
| PaqGateway | Mantiene el WebSocket, rutea jobs, timeouts, online/offline |
| PaqAgent | Autentica, heartbeat, ejecuta operación de lista blanca contra SQL local, devuelve JSON |

---

## 4. `empresas_conexion` — qué guarda y qué no

Esta tabla (catálogo de tenants en AWS) es la **llave de ruteo**, no un connection string de SQL remoto.

### 4.1 Campos esenciales del modo agente (MVP)

| Campo | Obligatorio | Para qué |
|-------|-------------|----------|
| `cliente` | Sí | Identificador del tenant (subdominio / `X-Paq-Cliente`) |
| `nombre` | Sí | Nombre visible |
| `agent_id` | Sí (modo agente) | A qué conexión SignalR mandar el job |
| `client_id` | Sí (modo agente) | Identidad que presenta el agente |
| `activo` | Sí | Habilitar / suspender el tenant |
| token del agente | Sí | Se genera en Laravel; el hash o el secreto vive en AWS; el valor en claro se entrega una vez al instalador. Puede ser columna de esta tabla o tabla `agents` asociada. Decisión: ver `02-decisiones-tecnicas.md` |

Opcionales de contexto (no de red):

| Campo | Obligatorio | Para qué |
|-------|-------------|----------|
| `dictionary_database` | No | Nombre de la base diccionario, solo informativo / diagnóstico |
| empresa activa | No en esta tabla | La elige la sesión del usuario; Laravel la manda como parámetro `_database` en el job |

### 4.2 Campos que el modo agente **no usa**

| Campo | Por qué no |
|-------|------------|
| `host` (IP o hostname del SQL) | Laravel no se conecta al SQL. El agente ya está en esa red. |
| `port` (1433) | Idem. |
| `username` / `password` SQL | Las credenciales SQL viven **solo** en el servidor del cliente (`appsettings.local.json` escrito por el instalador). |

`host` y `port` pueden quedar en el esquema por compatibilidad histórica, **nullable**, y **prohibidos** como camino de consulta en producción. Si están vacíos y hay `agent_id`, el sistema es válido.

### 4.3 Cómo “se conecta” AWS al SQL

Frase de negocio: la app en AWS consulta el SQL del cliente.

Frase técnica: Laravel usa `agent_id` de `empresas_conexion` → POST interno al Gateway → el Gateway usa la conexión **ya abierta por el agente** → el agente usa las credenciales SQL **locales**.

No hay un tercer significado. Si alguien pone una IP en `host` “para que ande”, está violando este SPEC.

---

## 5. Credenciales que pide el auto-instalador

El instalador es un .exe Windows, se ejecuta como Administrador, y **debe pedir todo lo esencial en la UI**. Prohibido dejar tokens por defecto o editar JSON a mano como paso de producción.

### Identidad (la da PaqSystems al dar de alta el cliente)

| Campo | Notas |
|-------|--------|
| AgentId | Obligatorio |
| ClientId | Obligatorio |
| AgentToken | Obligatorio, password-char, **sin valor por defecto** |
| Gateway URL | Obligatorio; default de fábrica `https://gateway.paqsuite.com/agent-hub` |

### SQL local (las conoce el administrador del servidor Tango)

| Campo | Notas |
|-------|--------|
| Servidor SQL | Instancia local o LAN, ej. `SERVIDORTM\AXSQLEXPRESS` o `localhost` |
| Puerto SQL | Opcional; vacío = 1433 |
| Base diccionario | Nombre exacto, ej. `Diccionario_000205_012` |
| Usuario SQL | Con permisos de lectura/ejecución/CREATE PROCEDURE en diccionario y empresas |
| Contraseña SQL | Password-char |

### Acciones del instalador

1. Validar que ningún campo obligatorio esté vacío.
2. **Probar conexión SQL** antes de instalar. Si falla, no instala.
3. Copiar binarios (desde el ZIP embebido o release).
4. Escribir `appsettings.local.json` (no se pisa en updates).
5. Registrar e iniciar el servicio Windows (`start= auto`).
6. Mostrar resultado: servicio running + “esperando aparecer online en PaqSuite”.

No pide IP pública. No pide Tailscale. No pide nada de AWS.

---

## 6. Gateway en Amazon

- Una instancia (MVP) en la **misma VPC** que Laravel.
- HTTPS/WSS en 443 (`gateway.paqsuite.com`).
- Kestrel interno; Nginx o ALB termina TLS y hace upgrade WebSocket.
- Endpoints internos `/internal/jobs/send` y `/internal/agents/{agentId}/status` protegidos con API key.
- El Gateway autentica agentes contra Laravel (o contra el catálogo de tokens). No hardcodea la lista de clientes en `appsettings` de producción.
- Laravel habla al Gateway por URL **interna** (IP privada / DNS interno), no por Tailscale.

---

## 7. Contrato de un job

Laravel → Gateway:

```json
{
  "agentId": "tecmetal-agent-01",
  "clientId": "Tec-Metal001",
  "operation": "clientes.buscar",
  "parameters": { "texto": "GARCIA", "limit": 20, "_database": "TEC_METAL" },
  "timeoutSeconds": 30
}
```

Respuestas de estado: `success` | `failed` | `timeout` | `offline`.

Si el agente está `offline`, Laravel responde error claro al usuario. **No hay fallback a SQL directo.**

El agente **no ejecuta SQL libre**. Solo operaciones de lista blanca → stored procedure parametrizado.

---

## 8. MVP — qué entra y qué no

### Entra

- Agente como Windows Service, reconexión automática, heartbeat, logs.
- Gateway en AWS con un agente piloto conectado por Internet (salida 443).
- Instalador con las credenciales de la sección 5.
- Alta en `empresas_conexion` sin `host` obligatorio.
- Laravel: enviar job + consultar status. Sin SQL remoto.
- Operaciones: `diagnostics.run` y **una** piloto (`auth.login` o `clientes.buscar`).
- Documentación de instalación del agente (paso a paso para el cliente) y del Gateway (paso a paso AWS).
- Página o link de descarga del instalador (GitHub Release público alcanza para el MVP, enlazado desde PaqSuite).

### No entra (fase 2, después del MVP verde)

- El resto de operaciones ya existentes (informes, acopios, etc.). Se portan **después**, una HU por módulo.
- Auto-update del agente.
- Múltiples instancias de Gateway / Redis backplane.
- Cache de resultados.
- Tailscale como feature.
- SQL directo como red de seguridad.

---

## 9. Criterios de aceptación del SPEC (MVP)

1. Un servidor de cliente **sin Tailscale** instala el agente con el .exe y el servicio queda `Running`.
2. El agente aparece online en PaqSuite.
3. `diagnostics.run` round-trip Laravel → Gateway → Agente → SQL local → respuesta.
4. La operación piloto live devuelve datos reales de Tango.
5. `empresas_conexion` del piloto tiene `agent_id` y **no requiere** `host` para que lo anterior funcione.
6. Si se detiene el servicio del agente, Laravel responde `AGENT_OFFLINE` (o equivalente) y **no** intenta SQL por IP.
7. El Gateway está publicado en AWS con HTTPS, no en una PC de desarrollo.
8. El instalador rechaza instalar sin `AgentToken` y sin SQL ok.

---

## 10. Seguridad (mínimo del SPEC)

- TLS en todo el tráfico AWS ↔ agente.
- Token de agente único, rotables a futuro (MVP: generar en el alta).
- No loguear tokens, passwords ni connection strings.
- Lista blanca de operaciones. Cero SQL concatenado.
- SQL Server no expuesto a Internet.
- API interna Gateway ↔ Laravel con API key; no pública.

---

## 11. Observabilidad mínima

- Agente: log de conexión, jobs, errores (archivos locales).
- Gateway: conexiones, jobs, timeouts, online/offline.
- Laravel: job id, duración, status, `agent_id` (sin payloads sensibles).

Sin esto no se puede soportar un cliente. Con esto alcanza el MVP.
