# PAQSuite IA Tango - Arquitectura del Agente Local

## 1. Objetivo

Este documento define la arquitectura del componente **PaqAgent**, un agente local instalado en el servidor del cliente para permitir que PAQSuite IA Tango consulte datos de Tango Gestion / SQL Server sin abrir puertos entrantes en la red del cliente y sin depender de una VPN como mecanismo principal de consulta.

El objetivo es reemplazar el esquema:

```text
Laravel AWS -> VPN/Tailscale -> SQL Server del cliente
```

por el esquema:

```text
Laravel AWS -> Agent Gateway -> PaqAgent local -> SQL Server Tango
```

El agente debe permitir consultas bajo demanda, iniciadas funcionalmente desde Laravel/AWS, pero usando una conexion saliente persistente abierta por el propio agente.

---

## 2. Principios de diseno

1. El cliente no debe abrir puertos entrantes.
2. SQL Server no debe exponerse a Internet.
3. El agente debe iniciar siempre la comunicacion hacia AWS.
4. Las consultas deben ser bajo demanda, no por polling periodico obligatorio.
5. El agente no debe ejecutar SQL libre recibido desde AWS.
6. Toda operacion debe estar basada en una lista blanca de operaciones permitidas.
7. Cada operacion debe ser auditable.
8. El cache debe ser opcional y parametrizable.
9. El modo por defecto debe ser `live`, para evitar informacion desactualizada.
10. La solucion debe poder escalar a multiples clientes y multiples agentes.

---

## 3. Arquitectura general

```text
                +---------------------+
                | Laravel AWS / Forge |
                | Backend principal   |
                +----------+----------+
                           |
                           | HTTP interno / API privada
                           |
                           v
                +---------------------+
                | Agent Gateway       |
                | WebSocket/SignalR   |
                +----------+----------+
                           |
                           | Conexion saliente persistente
                           |
        +------------------+------------------+
        |                  |                  |
        v                  v                  v
+---------------+  +---------------+  +---------------+
| PaqAgent      |  | PaqAgent      |  | PaqAgent      |
| Cliente A     |  | Cliente B     |  | Cliente C     |
+------+--------+  +------+--------+  +------+--------+
       |                  |                  |
       v                  v                  v
+---------------+  +---------------+  +---------------+
| SQL Server    |  | SQL Server    |  | SQL Server    |
| Tango         |  | Tango         |  | Tango         |
+---------------+  +---------------+  +---------------+
```

---

## 4. Tecnologia recomendada

### Plataforma

- .NET 8
- Worker Service
- Instalacion como Windows Service

### Dependencias sugeridas

```text
Microsoft.Extensions.Hosting.WindowsServices
Microsoft.AspNetCore.SignalR.Client
Microsoft.Data.SqlClient
Serilog
Serilog.Sinks.File
Polly
System.Text.Json
```

---

## 5. Estructura sugerida del proyecto

```text
PaqAgent/
├── Configuration/
│   ├── AgentSettings.cs
│   ├── SqlConnectionSettings.cs
│   └── OperationSettings.cs
├── Communication/
│   ├── IAgentConnection.cs
│   ├── SignalRAgentConnection.cs
│   └── WebSocketAgentConnection.cs
├── Database/
│   ├── ISqlExecutor.cs
│   ├── SqlExecutor.cs
│   └── SqlParameterMapper.cs
├── Jobs/
│   ├── JobDispatcher.cs
│   ├── JobExecutionContext.cs
│   └── JobResultFactory.cs
├── Operations/
│   ├── IOperationHandler.cs
│   ├── OperationRegistry.cs
│   ├── ClientesBuscarOperation.cs
│   ├── ArticulosBuscarOperation.cs
│   ├── StockConsultarOperation.cs
│   └── SaldosConsultarOperation.cs
├── Security/
│   ├── TokenProvider.cs
│   └── AgentAuthenticator.cs
├── Logging/
│   └── LogConfiguration.cs
├── Models/
│   ├── AgentIdentity.cs
│   ├── AgentJob.cs
│   ├── AgentJobResult.cs
│   ├── AgentHeartbeat.cs
│   └── AgentStatus.cs
├── Services/
│   ├── Worker.cs
│   ├── HeartbeatService.cs
│   └── DiagnosticsService.cs
├── Program.cs
└── appsettings.json
```

---

## 6. Configuracion local

Archivo sugerido:

```text
appsettings.json
```

Ejemplo:

```json
{
  "Agent": {
    "AgentId": "cliente001-servidortm",
    "ClientId": "cliente001",
    "DisplayName": "Servidor Tango Cliente 001",
    "Version": "1.0.0",
    "GatewayUrl": "https://gateway.paqsuite.com/agent-hub",
    "ApiBaseUrl": "https://api.paqsuite.com",
    "AgentToken": "TOKEN_SECRETO_DEL_AGENTE",
    "HeartbeatSeconds": 30,
    "DefaultTimeoutSeconds": 30,
    "MaxTimeoutSeconds": 120
  },
  "SqlConnection": {
    "Server": "SERVIDORTM\\AXSQLEXPRESS",
    "Database": "TANGO_GESTION",
    "User": "usuario_sql",
    "Password": "clave_sql",
    "Encrypt": false,
    "TrustServerCertificate": true,
    "ConnectionTimeoutSeconds": 15,
    "CommandTimeoutSeconds": 30
  },
  "Logging": {
    "LogDirectory": "logs",
    "MinimumLevel": "Information"
  }
}
```

---

## 7. Identificacion del agente

Cada agente debe identificarse mediante:

- `AgentId`
- `ClientId`
- `Version`
- `MachineName`
- `OSVersion`
- `SqlServerName`
- `SqlDatabase`

Ejemplo:

```json
{
  "agentId": "cliente001-servidortm",
  "clientId": "cliente001",
  "version": "1.0.0",
  "machineName": "SERVIDORTM",
  "sqlServerName": "SERVIDORTM\\AXSQLEXPRESS",
  "sqlDatabase": "TANGO_GESTION"
}
```

---

## 8. Comunicacion con AWS

El agente inicia una conexion saliente hacia el Agent Gateway.

```text
PaqAgent -> HTTPS/WSS 443 -> Agent Gateway AWS
```

Aunque la consulta sea funcionalmente iniciada por AWS, tecnicamente AWS envia el pedido por un canal ya abierto por el agente.

Esto evita:

- apertura de puertos entrantes en el cliente;
- exposicion directa de SQL Server;
- dependencia de VPN para cada consulta;
- configuraciones complejas en routers o firewalls.

---

## 9. Heartbeat

El agente debe enviar un heartbeat periodico al gateway.

Frecuencia sugerida:

```text
30 segundos
```

Payload:

```json
{
  "agentId": "cliente001-servidortm",
  "clientId": "cliente001",
  "timestampUtc": "2026-01-01T10:00:00Z",
  "status": "online",
  "version": "1.0.0",
  "machineName": "SERVIDORTM"
}
```

---

## 10. Modelo de job

Ejemplo de job recibido desde AWS:

```json
{
  "jobId": "job_123456",
  "clientId": "cliente001",
  "agentId": "cliente001-servidortm",
  "operation": "clientes.buscar",
  "parameters": {
    "texto": "GARCIA",
    "limit": 20
  },
  "timeoutSeconds": 30,
  "requestedAtUtc": "2026-01-01T10:00:00Z"
}
```

---

## 11. Modelo de respuesta

Respuesta exitosa:

```json
{
  "jobId": "job_123456",
  "agentId": "cliente001-servidortm",
  "status": "success",
  "durationMs": 420,
  "data": [
    {
      "codigo": "000123",
      "razonSocial": "Cliente Demo SA",
      "cuit": "30700000001"
    }
  ],
  "error": null
}
```

Respuesta con error:

```json
{
  "jobId": "job_123456",
  "agentId": "cliente001-servidortm",
  "status": "failed",
  "durationMs": 125,
  "data": null,
  "error": {
    "code": "SQL_TIMEOUT",
    "message": "La consulta supero el tiempo maximo permitido."
  }
}
```

---

## 12. Estados posibles de un job

```text
pending
received
running
success
failed
timeout
cancelled
```

---

## 13. Operaciones permitidas

El agente no debe ejecutar SQL libre recibido desde AWS.

Prohibido:

```json
{
  "sql": "SELECT * FROM GVA14"
}
```

Permitido:

```json
{
  "operation": "clientes.buscar",
  "parameters": {
    "texto": "GARCIA"
  }
}
```

---

## 14. Lista blanca inicial de operaciones

Operaciones sugeridas para el MVP:

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

---

## 15. Mapeo interno de operaciones

El agente debe traducir operaciones logicas a stored procedures o consultas parametrizadas locales.

Ejemplo:

```text
clientes.buscar -> EXEC PAQ_Clientes_Buscar @texto, @limit
clientes.obtener -> EXEC PAQ_Clientes_Obtener @codigo
stock.consultar -> EXEC PAQ_Stock_Consultar @codigoArticulo, @deposito
saldos.consultar -> EXEC PAQ_Saldos_Consultar @codigoCliente
```

---

## 16. Parametrizacion segura

Todas las consultas deben usar parametros SQL.

No concatenar valores del usuario dentro de strings SQL.

Correcto:

```csharp
command.Parameters.AddWithValue("@texto", texto);
```

Incorrecto:

```csharp
var sql = "SELECT * FROM Clientes WHERE Nombre LIKE '%" + texto + "%'";
```

---

## 17. Timeouts

Valores sugeridos:

```text
Conexion SQL: 15 segundos
Comando SQL por defecto: 30 segundos
Maximo configurable: 120 segundos
Job completo: 30 a 120 segundos
```

Si un job excede el timeout, el agente debe devolver estado `timeout`.

---

## 18. Reconexion

El agente debe reconectarse automaticamente si pierde conexion con el gateway.

Estrategia sugerida:

```text
5 segundos
10 segundos
20 segundos
30 segundos
60 segundos
```

Luego mantener reintentos cada 60 segundos.

Libreria recomendada:

```text
Polly
```

---

## 19. Logs

Directorio sugerido:

```text
logs/
```

Archivos sugeridos:

```text
agent.log
connection.log
jobs.log
errors.log
```

Eventos a registrar:

- inicio del servicio;
- detencion del servicio;
- conexion al gateway;
- reconexion;
- heartbeat;
- recepcion de job;
- finalizacion de job;
- errores SQL;
- errores de autenticacion;
- errores de configuracion.

---

## 20. Diagnostico local

El agente debe incluir una funcion de diagnostico que valide:

1. lectura de configuracion;
2. conexion al gateway;
3. autenticacion;
4. conexion a SQL Server;
5. acceso a base de datos Tango;
6. ejecucion de una consulta simple;
7. version del agente.

Operacion sugerida:

```text
diagnostics.run
```

---

## 21. Cache

El agente no debe depender del cache para funcionar.

Por defecto, las operaciones deben ejecutarse en modo:

```text
live
```

Los modos de cache se gestionaran principalmente desde Laravel, pero el agente debe estar preparado para recibir instrucciones de cache si en el futuro se define cache local.

Modos previstos:

```text
live
cache_first
live_refresh
cache_only
```

---

## 22. Instalacion como Windows Service

El agente debe poder instalarse como servicio Windows.

Ejemplo conceptual:

```powershell
sc.exe create PaqAgent binPath= "C:\PaqAgent\PaqAgent.exe"
sc.exe start PaqAgent
```

Tambien se puede considerar instalacion mediante PowerShell o instalador MSI.

---

## 23. Actualizaciones futuras

El diseno debe prever:

- actualizacion automatica o semiautomatica;
- instalacion silenciosa;
- monitoreo remoto;
- compresion de respuestas;
- metricas de performance;
- soporte para multiples bases Tango en el mismo servidor;
- soporte para multiples agentes por cliente;
- firma de binarios;
- rotacion de tokens;
- diagnostico remoto.

---

## 24. Criterios de aceptacion para el MVP

1. El agente instala como Windows Service.
2. El agente inicia una conexion saliente al gateway.
3. El agente se autentica con `AgentId` y `AgentToken`.
4. El gateway puede enviar un job bajo demanda.
5. El agente ejecuta una operacion permitida contra SQL Server local.
6. El agente devuelve resultado JSON.
7. No se ejecuta SQL libre recibido desde AWS.
8. El agente registra logs.
9. El agente reconecta automaticamente.
10. El agente permite diagnosticar conexion SQL y conexion al gateway.
