# 05 — Prompt de kickoff (desarrollo paralelo)

Copiar este bloque **entero** en una conversación nueva (rama `sdd-reformulacion` o worktree limpio). No implementar en el mismo turno en que se hace la revisión de ambigüedad.

---

Sos un ingeniero senior. Vas a **reformular** PaqAgent + PaqGateway en paralelo al código existente, con SDD.

## Fuente de verdad (leer en este orden, sin saltearse)

1. `prompts/README.md`
2. `prompts/00-contexto-reformulacion.md`
3. `prompts/01-SPEC-producto.md`
4. `prompts/02-decisiones-tecnicas.md`
5. `prompts/03-historias-usuario.md`
6. `prompts/04-tareas-mvp.md`

El código actual de `PaqAgent/`, `PaqGateway/` y `PaqAgentInstaller/` es **referencia**, no la especificación. Si el código contradice el SPEC, gana el SPEC.

## Objetivo del producto (no lo negociés)

Agente Windows en el servidor SQL del cliente + Gateway en Amazon. Laravel en AWS **no** se conecta a SQL remoto. `empresas_conexion` guarda `agent_id` / `client_id` / token, **no** la IP del cliente. Tailscale no es parte del producto.

## Lenguaje

- Agente, Gateway, instalador: **C# / .NET 8**
- App: Laravel (repo `PaqSuite-IA-TANGO`)
- Datos Tango: T-SQL (SP parametrizados)

## Circuito (obligatorio)

1. Ejecutá primero `prompts/07-prompt-revision-ambiguedad.md`. Si hay dudas de producto, **pará** y listalas. No codees.
2. Cuando el humano cierre el SPEC, implementá **una** HU por conversación usando `prompts/06-prompt-ejecutar-hu.md`.
3. Orden: HU-001 → … → HU-008. Prohibido saltar a acopios, informes u otras operaciones.
4. No hagas commit ni push salvo que te lo pidan.

## Prohibido

- Fallback SQL directo / usar `host` de `empresas_conexion` para consultar.
- Tailscale en config, runbooks de producción o `GatewayUrl`.
- `dev-agent-token` como default del instalador.
- SQL libre enviado desde AWS.
- Una clase C# por cada stored procedure (usar handler genérico).
- Documentar el Gateway “pendiente” si ya lo estás implementando.
- Ampliar el MVP (auto-update, Redis, 40 operaciones).

## Permitido reutilizar del repo actual

Contratos JSON, idea de SignalR, `SqlExecutor` parametrizado, SPs existentes **solo para la operación piloto** (HU-006). El instalador se rehace con token obligatorio.

## Primera respuesta esperada

No escribas código. Confirmá:

1. Que leíste el SPEC.
2. El resultado de la revisión de ambigüedad (cerrado / lista de preguntas).
3. Cuál es la primera HU que implementarás cuando te autoricen.

Respondé en español.
