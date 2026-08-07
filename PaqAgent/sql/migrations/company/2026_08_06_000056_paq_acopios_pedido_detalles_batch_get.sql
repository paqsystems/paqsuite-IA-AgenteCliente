CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_PedidoDetallesBatchGet
    @pedidos_xml   NVARCHAR(MAX),   -- XML: <pedidos><p talon="1" nro="000001"/></pedidos>
    @dictionary_db NVARCHAR(260),
    @grupo_id      INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ── Guard: parámetros obligatorios ───────────────────────────────────
    IF @grupo_id IS NULL OR @grupo_id <= 0
       OR @dictionary_db IS NULL OR LTRIM(RTRIM(@dictionary_db)) = N''
       OR DB_ID(@dictionary_db) IS NULL
       OR @pedidos_xml IS NULL OR LTRIM(RTRIM(@pedidos_xml)) = N''
    BEGIN
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        RETURN;
    END

    -- ── Parsear XML de entrada ────────────────────────────────────────────
    CREATE TABLE #pedidos_input (
        talonPed  INT           NOT NULL,
        nroPedido NVARCHAR(50)  NOT NULL
    );

    BEGIN TRY
        INSERT INTO #pedidos_input (talonPed, nroPedido)
        SELECT
            CAST(p.value(N'@talon', N'INT')        AS INT),
            LTRIM(RTRIM(p.value(N'@nro', N'NVARCHAR(50)')))
        FROM (SELECT TRY_CAST(@pedidos_xml AS XML) AS x) AS doc
        CROSS APPLY doc.x.nodes(N'/pedidos/p') AS t(p)
        WHERE p.value(N'@talon', N'INT') > 0
          AND LTRIM(RTRIM(p.value(N'@nro', N'NVARCHAR(50)'))) <> N'';
    END TRY
    BEGIN CATCH
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        RETURN;
    END CATCH

    IF NOT EXISTS (SELECT 1 FROM #pedidos_input)
    BEGIN
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        RETURN;
    END

    -- ── Resolver empresas del grupo (igual que 000053) ───────────────────
    DECLARE @dictQuoted NVARCHAR(270) = QUOTENAME(@dictionary_db);

    CREATE TABLE #empresas (
        rn            INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        id            INT           NOT NULL,
        nombreBd      NVARCHAR(260) NOT NULL,
        nombreEmpresa NVARCHAR(200) NULL
    );

    DECLARE @colEmpPk       SYSNAME = NULL,
            @colEmpNombreBd SYSNAME = NULL,
            @colEmpNombre   SYSNAME = NULL,
            @colEmpHabilita SYSNAME = NULL,
            @colRelGrupo    SYSNAME = NULL,
            @colRelEmpresa  SYSNAME = NULL,
            @hasRel         BIT = 0,
            @hasEmp         BIT = 0;

    DECLARE @detectSql NVARCHAR(MAX) = N'
        SELECT
            @o_empPk    = MAX(CASE WHEN c.TABLE_NAME = N''pq_empresa''
                AND LOWER(c.COLUMN_NAME) IN (N''idempresa'',N''id_empresa'') THEN c.COLUMN_NAME END),
            @o_empBd    = MAX(CASE WHEN c.TABLE_NAME = N''pq_empresa''
                AND LOWER(c.COLUMN_NAME) IN (N''nombrebd'',N''nombre_bd'') THEN c.COLUMN_NAME END),
            @o_empNom   = MAX(CASE WHEN c.TABLE_NAME = N''pq_empresa''
                AND LOWER(c.COLUMN_NAME) IN (N''nombreempresa'',N''nombre_empresa'') THEN c.COLUMN_NAME END),
            @o_empHab   = MAX(CASE WHEN c.TABLE_NAME = N''pq_empresa''
                AND LOWER(c.COLUMN_NAME) = N''habilita'' THEN c.COLUMN_NAME END),
            @o_relGrupo = MAX(CASE WHEN c.TABLE_NAME = N''pq_grupo_empresario_empresas''
                AND LOWER(c.COLUMN_NAME) IN (N''id_grupo'',N''idgrupo'') THEN c.COLUMN_NAME END),
            @o_relEmp   = MAX(CASE WHEN c.TABLE_NAME = N''pq_grupo_empresario_empresas''
                AND LOWER(c.COLUMN_NAME) IN (N''id_empresa'',N''idempresa'') THEN c.COLUMN_NAME END),
            @o_hasRel   = MAX(CASE WHEN t.TABLE_NAME = N''pq_grupo_empresario_empresas'' THEN 1 ELSE 0 END),
            @o_hasEmp   = MAX(CASE WHEN t.TABLE_NAME = N''pq_empresa'' THEN 1 ELSE 0 END)
        FROM ' + @dictQuoted + N'.INFORMATION_SCHEMA.TABLES t
        LEFT JOIN ' + @dictQuoted + N'.INFORMATION_SCHEMA.COLUMNS c
            ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME
        WHERE t.TABLE_SCHEMA = N''dbo''
          AND t.TABLE_NAME IN (N''pq_empresa'', N''pq_grupo_empresario_empresas'');';

    EXEC sp_executesql @detectSql,
        N'@o_empPk SYSNAME OUTPUT, @o_empBd SYSNAME OUTPUT, @o_empNom SYSNAME OUTPUT,
          @o_empHab SYSNAME OUTPUT, @o_relGrupo SYSNAME OUTPUT, @o_relEmp SYSNAME OUTPUT,
          @o_hasRel BIT OUTPUT, @o_hasEmp BIT OUTPUT',
        @o_empPk    = @colEmpPk       OUTPUT,
        @o_empBd    = @colEmpNombreBd OUTPUT,
        @o_empNom   = @colEmpNombre   OUTPUT,
        @o_empHab   = @colEmpHabilita OUTPUT,
        @o_relGrupo = @colRelGrupo    OUTPUT,
        @o_relEmp   = @colRelEmpresa  OUTPUT,
        @o_hasRel   = @hasRel         OUTPUT,
        @o_hasEmp   = @hasEmp         OUTPUT;

    IF @hasRel = 0 OR @hasEmp = 0
       OR @colEmpPk IS NULL OR @colEmpNombreBd IS NULL
       OR @colRelGrupo IS NULL OR @colRelEmpresa IS NULL
    BEGIN
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        RETURN;
    END

    DECLARE @sqlEmpresas NVARCHAR(MAX) = N'
        INSERT INTO #empresas (id, nombreBd, nombreEmpresa)
        SELECT
            emp.' + QUOTENAME(@colEmpPk) + N',
            LTRIM(RTRIM(CAST(emp.' + QUOTENAME(@colEmpNombreBd) + N' AS NVARCHAR(260)))),
            ' + CASE WHEN @colEmpNombre IS NOT NULL
                THEN N'CAST(emp.' + QUOTENAME(@colEmpNombre) + N' AS NVARCHAR(200))'
                ELSE N'CAST(NULL AS NVARCHAR(200))' END + N'
        FROM ' + @dictQuoted + N'.dbo.pq_grupo_empresario_empresas AS rel
        INNER JOIN ' + @dictQuoted + N'.dbo.pq_empresa AS emp
            ON emp.' + QUOTENAME(@colEmpPk) + N' = rel.' + QUOTENAME(@colRelEmpresa) + N'
        WHERE rel.' + QUOTENAME(@colRelGrupo) + N' = @p_grupo
          AND emp.' + QUOTENAME(@colEmpNombreBd) + N' IS NOT NULL
          AND LTRIM(RTRIM(CAST(emp.' + QUOTENAME(@colEmpNombreBd) + N' AS NVARCHAR(260)))) <> N'''' '
          + CASE WHEN @colEmpHabilita IS NOT NULL
                THEN N'AND emp.' + QUOTENAME(@colEmpHabilita) + N' = 1'
                ELSE N'' END + N';';

    EXEC sp_executesql @sqlEmpresas, N'@p_grupo INT', @p_grupo = @grupo_id;

    IF NOT EXISTS (SELECT 1 FROM #empresas)
    BEGIN
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        SELECT CAST(NULL AS INT) AS talonPed, CAST(NULL AS NVARCHAR(50)) AS nroPedido WHERE 1=0;
        RETURN;
    END

    -- ── Tablas resultado ─────────────────────────────────────────────────
    CREATE TABLE #cabecera (
        empresaId     INT            NOT NULL,
        empresaBd     NVARCHAR(260)  NOT NULL,
        empresaOrigen NVARCHAR(200)  NULL,
        talonPed      INT            NOT NULL,
        nroPedido     NVARCHAR(50)   NOT NULL,
        codClient     NVARCHAR(20)   NULL,
        razonSocial   NVARCHAR(200)  NULL,
        fechaPedido   DATETIME       NULL,
        fechaEntrega  DATETIME       NULL,
        totalPedido   DECIMAL(18,2)  NULL,
        estado        INT            NULL
    );

    CREATE TABLE #renglones (
        talonPed        INT            NOT NULL,
        nroPedido       NVARCHAR(50)   NOT NULL,
        codArticu       NVARCHAR(50)   NULL,
        cantidad        DECIMAL(18,4)  NULL,
        precioPedido    DECIMAL(18,4)  NULL,
        descuentoPedido DECIMAL(18,4)  NULL
    );

    -- ── Iterar empresas ──────────────────────────────────────────────────
    DECLARE @i   INT = 1,
            @max INT = (SELECT MAX(rn) FROM #empresas),
            @empresaId    INT,
            @nombreBd     NVARCHAR(260),
            @nombreEmpresa NVARCHAR(200),
            @bdQuoted     NVARCHAR(270);

    DECLARE @colTalon    SYSNAME, @colNroPedido SYSNAME, @colCodClient SYSNAME,
            @colFechaPedi SYSNAME, @colFechaEntr SYSNAME, @colTotalPedi SYSNAME,
            @colEstado   SYSNAME, @colRazon     SYSNAME,
            @colDetTalon SYSNAME, @colDetNro    SYSNAME, @colDetArt    SYSNAME,
            @colDetCant  SYSNAME, @colDetPrecio SYSNAME, @colDetDto    SYSNAME;

    DECLARE @sql     NVARCHAR(MAX),
            @colsSql NVARCHAR(MAX),
            @joinCli NVARCHAR(MAX),
            @selRazon     NVARCHAR(MAX),
            @selFechaPedi NVARCHAR(MAX),
            @selFechaEntr NVARCHAR(MAX),
            @selTotal     NVARCHAR(MAX),
            @selCant      NVARCHAR(MAX),
            @selPrecio    NVARCHAR(MAX),
            @selDto       NVARCHAR(MAX),
            @candCant  SYSNAME,
            @candPrecio SYSNAME,
            @candDto   SYSNAME;

    DECLARE @hasGva14 BIT;

    WHILE @i <= @max
    BEGIN
        -- ¿Quedan pedidos sin encontrar?
        IF NOT EXISTS (
            SELECT 1 FROM #pedidos_input pi
            WHERE NOT EXISTS (
                SELECT 1 FROM #cabecera c
                WHERE c.talonPed = pi.talonPed
                  AND LTRIM(RTRIM(c.nroPedido)) = LTRIM(RTRIM(pi.nroPedido))
            )
        ) BREAK;

        SELECT @empresaId = id, @nombreBd = nombreBd, @nombreEmpresa = nombreEmpresa
        FROM #empresas WHERE rn = @i;
        SET @bdQuoted = QUOTENAME(@nombreBd);

        IF OBJECT_ID(@bdQuoted + N'.dbo.GVA21') IS NULL
           OR OBJECT_ID(@bdQuoted + N'.dbo.GVA03') IS NULL
        BEGIN SET @i += 1; CONTINUE; END

        SET @hasGva14 = CASE WHEN OBJECT_ID(@bdQuoted + N'.dbo.GVA14') IS NOT NULL THEN 1 ELSE 0 END;

        -- Detectar columnas (igual que 000053)
        SET @colTalon = NULL; SET @colNroPedido = NULL; SET @colCodClient = NULL;
        SET @colFechaPedi = NULL; SET @colFechaEntr = NULL; SET @colTotalPedi = NULL;
        SET @colEstado = NULL; SET @colRazon = NULL;
        SET @colDetTalon = NULL; SET @colDetNro = NULL; SET @colDetArt = NULL;
        SET @colDetCant = NULL; SET @colDetPrecio = NULL; SET @colDetDto = NULL;

        SET @colsSql = N'
            SELECT
                @o_talon = MAX(CASE WHEN TABLE_NAME=N''GVA21'' AND LOWER(COLUMN_NAME)=N''talon_ped''   THEN COLUMN_NAME END),
                @o_nro   = MAX(CASE WHEN TABLE_NAME=N''GVA21'' AND LOWER(COLUMN_NAME)=N''nro_pedido''  THEN COLUMN_NAME END),
                @o_cli   = MAX(CASE WHEN TABLE_NAME=N''GVA21'' AND LOWER(COLUMN_NAME)=N''cod_client''  THEN COLUMN_NAME END),
                @o_fp    = MAX(CASE WHEN TABLE_NAME=N''GVA21'' AND LOWER(COLUMN_NAME)=N''fecha_pedi''  THEN COLUMN_NAME END),
                @o_fe    = MAX(CASE WHEN TABLE_NAME=N''GVA21'' AND LOWER(COLUMN_NAME)=N''fecha_entr''  THEN COLUMN_NAME END),
                @o_tot   = MAX(CASE WHEN TABLE_NAME=N''GVA21'' AND LOWER(COLUMN_NAME)=N''total_pedi''  THEN COLUMN_NAME END),
                @o_est   = MAX(CASE WHEN TABLE_NAME=N''GVA21'' AND LOWER(COLUMN_NAME)=N''estado''      THEN COLUMN_NAME END),
                @o_raz   = MAX(CASE WHEN TABLE_NAME=N''GVA14'' AND LOWER(COLUMN_NAME)=N''razon_soci''  THEN COLUMN_NAME END),
                @o_dt    = MAX(CASE WHEN TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''talon_ped''   THEN COLUMN_NAME END),
                @o_dn    = MAX(CASE WHEN TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''nro_pedido''  THEN COLUMN_NAME END),
                @o_da    = MAX(CASE WHEN TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''cod_articu''  THEN COLUMN_NAME END)
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA=N''dbo''
              AND TABLE_NAME IN (N''GVA21'',N''GVA14'',N''GVA03'');';

        EXEC sp_executesql @colsSql,
            N'@o_talon SYSNAME OUTPUT, @o_nro SYSNAME OUTPUT, @o_cli SYSNAME OUTPUT,
              @o_fp SYSNAME OUTPUT, @o_fe SYSNAME OUTPUT, @o_tot SYSNAME OUTPUT,
              @o_est SYSNAME OUTPUT, @o_raz SYSNAME OUTPUT,
              @o_dt SYSNAME OUTPUT, @o_dn SYSNAME OUTPUT, @o_da SYSNAME OUTPUT',
            @o_talon = @colTalon     OUTPUT, @o_nro = @colNroPedido OUTPUT,
            @o_cli   = @colCodClient OUTPUT, @o_fp  = @colFechaPedi  OUTPUT,
            @o_fe    = @colFechaEntr OUTPUT, @o_tot = @colTotalPedi  OUTPUT,
            @o_est   = @colEstado    OUTPUT, @o_raz = @colRazon      OUTPUT,
            @o_dt    = @colDetTalon  OUTPUT, @o_dn  = @colDetNro     OUTPUT,
            @o_da    = @colDetArt    OUTPUT;

        -- Candidatos cantidad/precio/descuento (igual que 000053)
        SET @candCant = NULL;
        SET @colsSql = N'SELECT @o=COLUMN_NAME FROM ' + @bdQuoted
            + N'.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=N''dbo'' AND TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''cant_pedid'';';
        EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o=@candCant OUTPUT;
        IF @candCant IS NULL
        BEGIN
            SET @colsSql = N'SELECT @o=COLUMN_NAME FROM ' + @bdQuoted
                + N'.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=N''dbo'' AND TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''cantidad'';';
            EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o=@candCant OUTPUT;
        END
        SET @colDetCant = @candCant;

        SET @candPrecio = NULL;
        SET @colsSql = N'SELECT @o=COLUMN_NAME FROM ' + @bdQuoted
            + N'.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=N''dbo'' AND TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''precio'';';
        EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o=@candPrecio OUTPUT;
        IF @candPrecio IS NULL
        BEGIN
            SET @colsSql = N'SELECT @o=COLUMN_NAME FROM ' + @bdQuoted
                + N'.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=N''dbo'' AND TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''precio_net'';';
            EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o=@candPrecio OUTPUT;
        END
        SET @colDetPrecio = @candPrecio;

        SET @candDto = NULL;
        SET @colsSql = N'SELECT @o=COLUMN_NAME FROM ' + @bdQuoted
            + N'.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=N''dbo'' AND TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''descuento'';';
        EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o=@candDto OUTPUT;
        IF @candDto IS NULL
        BEGIN
            SET @colsSql = N'SELECT @o=COLUMN_NAME FROM ' + @bdQuoted
                + N'.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=N''dbo'' AND TABLE_NAME=N''GVA03'' AND LOWER(COLUMN_NAME)=N''porc_dto'';';
            EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o=@candDto OUTPUT;
        END
        SET @colDetDto = @candDto;

        IF @colTalon IS NULL OR @colNroPedido IS NULL OR @colEstado IS NULL
           OR @colDetTalon IS NULL OR @colDetNro IS NULL OR @colDetArt IS NULL
        BEGIN SET @i += 1; CONTINUE; END

        -- Construir SELECTs opcionales
        SET @selFechaPedi = CASE WHEN @colFechaPedi IS NOT NULL
            THEN N'ped.' + QUOTENAME(@colFechaPedi) ELSE N'CAST(NULL AS DATETIME)' END;
        SET @selFechaEntr = CASE WHEN @colFechaEntr IS NOT NULL
            THEN N'ped.' + QUOTENAME(@colFechaEntr) ELSE N'CAST(NULL AS DATETIME)' END;
        SET @selTotal = CASE WHEN @colTotalPedi IS NOT NULL
            THEN N'CAST(COALESCE(ped.' + QUOTENAME(@colTotalPedi) + N',0) AS DECIMAL(18,2))'
            ELSE N'CAST(NULL AS DECIMAL(18,2))' END;
        SET @selCant = CASE WHEN @colDetCant IS NOT NULL
            THEN N'CAST(COALESCE(det.' + QUOTENAME(@colDetCant) + N',0) AS DECIMAL(18,4))'
            ELSE N'CAST(0 AS DECIMAL(18,4))' END;
        SET @selPrecio = CASE WHEN @colDetPrecio IS NOT NULL
            THEN N'CAST(det.' + QUOTENAME(@colDetPrecio) + N' AS DECIMAL(18,4))'
            ELSE N'CAST(NULL AS DECIMAL(18,4))' END;
        SET @selDto = CASE WHEN @colDetDto IS NOT NULL
            THEN N'CAST(det.' + QUOTENAME(@colDetDto) + N' AS DECIMAL(18,4))'
            ELSE N'CAST(NULL AS DECIMAL(18,4))' END;

        IF @hasGva14 = 1 AND @colCodClient IS NOT NULL
        BEGIN
            SET @joinCli  = N'LEFT JOIN ' + @bdQuoted + N'.dbo.GVA14 AS cli
                ON cli.COD_CLIENT COLLATE DATABASE_DEFAULT = ped.'
                + QUOTENAME(@colCodClient) + N' COLLATE DATABASE_DEFAULT';
            SET @selRazon = CASE WHEN @colRazon IS NOT NULL
                THEN N'CAST(cli.' + QUOTENAME(@colRazon) + N' AS NVARCHAR(200))'
                ELSE N'CAST(NULL AS NVARCHAR(200))' END;
        END
        ELSE
        BEGIN
            SET @joinCli  = N'';
            SET @selRazon = N'CAST(NULL AS NVARCHAR(200))';
        END

        -- INSERT cabecera: solo pedidos no encontrados aún
        SET @sql = N'
            INSERT INTO #cabecera (
                empresaId, empresaBd, empresaOrigen, talonPed, nroPedido,
                codClient, razonSocial, fechaPedido, fechaEntrega, totalPedido, estado)
            SELECT
                @p_empId,
                @p_empBd,
                @p_empNom,
                CAST(ped.' + QUOTENAME(@colTalon) + N' AS INT),
                LTRIM(RTRIM(CAST(ped.' + QUOTENAME(@colNroPedido) + N' AS NVARCHAR(50)))),
                ' + CASE WHEN @colCodClient IS NOT NULL
                    THEN N'CAST(ped.' + QUOTENAME(@colCodClient) + N' AS NVARCHAR(20))'
                    ELSE N'CAST(NULL AS NVARCHAR(20))' END + N',
                ' + @selRazon + N',
                ' + @selFechaPedi + N',
                ' + @selFechaEntr + N',
                ' + @selTotal + N',
                CAST(ped.' + QUOTENAME(@colEstado) + N' AS INT)
            FROM ' + @bdQuoted + N'.dbo.GVA21 AS ped
            ' + @joinCli + N'
            INNER JOIN #pedidos_input pi
                ON pi.talonPed = CAST(ped.' + QUOTENAME(@colTalon) + N' AS INT)
               AND LTRIM(RTRIM(pi.nroPedido)) = LTRIM(RTRIM(CAST(ped.'
               + QUOTENAME(@colNroPedido) + N' AS NVARCHAR(50))))
            WHERE ped.' + QUOTENAME(@colEstado) + N' <> 5
              AND NOT EXISTS (
                SELECT 1 FROM #cabecera c
                WHERE c.talonPed = CAST(ped.' + QUOTENAME(@colTalon) + N' AS INT)
                  AND LTRIM(RTRIM(c.nroPedido)) = LTRIM(RTRIM(CAST(ped.'
                  + QUOTENAME(@colNroPedido) + N' AS NVARCHAR(50))))
              );';

        EXEC sp_executesql @sql,
            N'@p_empId INT, @p_empBd NVARCHAR(260), @p_empNom NVARCHAR(200)',
            @p_empId  = @empresaId,
            @p_empBd  = @nombreBd,
            @p_empNom = @nombreEmpresa;

        -- INSERT renglones para las cabeceras recién insertadas de esta empresa
        SET @sql = N'
            INSERT INTO #renglones (talonPed, nroPedido, codArticu, cantidad, precioPedido, descuentoPedido)
            SELECT
                c.talonPed,
                c.nroPedido,
                CAST(det.' + QUOTENAME(@colDetArt) + N' AS NVARCHAR(50)),
                ' + @selCant + N',
                ' + @selPrecio + N',
                ' + @selDto + N'
            FROM #cabecera c
            INNER JOIN ' + @bdQuoted + N'.dbo.GVA03 AS det
                ON det.' + QUOTENAME(@colDetTalon) + N' = c.talonPed
               AND LTRIM(RTRIM(det.' + QUOTENAME(@colDetNro) + N')) = LTRIM(RTRIM(c.nroPedido))
            WHERE c.empresaBd = @p_empBd
              AND det.' + QUOTENAME(@colDetArt) + N' IS NOT NULL
              AND LTRIM(RTRIM(CAST(det.' + QUOTENAME(@colDetArt) + N' AS NVARCHAR(50)))) <> N''''
              AND NOT EXISTS (
                SELECT 1 FROM #renglones r
                WHERE r.talonPed = c.talonPed
                  AND LTRIM(RTRIM(r.nroPedido)) = LTRIM(RTRIM(c.nroPedido))
              );';

        EXEC sp_executesql @sql,
            N'@p_empBd NVARCHAR(260)',
            @p_empBd = @nombreBd;

        SET @i += 1;
    END

    -- ── Result sets ──────────────────────────────────────────────────────
    -- RS0: cabeceras
    SELECT
        empresaId, empresaBd, empresaOrigen, talonPed, nroPedido,
        codClient, razonSocial, fechaPedido, fechaEntrega, totalPedido, estado
    FROM #cabecera
    ORDER BY talonPed, nroPedido;

    -- RS1: renglones (con clave para correlación)
    SELECT
        talonPed, nroPedido,
        codArticu, cantidad, precioPedido, descuentoPedido
    FROM #renglones
    ORDER BY talonPed, nroPedido, codArticu;
END
