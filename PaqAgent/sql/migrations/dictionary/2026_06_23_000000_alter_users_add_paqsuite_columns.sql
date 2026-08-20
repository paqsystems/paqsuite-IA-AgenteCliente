/*
================================================================================
  000000 — Agregar columnas PaqSuite a tabla users preexistente
  
  La tabla users puede existir en el diccionario del cliente con una estructura
  mínima (Tango legacy). Esta migración agrega las columnas que PaqSuite 
  necesita de forma idempotente (IF NOT EXISTS), para que las migraciones 
  000001+ funcionen en cualquier cliente.
================================================================================
*/

-- password_hash
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users' 
    AND COLUMN_NAME = 'password_hash'
)
    ALTER TABLE dbo.users ADD password_hash NVARCHAR(255) NULL;

-- locale
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'locale'
)
    ALTER TABLE dbo.users ADD locale NVARCHAR(10) NULL;

-- menu_abrir_nueva_pestana
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'menu_abrir_nueva_pestana'
)
    ALTER TABLE dbo.users ADD menu_abrir_nueva_pestana BIT NULL;

-- sidebar_collapsed
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'sidebar_collapsed'
)
    ALTER TABLE dbo.users ADD sidebar_collapsed BIT NULL;

-- activo
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'activo'
)
    ALTER TABLE dbo.users ADD activo BIT NOT NULL DEFAULT 1;

-- inhabilitado
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'inhabilitado'
)
    ALTER TABLE dbo.users ADD inhabilitado BIT NOT NULL DEFAULT 0;

-- theme
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'theme'
)
    ALTER TABLE dbo.users ADD theme NVARCHAR(100) NULL;

-- menu_tree_expanded
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'menu_tree_expanded'
)
    ALTER TABLE dbo.users ADD menu_tree_expanded BIT NULL;

-- menu_display_mode
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'menu_display_mode'
)
    ALTER TABLE dbo.users ADD menu_display_mode NVARCHAR(50) NULL;

-- created_at
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'created_at'
)
    ALTER TABLE dbo.users ADD created_at DATETIME2 NULL;

-- updated_at
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'updated_at'
)
    ALTER TABLE dbo.users ADD updated_at DATETIME2 NULL;

-- personal_access_tokens.expires_at
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'personal_access_tokens'
    AND COLUMN_NAME = 'expires_at'
)
    ALTER TABLE dbo.personal_access_tokens ADD expires_at DATETIME2 NULL;

GO
