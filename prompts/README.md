# Paquete SDD — Reformulación PaqAgent + PaqGateway

Este directorio es la **fuente de verdad** para rehacer el proyecto en paralelo, con la misma metodología SDD que el resto de PaqSuite (SPEC → HU → TR → implementación → verificación).

El código actual de `PaqAgent/`, `PaqGateway/` y `PaqAgentInstaller/` **no se borra**. Se toma como referencia de lo que ya se aprendió, no como base a parchar. El desarrollo paralelo arranca desde estos documentos, no desde el prompt histórico.

---

## Circuito de trabajo (obligatorio)

```text
Contexto humano (00)
        │
        ▼
SPEC de producto (01)          ← no se escribe código sin SPEC cerrado
        │
        ▼
Decisiones técnicas (02)       ← lenguaje, tabla, prohibiciones
        │
        ▼
Revisión de ambigüedad         ← prompt 07; dudas se cierran o se marcan
        │
        ▼
Historias de usuario (03)      ← una capacidad observable por vez
        │
        ▼
Tareas técnicas / TR (04)      ← checklist verificable, sin inventar features
        │
        ▼
Kickoff (05) + ejecución HU (06)
        │
        ▼
Implementación HU por HU
        │
        ▼
Verificación contra criterios de aceptación
```

**Prohibido:** implementar operaciones de negocio (acopios, informes, etc.) antes de que el MVP de conectividad esté aceptado.

---

## Índice

| Archivo | Para qué |
|---------|----------|
| [00-contexto-reformulacion.md](00-contexto-reformulacion.md) | Por qué se reformula, qué falló, objetivo real |
| [01-SPEC-producto.md](01-SPEC-producto.md) | SPEC cerrado del producto (fuente de verdad) |
| [02-decisiones-tecnicas.md](02-decisiones-tecnicas.md) | Lenguaje, `empresas_conexion`, Tailscale, repos |
| [03-historias-usuario.md](03-historias-usuario.md) | HU del MVP (HU-001 a HU-008) |
| [04-tareas-mvp.md](04-tareas-mvp.md) | TR por HU, orden de ejecución |
| [05-prompt-kickoff.md](05-prompt-kickoff.md) | Prompt para arrancar el agente de desarrollo paralelo |
| [06-prompt-ejecutar-hu.md](06-prompt-ejecutar-hu.md) | Prompt para implementar **una** HU |
| [07-prompt-revision-ambiguedad.md](07-prompt-revision-ambiguedad.md) | Prompt SDD antes de pasar SPEC → HU |
| [historico/01-prompt-inicial.md](historico/01-prompt-inicial.md) | Prompt original (junio 2026). No usar. |

---

## Repos involucrados

| Repo | Qué se construye aquí |
|------|------------------------|
| `paqsuite-IA-AgenteCliente` (este) | Agente Windows, Gateway .NET, instalador |
| `PaqSuite-IA-TANGO` | Contrato Laravel: `empresas_conexion`, `AgentGatewayClient`, **sin** SQL directo |

El SPEC cubre ambos. El código de Laravel no vive en este repo; el contrato sí.

---

## Definición de terminado del MVP

Un cliente Tango, **sin Tailscale y sin IP pública en `empresas_conexion`**, puede:

1. Instalar el agente con el auto-instalador (credenciales esenciales + SQL local).
2. Ver el servicio Windows corriendo.
3. Aparecer online en PaqSuite.
4. Ejecutar `diagnostics.run` y una operación piloto live (`auth.login` o `clientes.buscar`).

Si eso no está verde, el MVP no está cerrado. El resto espera.
