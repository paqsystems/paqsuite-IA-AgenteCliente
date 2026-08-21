/*
================================================================================
  000000 — Crear o completar tablas PaqSuite en el diccionario

  Cubre tres escenarios:
  A) Instalación limpia (diccionario Tango puro): ninguna tabla existe → se crean todas
  B) Instalación parcial (users legacy con pocas columnas): se agregan columnas faltantes
  C) Diccionario ya actualizado (tecser): IF NOT EXISTS no hace nada

  Idempotente en los tres casos.
  Orden: users → personal_access_tokens → PQ_Empresa → pq_rol → pq_permiso
================================================================================
*/

-- ============================================================================
-- TABLA: users
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'users'
)
BEGIN
    CREATE TABLE dbo.users (
        id                       BIGINT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
        codigo                   NVARCHAR(255)   NOT NULL,
        name_user                NVARCHAR(255)   NOT NULL,
        email                    NVARCHAR(255)   NOT NULL,
        password                 NVARCHAR(255)   NULL,
        token                    NVARCHAR(255)   NULL,
        first_login              BIT             NULL DEFAULT 1,
        supervisor               BIT             NULL,
        activo                   BIT             NULL,
        inhabilitado             BIT             NULL,
        menu_abrir_nueva_pestana BIT             NULL,
        locale                   NVARCHAR(10)    NULL,
        created_at               DATETIME2       NULL,
        updated_at               DATETIME2       NULL,
        password_hash            NVARCHAR(255)   NULL,
        sidebar_collapsed        BIT             NOT NULL DEFAULT 0,
        theme                    NVARCHAR(32)    NOT NULL DEFAULT 'light',
        menu_tree_expanded       BIT             NOT NULL DEFAULT 0,
        menu_display_mode        NVARCHAR(20)    NOT NULL DEFAULT 'allBranches'
    );
END

-- Columnas faltantes si users ya existe (instalación parcial)
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='password_hash')
    ALTER TABLE dbo.users ADD password_hash NVARCHAR(255) NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='locale')
    ALTER TABLE dbo.users ADD locale NVARCHAR(10) NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='menu_abrir_nueva_pestana')
    ALTER TABLE dbo.users ADD menu_abrir_nueva_pestana BIT NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='sidebar_collapsed')
    ALTER TABLE dbo.users ADD sidebar_collapsed BIT NOT NULL DEFAULT 0;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='activo')
    ALTER TABLE dbo.users ADD activo BIT NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='inhabilitado')
    ALTER TABLE dbo.users ADD inhabilitado BIT NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='theme')
    ALTER TABLE dbo.users ADD theme NVARCHAR(32) NOT NULL DEFAULT 'light';

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='menu_tree_expanded')
    ALTER TABLE dbo.users ADD menu_tree_expanded BIT NOT NULL DEFAULT 0;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='menu_display_mode')
    ALTER TABLE dbo.users ADD menu_display_mode NVARCHAR(20) NOT NULL DEFAULT 'allBranches';

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='created_at')
    ALTER TABLE dbo.users ADD created_at DATETIME2 NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='users' AND COLUMN_NAME='updated_at')
    ALTER TABLE dbo.users ADD updated_at DATETIME2 NULL;

GO

-- ============================================================================
-- TABLA: personal_access_tokens
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'personal_access_tokens'
)
BEGIN
    CREATE TABLE dbo.personal_access_tokens (
        id              BIGINT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
        tokenable_type  NVARCHAR(255)   NOT NULL,
        tokenable_id    BIGINT          NOT NULL,
        name            NVARCHAR(255)   NOT NULL,
        token           NVARCHAR(64)    NOT NULL,
        abilities       NVARCHAR(MAX)   NULL,
        last_used_at    DATE            NULL,
        expires_at      DATE            NULL,
        created_at      DATE            NULL,
        updated_at      DATE            NULL,
        [user]          NVARCHAR(255)   NULL,
        empresa         NVARCHAR(255)   NULL,
        NombreBD        NVARCHAR(255)   NULL,
        produccion      NVARCHAR(50)    NULL DEFAULT 'false'
    );
END

-- Columnas faltantes si personal_access_tokens ya existe
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='personal_access_tokens' AND COLUMN_NAME='expires_at')
    ALTER TABLE dbo.personal_access_tokens ADD expires_at DATE NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='personal_access_tokens' AND COLUMN_NAME='user')
    ALTER TABLE dbo.personal_access_tokens ADD [user] NVARCHAR(255) NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='personal_access_tokens' AND COLUMN_NAME='empresa')
    ALTER TABLE dbo.personal_access_tokens ADD empresa NVARCHAR(255) NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='personal_access_tokens' AND COLUMN_NAME='NombreBD')
    ALTER TABLE dbo.personal_access_tokens ADD NombreBD NVARCHAR(255) NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='personal_access_tokens' AND COLUMN_NAME='produccion')
    ALTER TABLE dbo.personal_access_tokens ADD produccion NVARCHAR(50) NULL DEFAULT 'false';

GO

-- ============================================================================
-- TABLA: PQ_Empresa (perfil legacy Tango PascalCase)
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'PQ_Empresa'
)
BEGIN
    CREATE TABLE dbo.PQ_Empresa (
        IDEmpresa       INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
        NombreEmpresa   VARCHAR(100)    NOT NULL,
        NombreBD        VARCHAR(100)    NOT NULL,
        Habilita        INT             NULL,
        imagen          VARCHAR(100)    NULL,
        theme           NVARCHAR(255)   NULL
    );
END

-- Columnas faltantes si PQ_Empresa ya existe
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='PQ_Empresa' AND COLUMN_NAME='theme')
    ALTER TABLE dbo.PQ_Empresa ADD theme NVARCHAR(255) NULL;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='PQ_Empresa' AND COLUMN_NAME='imagen')
    ALTER TABLE dbo.PQ_Empresa ADD imagen VARCHAR(100) NULL;

GO

-- ============================================================================
-- TABLA: pq_rol
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'pq_rol'
)
BEGIN
    CREATE TABLE dbo.pq_rol (
        id              INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
        nombre_rol      NVARCHAR(100)   NULL,
        descripcion_rol NVARCHAR(100)   NULL,
        acceso_total    BIT             NOT NULL DEFAULT 0,
        created_at      DATETIME        NULL,
        updated_at      DATETIME        NULL
    );
END

GO

-- ============================================================================
-- TABLA: pq_permiso
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'pq_permiso'
)
BEGIN
    CREATE TABLE dbo.pq_permiso (
        id          INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
        id_rol      INT             NOT NULL,
        id_empresa  INT             NOT NULL,
        id_usuario  BIGINT          NOT NULL,
        created_at  DATETIME        NULL,
        updated_at  DATETIME        NULL,
        CONSTRAINT UQ_pq_permiso UNIQUE (id_rol, id_empresa, id_usuario)
    );
END

GO
