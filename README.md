# PAQSuite IA Tango — Agente Local (PaqAgent)

Agente local en **C# .NET 8** que permite a PAQSuite IA Tango consultar datos de **Tango Gestión / SQL Server** en el servidor del cliente, sin abrir puertos entrantes ni depender de una VPN como mecanismo principal de consulta.

---

## La idea del proyecto

Hoy, para consultar datos de un cliente, el backend en AWS (Laravel) necesita llegar al SQL Server del cliente, lo que implica VPN (por ejemplo Tailscale), configuración de red compleja y exposición indirecta de infraestructura sensible.

**PaqAgent invierte el modelo de conexión:** el agente, instalado en el servidor del cliente, abre una conexión **saliente y persistente** hacia un **Agent Gateway** en AWS. Cuando Laravel necesita datos, envía un *job* al gateway, que lo reenvía al agente conectado. El agente ejecuta una operación permitida contra SQL Server local y devuelve el resultado en JSON.

```text
ANTES (problemático):
  Laravel AWS ──VPN/Tailscale──► SQL Server del cliente

AHORA (propuesto):
  Laravel AWS ──HTTP──► Agent Gateway ──WSS──► PaqAgent local ──LAN──► SQL Server Tango
                              ▲
                              │
                    conexión saliente iniciada por el agente
```

### Beneficios

| Aspecto | Ventaja |
|---------|---------|
| **Red del cliente** | No requiere puertos entrantes ni exponer SQL Server a Internet |
| **Seguridad** | Solo operaciones de una lista blanca; nunca SQL libre desde la nube |
| **Datos en vivo** | Modo `live` por defecto: datos actualizados al momento |
| **Escalabilidad** | Un gateway puede atender múltiples clientes y múltiples agentes |
| **Auditoría** | Cada operación es trazable (job, duración, errores) |
| **Instalación** | Windows Service en el servidor del cliente, despliegue simple |

---

## Componentes del ecosistema

La solución completa se divide en cuatro piezas:

```text
┌─────────────────────────────────────────────────────────────┐
│                        AWS / Cloud                          │
│                                                             │
│   ┌──────────────────┐         ┌──────────────────┐      │
│   │ Laravel Backend  │  HTTP   │  Agent Gateway   │      │
│   │ (API principal)  │────────►│  SignalR Hub     │      │
│   └──────────────────┘         └────────┬─────────┘      │
│                                         │ WSS 443         │
└─────────────────────────────────────────┼─────────────────┘
                                          │
                        conexión saliente │
                                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Servidor del cliente                     │
│                                                             │
│   ┌──────────────────┐         ┌──────────────────┐      │
│   │    PaqAgent      │  LAN    │  SQL Server      │      │
│   │ Windows Service  │────────►│  Tango Gestión   │      │
│   └──────────────────┘         └──────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

| Componente | Ubicación | Tecnología | Estado en este repo |
|------------|-----------|------------|---------------------|
| **Laravel Backend** | AWS / Forge | PHP / Laravel | Documentado en `docs/architecture/LARAVEL_INTEGRATION.md` |
| **Agent Gateway** | AWS | .NET 8 + SignalR | Documentado en `docs/architecture/AGENT_GATEWAY.md` |
| **PaqAgent** | Servidor cliente | .NET 8 Worker Service | **Implementado** en `PaqAgent/` |
| **SQL Server Tango** | Servidor cliente | SQL Server | Base de datos existente del cliente |

---

## Principios de diseño

1. El cliente **no abre puertos entrantes**.
2. SQL Server **no se expone** a Internet.
3. El agente **siempre inicia** la comunicación hacia AWS.
4. Las consultas son **bajo demanda** (no polling obligatorio de datos).
5. **Prohibido** ejecutar SQL libre recibido desde el servidor.
6. Toda operación pasa por una **lista blanca** configurable.
7. Cada operación es **auditable**.
8. Modo por defecto: **`live`** (datos actualizados).
9. Reconexión automática ante caídas de red.
10. Instalable como **Windows Service**.

---

## Estructura del repositorio

```text
paqsuite-IA-AgenteCliente/
├── PaqAgent/                    # Proyecto .NET 8 (este repo)
│   ├── Configuration/           # AgentSettings, SqlConnection, Operations
│   ├── Communication/           # Cliente SignalR hacia el gateway
│   ├── Database/                # Ejecutor SQL con stored procedures
│   ├── Jobs/                    # Despacho y resultados de jobs
│   ├── Models/                  # AgentJob, AgentJobResult, Heartbeat...
│   ├── Operations/              # Registro de operaciones permitidas
│   ├── Security/                # Token y autenticación del agente
│   ├── Services/                # Worker, Heartbeat, Diagnostics
│   ├── Logging/                 # Configuración Serilog
│   ├── scripts/
│   │   └── install-service.ps1  # Instalación como Windows Service
│   ├── Program.cs
│   └── appsettings.json
├── docs/architecture/           # Documentación de arquitectura detallada
│   ├── AGENT_ARCHITECTURE.md
│   ├── AGENT_GATEWAY.md
│   ├── DEPLOYMENT_ARCHITECTURE.md
│   └── LARAVEL_INTEGRATION.md
├── prompts/
│   └── 01-prompt inicial.md     # Prompt de generación del MVP
├── PaqAgent.sln
└── README.md                    # Este archivo
```

---

## Cómo funciona PaqAgent

### 1. Inicio y conexión

Al arrancar el servicio, PaqAgent:

1. Lee la configuración de `appsettings.json`.
2. Abre una conexión SignalR saliente hacia `GatewayUrl` (ej. `https://gateway.paqsuite.com/agent-hub`).
3. Se autentica con `AgentId`, `ClientId` y `AgentToken`.
4. Invoca `RegisterAgent` con su identidad (versión, máquina, SQL Server, etc.).
5. Inicia el envío periódico de **heartbeat** (cada 30 segundos por defecto).

### 2. Recepción y ejecución de jobs

Cuando Laravel necesita datos, el flujo es:

```text
1. Usuario/API llama a Laravel
2. Laravel valida permisos y determina agentId
3. Laravel → POST /internal/jobs/send → Agent Gateway
4. Gateway verifica que el agente esté online
5. Gateway → ExecuteJob → PaqAgent
6. PaqAgent valida la operación contra la lista blanca
7. PaqAgent ejecuta el stored procedure parametrizado
8. PaqAgent → SendJobResult → Gateway → Laravel → Usuario
```

### 3. Ejemplo de job recibido

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

### 4. Ejemplo de respuesta

**Éxito:**

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

**Error:**

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

## Operaciones permitidas (lista blanca)

El agente **nunca** ejecuta SQL arbitrario. Solo operaciones definidas en `appsettings.json`:

| Operación | Stored Procedure | Parámetros |
|-----------|------------------|------------|
| `clientes.buscar` | `PAQ_Clientes_Buscar` | texto, limit |
| `clientes.obtener` | `PAQ_Clientes_Obtener` | codigo |
| `articulos.buscar` | `PAQ_Articulos_Buscar` | texto, limit |
| `articulos.obtener` | `PAQ_Articulos_Obtener` | codigo |
| `stock.consultar` | `PAQ_Stock_Consultar` | codigoArticulo, deposito |
| `saldos.consultar` | `PAQ_Saldos_Consultar` | codigoCliente |
| `pedidos.pendientes` | `PAQ_Pedidos_Pendientes` | codigoCliente, limit |
| `comprobantes.recientes` | `PAQ_Comprobantes_Recientes` | codigoCliente, dias, limit |
| `diagnostics.run` | *(interno)* | — |

> Los stored procedures `PAQ_*` deben crearse en SQL Server Tango del cliente. El agente solo los invoca con parámetros seguros (`AddWithValue`), sin concatenar strings SQL.

---

## Configuración

Archivo principal: `PaqAgent/appsettings.json`

```json
{
  "Agent": {
    "AgentId": "cliente001-servidortm",
    "ClientId": "cliente001",
    "DisplayName": "Servidor Tango Cliente 001",
    "Version": "1.0.0",
    "GatewayUrl": "https://gateway.paqsuite.com/agent-hub",
    "AgentToken": "TOKEN_SECRETO_DEL_AGENTE",
    "HeartbeatSeconds": 30,
    "DefaultTimeoutSeconds": 30,
    "MaxTimeoutSeconds": 120
  },
  "SqlConnection": {
    "Server": "SERVIDORTM\\AXSQLEXPRESS",
    "Database": "TANGO_GESTION",
    "User": "usuario_sql",
    "Password": "clave_sql"
  }
}
```

| Parámetro | Descripción |
|-----------|-------------|
| `AgentId` | Identificador único del agente (generado en Laravel) |
| `ClientId` | Identificador del cliente PAQSuite |
| `AgentToken` | Token secreto de autenticación |
| `GatewayUrl` | URL del hub SignalR del Agent Gateway |
| `HeartbeatSeconds` | Intervalo de heartbeat (default: 30s) |
| `SqlConnection` | Credenciales de conexión local a SQL Server Tango |

---

## Requisitos

- **Windows Server** o Windows 10/11 (servidor del cliente)
- **.NET 8 Runtime** (o SDK para compilar)
- **SQL Server** con Tango Gestión
- Salida **TCP 443** hacia `gateway.paqsuite.com`
- Stored procedures `PAQ_*` creados en la base Tango

### Dependencias NuGet

```text
Microsoft.Extensions.Hosting.WindowsServices
Microsoft.AspNetCore.SignalR.Client
Microsoft.Data.SqlClient
Serilog + Serilog.Sinks.File
Polly
```

---

## Instalación

### Compilar

```powershell
dotnet build PaqAgent.sln -c Release
dotnet publish PaqAgent/PaqAgent.csproj -c Release -o C:\PaqSuite\PaqAgent
```

### Instalar como Windows Service

```powershell
# Como administrador
cd PaqAgent\scripts
.\install-service.ps1 -Action install -Build
.\install-service.ps1 -Action start
```

### Comandos del script

| Acción | Comando |
|--------|---------|
| Instalar | `.\install-service.ps1 -Action install` |
| Compilar e instalar | `.\install-service.ps1 -Action install -Build` |
| Iniciar | `.\install-service.ps1 -Action start` |
| Detener | `.\install-service.ps1 -Action stop` |
| Reiniciar | `.\install-service.ps1 -Action restart` |
| Desinstalar | `.\install-service.ps1 -Action uninstall` |

### Instalación manual

```powershell
sc.exe create PaqAgent binPath= "C:\PaqSuite\PaqAgent\PaqAgent.exe" start= auto
sc.exe description PaqAgent "PAQSuite IA Tango - Agente Local"
sc.exe start PaqAgent
```

---

## Logs

Los logs se escriben en la carpeta `logs/` (configurable):

| Archivo | Contenido |
|---------|-----------|
| `agent.log` | Log general del servicio |
| `connection.log` | Conexión y reconexión al gateway |
| `jobs.log` | Recepción y ejecución de jobs |
| `errors.log` | Solo errores |

Rotación diaria, retención de 30 días (90 para errores).

---

## Seguridad

- Autenticación con `AgentId` + `AgentToken` (Bearer) en cada conexión SignalR.
- **Lista blanca estricta**: solo operaciones definidas en configuración.
- **Parámetros SQL parametrizados**: sin concatenación de valores de usuario.
- **Sin SQL libre**: rechazo automático de cualquier intento de ejecutar SQL arbitrario.
- Tokens y passwords **no se registran** en logs.
- Reconexión con backoff: 5s → 10s → 20s → 30s → 60s.

### Códigos de error

| Código | Significado |
|--------|-------------|
| `OPERATION_NOT_ALLOWED` | Operación no está en la lista blanca |
| `SQL_CONNECTION_FAILED` | No se pudo conectar a SQL Server |
| `SQL_TIMEOUT` | Consulta superó el tiempo máximo |
| `SQL_ERROR` | Error de ejecución SQL |
| `INVALID_PARAMETERS` | Parámetros inválidos o job de otro agente |
| `JOB_TIMEOUT` | Job completo superó el timeout |
| `INTERNAL_ERROR` | Error interno del agente |

---

## Diagnóstico

El agente incluye la operación `diagnostics.run` que valida:

1. Lectura de configuración
2. Conexión al gateway
3. Conexión a SQL Server
4. Operaciones permitidas habilitadas
5. Versión del agente

También puede invocarse remotamente vía `RunDiagnostics` desde el gateway.

---

## Roadmap / trabajo pendiente

| Ítem | Estado |
|------|--------|
| PaqAgent (Worker Service .NET 8) | ✅ Implementado |
| Agent Gateway (SignalR Hub en AWS) | 📋 Documentado, pendiente de implementar |
| Integración Laravel (`AgentGatewayClient`) | 📋 Documentado, pendiente de implementar |
| Stored procedures `PAQ_*` en SQL Server | 📋 Pendiente de crear |
| Prueba piloto end-to-end (`clientes.buscar`) | 📋 Pendiente |
| Cache local opcional | 🔮 Futuro |
| Actualización automática del agente | 🔮 Futuro |
| Redis backplane para gateway escalado | 🔮 Futuro |

---

## Documentación adicional

| Documento | Contenido |
|-----------|-----------|
| [AGENT_ARCHITECTURE.md](docs/architecture/AGENT_ARCHITECTURE.md) | Arquitectura detallada del agente |
| [AGENT_GATEWAY.md](docs/architecture/AGENT_GATEWAY.md) | Diseño del gateway SignalR en AWS |
| [DEPLOYMENT_ARCHITECTURE.md](docs/architecture/DEPLOYMENT_ARCHITECTURE.md) | Despliegue en AWS y en cliente |
| [LARAVEL_INTEGRATION.md](docs/architecture/LARAVEL_INTEGRATION.md) | Integración con el backend Laravel |
| [01-prompt inicial.md](prompts/01-prompt%20inicial.md) | Prompt original de generación del MVP |

---

## Alta de un nuevo cliente (checklist)

1. Crear cliente en PAQSuite (Laravel)
2. Crear registro de agente y generar `AgentId` + `AgentToken`
3. Crear stored procedures `PAQ_*` en SQL Server Tango del cliente
4. Descargar e instalar PaqAgent en el servidor del cliente
5. Configurar `appsettings.json` (token, SQL, gateway URL)
6. Iniciar el servicio Windows
7. Verificar estado **online** desde Laravel
8. Ejecutar `diagnostics.run`
9. Probar operación piloto: `clientes.buscar`

---

## Licencia

Proyecto interno de **PaqSystems**.
