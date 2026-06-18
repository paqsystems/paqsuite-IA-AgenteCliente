# PAQSuite IA Tango - Arquitectura de Deployment

## 1. Objetivo

Este documento define la arquitectura de despliegue para PAQSuite IA Tango con el nuevo esquema basado en agentes locales.

La solucion completa se divide en cuatro componentes principales:

1. Laravel Backend en AWS/Forge.
2. Agent Gateway en AWS.
3. PaqAgent instalado en servidores de clientes.
4. SQL Server Tango en servidores de clientes.

---

## 2. Vista general

```text
AWS / Cloud
+--------------------------------------------------+
|                                                  |
|  +---------------------+                         |
|  | Laravel / Forge     |                         |
|  | Backend API         |                         |
|  +----------+----------+                         |
|             |                                    |
|             | HTTP interno                       |
|             v                                    |
|  +---------------------+                         |
|  | Agent Gateway       |                         |
|  | SignalR/WebSocket   |                         |
|  +----------+----------+                         |
|             |                                    |
+-------------|------------------------------------+
              |
              | HTTPS/WSS 443 saliente desde cliente
              |
Cliente       v
+--------------------------------------------------+
|  +---------------------+                         |
|  | PaqAgent            |                         |
|  | Windows Service     |                         |
|  +----------+----------+                         |
|             |                                    |
|             | LAN/local                          |
|             v                                    |
|  +---------------------+                         |
|  | SQL Server Tango    |                         |
|  +---------------------+                         |
+--------------------------------------------------+
```

---

## 3. Componentes en AWS

### Laravel Backend

Responsabilidades:

- APIs funcionales;
- autenticacion de usuarios;
- permisos;
- configuracion por cliente;
- cache opcional;
- auditoria;
- comunicacion con Agent Gateway.

Entorno actual:

```text
AWS / Forge / Laravel
```

---

### Agent Gateway

Responsabilidades:

- conexiones persistentes de agentes;
- SignalR/WebSocket;
- autenticacion de agentes;
- enrutamiento de jobs;
- timeouts;
- estado online/offline;
- metricas.

Tecnologia sugerida:

```text
.NET 8 ASP.NET Core + SignalR
```

---

### Base de datos Laravel

Debe almacenar:

- agentes;
- jobs;
- configuracion de operaciones;
- cache opcional;
- auditoria.

---

### Redis opcional

Uso futuro:

- cache compartido;
- colas;
- estado de agentes;
- SignalR backplane;
- rate limiting.

Para MVP no es obligatorio, pero es recomendable preverlo.

---

## 4. Componentes en cliente

### PaqAgent

Instalado como:

```text
Windows Service
```

Ubicacion sugerida:

```text
C:\PaqSuite\PaqAgent\
```

Archivos:

```text
PaqAgent.exe
appsettings.json
logs\
```

---

### SQL Server Tango

El agente se conecta localmente usando:

```text
Microsoft.Data.SqlClient
```

Ejemplo de servidor:

```text
SERVIDORTM\AXSQLEXPRESS
```

---

## 5. Puertos y conectividad

### Cliente hacia AWS

Requerido:

```text
TCP 443 salida
```

Destino:

```text
https://gateway.paqsuite.com
https://api.paqsuite.com
```

No requerido:

```text
Puertos entrantes en cliente
VPN obligatoria
SQL Server expuesto a Internet
```

---

## 6. DNS sugerido

```text
api.paqsuite.com       -> Laravel Backend
gateway.paqsuite.com   -> Agent Gateway
```

---

## 7. Seguridad de red

1. Todo trafico externo debe usar HTTPS/WSS.
2. El gateway solo debe aceptar agentes autenticados.
3. La API interna Laravel-Gateway debe protegerse con API key, JWT interno o red privada.
4. No exponer SQL Server.
5. No abrir puertos entrantes en clientes.

---

## 8. Instalacion del agente

Proceso sugerido:

1. Crear cliente en Laravel.
2. Crear registro de agente.
3. Generar `AgentId` y `AgentToken`.
4. Descargar instalador o paquete del agente.
5. Instalar en servidor del cliente.
6. Configurar SQL Server local.
7. Iniciar servicio.
8. Verificar estado online desde Laravel.
9. Ejecutar diagnostico.
10. Ejecutar operacion piloto.

---

## 9. Actualizacion del agente

Para MVP:

- actualizacion manual controlada.

Futuro:

- update semiautomatico;
- versionado;
- rollback;
- firma de binarios;
- canal estable/beta.

---

## 10. Entornos

Se recomiendan al menos tres entornos:

```text
dev
staging
production
```

Variables por entorno:

```text
API URL
Gateway URL
Internal API Key
Certificados
Base de datos
Redis
Logging level
```

---

## 11. Deployment Laravel

Se mantiene en Forge.

Consideraciones:

- agregar variables `.env` del gateway;
- ejecutar migraciones nuevas;
- configurar colas si se usan jobs asincronicos;
- configurar cache si se usa Redis;
- agregar logs especificos de agentes.

---

## 12. Deployment Agent Gateway

Opciones:

1. EC2 con systemd.
2. Docker en EC2.
3. ECS/Fargate.
4. App Runner.

Para MVP se sugiere:

```text
EC2 Linux + .NET 8 + systemd + Nginx reverse proxy
```

---

## 13. Observabilidad

Logs minimos:

```text
Laravel logs
Gateway logs
Agent logs
```

Metricas minimas:

```text
agentes online
agentes offline
jobs por minuto
jobs fallidos
jobs timeout
duracion promedio por operacion
```

---

## 14. Backup y retencion

Laravel debe retener:

- historial de jobs;
- errores;
- auditoria;
- configuracion de agentes.

Definir politica de retencion:

```text
jobs exitosos: 30/60/90 dias
jobs fallidos: 180 dias
auditoria: segun necesidad legal/comercial
```

---

## 15. Escalabilidad

### MVP

```text
1 instancia Laravel
1 instancia Agent Gateway
N agentes
```

### Escalado futuro

```text
N instancias Laravel
N instancias Agent Gateway
Redis backplane
Load balancer
Observabilidad centralizada
```

---

## 16. Alta de nuevo cliente

Checklist:

1. Crear cliente en PAQSuite.
2. Crear agente asociado.
3. Generar token.
4. Descargar instalador.
5. Instalar agente.
6. Configurar SQL local.
7. Verificar conexion al gateway.
8. Verificar conexion SQL.
9. Ejecutar `diagnostics.run`.
10. Probar operacion funcional.

---

## 17. Modo degradado

Si el agente esta offline:

- operaciones `live`: deben fallar con error claro;
- operaciones `cache_first`: pueden responder cache vigente;
- operaciones `cache_only`: responden solo cache;
- operaciones criticas no deben responder datos vencidos salvo configuracion explicita.

---

## 18. Criterios de aceptacion MVP

1. Laravel desplegado en Forge.
2. Agent Gateway desplegado y accesible por HTTPS/WSS.
3. PaqAgent instalado en al menos un cliente piloto.
4. PaqAgent conecta sin abrir puertos entrantes.
5. Laravel consulta estado del agente.
6. Laravel ejecuta una operacion bajo demanda.
7. El agente consulta SQL Server local.
8. El resultado vuelve a Laravel.
9. Hay logs en los tres componentes.
10. Hay documentacion de instalacion inicial.
