CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_FacturasElegiblesList
    @prefijo_articulo NVARCHAR(100),
    @cliente          NVARCHAR(100) = NULL,
    @fecha_desde      DATE          = NULL,
    @fecha_hasta      DATE          = NULL,
    @dictionary_db    NVARCHAR(260),
    @grupo_id         INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @prefijo_articulo IS NULL OR LTRIM(RTRIM(@prefijo_articulo)) = N''
       OR @grupo_id IS NULL OR @grupo_id <= 0
       OR @dictionary_db IS NULL OR LTRIM(RTRIM(@dictionary_db)) = N''
       OR DB_ID(@dictionary_db) IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(260)) AS empresaBd,
            CAST(NULL AS NVARCHAR(10))  AS tComp,
            CAST(NULL AS NVARCHAR(50))  AS nComp,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaEmision,
            CAST(NULL AS DECIMAL(18,2)) AS importeTotal,
            CAST(NULL AS NVARCHAR(10))  AS estado,
            CAST(NULL AS BIT)           AS configurada,
            CAST(NULL AS INT)           AS acopioId,
            CAST(NULL AS INT)           AS listaPreciosId,
            CAST(NULL AS DATETIME)      AS fechaVigencia,
            CAST(NULL AS DECIMAL(5,2))  AS descuento
        WHERE 1 = 0;
        RETURN;
    END

    -- Replica prefixPattern() del PHP
    DECLARE @prefijo_escaped NVARCHAR(200) =
        REPLACE(REPLACE(REPLACE(@prefijo_articulo, N'[', N'[[]'), N'_', N'[_]'), N'%', N'[%]');

    DECLARE @dictQuoted NVARCHAR(270) = QUOTENAME(@dictionary_db);

    CREATE TABLE #empresas (
        rn       INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
        id       INT           NOT NULL,
        nombreBd NVARCHAR(260) NOT NULL
    );

    DECLARE @colEmpPk       SYSNAME = NULL,
            @colEmpNombreBd SYSNAME = NULL,
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
        N'@o_empPk SYSNAME OUTPUT, @o_empBd SYSNAME OUTPUT, @o_empHab SYSNAME OUTPUT,
          @o_relGrupo SYSNAME OUTPUT, @o_relEmp SYSNAME OUTPUT,
          @o_hasRel BIT OUTPUT, @o_hasEmp BIT OUTPUT',
        @o_empPk = @colEmpPk OUTPUT,
        @o_empBd = @colEmpNombreBd OUTPUT,
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
            CAST(NULL AS NVARCHAR(10))  AS tComp,
            CAST(NULL AS NVARCHAR(50))  AS nComp,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaEmision,
            CAST(NULL AS DECIMAL(18,2)) AS importeTotal,
            CAST(NULL AS NVARCHAR(10))  AS estado,
            CAST(NULL AS BIT)           AS configurada,
            CAST(NULL AS INT)           AS acopioId,
            CAST(NULL AS INT)           AS listaPreciosId,
            CAST(NULL AS DATETIME)      AS fechaVigencia,
            CAST(NULL AS DECIMAL(5,2))  AS descuento
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @sqlEmpresas NVARCHAR(MAX) = N'
        INSERT INTO #empresas (id, nombreBd)
        SELECT
            emp.' + QUOTENAME(@colEmpPk) + N',
            LTRIM(RTRIM(CAST(emp.' + QUOTENAME(@colEmpNombreBd) + N' AS NVARCHAR(260))))
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
            CAST(NULL AS NVARCHAR(10))  AS tComp,
            CAST(NULL AS NVARCHAR(50))  AS nComp,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaEmision,
            CAST(NULL AS DECIMAL(18,2)) AS importeTotal,
            CAST(NULL AS NVARCHAR(10))  AS estado,
            CAST(NULL AS BIT)           AS configurada,
            CAST(NULL AS INT)           AS acopioId,
            CAST(NULL AS INT)           AS listaPreciosId,
            CAST(NULL AS DATETIME)      AS fechaVigencia,
            CAST(NULL AS DECIMAL(5,2))  AS descuento
        WHERE 1 = 0;
        RETURN;
    END

    CREATE TABLE #resultados (
        empresaBd      NVARCHAR(260)  NOT NULL,
        tComp          NVARCHAR(10)   NULL,
        nComp          NVARCHAR(50)   NULL,
        codClient      NVARCHAR(20)   NULL,
        razonSocial    NVARCHAR(200)  NULL,
        fechaEmision   DATETIME       NULL,
        importeTotal   DECIMAL(18, 2) NULL,
        estado         NVARCHAR(10)   NULL,
        configurada    BIT            NOT NULL DEFAULT (0),
        acopioId       INT            NULL,
        listaPreciosId INT            NULL,
        fechaVigencia  DATETIME       NULL,
        descuento      DECIMAL(5, 2)  NULL
    );

    DECLARE @i INT = 1,
            @max INT = (SELECT MAX(rn) FROM #empresas),
            @nombreBd NVARCHAR(260),
            @bdQuoted NVARCHAR(270),
            @objGva12 INT,
            @objGva53 INT,
            @hasGva14 BIT,
            @hasAcopio BIT,
            @hasGva10 BIT;

    DECLARE @colImporte    SYSNAME,
            @colFecha      SYSNAME,
            @colEstado     SYSNAME,
            @colRazon      SYSNAME,
            @colAcTComp    SYSNAME,
            @colAcNComp    SYSNAME,
            @colAcId       SYSNAME,
            @colAcLista    SYSNAME,
            @colAcFechaVig SYSNAME,
            @colAcDesc     SYSNAME,
            @colGva10Lista SYSNAME;

    DECLARE @sql NVARCHAR(MAX),
            @colsSql NVARCHAR(MAX),
            @joinCli NVARCHAR(MAX),
            @joinAc NVARCHAR(MAX),
            @joinLis NVARCHAR(MAX),
            @selRazon NVARCHAR(MAX),
            @selAcopioId NVARCHAR(MAX),
            @selLista NVARCHAR(MAX),
            @selFechaVig NVARCHAR(MAX),
            @selDesc NVARCHAR(MAX),
            @selConfig NVARCHAR(MAX),
            @importeExpr NVARCHAR(MAX),
            @fechaExpr NVARCHAR(MAX),
            @estadoExpr NVARCHAR(MAX),
            @whereExtra NVARCHAR(MAX);

    WHILE @i <= @max
    BEGIN
        SELECT @nombreBd = nombreBd FROM #empresas WHERE rn = @i;
        SET @bdQuoted = QUOTENAME(@nombreBd);

        SET @objGva12 = OBJECT_ID(@bdQuoted + N'.dbo.GVA12');
        SET @objGva53 = OBJECT_ID(@bdQuoted + N'.dbo.GVA53');
        IF @objGva12 IS NULL OR @objGva53 IS NULL
        BEGIN
            SET @i += 1;
            CONTINUE;
        END

        SET @hasGva14 = CASE WHEN OBJECT_ID(@bdQuoted + N'.dbo.GVA14') IS NOT NULL THEN 1 ELSE 0 END;
        SET @hasAcopio = CASE WHEN OBJECT_ID(@bdQuoted + N'.dbo.PQ_ACOPIOS_FACTURAS') IS NOT NULL THEN 1 ELSE 0 END;
        SET @hasGva10 = CASE WHEN OBJECT_ID(@bdQuoted + N'.dbo.GVA10') IS NOT NULL THEN 1 ELSE 0 END;

        SET @colImporte = NULL; SET @colFecha = NULL; SET @colEstado = NULL; SET @colRazon = NULL;
        SET @colAcTComp = NULL; SET @colAcNComp = NULL; SET @colAcId = NULL;
        SET @colAcLista = NULL; SET @colAcFechaVig = NULL; SET @colAcDesc = NULL;
        SET @colGva10Lista = NULL;
        SET @whereExtra = N'';

        SET @colsSql = N'
            SELECT
                @o_imp = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''importe_tot'' THEN COLUMN_NAME END),
                @o_fec = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''fecha_emis'' THEN COLUMN_NAME END),
                @o_est = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''estado'' THEN COLUMN_NAME END),
                @o_raz = MAX(CASE WHEN TABLE_NAME = N''GVA14'' AND LOWER(COLUMN_NAME) = N''razon_soci'' THEN COLUMN_NAME END),
                @o_act = MAX(CASE WHEN TABLE_NAME = N''PQ_ACOPIOS_FACTURAS'' AND LOWER(COLUMN_NAME) = N''t_comp'' THEN COLUMN_NAME END),
                @o_acn = MAX(CASE WHEN TABLE_NAME = N''PQ_ACOPIOS_FACTURAS'' AND LOWER(COLUMN_NAME) = N''n_comp'' THEN COLUMN_NAME END),
                @o_acid = MAX(CASE WHEN TABLE_NAME = N''PQ_ACOPIOS_FACTURAS'' AND LOWER(COLUMN_NAME) IN (N''id'', N''acopio_id'', N''id_acopio'') THEN COLUMN_NAME END),
                @o_aclista = MAX(CASE WHEN TABLE_NAME = N''PQ_ACOPIOS_FACTURAS'' AND LOWER(COLUMN_NAME) IN (N''lista_precios'', N''nro_lista'', N''lista_precios_id'') THEN COLUMN_NAME END),
                @o_acfv = MAX(CASE WHEN TABLE_NAME = N''PQ_ACOPIOS_FACTURAS'' AND LOWER(COLUMN_NAME) IN (N''fecha_vigencia'', N''fecha_vig'') THEN COLUMN_NAME END),
                @o_acdesc = MAX(CASE WHEN TABLE_NAME = N''PQ_ACOPIOS_FACTURAS'' AND LOWER(COLUMN_NAME) IN (N''descuento'', N''dto'') THEN COLUMN_NAME END),
                @o_g10 = MAX(CASE WHEN TABLE_NAME = N''GVA10'' AND LOWER(COLUMN_NAME) = N''nro_lista'' THEN COLUMN_NAME END)
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = N''dbo''
              AND TABLE_NAME IN (N''GVA12'', N''GVA14'', N''PQ_ACOPIOS_FACTURAS'', N''GVA10'');';

        EXEC sp_executesql @colsSql,
            N'@o_imp SYSNAME OUTPUT, @o_fec SYSNAME OUTPUT, @o_est SYSNAME OUTPUT, @o_raz SYSNAME OUTPUT,
              @o_act SYSNAME OUTPUT, @o_acn SYSNAME OUTPUT, @o_acid SYSNAME OUTPUT,
              @o_aclista SYSNAME OUTPUT, @o_acfv SYSNAME OUTPUT, @o_acdesc SYSNAME OUTPUT,
              @o_g10 SYSNAME OUTPUT',
            @o_imp = @colImporte OUTPUT,
            @o_fec = @colFecha OUTPUT,
            @o_est = @colEstado OUTPUT,
            @o_raz = @colRazon OUTPUT,
            @o_act = @colAcTComp OUTPUT,
            @o_acn = @colAcNComp OUTPUT,
            @o_acid = @colAcId OUTPUT,
            @o_aclista = @colAcLista OUTPUT,
            @o_acfv = @colAcFechaVig OUTPUT,
            @o_acdesc = @colAcDesc OUTPUT,
            @o_g10 = @colGva10Lista OUTPUT;

        IF @colImporte IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o_imp = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA12''
                  AND LOWER(COLUMN_NAME) = N''importe'';';
            EXEC sp_executesql @colsSql, N'@o_imp SYSNAME OUTPUT', @o_imp = @colImporte OUTPUT;
        END

        SET @importeExpr = CASE
            WHEN @colImporte IS NOT NULL
                THEN N'CAST(COALESCE(cab.' + QUOTENAME(@colImporte) + N', 0) AS DECIMAL(18,2))'
            ELSE N'CAST(0 AS DECIMAL(18,2))'
        END;
        SET @fechaExpr = CASE
            WHEN @colFecha IS NOT NULL THEN N'cab.' + QUOTENAME(@colFecha)
            ELSE N'CAST(NULL AS DATETIME)'
        END;
        SET @estadoExpr = CASE
            WHEN @colEstado IS NOT NULL
                THEN N'CAST(cab.' + QUOTENAME(@colEstado) + N' AS NVARCHAR(10))'
            ELSE N'CAST(NULL AS NVARCHAR(10))'
        END;

        IF @hasGva14 = 1
        BEGIN
            SET @joinCli = N'LEFT JOIN ' + @bdQuoted + N'.dbo.GVA14 AS cli ON cli.COD_CLIENT = cab.COD_CLIENT';
            SET @selRazon = CASE
                WHEN @colRazon IS NOT NULL
                    THEN N'CAST(cli.' + QUOTENAME(@colRazon) + N' AS NVARCHAR(200))'
                ELSE N'CAST(NULL AS NVARCHAR(200))'
            END;
        END
        ELSE
        BEGIN
            SET @joinCli = N'';
            SET @selRazon = N'CAST(NULL AS NVARCHAR(200))';
        END

        IF @hasAcopio = 1 AND @colAcTComp IS NOT NULL AND @colAcNComp IS NOT NULL
        BEGIN
            SET @joinAc = N'LEFT JOIN ' + @bdQuoted + N'.dbo.PQ_ACOPIOS_FACTURAS AS ac
                ON ac.' + QUOTENAME(@colAcTComp) + N' = cab.T_COMP
               AND ac.' + QUOTENAME(@colAcNComp) + N' = cab.N_COMP';
            SET @selConfig = N'CAST(CASE WHEN ac.' + QUOTENAME(@colAcTComp) + N' IS NOT NULL THEN 1 ELSE 0 END AS BIT)';
            SET @selAcopioId = CASE WHEN @colAcId IS NOT NULL
                THEN N'CAST(ac.' + QUOTENAME(@colAcId) + N' AS INT)' ELSE N'CAST(NULL AS INT)' END;
            SET @selLista = CASE WHEN @colAcLista IS NOT NULL
                THEN N'CAST(ac.' + QUOTENAME(@colAcLista) + N' AS INT)' ELSE N'CAST(NULL AS INT)' END;
            SET @selFechaVig = CASE WHEN @colAcFechaVig IS NOT NULL
                THEN N'ac.' + QUOTENAME(@colAcFechaVig) ELSE N'CAST(NULL AS DATETIME)' END;
            SET @selDesc = CASE WHEN @colAcDesc IS NOT NULL
                THEN N'CAST(ac.' + QUOTENAME(@colAcDesc) + N' AS DECIMAL(5,2))'
                ELSE N'CAST(NULL AS DECIMAL(5,2))' END;

            IF @hasGva10 = 1 AND @colGva10Lista IS NOT NULL AND @colAcLista IS NOT NULL
                SET @joinLis = N'LEFT JOIN ' + @bdQuoted + N'.dbo.GVA10 AS lis
                    ON lis.' + QUOTENAME(@colGva10Lista) + N' = ac.' + QUOTENAME(@colAcLista);
            ELSE
                SET @joinLis = N'';
        END
        ELSE
        BEGIN
            SET @joinAc = N'';
            SET @joinLis = N'';
            SET @selConfig = N'CAST(0 AS BIT)';
            SET @selAcopioId = N'CAST(NULL AS INT)';
            SET @selLista = N'CAST(NULL AS INT)';
            SET @selFechaVig = N'CAST(NULL AS DATETIME)';
            SET @selDesc = N'CAST(NULL AS DECIMAL(5,2))';
        END

        IF @cliente IS NOT NULL AND LTRIM(RTRIM(@cliente)) <> N''
            SET @whereExtra += N' AND cab.COD_CLIENT = @p_cliente';
        IF @fecha_desde IS NOT NULL
            SET @whereExtra += N' AND CAST((' + @fechaExpr + N') AS DATE) >= @p_fd';
        IF @fecha_hasta IS NOT NULL
            SET @whereExtra += N' AND CAST((' + @fechaExpr + N') AS DATE) <= @p_fh';

        SET @sql = N'
            INSERT INTO #resultados (
                empresaBd, tComp, nComp, codClient, razonSocial, fechaEmision,
                importeTotal, estado, configurada, acopioId, listaPreciosId, fechaVigencia, descuento)
            SELECT
                @p_empresaBd,
                CAST(cab.T_COMP AS NVARCHAR(10)),
                CAST(cab.N_COMP AS NVARCHAR(50)),
                CAST(cab.COD_CLIENT AS NVARCHAR(20)),
                ' + @selRazon + N',
                ' + @fechaExpr + N',
                ' + @importeExpr + N',
                ' + @estadoExpr + N',
                ' + @selConfig + N',
                ' + @selAcopioId + N',
                ' + @selLista + N',
                ' + @selFechaVig + N',
                ' + @selDesc + N'
            FROM ' + @bdQuoted + N'.dbo.GVA12 AS cab
            ' + @joinCli + N'
            ' + @joinAc + N'
            ' + @joinLis + N'
            WHERE cab.T_COMP = N''FAC''
              AND EXISTS (
                    SELECT 1
                    FROM ' + @bdQuoted + N'.dbo.GVA53 AS det
                    WHERE det.T_COMP = cab.T_COMP
                      AND det.N_COMP = cab.N_COMP
                      AND det.COD_ARTICU LIKE @p_prefijo + N''%''
              )
              ' + @whereExtra + N';';

        EXEC sp_executesql @sql,
            N'@p_empresaBd NVARCHAR(260), @p_prefijo NVARCHAR(200),
              @p_cliente NVARCHAR(100), @p_fd DATE, @p_fh DATE',
            @p_empresaBd = @nombreBd,
            @p_prefijo = @prefijo_escaped,
            @p_cliente = @cliente,
            @p_fd = @fecha_desde,
            @p_fh = @fecha_hasta;

        SET @i += 1;
    END

    SELECT COUNT(*) AS total_filas FROM #resultados;

    SELECT
        empresaBd, tComp, nComp, codClient, razonSocial, fechaEmision,
        importeTotal, estado, configurada, acopioId, listaPreciosId, fechaVigencia, descuento
    FROM #resultados
    ORDER BY fechaEmision DESC;
END
