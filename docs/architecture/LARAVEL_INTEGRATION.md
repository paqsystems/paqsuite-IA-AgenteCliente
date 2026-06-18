# PAQSuite IA Tango - Integracion Laravel con Agente Local

## 1. Objetivo

Este documento define como debe adaptarse el backend Laravel de PAQSuite IA Tango para comunicarse con el nuevo esquema basado en agentes locales.

Laravel seguira siendo el backend principal, pero dejara de consultar directamente los SQL Server de los clientes como mecanismo principal.

La nueva responsabilidad de Laravel sera:

1. recibir las llamadas de las APIs funcionales;
2. validar usuarios y permisos;
3. determinar el cliente/agente asociado;
4. decidir si consulta en vivo o usa cache;
5. enviar jobs al Agent Gateway;
6. registrar auditoria;
7. responder al consumidor de la API.

---

## 2. Arquitectura funcional

```text
Usuario / Frontend / API Consumer
        |
        v
Laravel API
        |
        | evalua operacion, permisos y cache
        v
AgentGatewayClient Service
        |
        v
Agent Gateway
        |
        v
PaqAgent cliente
        |
        v
SQL Server Tango
```

---

## 3. Principios

1. Laravel no debe enviar SQL libre al agente.
2. Laravel debe trabajar con operaciones logicas.
3. Cada operacion debe ser auditable.
4. El modo por defecto debe ser `live`.
5. El cache debe ser opcional por cliente y operacion.
6. Las APIs funcionales no deben exponer detalles tecnicos del agente.
7. Debe existir una capa de abstraccion para comunicarse con el gateway.

---

## 4. Servicios Laravel sugeridos

```text
app/Services/Agents/
├── AgentGatewayClient.php
├── AgentOperationService.php
├── AgentCacheService.php
├── AgentStatusService.php
├── AgentJobService.php
└── AgentOperationResolver.php
```

---

## 5. AgentGatewayClient

Responsabilidad:

- comunicarse por HTTP interno con el Agent Gateway;
- enviar jobs;
- consultar estado del agente;
- manejar errores y timeouts.

Metodos sugeridos:

```php
public function sendJob(string $agentId, string $operation, array $parameters, int $timeoutSeconds = 30): AgentJobResult;

public function getAgentStatus(string $agentId): AgentStatus;

public function runDiagnostics(string $agentId): AgentJobResult;
```

---

## 6. AgentOperationService

Responsabilidad:

- recibir una operacion logica;
- validar que exista;
- determinar configuracion de cache;
- ejecutar live/cache segun corresponda;
- registrar auditoria.

Metodo sugerido:

```php
public function executeOperation(string $clientId, string $operation, array $parameters = []): array;
```

---

## 7. Operaciones logicas

Ejemplos iniciales:

```text
clientes.buscar
clientes.obtener
articulos.buscar
articulos.obtener
stock.consultar
saldos.consultar
pedidos.pendientes
comprobantes.recientes
```

La API Laravel debe usar estas operaciones, no SQL.

---

## 8. Modos de ejecucion

Cada operacion debe poder configurarse con un modo.

```text
live
cache_first
live_refresh
cache_only
```

### live

Siempre consulta al agente.

Uso recomendado:

```text
stock.consultar
saldos.consultar
clientes.obtener
validaciones criticas
```

### cache_first

Usa cache si esta vigente. Si no existe o vencio, consulta al agente.

Uso recomendado:

```text
articulos.buscar
listas_precio.listar
condiciones_venta.listar
```

### live_refresh

Consulta al agente y actualiza el cache.

Uso recomendado:

```text
sincronizaciones manuales
consultas donde se quiere maxima actualidad y dejar cache actualizado
```

### cache_only

Solo responde desde cache.

Uso recomendado:

```text
reportes rapidos
modo degradado si el agente esta offline
```

---

## 9. Configuracion por defecto

El modo por defecto debe ser:

```text
live
```

Esto evita el problema de datos desactualizados, por ejemplo clientes recien dados de alta en Tango que no aparecen hasta la proxima sincronizacion.

---

## 10. Tablas sugeridas

### agents

```text
id
client_id
agent_id
name
status
last_seen_at
version
machine_name
sql_server_name
sql_database
is_enabled
created_at
updated_at
```

### agent_jobs

```text
id
job_uuid
client_id
agent_id
operation
payload_json
status
requested_by
started_at
finished_at
duration_ms
error_code
error_message
created_at
updated_at
```

### agent_operation_settings

```text
id
client_id
operation
mode
ttl_seconds
timeout_seconds
is_enabled
created_at
updated_at
```

### agent_cache_entries

```text
id
client_id
operation
cache_key
parameters_hash
data_json
expires_at
created_at
updated_at
```

---

## 11. Cache key

La clave de cache debe depender de:

```text
client_id
operation
parameters_hash
```

Ejemplo:

```text
cliente001:clientes.buscar:sha256(parameters)
```

---

## 12. Configuracion ejemplo de operaciones

```json
{
  "clientes.buscar": {
    "mode": "live",
    "cacheEnabled": false,
    "timeoutSeconds": 30
  },
  "articulos.buscar": {
    "mode": "cache_first",
    "cacheEnabled": true,
    "ttlSeconds": 600,
    "timeoutSeconds": 30
  },
  "stock.consultar": {
    "mode": "live",
    "cacheEnabled": false,
    "timeoutSeconds": 30
  },
  "saldos.consultar": {
    "mode": "live",
    "cacheEnabled": false,
    "timeoutSeconds": 30
  }
}
```

---

## 13. Endpoints funcionales sugeridos

Las APIs publicas deben mantener nombres funcionales.

```http
GET /api/clientes/{clientId}/clientes/buscar?texto=GARCIA
GET /api/clientes/{clientId}/clientes/{codigo}
GET /api/clientes/{clientId}/articulos/buscar?texto=TORNILLO
GET /api/clientes/{clientId}/stock?articulo=ABC&deposito=01
GET /api/clientes/{clientId}/saldos?cliente=000123
GET /api/clientes/{clientId}/agent/status
```

Internamente se traducen a operaciones.

---

## 14. No exponer endpoints peligrosos

No crear endpoints del tipo:

```http
POST /api/execute-sql
```

No aceptar payloads como:

```json
{
  "sql": "SELECT * FROM GVA14"
}
```

---

## 15. Manejo de agente offline

Si el agente esta offline y la operacion es `live`, responder error claro.

Ejemplo:

```json
{
  "success": false,
  "error": {
    "code": "AGENT_OFFLINE",
    "message": "El servidor del cliente no se encuentra conectado. Intente nuevamente mas tarde."
  }
}
```

Si la operacion permite cache y existe cache no vencido, se puede responder desde cache.

Si existe cache vencido, se podria parametrizar si se permite `stale cache`.

---

## 16. Auditoria

Cada operacion debe registrar:

```text
usuario
client_id
agent_id
operation
parameters_hash
status
duration_ms
source: live/cache
error_code
created_at
```

No registrar passwords ni datos sensibles innecesarios.

---

## 17. Variables de entorno Laravel

Sugeridas:

```env
AGENT_GATEWAY_URL=https://gateway.paqsuite.com
AGENT_GATEWAY_INTERNAL_KEY=clave_interna
AGENT_DEFAULT_TIMEOUT=30
AGENT_MAX_TIMEOUT=120
AGENT_CACHE_DEFAULT_MODE=live
```

---

## 18. Transicion desde arquitectura actual

Etapa 1:

- mantener APIs existentes;
- crear servicios nuevos;
- redirigir una operacion piloto al agente.

Etapa 2:

- migrar operaciones criticas a `live` via agente;
- mantener SQL directo solo como fallback tecnico temporal.

Etapa 3:

- eliminar dependencia de Tailscale para consultas principales;
- dejar VPN solo para mantenimiento excepcional.

---

## 19. Prueba piloto sugerida

Operacion inicial recomendada:

```text
clientes.buscar
```

Motivo:

- es facil de verificar;
- permite validar datos recien dados de alta;
- demuestra la ventaja del modo `live`;
- no requiere transferencias masivas.

Segunda operacion:

```text
stock.consultar
```

Motivo:

- requiere actualidad;
- es buen caso de uso para consulta bajo demanda.

---

## 20. Criterios de aceptacion MVP

1. Laravel tiene servicio `AgentGatewayClient`.
2. Laravel puede consultar estado de un agente.
3. Laravel puede ejecutar una operacion live.
4. Laravel registra un job en `agent_jobs`.
5. Laravel maneja agente offline.
6. Laravel soporta configuracion por operacion.
7. El cache puede activarse o desactivarse por operacion.
8. Las APIs funcionales no exponen SQL.
9. El modo por defecto es `live`.
10. Una operacion piloto funciona de punta a punta.
