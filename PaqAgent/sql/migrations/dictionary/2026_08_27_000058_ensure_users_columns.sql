/*
================================================================================
  000058 — Garantizar columnas requeridas en dbo.USERS
  
  PAQ_Auth_Login asume que dbo.USERS tiene 10 columnas específicas.
  En algunos diccionarios Tango esas columnas pueden no existir o
  tener nombres distintos según la versión del cliente.
  
  Esta migración verifica cada columna y la agrega si no existe,
  sin tocar las columnas existentes ni los datos.
  Idempotente: segura de ejecutar múltiples veces.
================================================================================
*/

-- codigo
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'codigo'
)
    ALTER TABLE dbo.USERS ADD codigo NVARCHAR(100) NULL;
GO

-- name_user
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'name_user'
)
    ALTER TABLE dbo.USERS ADD name_user NVARCHAR(255) NULL;
GO

-- email
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'email'
)
    ALTER TABLE dbo.USERS ADD email NVARCHAR(255) NULL;
GO

-- password_hash
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'password_hash'
)
    ALTER TABLE dbo.USERS ADD password_hash NVARCHAR(255) NULL;
GO

-- locale
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'locale'
)
    ALTER TABLE dbo.USERS ADD locale NVARCHAR(10) NULL;
GO

-- menu_abrir_nueva_pestana
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'menu_abrir_nueva_pestana'
)
    ALTER TABLE dbo.USERS ADD menu_abrir_nueva_pestana BIT NULL;
GO

-- sidebar_collapsed
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'sidebar_collapsed'
)
    ALTER TABLE dbo.USERS ADD sidebar_collapsed BIT NULL;
GO

-- activo
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'activo'
)
    ALTER TABLE dbo.USERS ADD activo BIT NULL;
GO

-- inhabilitado
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'USERS'
    AND COLUMN_NAME = 'inhabilitado'
)
    ALTER TABLE dbo.USERS ADD inhabilitado BIT NULL;
GO
