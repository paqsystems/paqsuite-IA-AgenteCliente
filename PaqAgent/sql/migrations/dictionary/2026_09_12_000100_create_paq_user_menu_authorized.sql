/*
  2026_09_12_000100 — PAQ_User_Menu_Authorized (GEN-33 F3)

  Menú autorizado user+empresa para snapshot gateway (host TANGO GET /user/menu).
  Salida:
    RS1 header: acceso_total, empresa_id
    RS2 items: id, text, parentId, orden, routeName, procedimiento, icon_name, tipo_proceso
*/
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.PAQ_User_Menu_Authorized
    @user_id    INT,
    @empresa_id INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccesoTotal BIT = 0;
    DECLARE @HasPermiso BIT = 0;
    DECLARE @PermisoUsuarioCol SYSNAME;
    DECLARE @PermisoEmpresaCol SYSNAME;
    DECLARE @PermisoRolCol SYSNAME;
    DECLARE @RolIdCol SYSNAME;
    DECLARE @RolAccesoCol SYSNAME;
    DECLARE @MenuIdCol SYSNAME;
    DECLARE @MenuTextCol SYSNAME;
    DECLARE @MenuProcCol SYSNAME;
    DECLARE @MenuEnabledCol SYSNAME;
    DECLARE @MenuParentCol SYSNAME;
    DECLARE @MenuOrderCol SYSNAME;
    DECLARE @MenuRouteCol SYSNAME;
    DECLARE @MenuIconCol SYSNAME = NULL;
    DECLARE @MenuTipoCol SYSNAME = NULL;
    DECLARE @AtrRolCol SYSNAME;
    DECLARE @AtrMenuCol SYSNAME;
    DECLARE @AtrAltaCol SYSNAME;
    DECLARE @AtrBajaCol SYSNAME;
    DECLARE @AtrModiCol SYSNAME;
    DECLARE @AtrRepoCol SYSNAME;
    DECLARE @Sql NVARCHAR(MAX);

    IF @user_id IS NULL OR @user_id <= 0 OR @empresa_id IS NULL OR @empresa_id <= 0
    BEGIN
        SELECT CAST(0 AS BIT) AS [acceso_total], CAST(ISNULL(@empresa_id, 0) AS INT) AS [empresa_id];
        SELECT
            CAST(NULL AS INT) AS [id],
            CAST(NULL AS NVARCHAR(255)) AS [text],
            CAST(NULL AS INT) AS [parentId],
            CAST(NULL AS INT) AS [orden],
            CAST(NULL AS NVARCHAR(150)) AS [routeName],
            CAST(NULL AS NVARCHAR(150)) AS [procedimiento],
            CAST(NULL AS NVARCHAR(50)) AS [icon_name],
            CAST(NULL AS NVARCHAR(20)) AS [tipo_proceso]
        WHERE 1 = 0;
        RETURN;
    END;

    IF OBJECT_ID(N'dbo.pq_menus', N'U') IS NULL
       OR OBJECT_ID(N'dbo.pq_permiso', N'U') IS NULL
       OR OBJECT_ID(N'dbo.pq_rol', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS [acceso_total], @empresa_id AS [empresa_id];
        SELECT
            CAST(NULL AS INT) AS [id],
            CAST(NULL AS NVARCHAR(255)) AS [text],
            CAST(NULL AS INT) AS [parentId],
            CAST(NULL AS INT) AS [orden],
            CAST(NULL AS NVARCHAR(150)) AS [routeName],
            CAST(NULL AS NVARCHAR(150)) AS [procedimiento],
            CAST(NULL AS NVARCHAR(50)) AS [icon_name],
            CAST(NULL AS NVARCHAR(20)) AS [tipo_proceso]
        WHERE 1 = 0;
        RETURN;
    END;

    SET @PermisoUsuarioCol = CASE WHEN COL_LENGTH('dbo.pq_permiso', 'IDUsuario') IS NOT NULL THEN N'IDUsuario' ELSE N'id_usuario' END;
    SET @PermisoEmpresaCol = CASE WHEN COL_LENGTH('dbo.pq_permiso', 'IDEmpresa') IS NOT NULL THEN N'IDEmpresa' ELSE N'id_empresa' END;
    SET @PermisoRolCol = CASE WHEN COL_LENGTH('dbo.pq_permiso', 'IDRol') IS NOT NULL THEN N'IDRol' ELSE N'id_rol' END;
    SET @RolIdCol = CASE WHEN COL_LENGTH('dbo.pq_rol', 'IDRol') IS NOT NULL THEN N'IDRol' ELSE N'id' END;
    SET @RolAccesoCol = CASE WHEN COL_LENGTH('dbo.pq_rol', 'AccesoTotal') IS NOT NULL THEN N'AccesoTotal' ELSE N'acceso_total' END;
    SET @MenuIdCol = CASE WHEN COL_LENGTH('dbo.pq_menus', 'ID') IS NOT NULL THEN N'ID' ELSE N'id' END;
    SET @MenuTextCol = CASE
        WHEN COL_LENGTH('dbo.pq_menus', 'Text') IS NOT NULL THEN N'Text'
        WHEN COL_LENGTH('dbo.pq_menus', 'text') IS NOT NULL THEN N'text'
        ELSE N'descr'
    END;
    SET @MenuProcCol = CASE WHEN COL_LENGTH('dbo.pq_menus', 'Procedimiento') IS NOT NULL THEN N'Procedimiento' ELSE N'procedimiento' END;
    SET @MenuEnabledCol = CASE WHEN COL_LENGTH('dbo.pq_menus', 'Enabled') IS NOT NULL THEN N'Enabled' ELSE N'enabled' END;
    SET @MenuParentCol = CASE
        WHEN COL_LENGTH('dbo.pq_menus', 'IDParent') IS NOT NULL THEN N'IDParent'
        WHEN COL_LENGTH('dbo.pq_menus', 'Idparent') IS NOT NULL THEN N'Idparent'
        WHEN COL_LENGTH('dbo.pq_menus', 'idparent') IS NOT NULL THEN N'idparent'
        ELSE N'parent'
    END;
    SET @MenuOrderCol = CASE
        WHEN COL_LENGTH('dbo.pq_menus', 'Order') IS NOT NULL THEN N'[Order]'
        WHEN COL_LENGTH('dbo.pq_menus', 'order') IS NOT NULL THEN N'[order]'
        ELSE N'orden'
    END;
    SET @MenuRouteCol = CASE WHEN COL_LENGTH('dbo.pq_menus', 'routeName') IS NOT NULL THEN N'routeName' ELSE N'route_name' END;
    IF COL_LENGTH('dbo.pq_menus', 'icon_name') IS NOT NULL SET @MenuIconCol = N'icon_name';
    IF COL_LENGTH('dbo.pq_menus', 'tipo_proceso') IS NOT NULL SET @MenuTipoCol = N'tipo_proceso';

    SET @Sql = N'
        SELECT @acc = CASE WHEN EXISTS (
            SELECT 1
            FROM dbo.pq_permiso AS p
            INNER JOIN dbo.pq_rol AS r ON p.' + QUOTENAME(@PermisoRolCol) + N' = r.' + QUOTENAME(@RolIdCol) + N'
            WHERE p.' + QUOTENAME(@PermisoUsuarioCol) + N' = @uid
              AND p.' + QUOTENAME(@PermisoEmpresaCol) + N' = @eid
              AND ISNULL(r.' + QUOTENAME(@RolAccesoCol) + N', 0) = 1
        ) THEN 1 ELSE 0 END;
        SELECT @perm = CASE WHEN EXISTS (
            SELECT 1 FROM dbo.pq_permiso AS p
            WHERE p.' + QUOTENAME(@PermisoUsuarioCol) + N' = @uid
              AND p.' + QUOTENAME(@PermisoEmpresaCol) + N' = @eid
        ) THEN 1 ELSE 0 END;';

    EXEC sp_executesql
        @Sql,
        N'@uid INT, @eid INT, @acc BIT OUTPUT, @perm BIT OUTPUT',
        @uid = @user_id,
        @eid = @empresa_id,
        @acc = @AccesoTotal OUTPUT,
        @perm = @HasPermiso OUTPUT;

    SELECT @AccesoTotal AS [acceso_total], @empresa_id AS [empresa_id];

    IF @AccesoTotal = 0 AND @HasPermiso = 0
    BEGIN
        SELECT
            CAST(NULL AS INT) AS [id],
            CAST(NULL AS NVARCHAR(255)) AS [text],
            CAST(NULL AS INT) AS [parentId],
            CAST(NULL AS INT) AS [orden],
            CAST(NULL AS NVARCHAR(150)) AS [routeName],
            CAST(NULL AS NVARCHAR(150)) AS [procedimiento],
            CAST(NULL AS NVARCHAR(50)) AS [icon_name],
            CAST(NULL AS NVARCHAR(20)) AS [tipo_proceso]
        WHERE 1 = 0;
        RETURN;
    END;

    IF OBJECT_ID(N'tempdb..#MenuAuthIds') IS NOT NULL DROP TABLE #MenuAuthIds;
    CREATE TABLE #MenuAuthIds (id INT NOT NULL PRIMARY KEY);

    IF @AccesoTotal = 1
    BEGIN
        SET @Sql = N'
            INSERT INTO #MenuAuthIds(id)
            SELECT m.' + QUOTENAME(@MenuIdCol) + N'
            FROM dbo.pq_menus AS m
            WHERE ISNULL(m.' + QUOTENAME(@MenuEnabledCol) + N', 0) = 1
              AND NULLIF(LTRIM(RTRIM(CAST(m.' + QUOTENAME(@MenuTextCol) + N' AS NVARCHAR(255)))), N'''') IS NOT NULL;';
        EXEC sp_executesql @Sql;
    END
    ELSE IF OBJECT_ID(N'dbo.pq_rol_atributo', N'U') IS NOT NULL
    BEGIN
        SET @AtrRolCol = CASE WHEN COL_LENGTH('dbo.pq_rol_atributo', 'IDRol') IS NOT NULL THEN N'IDRol' ELSE N'id_rol' END;
        SET @AtrMenuCol = CASE WHEN COL_LENGTH('dbo.pq_rol_atributo', 'IDOpcionMenu') IS NOT NULL THEN N'IDOpcionMenu' ELSE N'id_opcion_menu' END;
        SET @AtrAltaCol = CASE WHEN COL_LENGTH('dbo.pq_rol_atributo', 'PermisoAlta') IS NOT NULL THEN N'PermisoAlta' ELSE N'permiso_alta' END;
        SET @AtrBajaCol = CASE WHEN COL_LENGTH('dbo.pq_rol_atributo', 'PermisoBaja') IS NOT NULL THEN N'PermisoBaja' ELSE N'permiso_baja' END;
        SET @AtrModiCol = CASE WHEN COL_LENGTH('dbo.pq_rol_atributo', 'PermisoModi') IS NOT NULL THEN N'PermisoModi' ELSE N'permiso_modi' END;
        SET @AtrRepoCol = CASE WHEN COL_LENGTH('dbo.pq_rol_atributo', 'PermisoRepo') IS NOT NULL THEN N'PermisoRepo' ELSE N'permiso_repo' END;

        SET @Sql = N'
            INSERT INTO #MenuAuthIds(id)
            SELECT DISTINCT a.' + QUOTENAME(@AtrMenuCol) + N'
            FROM dbo.pq_permiso AS p
            INNER JOIN dbo.pq_rol_atributo AS a
                ON a.' + QUOTENAME(@AtrRolCol) + N' = p.' + QUOTENAME(@PermisoRolCol) + N'
            WHERE p.' + QUOTENAME(@PermisoUsuarioCol) + N' = @uid
              AND p.' + QUOTENAME(@PermisoEmpresaCol) + N' = @eid
              AND (
                    ISNULL(a.' + QUOTENAME(@AtrAltaCol) + N', 0) = 1
                 OR ISNULL(a.' + QUOTENAME(@AtrBajaCol) + N', 0) = 1
                 OR ISNULL(a.' + QUOTENAME(@AtrModiCol) + N', 0) = 1
                 OR ISNULL(a.' + QUOTENAME(@AtrRepoCol) + N', 0) = 1
              );';
        EXEC sp_executesql @Sql, N'@uid INT, @eid INT', @uid = @user_id, @eid = @empresa_id;

        /* Ancestros */
        DECLARE @Changed INT = 1;
        WHILE @Changed > 0
        BEGIN
            SET @Sql = N'
                INSERT INTO #MenuAuthIds(id)
                SELECT DISTINCT m.' + QUOTENAME(@MenuParentCol) + N'
                FROM dbo.pq_menus AS m
                INNER JOIN #MenuAuthIds AS a ON a.id = m.' + QUOTENAME(@MenuIdCol) + N'
                WHERE m.' + QUOTENAME(@MenuParentCol) + N' IS NOT NULL
                  AND m.' + QUOTENAME(@MenuParentCol) + N' > 0
                  AND NOT EXISTS (SELECT 1 FROM #MenuAuthIds x WHERE x.id = m.' + QUOTENAME(@MenuParentCol) + N');';
            EXEC sp_executesql @Sql;
            SET @Changed = @@ROWCOUNT;
        END;
    END;

    SET @Sql = N'
        SELECT
            m.' + QUOTENAME(@MenuIdCol) + N' AS [id],
            CAST(m.' + QUOTENAME(@MenuTextCol) + N' AS NVARCHAR(255)) AS [text],
            CASE WHEN m.' + QUOTENAME(@MenuParentCol) + N' IS NULL OR m.' + QUOTENAME(@MenuParentCol) + N' <= 0
                 THEN NULL ELSE CAST(m.' + QUOTENAME(@MenuParentCol) + N' AS INT) END AS [parentId],
            CAST(m.' + @MenuOrderCol + N' AS INT) AS [orden],
            CAST(m.' + QUOTENAME(@MenuRouteCol) + N' AS NVARCHAR(150)) AS [routeName],
            CAST(m.' + QUOTENAME(@MenuProcCol) + N' AS NVARCHAR(150)) AS [procedimiento],
            ' + CASE WHEN @MenuIconCol IS NULL THEN N'CAST(NULL AS NVARCHAR(50))' ELSE N'CAST(m.' + QUOTENAME(@MenuIconCol) + N' AS NVARCHAR(50))' END + N' AS [icon_name],
            ' + CASE WHEN @MenuTipoCol IS NULL THEN N'CAST(NULL AS NVARCHAR(20))' ELSE N'CAST(m.' + QUOTENAME(@MenuTipoCol) + N' AS NVARCHAR(20))' END + N' AS [tipo_proceso]
        FROM dbo.pq_menus AS m
        INNER JOIN #MenuAuthIds AS a ON a.id = m.' + QUOTENAME(@MenuIdCol) + N'
        WHERE ISNULL(m.' + QUOTENAME(@MenuEnabledCol) + N', 0) = 1
          AND NULLIF(LTRIM(RTRIM(CAST(m.' + QUOTENAME(@MenuTextCol) + N' AS NVARCHAR(255)))), N'''') IS NOT NULL
        ORDER BY m.' + QUOTENAME(@MenuParentCol) + N', m.' + @MenuOrderCol + N';';

    EXEC sp_executesql @Sql;
END
GO
