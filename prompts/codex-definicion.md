# PaqSuite IA

## Especificación de reinicio del proyecto

**Componentes:** agente local + Agent Gateway + integración Laravel  
**Versión:** 1.0  
**Fecha:** 3 de septiembre de 2026  
**Alcance:** especificación de desarrollo y aceptación. No modifica código ni define todavía el detalle de migraciones SQL ni el sistema completo de actualizaciones.

## 1. Propósito y criterio de éxito

Este documento define cómo reiniciar el proyecto con prioridades, capas y criterios verificables. El objetivo es que una aplicación Laravel alojada en AWS consulte de forma segura y controlada la base SQL Server de cada tenant mediante un agente instalado en el servidor del cliente.

La primera entrega se considera terminada cuando un tenant real, fuera de Tailscale y detrás de una IP pública dinámica, puede ejecutar una operación permitida desde Laravel y recibir su respuesta desde SQL Server local, sin puertos entrantes en la red del cliente.

```text
Frontend → Laravel (tenant x-paq-cliente) → Agent Gateway AWS
                                                   │ WSS/HTTPS 443
                                                   ▼
                                            PaqAgent Windows
                                                   │ LAN/local
                                                   ▼
                                            SQL Server Tango
```

## 2. Decisiones arquitectónicas obligatorias

1. Producción no depende de Tailscale. Tailscale queda permitido sólo para desarrollo, soporte excepcional o una red administrativa separada.
2. El cliente no abre puertos entrantes y SQL Server no se publica en Internet.
3. El agente inicia y mantiene la conexión saliente hacia el gateway público por HTTPS/WSS, normalmente TCP 443.
4. La IP pública del cliente no es requisito de identidad, ruteo ni disponibilidad. Puede guardarse como dato observado de auditoría, nunca como condición para conectar.
5. Laravel conserva la autoridad sobre tenant, permisos y selección del agente.
6. El gateway valida la coherencia del mensaje y el agente valida que el trabajo le corresponde.
7. Las operaciones funcionales usan stored procedures permitidos; no se acepta SQL libre desde Laravel ni desde el gateway.
8. El estado de un agente se calcula con heartbeat y TTL, no sólo por la existencia de un socket en memoria.
9. No se agregan nuevas operaciones de negocio hasta completar y aceptar una vertical end-to-end mínima.
10. Si una tarea no acerca a la siguiente demostración end-to-end o no elimina un riesgo P0/P1, queda fuera de la iteración actual.

## 3. Alcance de la primera entrega

### Incluido

- PaqAgent para Windows Server/Windows 10/11 como Windows Service.
- Agent Gateway .NET 8 desplegado en AWS detrás de DNS y TLS.
- Integración Laravel para autenticar agentes, consultar estado, enviar jobs y recibir resultados.
- Registro de empresa, agente, token/revocación, estado y metadatos.
- Dos operaciones piloto: `diagnostics.run` y una operación funcional simple como `clientes.buscar`.
- Instalador descargable, configuración guiada, prueba de SQL y registro del servicio.
- Logs estructurados, correlación de job y métricas mínimas.
- Pruebas de reconexión, timeout, agente offline, IP pública dinámica y caída del gateway.

### Fuera de alcance inicial

- Migraciones masivas de todas las bases Tango como mecanismo automático de arranque.
- Catálogo completo de operaciones funcionales.
- Cache de datos como sustituto del modo live.
- Escalamiento multi-gateway y alta disponibilidad antes de tener un piloto estable.
- Panel administrativo completo, auto-update complejo o distribución multiplataforma.
- Conexión directa Laravel → SQL Server como camino normal de producción.

Las migraciones SQL y la estrategia completa de actualización se especificarán en una segunda fase, pero desde ahora deben quedar separadas del runtime del agente.

## 4. Responsabilidades por componente

| Componente | Debe hacer | No debe hacer |
|---|---|---|
| Frontend | Enviar el identificador de tenant según el contrato vigente. | Elegir IP, SQL Server, agente o credenciales. |
| Laravel | Validar usuario, tenant y permisos; resolver agente; auditar; traducir respuestas. | Abrir SQL directo en producción ni mantener sockets. |
| Gateway | Autenticar agentes, mantener conexiones, entregar jobs, correlacionar respuestas y aplicar límites. | Ejecutar SQL o confiar en la IP del cliente. |
| PaqAgent | Conectar salientemente, validar job, ejecutar operación permitida y devolver resultado. | Aceptar SQL libre o exponer administración entrante. |
| SQL Server | Ejecutar stored procedures aprobados sobre bases locales. | Ser accesible desde Internet o Laravel. |

## 5. Modelo de datos y resolución por tenant

La tabla `empresas_conexion` debe adaptarse o complementarse sin romper el modo legacy. Para el modo gateway, la IP no es obligatoria.

| Dato lógico | Obligatorio gateway | Regla |
|---|---:|---|
| `tenant` / `x-paq-cliente` | Sí | Identifica la empresa recibida desde Laravel y debe validarse contra la sesión. |
| `agent_id` | Sí | Identificador único del agente instalado. |
| `client_id` | Sí | Identificador lógico que debe coincidir con el agente. |
| Token/hash y revocación | Sí | Secreto revocable; nunca en logs. Preferir hash en Laravel. |
| Gateway/entorno | Sí | Preferentemente configuración por entorno, no IP por empresa. |
| `enabled` / `revoked_at` | Sí | Control de habilitación y revocación. |
| `last_seen_at` / `status` | Sí | Estado derivado de heartbeat y TTL. |
| `last_seen_ip` | No | Auditoría/soporte; jamás requisito de conexión. |
| Host, puerto o IP SQL | No | Sólo pertenecen al modo legacy/directo, si aún se conserva. |

La relación recomendada es:

```text
empresa/tenant
  └── agente(s)
        ├── agent_id único
        ├── client_id
        ├── token revocable
        ├── enabled
        ├── last_seen_at
        ├── last_seen_ip (observación)
        └── estado calculado por TTL
```

### Flujo de resolución

1. Laravel valida al usuario y extrae/normaliza `x-paq-cliente`.
2. Laravel obtiene el registro activo de empresa y su agente habilitado.
3. Laravel verifica que la operación esté autorizada para ese tenant.
4. Laravel envía al gateway `agent_id`, `client_id`, operación, parámetros, timeout y `trace_id`.
5. El gateway rechaza inconsistencias, agente inexistente, revocado u offline.
6. El agente vuelve a validar que el job corresponde a su `agent_id` y ejecuta sólo la operación permitida.

No se debe usar una IP como clave para seleccionar al agente.

## 6. Contratos de comunicación

### 6.1 Agente → Gateway

- Conexión HTTPS/WSS al hub público.
- Identificación mediante `agent_id`, `client_id` y token secreto.
- Registro inicial con versión, máquina, sistema operativo y metadatos no sensibles.
- Heartbeat periódico con timestamp, versión y estado.
- Reconexión automática con backoff y re-registro.
- Resultado de job con `job_id`, estado, duración, datos y error normalizado.

### 6.2 Laravel → Gateway

```http
POST /internal/jobs/send
Headers: autenticación interna fuerte
Body: {
  traceId,
  agentId,
  clientId,
  operation,
  parameters,
  timeoutSeconds
}
```

El endpoint interno debe estar restringido por red privada/VPC cuando sea posible y protegido por secreto rotado o mecanismo equivalente. Nunca debe quedar abierto públicamente sólo con una clave fija dentro del repositorio.

### 6.3 Estados

| Estado | Significado |
|---|---|
| `success` | El stored procedure terminó y la respuesta es válida. |
| `failed` | Error controlado de operación o SQL. |
| `offline` | No hay agente elegible conectado. |
| `timeout` | Se superó el límite del gateway o agente. |
| `degraded` | Hay red, pero el agente no está listo para operar SQL. |
| `cancelled` | El trabajo fue cancelado antes de completar. |

## 7. Diseño del agente

El agente se instala como servicio Windows y debe separar la configuración por sitio. Debe solicitar o recibir de forma segura:

- `agent_id`.
- `client_id`.
- Token de enrolamiento o token del agente.
- URL del gateway.
- Servidor SQL, instancia/puerto y base diccionario.
- Usuario y contraseña SQL.
- Parámetros TLS de SQL.

### Requisitos del instalador

1. No depender ciegamente de `latest` sin checksum o firma.
2. Solicitar todos los valores obligatorios o implementar un enrolamiento seguro.
3. Probar SQL local y conectividad HTTPS/WSS al gateway.
4. Escribir configuración en un archivo protegido con permisos de servicio.
5. No crear una instalación productiva con token `dev-*`, placeholder o secreto vacío.
6. Instalar/actualizar el Windows Service y mostrar estado, versión y ubicación de logs.
7. Ejecutar una verificación final: servicio, gateway, SQL, diagnóstico y versión.

El agente debe distinguir claramente estos estados:

```text
network_ok
gateway_authenticated
sql_connection_ok
schema_ready
operational
```

Una falla de esquema no debe ocultar una falla de red ni impedir el diagnóstico del equipo.

## 8. Diseño del gateway y operación AWS

Para el primer piloto es suficiente una instancia pública, pero debe tener:

- DNS del tipo `gateway.paqsuite.com`.
- TLS válido y renovación automatizada.
- Entrada sólo por 443 desde Internet; administración restringida.
- Salida hacia Laravel.
- Comunicación Laravel ↔ gateway preferentemente por red privada/VPC.
- Health/readiness endpoints.
- Logs con `trace_id`, `job_id`, `agent_id`, `client_id`, operación, resultado y duración.
- Límites de concurrencia, tamaño de mensaje, timeout y tasa por agente.
- TTL de heartbeat.
- Política de reinicio y reconexión.

Al reiniciar el gateway, los agentes deben reconectar sin intervención. Los jobs en vuelo deben quedar auditados como indeterminados o fallidos; nunca duplicarse silenciosamente.

Redis/backplane y múltiples instancias sólo se incorporan cuando el piloto demuestre una necesidad concreta.

## 9. Stored procedures como frontera SQL

Laravel envía una operación lógica; el agente resuelve esa operación contra un catálogo local de stored procedures permitidos. El nombre del procedimiento nunca debe provenir de un campo libre del usuario.

Cada operación debe declarar:

- nombre lógico;
- stored procedure;
- conexión (`dictionary` o `company`);
- parámetros permitidos y sus tipos/validaciones;
- timeout;
- si es lectura o escritura;
- contrato de respuesta;
- política de auditoría.

Reglas:

- Parámetros tipados y parametrizados; nunca concatenados en SQL.
- No existe endpoint genérico “execute SQL”.
- Las operaciones de escritura requieren autorización adicional, idempotencia y auditoría.
- Los procedimientos deben devolver un contrato estable y versionable.
- La distribución de procedimientos, compatibilidad y rollback se definirá en el documento posterior de inicialización/actualización SQL.

## 10. Plan de desarrollo por capas

| Fase | Entregable | Criterio de salida |
|---|---|---|
| 0 — Contrato | Diagrama, modelo empresa-agente, JSON, estados, seguridad y responsabilidades. | Aprobación escrita; IP no requerida en gateway. |
| 1 — Vertical mínima | Gateway AWS + un agente + diagnóstico + una operación piloto. | Prueba sin Tailscale, sólo salida 443, respuesta desde SQL local. |
| 2 — Robustez | Reconexión, TTL, timeouts, límites, errores, auditoría y health checks. | Pruebas de caída, IP dinámica, offline y job tardío. |
| 3 — Instalación | Instalador guiado, configuración segura, servicio y logs. | Instalación desde máquina limpia y verificación completa. |
| 4 — Operación | Runbook AWS, monitoreo, alertas, rollback y soporte. | Otra persona despliega y diagnostica siguiendo el documento. |
| 5 — Expansión | Nuevas operaciones funcionales. | Cada operación tiene contrato, SP, prueba y aceptación. |

No se permite saltar a la fase 5 mientras la fase 1 no esté aceptada.

## 11. SDD obligatorio

El desarrollo se gestionará con Specification-Driven Development. Ninguna tarea se considera iniciada sólo porque exista un prompt o un commit.

| Artefacto | Contenido mínimo |
|---|---|
| Especificación | Problema, alcance, no-alcance, contrato, supuestos, riesgos y aceptación. |
| Plan | Tareas ordenadas, dependencias, componentes afectados y pruebas. |
| Implementación | Cambios mínimos alineados; sin expansión silenciosa. |
| Verificación | Pruebas, evidencia de logs, resultados y casos negativos. |
| Cierre | Estado aceptado, pendientes, riesgos residuales y siguiente fase. |

### Definition of Done

- La especificación fue aprobada antes de implementar.
- El caso feliz y los errores definidos fueron probados.
- No quedan secretos, placeholders ni configuraciones de desarrollo en producción.
- La documentación operativa se actualizó junto con el cambio.
- La prueba puede reproducirse desde un entorno limpio.
- El cambio no agrega alcance no aprobado.

## 12. Pruebas de aceptación de la primera vertical

| ID | Caso | Acción | Resultado esperado |
|---|---|---|---|
| A-01 | Instalación limpia | Instalar agente sin repositorio ni Tailscale. | Servicio iniciado y configuración persistida. |
| A-02 | Conexión saliente | Permitir sólo salida TCP 443. | Agente conectado al gateway público. |
| A-03 | Tenant correcto | Solicitar con `x-paq-cliente` válido. | Laravel selecciona el agente esperado. |
| A-04 | Tenant cruzado | Forzar agent/client incompatibles. | Solicitud rechazada y auditada. |
| A-05 | IP dinámica | Cambiar IP/NAT de salida del cliente. | Reconecta sin cambiar el registro de empresa. |
| A-06 | SQL local | Ejecutar operación piloto. | Resultado correcto desde SQL local. |
| A-07 | Agente offline | Detener servicio. | Laravel recibe `offline` sin espera indefinida. |
| A-08 | Gateway caído | Reiniciar gateway. | Agente reconecta y vuelve a online. |
| A-09 | Timeout | Ejecutar operación lenta controlada. | Timeout único; sin job duplicado ni conexión colgada. |
| A-10 | Seguridad | Enviar SQL libre o SP no permitido. | Rechazo y registro sin filtrar secretos. |

## 13. Observabilidad y rendimiento

El rendimiento se medirá sobre el flujo real, no probando la IP pública del cliente. Cada request porta `trace_id`; cada job tiene `job_id` único.

Se deben separar estos tiempos:

1. Laravel → gateway.
2. Resolución del agente.
3. Gateway → agente.
4. Apertura de conexión SQL.
5. Ejecución del stored procedure.
6. Lectura y serialización del resultado.
7. Retorno agente → gateway → Laravel.

Métricas mínimas:

| Métrica | Uso |
|---|---|
| Disponibilidad de agentes | Online/degraded/offline y edad del heartbeat. |
| Latencia end-to-end p50/p95 | Experiencia real por operación. |
| Duración SQL p50/p95 | Separar red de stored procedure. |
| Tasa de timeout | Detectar límites mal configurados o SQL inestable. |
| Reconnect count | Detectar cortes, TLS, NAT o gateway inestable. |
| Jobs in-flight/rejected | Controlar saturación y concurrencia. |

## 14. Entregables exigibles al equipo

1. Arquitectura aprobada y actualizada.
2. Gateway desplegable por entorno y sin secretos en el repositorio.
3. Contrato Laravel-Gateway con ejemplos reales.
4. Instalador con versión, checksum/firma y guía de uso.
5. Runbook AWS: DNS, TLS, servicio, logs, health check, firewall, rollback y configuración.
6. Runbook de alta de tenant y agente.
7. Matriz de pruebas con evidencia.
8. Lista de pendientes dividida en P0, P1, P2 y fuera de alcance.
9. Demostración de la vertical mínima sin Tailscale.
10. Documento posterior para inicialización SQL y actualizaciones compatibles de agente, aplicación y esquema.

## 15. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Token o contraseña expuestos | Secretos protegidos, sin defaults productivos, rotación y logs saneados. |
| Tango con esquemas diferentes | Compatibilidad versionada y migraciones separadas del arranque. |
| Gateway reiniciado con jobs en vuelo | Idempotencia, estado indeterminado auditado y reintentos controlados. |
| Resultado demasiado grande | Límites, paginación y contratos de tamaño. |
| Operaciones de escritura duplicadas | Idempotency key y autorización específica. |
| Dependencia accidental de IP | Prueba explícita con cambio de IP y revisión de consultas Laravel. |
| Desarrollo sin foco | Fases con criterios de salida y prohibición de expansión sin aprobación. |

## 16. Decisiones para la siguiente especificación

Antes de implementar migraciones y actualización se debe definir formalmente:

- cómo se inicializan los stored procedures en diccionario y bases de empresa;
- permisos SQL de instalación frente a permisos de runtime;
- versionado conjunto de agente, Laravel y esquema SQL;
- enrolamiento por token único, código de instalación o aprobación desde Laravel;
- almacenamiento de instaladores, checksums, releases y canales estable/beta;
- rollback cuando un agente requiere cambios de esquema;
- clasificación de operaciones de lectura/escritura y auditoría de cada una.

## 17. Regla final de gobierno

El proyecto no debe avanzar por cantidad de commits ni por cantidad de operaciones agregadas. Avanza cuando demuestra una capacidad completa, reproducible y aceptada.

La primera demostración obligatoria es:

```text
tenant válido → Laravel → gateway público AWS → agente sin Tailscale
→ stored procedure local → respuesta auditada
```

Hasta que esa cadena funcione y esté documentada, todo trabajo secundario queda subordinado a ella.
