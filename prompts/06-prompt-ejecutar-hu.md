# 06 — Prompt para ejecutar una HU

Usar **después** del kickoff y con el SPEC cerrado. Una HU por conversación (o por PR). Completar los placeholders.

---

Actuá como ingeniero senior. Implementá **solo** esta historia y su TR.

## Historia

- HU: `HU-00X — [título]`
- TR: `TR-00X`
- Repo: `[paqsuite-IA-AgenteCliente | PaqSuite-IA-TANGO]`
- Documentos: `prompts/01-SPEC-producto.md`, `prompts/02-decisiones-tecnicas.md`, la HU en `prompts/03-historias-usuario.md`, la TR en `prompts/04-tareas-mvp.md`

## Reglas

1. Usá **exclusivamente** el SPEC y la HU como alcance. Si falta un dato, declaralo supuesto o preguntá; no inventes features.
2. Lenguaje: C# / .NET 8 en este repo; PHP Laravel en TANGO. Miembros y JSON en camelCase.
3. No Tailscale. No fallback SQL. No token default. No SQL libre.
4. Al terminar:
   - Marcá los checkboxes de la TR que cumpliste.
   - Completá la tabla Traza (archivos, comandos, notas, pendientes).
   - Listá cómo verificaste cada criterio de aceptación de la HU.
5. No implementes la HU siguiente.
6. No commit/push sin pedido explícito.

## Entrega

- Código necesario para cerrar la HU.
- Tests o prueba e2e descrita (si es infra: comandos reales).
- Lo que quedó fuera, en Pendientes de la TR, no en código “por las dudas”.

Respondé en español.
