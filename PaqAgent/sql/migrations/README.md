# Migraciones SQL del agente

## Fuente de verdad

`PaqAgent/sql/migrations/` es la **única** fuente de verdad de cualquier stored procedure del agente. No mantener archivos sueltos con la misma lógica en paralelo (por ejemplo copias de diagnóstico bajo `sql/` fuera de esta carpeta).

## Cómo aplicar un cambio a un SP

Cualquier cambio a un SP — incluso un hotfix validado a mano en SSMS durante un diagnóstico — se vuelca a una **migración nueva** en el mismo momento en que se valida, copiando el `ALTER PROCEDURE` tal cual se probó, no reconstruido de memoria después.

## Inmutabilidad

Las migraciones ya registradas en `dbo.paq_sp_migrations` (en cualquier base) son **inmutables**. Toda corrección posterior es una migración nueva con su propio archivo.

## Cierre de sesión

Antes de cerrar una sesión que tocó un SP: comparar `OBJECT_DEFINITION` / `sp_helptext` en vivo contra el archivo de migración correspondiente, para detectar divergencia antes de que quede documentada como "corregida" sin estarlo realmente.

Este es el caso real que motivó esta regla (ver commit `f3e7d4e`).
