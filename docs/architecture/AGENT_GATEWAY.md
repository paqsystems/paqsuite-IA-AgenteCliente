# PAQSuite IA Tango - Arquitectura del Agent Gateway

## 1. Objetivo

El **Agent Gateway** es el componente responsable de mantener las conexiones persistentes con los agentes locales instalados en los servidores de los clientes.

Laravel continua siendo el backend principal de PAQSuite IA Tango, pero no debe encargarse directamente de mantener cientos de conexiones WebSocket persistentes. Para esa funcion se propone un gateway especializado.

---

## 2. Responsabilidades principales

El Agent Gateway debe:

1. Recibir conexiones de PaqAgent.
2. Autenticar cada agente.
3. Mantener un registro de agentes conectados.
4. Recibir pedidos desde Laravel.
5. Enviar jobs al agente correspondiente.
6. Esperar y recibir respuestas.
7. Devolver los resultados a Laravel.
8. Manejar timeouts.
9. Informar estado online/offline de cada agente.
10. Registrar logs y metricas.

---

## 3. Arquitectura

```text
+---------------------+
| Laravel AWS / Forge |
| Backend principal   |
+----------+----------+
           |
           | HTTP interno seguro
           v
+---------------------+
| Agent Gateway       |
| SignalR/WebSocket   |
+----------+----------+
           |
           | WSS / HTTPS 443
           v
+---------------------+
| PaqAgent cliente    |
+---------------------+
```

---

## 4. Tecnologia recomendada

Opcion preferida:

```text
.NET 8 ASP.NET Core
SignalR Hub
```

Motivos:

- integracion natural con agente C#;
- manejo maduro de reconexion;
- soporte para grupos;
- soporte para mensajes bidireccionales;
- buena escalabilidad;
- menor complejidad que WebSocket puro.

---

## 5. Relacion con Laravel

Laravel no se comunica directamente con SQL Server del cliente.

Laravel invoca al Agent Gateway mediante HTTP interno.

Ejemplo:

```text
Laravel -> POST /internal/jobs/send -> Agent Gateway -> PaqAgent
```

---

## 6. Endpoints internos sugeridos

### Enviar job a un agente

```http
POST /internal/jobs/send
```

Payload:

```json
{
  "agentId": "cliente001-servidortm",
  "clientId": "cliente001",
  "operation": "clientes.buscar",
  "parameters": {
    "texto": "GARCIA",
    "limit": 20
  },
  "timeoutSeconds": 30
}
```

Respuesta exitosa:

```json
{
  "jobId": "job_123456",
  "status": "success",
  "durationMs": 420,
  "data": []
}
```

Respuesta agente offline:

```json
{
  "jobId": "job_123456",
  "status": "offline",
  "error": {
    "code": "AGENT_OFFLINE",
    "message": "El agente no se encuentra conectado."
  }
}
```

---

### Consultar estado del agente

```http
GET /internal/agents/{agentId}/status
```

Respuesta:

```json
{
  "agentId": "cliente001-servidortm",
  "status": "online",
  "lastSeenAtUtc": "2026-01-01T10:00:00Z",
  "connectionId": "abc123",
  "version": "1.0.0"
}
```

---

### Desconectar agente

```http
POST /internal/agents/{agentId}/disconnect
```

Uso previsto:

- mantenimiento;
- bloqueo de agente comprometido;
- forzar reconexion;
- rotacion de token.

---

## 7. SignalR Hub

Nombre sugerido:

```text
AgentHub
```

Ruta sugerida:

```text
/agent-hub
```

Metodos del agente hacia el gateway:

```text
RegisterAgent
SendHeartbeat
SendJobResult
SendLogEvent
```

Metodos del gateway hacia el agente:

```text
ExecuteJob
CancelJob
RunDiagnostics
UpdateConfiguration
```

---

## 8. Autenticacion del agente

El agente debe conectarse usando:

- `AgentId`
- `ClientId`
- `AgentToken`

El token puede enviarse como:

```text
Authorization: Bearer <token>
```

o como access token de SignalR.

El gateway debe validar:

1. que el `AgentId` exista;
2. que el token sea valido;
3. que el agente este habilitado;
4. que el cliente este activo.

---

## 9. Autenticacion de Laravel contra el Gateway

Los endpoints internos del gateway no deben ser publicos.

Opciones:

1. API key interna.
2. JWT interno.
3. Restriccion por IP privada/VPC.
4. Mutual TLS en una etapa futura.

Para MVP:

```text
X-Internal-Api-Key: <clave_interna>
```

---

## 10. Registro de conexiones

El gateway debe mantener un mapa en memoria:

```text
agentId -> connectionId
```

Tambien debe informar a Laravel o a la base compartida:

```text
agentId
clientId
status
lastSeenAt
connectionId
version
```

Si se escala a multiples instancias del gateway, se debera usar Redis backplane o un mecanismo equivalente.

---

## 11. Flujo de job bajo demanda

```text
1. Usuario llama API Laravel.
2. Laravel valida permisos.
3. Laravel determina clientId y agentId.
4. Laravel llama POST /internal/jobs/send.
5. Gateway verifica si el agente esta conectado.
6. Gateway envia ExecuteJob al agente.
7. Agente ejecuta operacion local.
8. Agente devuelve SendJobResult.
9. Gateway responde a Laravel.
10. Laravel responde al usuario.
```

---

## 12. Manejo de timeouts

El gateway debe manejar timeout aunque el agente no responda.

Estados posibles:

```text
success
failed
timeout
offline
cancelled
```

Timeout sugerido por defecto:

```text
30 segundos
```

Maximo sugerido:

```text
120 segundos
```

---

## 13. Correlacion de mensajes

Cada job debe tener un identificador unico:

```text
jobId
```

El gateway debe correlacionar:

```text
jobId -> TaskCompletionSource / promise / pending request
```

Cuando llega la respuesta del agente, el gateway resuelve el pedido pendiente.

---

## 14. Errores normalizados

Codigos sugeridos:

```text
AGENT_OFFLINE
AGENT_TIMEOUT
AGENT_AUTH_FAILED
OPERATION_NOT_ALLOWED
SQL_CONNECTION_FAILED
SQL_TIMEOUT
SQL_ERROR
INVALID_PARAMETERS
INTERNAL_ERROR
```

---

## 15. Logs y metricas

Registrar:

- conexiones;
- desconexiones;
- autenticaciones fallidas;
- jobs enviados;
- jobs exitosos;
- jobs con error;
- duracion por operacion;
- agentes offline;
- timeouts.

Metricas sugeridas:

```text
connected_agents_count
jobs_total
jobs_success_total
jobs_failed_total
jobs_timeout_total
job_duration_ms
agent_last_seen_seconds
```

---

## 16. Escalabilidad

Para MVP puede ejecutarse una sola instancia del gateway.

Para escalar:

- usar Redis para SignalR backplane;
- almacenar estado de agentes en Redis;
- usar sticky sessions si corresponde;
- separar logs y metricas.

---

## 17. Seguridad

1. Usar HTTPS/WSS.
2. No aceptar agentes sin token.
3. Rotar tokens.
4. Permitir deshabilitar agentes.
5. No permitir SQL libre.
6. Validar operaciones y parametros.
7. No registrar passwords ni connection strings completas en logs.
8. Separar API interna de endpoints publicos.

---

## 18. Criterios de aceptacion MVP

1. El gateway recibe conexion de un agente.
2. El gateway autentica el agente.
3. El gateway registra estado online.
4. Laravel puede consultar estado del agente.
5. Laravel puede enviar un job.
6. El gateway envia el job al agente correcto.
7. El gateway recibe respuesta.
8. El gateway devuelve resultado a Laravel.
9. Se manejan timeouts.
10. Se registran logs basicos.
