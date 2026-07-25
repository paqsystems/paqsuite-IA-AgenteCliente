CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_PedidoDetalleGet
    @talon_ped     INT,
    @nro_pedido    NVARCHAR(50),
    @dictionary_db NVARCHAR(260),
    @grupo_id      INT,
    @empresa_id    INT          = NULL,
    @empresa_bd    NVARCHAR(260) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @talon_ped IS NULL OR @talon_ped <= 0
       OR @nro_pedido IS NULL OR LTRIM(RTRIM(@nro_pedido)) = N''
       OR @grupo_id IS NULL OR @grupo_id <= 0
       OR @dictionary_db IS NULL OR LTRIM(RTRIM(@dictionary_db)) = N''
       OR DB_ID(@dictionary_db) IS NULL
    BEGIN
        SELECT
            CAST(NULL AS INT)           AS empresaId,
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
        SELECT
            CAST(NULL AS NVARCHAR(50))  AS codArticu,
            CAST(NULL AS DECIMAL(18,4)) AS cantidad,
            CAST(NULL AS DECIMAL(18,4)) AS precioPedido,
            CAST(NULL AS DECIMAL(18,4)) AS descuentoPedido
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
        SELECT
            CAST(NULL AS INT)           AS empresaId,
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
        SELECT
            CAST(NULL AS NVARCHAR(50))  AS codArticu,
            CAST(NULL AS DECIMAL(18,4)) AS cantidad,
            CAST(NULL AS DECIMAL(18,4)) AS precioPedido,
            CAST(NULL AS DECIMAL(18,4)) AS descuentoPedido
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

    IF @empresa_id IS NOT NULL AND @empresa_id > 0
    BEGIN
        DELETE FROM #empresas WHERE id <> @empresa_id;
    END
    ELSE IF @empresa_bd IS NOT NULL AND LTRIM(RTRIM(@empresa_bd)) <> N''
    BEGIN
        DELETE FROM #empresas
        WHERE LOWER(LTRIM(RTRIM(nombreBd))) <> LOWER(LTRIM(RTRIM(@empresa_bd)));
    END

    IF NOT EXISTS (SELECT 1 FROM #empresas)
    BEGIN
        SELECT
            CAST(NULL AS INT)           AS empresaId,
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
        SELECT
            CAST(NULL AS NVARCHAR(50))  AS codArticu,
            CAST(NULL AS DECIMAL(18,4)) AS cantidad,
            CAST(NULL AS DECIMAL(18,4)) AS precioPedido,
            CAST(NULL AS DECIMAL(18,4)) AS descuentoPedido
        WHERE 1 = 0;
        RETURN;
    END

    CREATE TABLE #cabecera (
        empresaId     INT            NOT NULL,
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

    CREATE TABLE #renglones_pedido (
        codArticu       NVARCHAR(50)   NULL,
        cantidad        DECIMAL(18, 4) NULL,
        precioPedido    DECIMAL(18, 4) NULL,
        descuentoPedido DECIMAL(18, 4) NULL
    );

    DECLARE @i INT = 1,
            @max INT = (SELECT MAX(rn) FROM #empresas),
            @empresaId INT,
            @nombreBd NVARCHAR(260),
            @nombreEmpresa NVARCHAR(200),
            @bdQuoted NVARCHAR(270),
            @objGva21 INT,
            @objGva03 INT,
            @hasGva14 BIT,
            @found BIT = 0;

    DECLARE @colTalon     SYSNAME,
            @colNroPedido SYSNAME,
            @colCodClient SYSNAME,
            @colFechaPedi SYSNAME,
            @colFechaEntr SYSNAME,
            @colTotalPedi SYSNAME,
            @colEstado    SYSNAME,
            @colRazon     SYSNAME,
            @colDetTalon  SYSNAME,
            @colDetNro    SYSNAME,
            @colDetArt    SYSNAME,
            @colDetCant   SYSNAME,
            @colDetPrecio SYSNAME,
            @colDetDto    SYSNAME;

    DECLARE @sql NVARCHAR(MAX),
            @colsSql NVARCHAR(MAX),
            @joinCli NVARCHAR(MAX),
            @selRazon NVARCHAR(MAX),
            @selFechaPedi NVARCHAR(MAX),
            @selFechaEntr NVARCHAR(MAX),
            @selTotal NVARCHAR(MAX),
            @selCant NVARCHAR(MAX),
            @selPrecio NVARCHAR(MAX),
            @selDto NVARCHAR(MAX),
            @whereExtra NVARCHAR(MAX);

    DECLARE @o_talon INT,
            @o_nro NVARCHAR(50),
            @o_codClient NVARCHAR(20),
            @o_razonSocial NVARCHAR(200),
            @o_fechaPedido DATETIME,
            @o_fechaEntrega DATETIME,
            @o_total DECIMAL(18, 2),
            @o_estado INT,
            @rowCount INT;

    DECLARE @candCant SYSNAME,
            @candPrecio SYSNAME,
            @candDto SYSNAME;

    WHILE @i <= @max AND @found = 0
    BEGIN
        SELECT @empresaId = id, @nombreBd = nombreBd, @nombreEmpresa = nombreEmpresa
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
        SET @colDetTalon = NULL; SET @colDetNro = NULL; SET @colDetArt = NULL;
        SET @colDetCant = NULL; SET @colDetPrecio = NULL; SET @colDetDto = NULL;
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
                @o_raz = MAX(CASE WHEN TABLE_NAME = N''GVA14'' AND LOWER(COLUMN_NAME) = N''razon_soci'' THEN COLUMN_NAME END),
                @o_dt = MAX(CASE WHEN TABLE_NAME = N''GVA03'' AND LOWER(COLUMN_NAME) = N''talon_ped'' THEN COLUMN_NAME END),
                @o_dn = MAX(CASE WHEN TABLE_NAME = N''GVA03'' AND LOWER(COLUMN_NAME) = N''nro_pedido'' THEN COLUMN_NAME END),
                @o_da = MAX(CASE WHEN TABLE_NAME = N''GVA03'' AND LOWER(COLUMN_NAME) = N''cod_articu'' THEN COLUMN_NAME END)
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = N''dbo''
              AND TABLE_NAME IN (N''GVA21'', N''GVA14'', N''GVA03'');';

        EXEC sp_executesql @colsSql,
            N'@o_talon SYSNAME OUTPUT, @o_nro SYSNAME OUTPUT, @o_cli SYSNAME OUTPUT,
              @o_fp SYSNAME OUTPUT, @o_fe SYSNAME OUTPUT, @o_tot SYSNAME OUTPUT,
              @o_est SYSNAME OUTPUT, @o_raz SYSNAME OUTPUT,
              @o_dt SYSNAME OUTPUT, @o_dn SYSNAME OUTPUT, @o_da SYSNAME OUTPUT',
            @o_talon = @colTalon OUTPUT,
            @o_nro = @colNroPedido OUTPUT,
            @o_cli = @colCodClient OUTPUT,
            @o_fp = @colFechaPedi OUTPUT,
            @o_fe = @colFechaEntr OUTPUT,
            @o_tot = @colTotalPedi OUTPUT,
            @o_est = @colEstado OUTPUT,
            @o_raz = @colRazon OUTPUT,
            @o_dt = @colDetTalon OUTPUT,
            @o_dn = @colDetNro OUTPUT,
            @o_da = @colDetArt OUTPUT;

        -- Candidatos cantidad: CANT_PEDID → CANTIDAD
        SET @candCant = NULL;
        SET @colsSql = N'
            SELECT @o = COLUMN_NAME
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA03''
              AND LOWER(COLUMN_NAME) = N''cant_pedid'';';
        EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o = @candCant OUTPUT;
        IF @candCant IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA03''
                  AND LOWER(COLUMN_NAME) = N''cantidad'';';
            EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o = @candCant OUTPUT;
        END
        SET @colDetCant = @candCant;

        -- Candidatos precio: PRECIO → PRECIO_NET
        SET @candPrecio = NULL;
        SET @colsSql = N'
            SELECT @o = COLUMN_NAME
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA03''
              AND LOWER(COLUMN_NAME) = N''precio'';';
        EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o = @candPrecio OUTPUT;
        IF @candPrecio IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA03''
                  AND LOWER(COLUMN_NAME) = N''precio_net'';';
            EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o = @candPrecio OUTPUT;
        END
        SET @colDetPrecio = @candPrecio;

        -- Candidatos descuento: DESCUENTO → PORC_DTO
        SET @candDto = NULL;
        SET @colsSql = N'
            SELECT @o = COLUMN_NAME
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA03''
              AND LOWER(COLUMN_NAME) = N''descuento'';';
        EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o = @candDto OUTPUT;
        IF @candDto IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA03''
                  AND LOWER(COLUMN_NAME) = N''porc_dto'';';
            EXEC sp_executesql @colsSql, N'@o SYSNAME OUTPUT', @o = @candDto OUTPUT;
        END
        SET @colDetDto = @candDto;

        IF @colTalon IS NULL OR @colNroPedido IS NULL OR @colEstado IS NULL
           OR @colDetTalon IS NULL OR @colDetNro IS NULL OR @colDetArt IS NULL
        BEGIN
            SET @i += 1;
            CONTINUE;
        END

        SET @selFechaPedi = CASE WHEN @colFechaPedi IS NOT NULL
            THEN N'ped.' + QUOTENAME(@colFechaPedi) ELSE N'CAST(NULL AS DATETIME)' END;
        SET @selFechaEntr = CASE WHEN @colFechaEntr IS NOT NULL
            THEN N'ped.' + QUOTENAME(@colFechaEntr) ELSE N'CAST(NULL AS DATETIME)' END;
        SET @selTotal = CASE WHEN @colTotalPedi IS NOT NULL
            THEN N'CAST(COALESCE(ped.' + QUOTENAME(@colTotalPedi) + N', 0) AS DECIMAL(18,2))'
            ELSE N'CAST(NULL AS DECIMAL(18,2))' END;

        IF @hasGva14 = 1 AND @colCodClient IS NOT NULL
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

        SET @o_talon = NULL; SET @o_nro = NULL; SET @o_codClient = NULL;
        SET @o_razonSocial = NULL; SET @o_fechaPedido = NULL; SET @o_fechaEntrega = NULL;
        SET @o_total = NULL; SET @o_estado = NULL;

        SET @sql = N'
            SELECT TOP 1
                @o_talon = CAST(ped.' + QUOTENAME(@colTalon) + N' AS INT),
                @o_nro = CAST(ped.' + QUOTENAME(@colNroPedido) + N' AS NVARCHAR(50)),
                @o_codClient = ' + CASE WHEN @colCodClient IS NOT NULL
                    THEN N'CAST(ped.' + QUOTENAME(@colCodClient) + N' AS NVARCHAR(20))'
                    ELSE N'CAST(NULL AS NVARCHAR(20))' END + N',
                @o_razonSocial = ' + @selRazon + N',
                @o_fechaPedido = ' + @selFechaPedi + N',
                @o_fechaEntrega = ' + @selFechaEntr + N',
                @o_total = ' + @selTotal + N',
                @o_estado = CAST(ped.' + QUOTENAME(@colEstado) + N' AS INT)
            FROM ' + @bdQuoted + N'.dbo.GVA21 AS ped
            ' + @joinCli + N'
            WHERE ped.' + QUOTENAME(@colTalon) + N' = @p_talon
              AND LTRIM(RTRIM(ped.' + QUOTENAME(@colNroPedido) + N')) = LTRIM(RTRIM(@p_nro))
              AND ped.' + QUOTENAME(@colEstado) + N' <> 5
              ' + @whereExtra + N';';

        EXEC sp_executesql @sql,
            N'@p_talon INT, @p_nro NVARCHAR(50),
              @o_talon INT OUTPUT, @o_nro NVARCHAR(50) OUTPUT,
              @o_codClient NVARCHAR(20) OUTPUT, @o_razonSocial NVARCHAR(200) OUTPUT,
              @o_fechaPedido DATETIME OUTPUT, @o_fechaEntrega DATETIME OUTPUT,
              @o_total DECIMAL(18,2) OUTPUT, @o_estado INT OUTPUT',
            @p_talon = @talon_ped,
            @p_nro = @nro_pedido,
            @o_talon = @o_talon OUTPUT,
            @o_nro = @o_nro OUTPUT,
            @o_codClient = @o_codClient OUTPUT,
            @o_razonSocial = @o_razonSocial OUTPUT,
            @o_fechaPedido = @o_fechaPedido OUTPUT,
            @o_fechaEntrega = @o_fechaEntrega OUTPUT,
            @o_total = @o_total OUTPUT,
            @o_estado = @o_estado OUTPUT;

        SET @rowCount = @@ROWCOUNT;
        IF @rowCount = 0
        BEGIN
            SET @i += 1;
            CONTINUE;
        END

        SET @found = 1;

        INSERT INTO #cabecera (
            empresaId, empresaBd, empresaOrigen, talonPed, nroPedido, codClient,
            razonSocial, fechaPedido, fechaEntrega, totalPedido, estado)
        VALUES (
            @empresaId, @nombreBd, @nombreEmpresa, @o_talon, @o_nro, @o_codClient,
            @o_razonSocial, @o_fechaPedido, @o_fechaEntrega, @o_total, @o_estado);

        SET @selCant = CASE WHEN @colDetCant IS NOT NULL
            THEN N'CAST(COALESCE(det.' + QUOTENAME(@colDetCant) + N', 0) AS DECIMAL(18,4))'
            ELSE N'CAST(0 AS DECIMAL(18,4))' END;
        SET @selPrecio = CASE WHEN @colDetPrecio IS NOT NULL
            THEN N'CAST(det.' + QUOTENAME(@colDetPrecio) + N' AS DECIMAL(18,4))'
            ELSE N'CAST(NULL AS DECIMAL(18,4))' END;
        SET @selDto = CASE WHEN @colDetDto IS NOT NULL
            THEN N'CAST(det.' + QUOTENAME(@colDetDto) + N' AS DECIMAL(18,4))'
            ELSE N'CAST(NULL AS DECIMAL(18,4))' END;

        SET @sql = N'
            INSERT INTO #renglones_pedido (codArticu, cantidad, precioPedido, descuentoPedido)
            SELECT
                CAST(det.' + QUOTENAME(@colDetArt) + N' AS NVARCHAR(50)),
                ' + @selCant + N',
                ' + @selPrecio + N',
                ' + @selDto + N'
            FROM ' + @bdQuoted + N'.dbo.GVA03 AS det
            WHERE det.' + QUOTENAME(@colDetTalon) + N' = @p_talon
              AND LTRIM(RTRIM(det.' + QUOTENAME(@colDetNro) + N')) = LTRIM(RTRIM(@p_nro))
              AND det.' + QUOTENAME(@colDetArt) + N' IS NOT NULL
              AND LTRIM(RTRIM(CAST(det.' + QUOTENAME(@colDetArt) + N' AS NVARCHAR(50)))) <> N'''';';

        EXEC sp_executesql @sql,
            N'@p_talon INT, @p_nro NVARCHAR(50)',
            @p_talon = @talon_ped,
            @p_nro = @nro_pedido;

        BREAK;
    END

    SELECT
        empresaId, empresaBd, empresaOrigen, talonPed, nroPedido, codClient,
        razonSocial, fechaPedido, fechaEntrega, totalPedido, estado
    FROM #cabecera;

    SELECT
        codArticu, cantidad, precioPedido, descuentoPedido
    FROM #renglones_pedido
    ORDER BY codArticu;
END
