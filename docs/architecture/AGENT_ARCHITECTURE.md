# PAQSuite IA Tango
# Arquitectura del Agente Local (PaqAgent)

## Objetivo

Reemplazar el acceso directo desde AWS hacia los SQL Server de los clientes mediante VPN/Tailscale por una arquitectura basada en un agente local instalado en cada servidor cliente.

La nueva arquitectura debe:

- Evitar accesos SQL remotos desde AWS.
- Evitar apertura de puertos entrantes en los clientes.
- Permitir consultas bajo demanda.
- Reducir latencia.
- Mejorar seguridad.
- Facilitar instalación y soporte.
- Escalar a cientos de clientes.

---

# Arquitectura General

```text
                ┌─────────────────────┐
                │ Laravel AWS / Forge │
                │     Backend API     │
                └──────────┬──────────┘
                           │
                           │ HTTP Interno
                           │
                           ▼
                ┌─────────────────────┐
                │ Agent Gateway       │
                │ WebSocket / SignalR │
                └──────────┬──────────┘
                           │
          Conexiones salientes permanentes
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼

 ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
 │ PaqAgent    │  │ PaqAgent    │  │ PaqAgent    │
 │ Cliente A   │  │ Cliente B   │  │ Cliente C   │
 └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
        │                │                │
        ▼                ▼                ▼

 ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
 │ SQL Server  │  │ SQL Server  │  │ SQL Server  │
 │ Tango       │  │ Tango       │  │ Tango       │
 └─────────────┘  └─────────────┘  └─────────────┘
```

---

# Principio de funcionamiento

El agente inicia una conexión saliente permanente hacia AWS.

AWS nunca abre conexiones entrantes hacia el cliente.

El agente mantiene un canal persistente mediante:

- SignalR
- o WebSocket

preferentemente sobre:

```text
TCP 443
HTTPS
```

para evitar configuraciones especiales de red.

---

# Flujo de una consulta

```text
Usuario
    │
    ▼
Laravel API
    │
    ▼
Agent Gateway
    │
    ▼
PaqAgent
    │
    ▼
SQL Server Tango
    │
    ▼
PaqAgent
    │
    ▼
Agent Gateway
    │
    ▼
Laravel API
    │
    ▼
Usuario
```

---

# Tecnología del Agente

## Plataforma

.NET 8

## Tipo de aplicación

Worker Service

Instalable como:

```text
Windows Service
```

---

# Dependencias sugeridas

```text
Microsoft.AspNetCore.SignalR.Client
Microsoft.Data.SqlClient
Microsoft.Extensions.Hosting.WindowsServices
Serilog
Serilog.Sinks.File
Polly
System.Text.Json
```

---

# Nombre del producto

```text
PaqAgent
```

---

# Estructura del proyecto

```text
PaqAgent/

├── Configuration/
├── Communication/
├── Database/
├── Jobs/
├── Operations/
├── Security/
├── Logging/
├── Models/
├── Services/
├── Program.cs
└── appsettings.json
```

---

# Configuración local

Archivo:

```text
appsettings.json
```

Ejemplo:

```json
{
  "AgentId": "cliente001-servidortm",
  "ClientId": "cliente001",

  "GatewayUrl": "https://gateway.paqsuite.com",

  "AgentToken": "TOKEN_SECRETO",

  "SqlConnection": {
    "Server": "SERVIDORTM\\AXSQLEXPRESS",
    "Database": "TANGO_GESTION",
    "User": "usuario",
    "Password": "clave",
    "TrustServerCertificate": true,
    "Encrypt": false
  }
}
```

---

# Identificación del Agente

Cada agente debe poseer:

```text
AgentId
ClientId
Version
MachineName
```

Ejemplo:

```json
{
  "agentId": "cliente001-servidortm",
  "clientId": "cliente001",
  "version": "1.0.0",
  "machineName": "SERVIDORTM"
}
```

---

# Heartbeat

Frecuencia sugerida:

```text
30 segundos
```

Información enviada:

```json
{
  "agentId": "cliente001-servidortm",
  "timestamp": "2026-01-01T10:00:00",
  "status": "online",
  "version": "1.0.0"
}
```

---

# Seguridad

## Autenticación

JWT o Token fijo.

Cada instalación posee:

```text
AgentToken
```

único.

---

## TLS

Toda comunicación debe realizarse mediante:

```text
HTTPS
WSS
```

---

# Operaciones Permitidas

El agente NO debe ejecutar SQL libre enviado por AWS.

Prohibido:

```json
{
  "sql": "SELECT * FROM GVA14"
}
```

---

# Lista Blanca de Operaciones

Ejemplo:

```json
{
  "clientes.buscar": {},
  "clientes.obtener": {},
  "articulos.buscar": {},
  "stock.consultar": {},
  "saldos.consultar": {},
  "pedidos.obtener": {}
}
```

---

# Mapeo interno

```text
clientes.buscar
        │
        ▼
PAQ_Clientes_Buscar

stock.consultar
        │
        ▼
PAQ_Stock_Consultar
```

---

# Modelo de Job

```json
{
  "jobId": "job_123456",
  "operation": "clientes.buscar",
  "parameters": {
    "codigo": "000123"
  },
  "timeoutSeconds": 30
}
```

---

# Resultado de Job

```json
{
  "jobId": "job_123456",
  "status": "success",
  "durationMs": 420,
  "data": {
  }
}
```

---

# Estados posibles

```text
pending
running
success
failed
timeout
cancelled
```

---

# Timeouts

Timeout sugerido:

```text
30 segundos
```

Máximo:

```text
120 segundos
```

---

# Reconexión

Utilizar Polly.

Estrategia:

```text
5 segundos
10 segundos
20 segundos
30 segundos
60 segundos
```

hasta reconectar.

---

# Logs

Directorio:

```text
logs/
```

Archivos:

```text
agent.log
errors.log
connection.log
```

---

# Caché

El agente NO debe depender del caché para funcionar.

Por defecto:

```text
LIVE
```

---

# Modos soportados

```text
LIVE
CACHE_FIRST
LIVE_REFRESH
CACHE_ONLY
```

---

# Actualizaciones futuras

El agente deberá estar preparado para:

- auto actualización
- instalación silenciosa
- monitoreo remoto
- diagnóstico remoto
- compresión de respuestas
- ejecución concurrente de jobs
- métricas de performance

---

# Restricciones

1. No abrir puertos en clientes.
2. No exponer SQL Server.
3. No ejecutar SQL libre.
4. Toda comunicación debe ser saliente.
5. Todas las operaciones deben ser auditables.
6. Todo resultado debe estar asociado a un JobId.
7. Toda operación debe ser parametrizada.
8. Mantener compatibilidad con SQL Server 2016 o superior.
9. Optimizar para instalaciones Tango Gestión.
10. Diseñar para cientos de agentes concurrentes.
