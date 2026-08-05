# Instructivo de instalaciones — PaqAgent y PaqGateway

Guía operativa para instalar el **agente en el servidor del cliente** y desplegar el **gateway en AWS**.

```text
Laravel (AWS) ──HTTP interno──► PaqGateway (SignalR) ◄──WSS 443── PaqAgent (Windows Service)
                                                                      │
                                                                      └── LAN ► SQL Server Tango
```

El agente abre una conexión **saliente**. El cliente **no** abre puertos entrantes ni expone SQL Server a Internet.

---

## 1. Requisitos previos

### 1.1 Alta en PAQSuite (Laravel)

Antes de instalar en el cliente:

1. Crear el cliente en PAQSuite.
2. Crear el registro del agente.
3. Generar y anotar:
   - `AgentId`
   - `ClientId`
   - `AgentToken`

### 1.2 Servidor del cliente (PaqAgent)

| Requisito | Detalle |
|-----------|---------|
| SO | Windows Server o Windows 10/11 |
| Runtime | .NET 8 Runtime |
| SQL | SQL Server con Tango Gestión (base **diccionario** + bases de empresa) |
| Red | Salida **TCP 443** hacia `gateway.paqsuite.com` (y `api.paqsuite.com` si aplica) |
| Privilegios | Administrador para instalar el servicio Windows |
| Credenciales | Usuario SQL con permiso de lectura/ejecución sobre diccionario y empresas |

### 1.3 AWS (PaqGateway)

| Requisito | Detalle |
|-----------|---------|
| Host | EC2 Linux (MVP sugerido) o equivalente |
| Runtime | .NET 8 ASP.NET Core Runtime |
| Proxy TLS | Nginx (o ALB) con certificado HTTPS |
| DNS | `gateway.paqsuite.com` → instancia / balanceador |
| Red | Puerto **443** entrante; salida hacia la API Laravel |
| Integración | Endpoints internos Laravel de autenticación/heartbeat del gateway |

---

## 2. Instalación del agente en el cliente

Ruta sugerida de instalación:

```text
C:\PaqSuite\PaqAgent\
```

La configuración de sitio se guarda en:

```text
C:\PaqSuite\PaqAgent\appsettings.local.json
```

Ese archivo **no** se sobrescribe con los updates del binario. Plantilla de ejemplo: `PaqAgent/appsettings.local.example.json`.

### 2.1 Opción recomendada: PaqAgentInstaller

El instalador WinForms (`PaqAgentInstaller`) automatiza descarga, configuración, servicio y auto-update.

#### Pasos

1. Ejecutar el instalador **como Administrador**.
2. Completar la pestaña **Instalar**:
   - **AgentId** / **ClientId**
   - **Gateway URL** (producción): `https://gateway.paqsuite.com/agent-hub`
   - **Servidor SQL**, **Base diccionario**, usuario y contraseña
   - **Carpeta destino** (default `C:\PaqSuite\PaqAgent`)
3. Pulsar **Probar conexión** y verificar SQL.
4. Pulsar **Instalar**.
5. El instalador:
   - descarga el último release ZIP desde GitHub (`paqsystems/paqsuite-IA-AgenteCliente`);
   - copia binarios a la carpeta destino;
   - escribe `appsettings.local.json`;
   - registra el servicio Windows `PaqAgent` (`start= auto`) y lo inicia;
   - registra la tarea programada `PaqAgent-AutoUpdate` (al arranque + diario 03:00).

#### AgentToken

El formulario **no** pide el token. Comportamiento actual:

- Si ya existía `appsettings.local.json` con `AgentToken`, se **preserva**.
- En instalación nueva se escribe un valor por defecto (`dev-agent-token`).

**Obligatorio en producción:** editar `appsettings.local.json` y colocar el `AgentToken` real generado en Laravel, luego reiniciar el servicio:

```powershell
Restart-Service PaqAgent
```

### 2.2 Opción alternativa: script PowerShell

Desde una máquina con el código fuente / SDK:

```powershell
# Como Administrador
cd PaqAgent\scripts
.\install-service.ps1 -Action install -Build
```

Luego configurar `appsettings.local.json` (o `appsettings.json`) con AgentId, ClientId, AgentToken, GatewayUrl y SqlConnection, y arrancar:

```powershell
.\install-service.ps1 -Action start
```

Otras acciones: `stop`, `restart`, `uninstall`.

### 2.3 Instalación manual

```powershell
dotnet publish PaqAgent\PaqAgent.csproj -c Release -o C:\PaqSuite\PaqAgent
sc.exe create PaqAgent binPath= "C:\PaqSuite\PaqAgent\PaqAgent.exe" DisplayName= "PAQSuite IA Tango - Agente Local" start= auto
sc.exe description PaqAgent "Agente local para consultas SQL Server Tango via Agent Gateway"
# Configurar appsettings.local.json
sc.exe start PaqAgent
```

### 2.4 Configuración mínima del agente

Ejemplo de `appsettings.local.json`:

```json
{
  "Agent": {
    "AgentId": "cliente001-servidortm",
    "ClientId": "cliente001",
    "AgentToken": "TOKEN_SECRETO_DEL_AGENTE",
    "GatewayUrl": "https://gateway.paqsuite.com/agent-hub"
  },
  "SqlConnection": {
    "Server": "SERVIDORTM\\AXSQLEXPRESS",
    "Database": "Diccionario_CLIENTE",
    "User": "usuario_sql",
    "Password": "clave_sql"
  }
}
```

Notas:

- `GatewayUrl` debe incluir el path del hub: `/agent-hub`.
- `SqlConnection.Database` es la base **diccionario** Tango, no una empresa aislada.
- Al arrancar, el agente aplica migraciones SQL embebidas (`PaqAgent/sql/migrations/`). Si fallan de forma reiterada, el proceso no conecta al gateway.

### 2.5 Verificación en el cliente

1. Servicio `PaqAgent` en estado **Running**.
2. Logs en `C:\PaqSuite\PaqAgent\logs\` (conexión y errores).
3. En Laravel: agente en estado **online**.
4. Ejecutar diagnóstico remoto / operación `diagnostics.run`.
5. Probar una operación piloto (por ejemplo `clientes.buscar`).

### 2.6 Actualización del agente

- **Con instalador:** pestaña **Actualizar**, o la tarea `PaqAgent-AutoUpdate` (`installer.exe --update`).
- Los updates preservan `appsettings.local.json`.
- Sin instalador: republicar binarios y reiniciar el servicio, sin borrar la config local.

---

## 3. Instalación del gateway en AWS

Estado del repo: el código de `PaqGateway/` está implementado. El despliegue productivo sugerido para MVP es **EC2 Linux + .NET 8 + systemd + Nginx** (sin Dockerfile ni pipeline CI/CD en este repositorio).

### 3.1 Preparar la instancia

1. Provisionar EC2 Linux en la misma VPC/red que Laravel cuando sea posible.
2. Security Group:
   - **Entrada:** TCP 443 (público o restringido según política).
   - **Salida:** hacia Laravel (`api.paqsuite.com` / IP interna).
3. Asociar DNS: `gateway.paqsuite.com` → instancia o ALB.
4. Instalar .NET 8 ASP.NET Core Runtime.

### 3.2 Publicar la aplicación

Desde una máquina de build (o en la propia instancia con SDK):

```bash
dotnet publish PaqGateway/PaqGateway.csproj -c Release -o /opt/paqgateway
```

Copiar el contenido publicado a `/opt/paqgateway` (o la ruta elegida).

### 3.3 Configuración del gateway

Editar `appsettings.json` / variables de entorno en el servidor. Claves principales:

| Clave | Uso |
|-------|-----|
| `Gateway:InternalApiKey` | API key que Laravel envía a endpoints `/internal/*` |
| `Gateway:DefaultJobTimeoutSeconds` | Timeout de jobs (default 30) |
| `LaravelApi:BaseUrl` | URL pública de la API Laravel (ej. `https://api.paqsuite.com`) |
| `LaravelApi:InternalUrl` | URL interna opcional (IP privada / Tailscale). Si se usa IP, el Host header se toma de `BaseUrl` |
| `LaravelApi:InternalApiKey` | API key hacia Laravel (`X-Internal-Api-Key`) |
| `LaravelApi:AuthCacheTtlSeconds` | Cache de autenticación de agentes (prod típico: 300) |

**Importante:** reemplazar los valores `change-me-in-production` antes de abrir el servicio.

Hub SignalR:

```text
/agent-hub
```

Endpoints internos (protegidos con `X-Internal-Api-Key`):

- `POST /internal/jobs/send`
- `GET /internal/agents/{agentId}/status` (y demás bajo `/internal/agents`)

### 3.4 Servicio systemd (ejemplo)

Archivo `/etc/systemd/system/paqgateway.service`:

```ini
[Unit]
Description=PaqSuite Agent Gateway
After=network.target

[Service]
WorkingDirectory=/opt/paqgateway
ExecStart=/usr/bin/dotnet /opt/paqgateway/PaqGateway.dll
Restart=always
RestartSec=5
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://127.0.0.1:5100
# Opcional: sobrescribir secretos por entorno
# Environment=Gateway__InternalApiKey=...
# Environment=LaravelApi__InternalApiKey=...

[Install]
WantedBy=multi-user.target
```

Activar:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now paqgateway
sudo systemctl status paqgateway
```

### 3.5 Nginx como reverse proxy (HTTPS / WSS)

Nginx termina TLS en 443 y hace proxy a Kestrel. Ejemplo mínimo:

```nginx
server {
    listen 443 ssl http2;
    server_name gateway.paqsuite.com;

    ssl_certificate     /etc/ssl/certs/gateway.paqsuite.com.crt;
    ssl_certificate_key /etc/ssl/private/gateway.paqsuite.com.key;

    location / {
        proxy_pass         http://127.0.0.1:5100;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host $host;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
    }
}
```

Recargar Nginx y verificar que `https://gateway.paqsuite.com/agent-hub` acepte el handshake WebSocket/SignalR.

### 3.6 Integración con Laravel

En Laravel / Forge:

1. Configurar la URL del gateway (base HTTPS, sin path de hub si el cliente la arma).
2. Configurar la misma `InternalApiKey` que usa `Gateway:InternalApiKey`.
3. Exponer y asegurar los endpoints internos que el gateway llama, por ejemplo:
   - `POST /api/internal/gateway/authenticate`
   - heartbeat de agentes bajo `/api/internal/gateway/agents/...`
4. Restringir esos endpoints (API key + red privada cuando sea posible).

### 3.7 Verificación del gateway

1. `systemctl status paqgateway` activo.
2. Nginx responde 443 con certificado válido.
3. Laravel puede autenticar/enviar jobs vía `/internal/...`.
4. Un agente de prueba conecta con `GatewayUrl=https://gateway.paqsuite.com/agent-hub`.
5. Enviar un job de diagnóstico y confirmar round-trip.

---

## 4. Checklist de alta de cliente

1. Alta de cliente y agente en Laravel (`AgentId`, `ClientId`, `AgentToken`).
2. Confirmar gateway productivo online (`gateway.paqsuite.com`).
3. Instalar PaqAgent en el servidor del cliente (Installer o script).
4. Configurar `appsettings.local.json` (incluido **AgentToken** real).
5. Verificar salida TCP 443 hacia el gateway.
6. Iniciar servicio `PaqAgent`.
7. Confirmar estado **online** en Laravel.
8. Ejecutar `diagnostics.run`.
9. Probar operación funcional piloto.
10. Revisar logs del agente y del gateway ante el primer job.

---

## 5. Desarrollo local (referencia rápida)

No es el despliegue de producción. Para pruebas con Tailscale, ver `docs/runbook-gateway-agente-dev.md`.

Resumen:

- Gateway: `ASPNETCORE_ENVIRONMENT=Development`, binding `http://0.0.0.0:5100`.
- Agente: `DOTNET_ENVIRONMENT=Development` (no usar `ASPNETCORE_ENVIRONMENT` en el worker).
- `GatewayUrl` del agente: `http://<IP_TAILSCALE>:5100/agent-hub`.

---

## 6. Documentación relacionada

| Documento | Contenido |
|-----------|-----------|
| [README.md](README.md) | Visión general del agente |
| [docs/architecture/DEPLOYMENT_ARCHITECTURE.md](docs/architecture/DEPLOYMENT_ARCHITECTURE.md) | Arquitectura de despliegue |
| [docs/architecture/AGENT_GATEWAY.md](docs/architecture/AGENT_GATEWAY.md) | Diseño del gateway |
| [docs/architecture/AGENT_ARCHITECTURE.md](docs/architecture/AGENT_ARCHITECTURE.md) | Arquitectura del agente |
| [docs/architecture/LARAVEL_INTEGRATION.md](docs/architecture/LARAVEL_INTEGRATION.md) | Integración Laravel |
| [docs/runbook-gateway-agente-dev.md](docs/runbook-gateway-agente-dev.md) | Runbook de desarrollo |
| [PaqAgent/appsettings.local.example.json](PaqAgent/appsettings.local.example.json) | Plantilla de config local |
| [PaqAgent/scripts/install-service.ps1](PaqAgent/scripts/install-service.ps1) | Script de servicio Windows |
