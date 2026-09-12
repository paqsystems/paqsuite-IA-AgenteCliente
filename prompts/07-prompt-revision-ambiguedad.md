# 07 — Prompt de revisión de ambigüedad (SPEC → HU)

Correr **antes** de la primera línea de código del desarrollo paralelo. No genera HU nuevas: audita el SPEC.

---

Actuá como revisor de SPEC (no como implementador).

Leé en este orden:

- `prompts/00-contexto-reformulacion.md`
- `prompts/01-SPEC-producto.md`
- `prompts/02-decisiones-tecnicas.md`
- `prompts/03-historias-usuario.md`

## Tarea

1. Listá **ambigüedades** (dos lecturas posibles del mismo párrafo).
2. Listá **huecos** (el implementador tendría que inventar).
3. Listá **contradicciones** entre SPEC, decisiones y HU.
4. Listá **supuestos** que el SPEC da por cerrados y podrían ser falsos (DNS, VPC, permisos SQL, un solo agente por tenant, etc.).
5. Clasificá cada ítem: `bloquea MVP` | `no bloquea (se puede decidir en la TR)`.
6. **No** propongas features nuevas (auto-update, más operaciones, Redis, app móvil…).
7. **No** escribas código ni reescribas el SPEC entero. Si hace falta un cambio de redacción, sugerí el párrafo exacto.

## Preguntas que ya están cerradas (no las reabras)

- Laravel no usa la IP del cliente para consultar SQL.
- Tailscale no es requisito de producto.
- Lenguaje del agente/gateway/instalador: C# .NET 8.
- El instalador pide AgentToken; no hay default de desarrollo en producción.
- Sin fallback SQL directo en el MVP.

## Salida

Un informe corto en español: tabla de hallazgos + “¿se puede implementar el MVP o hay que devolver el SPEC al humano?”.
