/*
  Migración: fix @ColRolPK fallback en PAQ_Auth_Login
  pq_rol (esquema híbrido Laravel) usa columna PK "id", no "id_rol".
*/
ALTER PROCEDURE dbo.PAQ_Auth_Login
    @Codigo NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* --- Variables de usuario --- */
    DECLARE @UserId                   INT;
    DECLARE @UserCodigo               NVARCHAR(100);
    DECLARE @NameUser                 NVARCHAR(255);
    DECLARE @Email                    NVARCHAR(255);
    DECLARE @PasswordHash             NVARCHAR(255);
    DECLARE @Locale                   NVARCHAR(10);
    DECLARE @MenuAbrirNuevaPestana     BIT;
    DECLARE @SidebarCollapsed          BIT;
    DECLARE @Activo                   BIT;
    DECLARE @Inhabilitado             BIT;

    /* --- Variables de resultado --- */
    DECLARE @Status                   NVARCHAR(20);
    DECLARE @EsAdmin                  BIT = 0;
    DECLARE @RedirectTo               NVARCHAR(20) = NULL;
    DECLARE @EmpresaCount             INT = 0;
    DECLARE @ErrorMessage             NVARCHAR(500) = NULL;

    /* --- Nombres de columna resueltos (legacy → snake_case) --- */
    DECLARE @ColPermisoRol            SYSNAME;
    DECLARE @ColPermisoEmpresa        SYSNAME;
    DECLARE @ColPermisoUsuario        SYSNAME;
    DECLARE @ColRolPK                 SYSNAME;
    DECLARE @ColRolAccesoTotal        SYSNAME;
    DECLARE @ColEmpresaPK             SYSNAME;
    DECLARE @ColEmpresaNombre         SYSNAME;
    DECLARE @ColEmpresaNombreBD       SYSNAME;
    DECLARE @ColEmpresaHabilita       SYSNAME;

    /* --- SQL dinámico --- */
    DECLARE @SqlAdmin                 NVARCHAR(MAX);
    DECLARE @SqlEmpresas              NVARCHAR(MAX);
    DECLARE @EsAdminOut               BIT;

    /* Temp table empresas (segundo result set) */
    CREATE TABLE #Empresas
    (
        id              INT             NOT NULL,
        nombreEmpresa   NVARCHAR(100)   NOT NULL,
        nombreBd        NVARCHAR(100)   NOT NULL,
        theme           NVARCHAR(100)   NOT NULL,
        imagen          NVARCHAR(100)   NULL
    );

    BEGIN TRY
        /* ------------------------------------------------------------------
           0. Detección de esquema (AuthService.php: legacy primero)
           ------------------------------------------------------------------ */
        SELECT @ColPermisoRol = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_permiso'
                  AND COLUMN_NAME = N'IDRol'
            ) THEN N'IDRol' ELSE N'id_rol' END;

        SELECT @ColPermisoEmpresa = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_permiso'
                  AND COLUMN_NAME = N'IDEmpresa'
            ) THEN N'IDEmpresa' ELSE N'id_empresa' END;

        SELECT @ColPermisoUsuario = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_permiso'
                  AND COLUMN_NAME = N'IDUsuario'
            ) THEN N'IDUsuario' ELSE N'id_usuario' END;

        SELECT @ColRolPK = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_rol'
                  AND COLUMN_NAME = N'IDRol'
            ) THEN N'IDRol' ELSE N'id' END;

        SELECT @ColRolAccesoTotal = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_rol'
                  AND COLUMN_NAME = N'AccesoTotal'
            ) THEN N'AccesoTotal' ELSE N'acceso_total' END;

        /* @ColEmpresaPK: fallback id_empresa sin validar aún contra un esquema
           snake_case real en producción; en diccionario_klaus y
           Diccionario_000205_012 siempre existe IDEmpresa y el fallback no se activa. */
        SELECT @ColEmpresaPK = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_empresa'
                  AND COLUMN_NAME = N'IDEmpresa'
            ) THEN N'IDEmpresa' ELSE N'id_empresa' END;

        SELECT @ColEmpresaNombre = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_empresa'
                  AND COLUMN_NAME = N'NombreEmpresa'
            ) THEN N'NombreEmpresa' ELSE N'nombre_empresa' END;

        SELECT @ColEmpresaNombreBD = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_empresa'
                  AND COLUMN_NAME = N'NombreBD'
            ) THEN N'NombreBD' ELSE N'nombre_bd' END;

        SELECT @ColEmpresaHabilita = CASE
            WHEN EXISTS (
                SELECT 1
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N'dbo'
                  AND TABLE_NAME = N'pq_empresa'
                  AND COLUMN_NAME = N'Habilita'
            ) THEN N'Habilita' ELSE N'habilita' END;

        /* ------------------------------------------------------------------
           1. Buscar usuario por codigo (parámetro tipado, sin concatenación)
           ------------------------------------------------------------------ */
        SELECT
            @UserId                 = u.id,
            @UserCodigo             = u.codigo,
            @NameUser               = u.name_user,
            @Email                  = u.email,
            @PasswordHash           = u.password_hash,
            @Locale                 = u.locale,
            @MenuAbrirNuevaPestana   = u.menu_abrir_nueva_pestana,
            @SidebarCollapsed        = u.sidebar_collapsed,
            @Activo                 = u.activo,
            @Inhabilitado           = u.inhabilitado
        FROM dbo.USERS AS u
        WHERE u.codigo = @Codigo;

        /* ------------------------------------------------------------------
           2. NOT_FOUND
           ------------------------------------------------------------------ */
        IF @UserId IS NULL
        BEGIN
            SET @Status = N'NOT_FOUND';
            GOTO EmitResults;
        END

        /* ------------------------------------------------------------------
           3. INACTIVE (activo = 0 OR inhabilitado = 1)
           ------------------------------------------------------------------ */
        IF @Activo = 0 OR @Inhabilitado = 1
        BEGIN
            SET @Status = N'INACTIVE';
            /* No exponer datos del usuario en estados de rechazo temprano */
            SET @UserId = NULL;
            SET @UserCodigo = NULL;
            SET @NameUser = NULL;
            SET @Email = NULL;
            SET @PasswordHash = NULL;
            SET @Locale = NULL;
            SET @MenuAbrirNuevaPestana = NULL;
            SET @SidebarCollapsed = NULL;
            GOTO EmitResults;
        END

        /* ------------------------------------------------------------------
           4b. es_admin — rol con AccesoTotal = 1 (SQL dinámico)
           ------------------------------------------------------------------ */
        SET @EsAdminOut = 0;

        SET @SqlAdmin = N'
IF EXISTS (
    SELECT 1
    FROM dbo.pq_permiso AS p
    INNER JOIN dbo.pq_rol AS r
        ON p.' + QUOTENAME(@ColPermisoRol) + N' = r.' + QUOTENAME(@ColRolPK) + N'
    WHERE p.' + QUOTENAME(@ColPermisoUsuario) + N' = @UserId
      AND r.' + QUOTENAME(@ColRolAccesoTotal) + N' = 1
)
    SET @EsAdminOut = 1;';

        EXEC sys.sp_executesql
            @SqlAdmin,
            N'@UserId INT, @EsAdminOut BIT OUTPUT',
            @UserId = @UserId,
            @EsAdminOut = @EsAdminOut OUTPUT;

        SET @EsAdmin = @EsAdminOut;

        /* ------------------------------------------------------------------
           4c. Empresas habilitadas del usuario (SQL dinámico)
           ------------------------------------------------------------------ */
        SET @SqlEmpresas = N'
INSERT INTO #Empresas (id, nombreEmpresa, nombreBd, theme, imagen)
SELECT DISTINCT
    e.' + QUOTENAME(@ColEmpresaPK) + N',
    e.' + QUOTENAME(@ColEmpresaNombre) + N',
    e.' + QUOTENAME(@ColEmpresaNombreBD) + N',
    ISNULL(e.theme, N''default''),
    e.imagen
FROM dbo.pq_permiso AS p
INNER JOIN dbo.pq_empresa AS e
    ON p.' + QUOTENAME(@ColPermisoEmpresa) + N' = e.' + QUOTENAME(@ColEmpresaPK) + N'
WHERE p.' + QUOTENAME(@ColPermisoUsuario) + N' = @UserId
  AND (e.' + QUOTENAME(@ColEmpresaHabilita) + N' IS NULL OR e.' + QUOTENAME(@ColEmpresaHabilita) + N' IN (0, 1));';

        EXEC sys.sp_executesql
            @SqlEmpresas,
            N'@UserId INT',
            @UserId = @UserId;

        SELECT @EmpresaCount = COUNT(*) FROM #Empresas;

        /* ------------------------------------------------------------------
           4d. NO_EMPRESAS — sin password_hash (no tiene sentido seguir)
           ------------------------------------------------------------------ */
        IF @EmpresaCount = 0
        BEGIN
            SET @Status = N'NO_EMPRESAS';
            SET @PasswordHash = NULL;
            SET @RedirectTo = NULL;
            GOTO EmitResults;
        END

        /* ------------------------------------------------------------------
           4e. OK — incluye password_hash para validación en Laravel
           ------------------------------------------------------------------ */
        SET @Status = N'OK';
        SET @RedirectTo = CASE
            WHEN @EmpresaCount > 1 THEN N'selector'
            ELSE N'layout'
        END;

        EmitResults:
        /* ==============================================================
           RESULT SET 1 — Header (siempre 1 fila)
           ============================================================== */
        SELECT
            @Status                                             AS [status],
            @UserId                                             AS [user_id],
            @UserCodigo                                         AS [codigo],
            @NameUser                                           AS [name_user],
            @Email                                              AS [email],
            @PasswordHash                                       AS [password_hash],
            ISNULL(@Locale, N'es')                              AS [locale],
            CAST(ISNULL(@MenuAbrirNuevaPestana, 0) AS BIT)      AS [menu_abrir_nueva_pestana],
            CAST(ISNULL(@SidebarCollapsed, 0) AS BIT)           AS [sidebar_collapsed],
            CAST(@EsAdmin AS BIT)                               AS [es_admin],
            @RedirectTo                                         AS [redirectTo],
            @ErrorMessage                                       AS [error_message];

        /* ==============================================================
           RESULT SET 2 — Empresas (solo filas cuando status = OK)
           ============================================================== */
        SELECT
            e.id,
            e.nombreEmpresa,
            e.nombreBd,
            e.theme,
            e.imagen
        FROM #Empresas AS e
        WHERE @Status = N'OK'
        ORDER BY e.nombreEmpresa;

    END TRY
    BEGIN CATCH
        /* Log server-side (visible en SQL Server Error Log) sin filtrar al cliente */
        DECLARE @InternalError NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @InternalNumber INT = ERROR_NUMBER();

        RAISERROR(
            N'PAQ_Auth_Login error %d: %s',
            0, 1,
            @InternalNumber,
            @InternalError
        ) WITH LOG;

        SET @Status = N'SQL_ERROR';
        SET @ErrorMessage = N'Error interno al procesar la solicitud de autenticación.';

        /* Header de error */
        SELECT
            @Status                                             AS [status],
            CAST(NULL AS INT)                                   AS [user_id],
            CAST(NULL AS NVARCHAR(100))                         AS [codigo],
            CAST(NULL AS NVARCHAR(255))                         AS [name_user],
            CAST(NULL AS NVARCHAR(255))                         AS [email],
            CAST(NULL AS NVARCHAR(255))                         AS [password_hash],
            CAST(NULL AS NVARCHAR(10))                          AS [locale],
            CAST(NULL AS BIT)                                   AS [menu_abrir_nueva_pestana],
            CAST(NULL AS BIT)                                   AS [sidebar_collapsed],
            CAST(0 AS BIT)                                      AS [es_admin],
            CAST(NULL AS NVARCHAR(20))                          AS [redirectTo],
            @ErrorMessage                                       AS [error_message];

        /* Segundo result set vacío (mantiene contrato de 2 result sets) */
        SELECT
            CAST(NULL AS INT)           AS [id],
            CAST(NULL AS NVARCHAR(100)) AS [nombreEmpresa],
            CAST(NULL AS NVARCHAR(100)) AS [nombreBd],
            CAST(NULL AS NVARCHAR(100)) AS [theme],
            CAST(NULL AS NVARCHAR(100)) AS [imagen]
        WHERE 1 = 0;
    END CATCH
END
GO
