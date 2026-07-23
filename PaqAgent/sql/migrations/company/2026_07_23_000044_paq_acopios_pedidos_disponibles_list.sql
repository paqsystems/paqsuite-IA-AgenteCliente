CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_PedidosDisponiblesList
    @cliente       NVARCHAR(100) = NULL,
    @fecha_desde   DATE          = NULL,
    @fecha_hasta   DATE          = NULL,
    @dictionary_db NVARCHAR(260),
    @grupo_id      INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @grupo_id IS NULL OR @grupo_id <= 0
       OR @dictionary_db IS NULL OR LTRIM(RTRIM(@dictionary_db)) = N''
       OR DB_ID(@dictionary_db) IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(260)) AS empresaBd,
            CAST(NULL AS NVARCHAR(200)) AS empresaOrigen,
            CAST(NULL AS INT)           AS talonPed,
            CAST(NULL AS NVARCHAR(50))  AS nroPedido,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaPedido,
            CAST(NULL AS DATETIME)      AS fechaEntrega,
            CAST(NULL AS DECIMAL(18,2)) AS totalPedido,
            CAST(NULL AS INT)           AS estado
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @dictQuoted NVARCHAR(270) = QUOTENAME(@dictionary_db);

    CREATE TABLE #empresas (
        rn            INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
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
            @o_empPk = MAX(CASE WHEN c.TABLE_NAME = N''pq_empresa''
                AND LOWER(c.COLUMN_NAME) IN (N''idempresa'', N''id_empresa'') THEN c.COLUMN_NAME END),
            @o_empBd = MAX(CASE WHEN c.TABLE_NAME = N''pq_empresa''
                AND LOWER(c.COLUMN_NAME) IN (N''nombrebd'', N''nombre_bd'') THEN c.COLUMN_NAME END),
            @o_empNom = MAX(CASE WHEN c.TABLE_NAME = N''pq_empresa''
                AND LOWER(c.COLUMN_NAME) IN (N''nombreempresa'', N''nombre_empresa'') THEN c.COLUMN_NAME END),
            @o_empHab = MAX(CASE WHEN c.TABLE_NAME = N''pq_empresa''
                AND LOWER(c.COLUMN_NAME) = N''habilita'' THEN c.COLUMN_NAME END),
            @o_relGrupo = MAX(CASE WHEN c.TABLE_NAME = N''pq_grupo_empresario_empresas''
                AND LOWER(c.COLUMN_NAME) IN (N''id_grupo'', N''idgrupo'') THEN c.COLUMN_NAME END),
            @o_relEmp = MAX(CASE WHEN c.TABLE_NAME = N''pq_grupo_empresario_empresas''
                AND LOWER(c.COLUMN_NAME) IN (N''id_empresa'', N''idempresa'') THEN c.COLUMN_NAME END),
            @o_hasRel = MAX(CASE WHEN t.TABLE_NAME = N''pq_grupo_empresario_empresas'' THEN 1 ELSE 0 END),
            @o_hasEmp = MAX(CASE WHEN t.TABLE_NAME = N''pq_empresa'' THEN 1 ELSE 0 END)
        FROM ' + @dictQuoted + N'.INFORMATION_SCHEMA.TABLES t
        LEFT JOIN ' + @dictQuoted + N'.INFORMATION_SCHEMA.COLUMNS c
            ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME
        WHERE t.TABLE_SCHEMA = N''dbo''
          AND t.TABLE_NAME IN (N''pq_empresa'', N''pq_grupo_empresario_empresas'');';

    EXEC sp_executesql @detectSql,
        N'@o_empPk SYSNAME OUTPUT, @o_empBd SYSNAME OUTPUT, @o_empNom SYSNAME OUTPUT, @o_empHab SYSNAME OUTPUT,
          @o_relGrupo SYSNAME OUTPUT, @o_relEmp SYSNAME OUTPUT,
          @o_hasRel BIT OUTPUT, @o_hasEmp BIT OUTPUT',
        @o_empPk = @colEmpPk OUTPUT,
        @o_empBd = @colEmpNombreBd OUTPUT,
        @o_empNom = @colEmpNombre OUTPUT,
        @o_empHab = @colEmpHabilita OUTPUT,
        @o_relGrupo = @colRelGrupo OUTPUT,
        @o_relEmp = @colRelEmpresa OUTPUT,
        @o_hasRel = @hasRel OUTPUT,
        @o_hasEmp = @hasEmp OUTPUT;

    IF @hasRel = 0 OR @hasEmp = 0
       OR @colEmpPk IS NULL OR @colEmpNombreBd IS NULL
       OR @colRelGrupo IS NULL OR @colRelEmpresa IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(260)) AS empresaBd,
            CAST(NULL AS NVARCHAR(200)) AS empresaOrigen,
            CAST(NULL AS INT)           AS talonPed,
            CAST(NULL AS NVARCHAR(50))  AS nroPedido,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaPedido,
            CAST(NULL AS DATETIME)      AS fechaEntrega,
            CAST(NULL AS DECIMAL(18,2)) AS totalPedido,
            CAST(NULL AS INT)           AS estado
        WHERE 1 = 0;
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
          AND LTRIM(RTRIM(CAST(emp.' + QUOTENAME(@colEmpNombreBd) + N' AS NVARCHAR(260)))) <> N''''
          ' + CASE WHEN @colEmpHabilita IS NOT NULL
                THEN N'AND emp.' + QUOTENAME(@colEmpHabilita) + N' = 1'
                ELSE N'' END + N';';

    EXEC sp_executesql @sqlEmpresas, N'@p_grupo INT', @p_grupo = @grupo_id;

    IF NOT EXISTS (SELECT 1 FROM #empresas)
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(260)) AS empresaBd,
            CAST(NULL AS NVARCHAR(200)) AS empresaOrigen,
            CAST(NULL AS INT)           AS talonPed,
            CAST(NULL AS NVARCHAR(50))  AS nroPedido,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaPedido,
            CAST(NULL AS DATETIME)      AS fechaEntrega,
            CAST(NULL AS DECIMAL(18,2)) AS totalPedido,
            CAST(NULL AS INT)           AS estado
        WHERE 1 = 0;
        RETURN;
    END

    -- Columnas de tablas company (sin calificador de BD)
    DECLARE @hasApPedidos BIT = CASE WHEN OBJECT_ID(N'dbo.PQ_ACOPIOS_PEDIDOS') IS NOT NULL THEN 1 ELSE 0 END,
            @hasApFacturas BIT = CASE WHEN OBJECT_ID(N'dbo.PQ_ACOPIOS_FACTURAS') IS NOT NULL THEN 1 ELSE 0 END,
            @colApTalon SYSNAME = NULL,
            @colApNro   SYSNAME = NULL,
            @colAfClient SYSNAME = NULL,
            @colAfEstado SYSNAME = NULL;

    SELECT
        @colApTalon = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) IN (N'talon_ped', N'talonped') THEN COLUMN_NAME END),
        @colApNro = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) IN (N'nro_pedido', N'nropedido') THEN COLUMN_NAME END),
        @colAfClient = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'cod_client', N'codclient') THEN COLUMN_NAME END),
        @colAfEstado = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'estado' THEN COLUMN_NAME END)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = N'dbo'
      AND TABLE_NAME IN (N'PQ_ACOPIOS_PEDIDOS', N'PQ_ACOPIOS_FACTURAS');

    IF @hasApPedidos = 0 OR @colApTalon IS NULL OR @colApNro IS NULL
        SET @hasApPedidos = 0;
    IF @hasApFacturas = 0 OR @colAfClient IS NULL OR @colAfEstado IS NULL
        SET @hasApFacturas = 0;

    CREATE TABLE #resultados (
        empresaBd     NVARCHAR(260)  NOT NULL,
        empresaOrigen NVARCHAR(200)  NULL,
        talonPed      INT            NULL,
        nroPedido     NVARCHAR(50)   NULL,
        codClient     NVARCHAR(20)   NULL,
        razonSocial   NVARCHAR(200)  NULL,
        fechaPedido   DATETIME       NULL,
        fechaEntrega  DATETIME       NULL,
        totalPedido   DECIMAL(18, 2) NULL,
        estado        INT            NULL
    );

    DECLARE @i INT = 1,
            @max INT = (SELECT MAX(rn) FROM #empresas),
            @nombreBd NVARCHAR(260),
            @nombreEmpresa NVARCHAR(200),
            @bdQuoted NVARCHAR(270),
            @objGva21 INT,
            @objGva03 INT,
            @hasGva14 BIT;

    DECLARE @colTalon     SYSNAME,
            @colNroPedido SYSNAME,
            @colCodClient SYSNAME,
            @colFechaPedi SYSNAME,
            @colFechaEntr SYSNAME,
            @colTotalPedi SYSNAME,
            @colEstado    SYSNAME,
            @colRazon     SYSNAME;

    DECLARE @sql NVARCHAR(MAX),
            @colsSql NVARCHAR(MAX),
            @joinCli NVARCHAR(MAX),
            @selRazon NVARCHAR(MAX),
            @selTalon NVARCHAR(MAX),
            @selNro NVARCHAR(MAX),
            @selClient NVARCHAR(MAX),
            @selFechaPedi NVARCHAR(MAX),
            @selFechaEntr NVARCHAR(MAX),
            @selTotal NVARCHAR(MAX),
            @selEstado NVARCHAR(MAX),
            @whereBase NVARCHAR(MAX),
            @whereExtra NVARCHAR(MAX),
            @fechaExpr NVARCHAR(MAX);

    WHILE @i <= @max
    BEGIN
        SELECT @nombreBd = nombreBd, @nombreEmpresa = nombreEmpresa
        FROM #empresas WHERE rn = @i;
        SET @bdQuoted = QUOTENAME(@nombreBd);

        SET @objGva21 = OBJECT_ID(@bdQuoted + N'.dbo.GVA21');
        SET @objGva03 = OBJECT_ID(@bdQuoted + N'.dbo.GVA03');
        IF @objGva21 IS NULL OR @objGva03 IS NULL
        BEGIN
            SET @i += 1;
            CONTINUE;
        END

        SET @hasGva14 = CASE WHEN OBJECT_ID(@bdQuoted + N'.dbo.GVA14') IS NOT NULL THEN 1 ELSE 0 END;

        SET @colTalon = NULL; SET @colNroPedido = NULL; SET @colCodClient = NULL;
        SET @colFechaPedi = NULL; SET @colFechaEntr = NULL; SET @colTotalPedi = NULL;
        SET @colEstado = NULL; SET @colRazon = NULL;
        SET @whereExtra = N'';

        SET @colsSql = N'
            SELECT
                @o_talon = MAX(CASE WHEN TABLE_NAME = N''GVA21'' AND LOWER(COLUMN_NAME) = N''talon_ped'' THEN COLUMN_NAME END),
                @o_nro = MAX(CASE WHEN TABLE_NAME = N''GVA21'' AND LOWER(COLUMN_NAME) = N''nro_pedido'' THEN COLUMN_NAME END),
                @o_cli = MAX(CASE WHEN TABLE_NAME = N''GVA21'' AND LOWER(COLUMN_NAME) = N''cod_client'' THEN COLUMN_NAME END),
                @o_fp = MAX(CASE WHEN TABLE_NAME = N''GVA21'' AND LOWER(COLUMN_NAME) = N''fecha_pedi'' THEN COLUMN_NAME END),
                @o_fe = MAX(CASE WHEN TABLE_NAME = N''GVA21'' AND LOWER(COLUMN_NAME) = N''fecha_entr'' THEN COLUMN_NAME END),
                @o_tot = MAX(CASE WHEN TABLE_NAME = N''GVA21'' AND LOWER(COLUMN_NAME) = N''total_pedi'' THEN COLUMN_NAME END),
                @o_est = MAX(CASE WHEN TABLE_NAME = N''GVA21'' AND LOWER(COLUMN_NAME) = N''estado'' THEN COLUMN_NAME END),
                @o_raz = MAX(CASE WHEN TABLE_NAME = N''GVA14'' AND LOWER(COLUMN_NAME) = N''razon_soci'' THEN COLUMN_NAME END)
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = N''dbo''
              AND TABLE_NAME IN (N''GVA21'', N''GVA14'');';

        EXEC sp_executesql @colsSql,
            N'@o_talon SYSNAME OUTPUT, @o_nro SYSNAME OUTPUT, @o_cli SYSNAME OUTPUT,
              @o_fp SYSNAME OUTPUT, @o_fe SYSNAME OUTPUT, @o_tot SYSNAME OUTPUT,
              @o_est SYSNAME OUTPUT, @o_raz SYSNAME OUTPUT',
            @o_talon = @colTalon OUTPUT,
            @o_nro = @colNroPedido OUTPUT,
            @o_cli = @colCodClient OUTPUT,
            @o_fp = @colFechaPedi OUTPUT,
            @o_fe = @colFechaEntr OUTPUT,
            @o_tot = @colTotalPedi OUTPUT,
            @o_est = @colEstado OUTPUT,
            @o_raz = @colRazon OUTPUT;

        IF @colTalon IS NULL OR @colNroPedido IS NULL OR @colCodClient IS NULL OR @colEstado IS NULL
        BEGIN
            SET @i += 1;
            CONTINUE;
        END

        SET @selTalon = N'CAST(ped.' + QUOTENAME(@colTalon) + N' AS INT)';
        SET @selNro = N'CAST(ped.' + QUOTENAME(@colNroPedido) + N' AS NVARCHAR(50))';
        SET @selClient = N'CAST(ped.' + QUOTENAME(@colCodClient) + N' AS NVARCHAR(20))';
        SET @selFechaPedi = CASE WHEN @colFechaPedi IS NOT NULL
            THEN N'ped.' + QUOTENAME(@colFechaPedi) ELSE N'CAST(NULL AS DATETIME)' END;
        SET @selFechaEntr = CASE WHEN @colFechaEntr IS NOT NULL
            THEN N'ped.' + QUOTENAME(@colFechaEntr) ELSE N'CAST(NULL AS DATETIME)' END;
        SET @selTotal = CASE WHEN @colTotalPedi IS NOT NULL
            THEN N'CAST(COALESCE(ped.' + QUOTENAME(@colTotalPedi) + N', 0) AS DECIMAL(18,2))'
            ELSE N'CAST(NULL AS DECIMAL(18,2))' END;
        SET @selEstado = N'CAST(ped.' + QUOTENAME(@colEstado) + N' AS INT)';
        SET @fechaExpr = @selFechaPedi;

        IF @hasGva14 = 1
        BEGIN
            SET @joinCli = N'LEFT JOIN ' + @bdQuoted + N'.dbo.GVA14 AS cli
                ON cli.COD_CLIENT = ped.' + QUOTENAME(@colCodClient);
            SET @selRazon = CASE WHEN @colRazon IS NOT NULL
                THEN N'CAST(cli.' + QUOTENAME(@colRazon) + N' AS NVARCHAR(200))'
                ELSE N'CAST(NULL AS NVARCHAR(200))' END;
        END
        ELSE
        BEGIN
            SET @joinCli = N'';
            SET @selRazon = N'CAST(NULL AS NVARCHAR(200))';
        END

        -- Exclusiones fijas + subqueries contra company
        SET @whereBase = N'ped.' + QUOTENAME(@colEstado) + N' <> 5';

        IF @hasApPedidos = 1
            SET @whereBase += N'
              AND NOT EXISTS (
                    SELECT 1 FROM dbo.PQ_ACOPIOS_PEDIDOS AS ap
                    WHERE ap.' + QUOTENAME(@colApTalon) + N' = ped.' + QUOTENAME(@colTalon) + N'
                      AND ap.' + QUOTENAME(@colApNro) + N' = ped.' + QUOTENAME(@colNroPedido) + N'
              )';

        IF @hasApFacturas = 1
            SET @whereBase += N'
              AND ped.' + QUOTENAME(@colCodClient) + N' IN (
                    SELECT DISTINCT af.' + QUOTENAME(@colAfClient) + N'
                    FROM dbo.PQ_ACOPIOS_FACTURAS AS af
                    WHERE af.' + QUOTENAME(@colAfEstado) + N' = 0
              )';

        IF @cliente IS NOT NULL AND LTRIM(RTRIM(@cliente)) <> N''
            SET @whereExtra += N' AND ped.' + QUOTENAME(@colCodClient) + N' = @p_cliente';
        IF @fecha_desde IS NOT NULL
            SET @whereExtra += N' AND CAST((' + @fechaExpr + N') AS DATE) >= @p_fd';
        IF @fecha_hasta IS NOT NULL
            SET @whereExtra += N' AND CAST((' + @fechaExpr + N') AS DATE) <= @p_fh';

        SET @sql = N'
            INSERT INTO #resultados (
                empresaBd, empresaOrigen, talonPed, nroPedido, codClient, razonSocial,
                fechaPedido, fechaEntrega, totalPedido, estado)
            SELECT
                @p_empresaBd,
                @p_empresaOrigen,
                ' + @selTalon + N',
                ' + @selNro + N',
                ' + @selClient + N',
                ' + @selRazon + N',
                ' + @selFechaPedi + N',
                ' + @selFechaEntr + N',
                ' + @selTotal + N',
                ' + @selEstado + N'
            FROM ' + @bdQuoted + N'.dbo.GVA21 AS ped
            ' + @joinCli + N'
            WHERE ' + @whereBase + N'
              ' + @whereExtra + N';';

        EXEC sp_executesql @sql,
            N'@p_empresaBd NVARCHAR(260), @p_empresaOrigen NVARCHAR(200),
              @p_cliente NVARCHAR(100), @p_fd DATE, @p_fh DATE',
            @p_empresaBd = @nombreBd,
            @p_empresaOrigen = @nombreEmpresa,
            @p_cliente = @cliente,
            @p_fd = @fecha_desde,
            @p_fh = @fecha_hasta;

        SET @i += 1;
    END

    SELECT COUNT(*) AS total_filas FROM #resultados;

    SELECT
        empresaBd, empresaOrigen, talonPed, nroPedido, codClient, razonSocial,
        fechaPedido, fechaEntrega, totalPedido, estado
    FROM #resultados
    ORDER BY fechaPedido DESC;
END
