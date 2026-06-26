# Runbook — Levantar Gateway + Agente en desarrollo local

> Documento operativo para el repo `paqsuite-IA-AgenteCliente`.
> Cubre el escenario de prueba real: **Gateway en una PC de desarrollo** +
> **Agente corriendo en `srv-pq`** (u otro servidor con acceso real a SQL
> Server de clientes), conectados a través de Tailscale.

---

## 1. Arquitectura de esta prueba

```
PC de desarrollo (ej. tu PC)          srv-pq (u otro servidor con SQL real)
┌─────────────────────────┐           ┌─────────────────────────┐
│   PaqGateway (ASP.NET)   │ ◄──────── │   PaqAgent (Worker Svc)  │
│   Puerto 5100            │ Tailscale │                          │
│   IP Tailscale propia    │           │   Conecta a SQL Server   │
└─────────────────────────┘           │   real (Tec-Metal, etc.) │
                                       └─────────────────────────┘
```

- El **Gateway** es ASP.NET Core → usa `ASPNETCORE_ENVIRONMENT`.
- El **Agente** es un Worker Service .NET puro → usa `DOTNET_ENVIRONMENT`
  (¡no `ASPNETCORE_ENVIRONMENT`! son convenciones distintas).

---

## 2. Pre-requisitos (una sola vez)

### 2.1 — Ambas máquinas en la misma red Tailscale

Verificar con:

```powershell
tailscale status
```

Ambas máquinas deben aparecer **conectadas** (sin "offline"), y preferentemente
logueadas con la **misma cuenta organizacional** (ej. `tailscale@paqsystems.com.ar`),
no con cuentas personales — evita el problema de "Tailscale already in use by
otro_usuario" cuando varias personas comparten el mismo servidor físico.

Si aparece ese error de "ya en uso por otro usuario":

```powershell
# Desde una sesión con privilegios de Administrador, en la máquina afectada:
tailscale up
# Si pide loguear, hacerlo con la cuenta organizacional compartida
```

### 2.2 — Obtener la IP de Tailscale de la PC que va a correr el Gateway

```powershell
tailscale ip -4
```

Anotar este valor — se usa como `GatewayUrl` en la configuración del agente.

### 2.3 — Regla de firewall en la PC que corre el Gateway (una sola vez por máquina)

El Gateway necesita aceptar conexiones entrantes desde la red Tailscale.
Ejecutar **como Administrador**:

```powershell
New-NetFirewallRule `
  -DisplayName "PaqGateway HTTP 5100 Tailscale" `
  -Description "PaqGateway puerto 5100 solo desde interfaz Tailscale" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 5100 `
  -InterfaceAlias "Tailscale" `
  -Profile Any
```

> El nombre exacto de la interfaz puede variar. Confirmarlo antes con:
> `Get-NetAdapter | Format-Table Name, InterfaceDescription, Status`
> — buscar la que dice `Tailscale Tunnel`.

### 2.4 — Configurar el binding del Gateway a todas las interfaces

Editar `PaqGateway/Properties/launchSettings.json` y confirmar:

```json
{
  "$schema": "http://json.schemastore.org/launchsettings.json",
  "profiles": {
    "PaqGateway": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": false,
      "applicationUrl": "http://0.0.0.0:5100",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
```

⚠️ **Ojo con el typo más común**: que diga `http://` y NO `https://`. Si
queda en `https://`, Kestrel usa el certificado de desarrollo (no confiable
para otras máquinas) y la conexión falla.

---

## 3. Configuración de archivos (cada vez que cambia el escenario de prueba)

### 3.1 — `PaqGateway/appsettings.Development.json` (en la PC del Gateway)

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft.AspNetCore": "Information"
    }
  },
  "Gateway": {
    "InternalApiKey": "dev-internal-key",
    "Agents": [
      {
        "AgentId": "tecser-agent-01",
        "ClientId": "000205_012",
        "Token": "dev-agent-token",
        "Enabled": true
      }
    ]
  }
}
```

> ⚠️ Este archivo vive en `PaqGateway/`, NO en `PaqAgent/`. Es un error
> frecuente editar el archivo equivocado — ambos proyectos tienen su propio
> `appsettings.Development.json` con secciones distintas (`Gateway` vs `Agent`).

### 3.2 — `PaqAgent/appsettings.Development.json` (en la máquina del agente, ej. srv-pq)

```json
{
  "Agent": {
    "AgentId": "tecser-agent-01",
    "ClientId": "000205_012",
    "AgentToken": "dev-agent-token",
    "GatewayUrl": "http://<IP_TAILSCALE_DEL_GATEWAY>:5100/agent-hub",
    "Version": "1.0.0"
  },
  "Logging": {
    "LogDirectory": "logs",
    "MinimumLevel": "Debug"
  }
}
```

Reemplazar `<IP_TAILSCALE_DEL_GATEWAY>` por la IP obtenida en el paso 2.2
(ej. `100.115.8.101`).

> Los valores `AgentId`, `ClientId` y `AgentToken` deben coincidir
> **exactamente** entre este archivo y el `Gateway:Agents[]` del paso 3.1.

### 3.3 — `PaqAgent/appsettings.json` (sección `SqlConnection`, base del agente)

```json
"SqlConnection": {
  "Server": "<host_o_localhost>",
  "Database": "<nombre_de_la_base>",
  "User": "Axoft",
  "Password": "Axoft",
  "Encrypt": false,
  "TrustServerCertificate": true,
  "ConnectionTimeoutSeconds": 15,
  "CommandTimeoutSeconds": 30
}
```

Apuntar a la base real contra la que se quiere probar (ej. una base de
pruebas local en `srv-pq`, o un cliente real como Tec-Metal).

---

## 4. Levantar el Gateway (en la PC de desarrollo)

```powershell
cd D:\PaqSystems\paqsuite-IA-AgenteCliente   # ajustar ruta real
$env:ASPNETCORE_ENVIRONMENT="Development"
dotnet run --project PaqGateway\PaqGateway.csproj
```

**Confirmar en el log:**

```
Now listening on: http://0.0.0.0:5100
```

Si dice `https://` o `localhost` en vez de `http://0.0.0.0`, revisar el
paso 2.4 (`launchSettings.json`).

> Dejar esta terminal abierta y corriendo durante toda la sesión de prueba.

---

## 5. Levantar el Agente (en la máquina con acceso a SQL real, ej. srv-pq)

```powershell
cd C:\Programacion\paqsuite-IA-AgenteCliente   # ajustar ruta real
$env:DOTNET_ENVIRONMENT="Development"
dotnet run --project PaqAgent\PaqAgent.csproj
```

**Confirmar en el log:**

```
PaqAgent v1.0.0 iniciando, AgentId: tecser-agent-01
Conectando al gateway http://<IP_TAILSCALE>:5100/agent-hub
Conectado y registrado como agente tecser-agent-01
```

**En la terminal del Gateway**, debería aparecer en simultáneo:

```
Agente conectado: agentId=tecser-agent-01, clientId=000205_012, connectionId=...
Agente registrado: agentId=tecser-agent-01, ...
```

> Dejar esta terminal abierta y corriendo durante toda la sesión de prueba.

---

## 6. Probar el cableado — `diagnostics.run`

Desde una tercera terminal, **en la PC del Gateway** (porque el endpoint
HTTP escucha ahí):

```powershell
$body = @{
  agentId        = "tecser-agent-01"
  clientId       = "000205_012"
  operation      = "diagnostics.run"
  parameters     = @{}
  timeoutSeconds = 30
} | ConvertTo-Json

Invoke-RestMethod `
  -Method POST `
  -Uri "http://localhost:5100/internal/jobs/send" `
  -Headers @{ "X-Internal-Api-Key" = "dev-internal-key" } `
  -ContentType "application/json" `
  -Body $body
```

**Resultado esperado** (cableado OK + SQL real accesible):

```
status     : success
data       : @{... sqlConnectionOk=True; status=healthy ...}
```

Si `sqlConnectionOk=False`, revisar la sección `SqlConnection` del paso 3.3.

---

## 7. Probar `auth.login` (end-to-end completo)

Requiere que el SP `PAQ_Auth_Login` ya exista en la base configurada en 3.3
(ver script en `PaqAgent/sql/PAQ_Auth_Login.sql`).

```powershell
$body = @{
  agentId        = "tecser-agent-01"
  clientId       = "000205_012"
  operation      = "auth.login"
  parameters     = @{ codigo = "ADMIN" }   # usar un código real existente
  timeoutSeconds = 30
} | ConvertTo-Json

Invoke-RestMethod `
  -Method POST `
  -Uri "http://localhost:5100/internal/jobs/send" `
  -Headers @{ "X-Internal-Api-Key" = "dev-internal-key" } `
  -ContentType "application/json" `
  -Body $body
```

**Resultado esperado:** `status: success`, con `data.status` en `OK`,
`NOT_FOUND`, `INACTIVE` o `NO_EMPRESAS` según el usuario probado.

---

## 8. Problema recurrente — Windows Firewall bloquea el puerto 5100

### Síntoma

El agente, desde otra máquina, da timeout (`SocketException 10060` o
`10061`) al conectar al Gateway, **aunque el Gateway esté corriendo y
escuchando en `0.0.0.0:5100`**.

### Causa

Cada vez que el Gateway arranca en una sesión nueva de Windows (PC
reiniciada, usuario distinto, etc.), Windows puede mostrar el cartel de
"¿permitir acceso a redes públicas/privadas?". Si ese cartel se cierra sin
confirmar explícitamente, **Windows genera automáticamente reglas de
firewall en `Block`** (bloqueo), que tapan a la regla `Allow` que ya
creamos en el paso 2.3.

### Diagnóstico

En PowerShell **como Administrador**, en la PC del Gateway:

```powershell
Get-NetFirewallRule -DisplayName "*PaqGateway*" | Format-Table DisplayName, Enabled, Direction, Action
```

Si aparece algo así:

```
DisplayName                    Enabled Direction Action
-----------                    ------- --------- ------
PaqGateway HTTP 5100 Tailscale    True   Inbound  Allow   ← la nuestra, OK
PaqGateway                        True   Inbound  Block   ← intrusa, hay que borrarla
PaqGateway                        True   Inbound  Block   ← intrusa, hay que borrarla
```

### Solución — eliminar las reglas intrusas

```powershell
Remove-NetFirewallRule -DisplayName "PaqGateway"
```

> Ojo: el nombre es exactamente `PaqGateway` (sin más texto) — borra las
> automáticas, sin tocar la nuestra (`PaqGateway HTTP 5100 Tailscale`,
> que tiene un `DisplayName` distinto).

### Verificar que quedó limpio

```powershell
Get-NetFirewallRule -DisplayName "*PaqGateway*" | Format-Table DisplayName, Enabled, Direction, Action
```

Debe mostrar **únicamente**:

```
PaqGateway HTTP 5100 Tailscale    True   Inbound  Allow
```

### Si hace falta recrear la regla correcta desde cero

```powershell
# 1. Borrar todo lo que exista con ese nombre
Remove-NetFirewallRule -DisplayName "PaqGateway HTTP 5100 Tailscale" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "PaqGateway" -ErrorAction SilentlyContinue

# 2. Confirmar el nombre exacto de la interfaz Tailscale
Get-NetAdapter | Format-Table Name, InterfaceDescription, Status

# 3. Crear la regla correcta
New-NetFirewallRule `
  -DisplayName "PaqGateway HTTP 5100 Tailscale" `
  -Description "PaqGateway puerto 5100 solo desde interfaz Tailscale" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 5100 `
  -InterfaceAlias "Tailscale" `
  -Profile Any

# 4. Confirmar
Get-NetFirewallRule -DisplayName "*PaqGateway*" | Format-Table DisplayName, Enabled, Direction, Action
```

### Nota sobre por qué pasa esto en desarrollo (y no en producción)

Esto es un problema específico de correr el Gateway en una PC de
**desarrollo con Windows**, donde el firewall pregunta de forma interactiva
cada vez que una app nueva escucha en un puerto. En el deploy real a AWS
(EC2 Linux o Windows Server sin esas notificaciones interactivas), este
problema no debería repetirse — ahí la seguridad de red se gestiona con
Security Groups de AWS, no con el firewall interactivo de escritorio.

---

## 9. Checklist rápido de arranque (para copiar y pegar)

**En la PC del Gateway:**

```powershell
# 0. (Solo si reaparecen reglas de Block) Limpiar firewall
Get-NetFirewallRule -DisplayName "*PaqGateway*" | Format-Table DisplayName, Enabled, Direction, Action
Remove-NetFirewallRule -DisplayName "PaqGateway" -ErrorAction SilentlyContinue

# 1. Levantar el Gateway
cd <ruta_repo>
$env:ASPNETCORE_ENVIRONMENT="Development"
dotnet run --project PaqGateway\PaqGateway.csproj
# Confirmar: "Now listening on: http://0.0.0.0:5100"
```

**En la máquina del Agente (ej. srv-pq):**

```powershell
# 2. Levantar el Agente
cd <ruta_repo>
$env:DOTNET_ENVIRONMENT="Development"
dotnet run --project PaqAgent\PaqAgent.csproj
# Confirmar: "Conectado y registrado como agente <agentId>"
```

**De vuelta en la PC del Gateway (tercera terminal):**

```powershell
# 3. Probar diagnostics.run
$body = @{ agentId="tecser-agent-01"; clientId="000205_012"; operation="diagnostics.run"; parameters=@{}; timeoutSeconds=30 } | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri "http://localhost:5100/internal/jobs/send" -Headers @{ "X-Internal-Api-Key"="dev-internal-key" } -ContentType "application/json" -Body $body
```

---

## 10. Limpieza al terminar la sesión de pruebas

- `Ctrl+C` en ambas terminales (Gateway y Agente) para detener los procesos.
- No es necesario borrar las reglas de firewall si se va a seguir probando
  en los próximos días — solo limpiar si aparecen reglas `Block` nuevas
  (ver sección 8).
- Si se creó algún SP de diagnóstico temporal (ej. `PAQ_Auth_Login_Debug`),
  eliminarlo de la base de pruebas:
  ```sql
  DROP PROCEDURE IF EXISTS dbo.PAQ_Auth_Login_Debug;
  ```
