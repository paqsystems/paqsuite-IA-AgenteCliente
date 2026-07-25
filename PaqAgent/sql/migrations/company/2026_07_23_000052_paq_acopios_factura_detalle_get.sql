CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_FacturaDetalleGet
    @t_comp           NVARCHAR(10),
    @n_comp           NVARCHAR(50),
    @prefijo_articulo NVARCHAR(100),
    @dictionary_db    NVARCHAR(260),
    @grupo_id         INT,
    @empresa_bd       NVARCHAR(260) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @t_comp IS NULL OR LTRIM(RTRIM(@t_comp)) = N''
       OR @n_comp IS NULL OR LTRIM(RTRIM(@n_comp)) = N''
       OR @grupo_id IS NULL OR @grupo_id <= 0
       OR @dictionary_db IS NULL OR LTRIM(RTRIM(@dictionary_db)) = N''
       OR DB_ID(@dictionary_db) IS NULL
    BEGIN
        SELECT
            CAST(NULL AS NVARCHAR(260)) AS empresaBd,
            CAST(NULL AS NVARCHAR(200)) AS empresaOrigen,
            CAST(NULL AS NVARCHAR(10))  AS tComp,
            CAST(NULL AS NVARCHAR(50))  AS nComp,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaEmision,
            CAST(NULL AS DECIMAL(18,2)) AS importeGravado,
            CAST(NULL AS DECIMAL(18,2)) AS importeExento,
            CAST(NULL AS DECIMAL(18,2)) AS importeImpuestos,
            CAST(NULL AS DECIMAL(18,2)) AS importeTotal,
            CAST(NULL AS NVARCHAR(10))  AS estado
        WHERE 1 = 0;
        SELECT
            CAST(NULL AS NVARCHAR(50))  AS codArticu,
            CAST(NULL AS DECIMAL(18,4)) AS cantidad,
            CAST(NULL AS DECIMAL(18,4)) AS precioNeto,
            CAST(NULL AS DECIMAL(18,2)) AS importeNeto,
            CAST(NULL AS DECIMAL(18,4)) AS descuento,
            CAST(NULL AS DECIMAL(18,4)) AS porcIva
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @prefijo_escaped NVARCHAR(200) =
        REPLACE(REPLACE(REPLACE(ISNULL(@prefijo_articulo, N''), N'[', N'[[]'), N'_', N'[_]'), N'%', N'[%]');

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
            CAST(NULL AS NVARCHAR(260)) AS empresaBd,
            CAST(NULL AS NVARCHAR(200)) AS empresaOrigen,
            CAST(NULL AS NVARCHAR(10))  AS tComp,
            CAST(NULL AS NVARCHAR(50))  AS nComp,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaEmision,
            CAST(NULL AS DECIMAL(18,2)) AS importeGravado,
            CAST(NULL AS DECIMAL(18,2)) AS importeExento,
            CAST(NULL AS DECIMAL(18,2)) AS importeImpuestos,
            CAST(NULL AS DECIMAL(18,2)) AS importeTotal,
            CAST(NULL AS NVARCHAR(10))  AS estado
        WHERE 1 = 0;
        SELECT
            CAST(NULL AS NVARCHAR(50))  AS codArticu,
            CAST(NULL AS DECIMAL(18,4)) AS cantidad,
            CAST(NULL AS DECIMAL(18,4)) AS precioNeto,
            CAST(NULL AS DECIMAL(18,2)) AS importeNeto,
            CAST(NULL AS DECIMAL(18,4)) AS descuento,
            CAST(NULL AS DECIMAL(18,4)) AS porcIva
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

    IF @empresa_bd IS NOT NULL AND LTRIM(RTRIM(@empresa_bd)) <> N''
    BEGIN
        DELETE FROM #empresas
        WHERE LOWER(LTRIM(RTRIM(nombreBd))) <> LOWER(LTRIM(RTRIM(@empresa_bd)));
    END

    IF NOT EXISTS (SELECT 1 FROM #empresas)
    BEGIN
        SELECT
            CAST(NULL AS NVARCHAR(260)) AS empresaBd,
            CAST(NULL AS NVARCHAR(200)) AS empresaOrigen,
            CAST(NULL AS NVARCHAR(10))  AS tComp,
            CAST(NULL AS NVARCHAR(50))  AS nComp,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaEmision,
            CAST(NULL AS DECIMAL(18,2)) AS importeGravado,
            CAST(NULL AS DECIMAL(18,2)) AS importeExento,
            CAST(NULL AS DECIMAL(18,2)) AS importeImpuestos,
            CAST(NULL AS DECIMAL(18,2)) AS importeTotal,
            CAST(NULL AS NVARCHAR(10))  AS estado
        WHERE 1 = 0;
        SELECT
            CAST(NULL AS NVARCHAR(50))  AS codArticu,
            CAST(NULL AS DECIMAL(18,4)) AS cantidad,
            CAST(NULL AS DECIMAL(18,4)) AS precioNeto,
            CAST(NULL AS DECIMAL(18,2)) AS importeNeto,
            CAST(NULL AS DECIMAL(18,4)) AS descuento,
            CAST(NULL AS DECIMAL(18,4)) AS porcIva
        WHERE 1 = 0;
        RETURN;
    END

    CREATE TABLE #cabecera (
        empresaBd         NVARCHAR(260)  NOT NULL,
        empresaOrigen     NVARCHAR(200)  NULL,
        tComp             NVARCHAR(10)   NULL,
        nComp             NVARCHAR(50)   NULL,
        codClient         NVARCHAR(20)   NULL,
        razonSocial       NVARCHAR(200)  NULL,
        fechaEmision      DATETIME       NULL,
        importeGravado    DECIMAL(18, 2) NULL,
        importeExento     DECIMAL(18, 2) NULL,
        importeImpuestos  DECIMAL(18, 2) NULL,
        importeTotal      DECIMAL(18, 2) NULL,
        estado            NVARCHAR(10)   NULL
    );

    CREATE TABLE #renglones (
        codArticu   NVARCHAR(50)   NULL,
        cantidad    DECIMAL(18, 4) NULL,
        precioNeto  DECIMAL(18, 4) NULL,
        importeNeto DECIMAL(18, 2) NULL,
        descuento   DECIMAL(18, 4) NULL,
        porcIva     DECIMAL(18, 4) NULL
    );

    DECLARE @i INT = 1,
            @max INT = (SELECT MAX(rn) FROM #empresas),
            @nombreBd NVARCHAR(260),
            @nombreEmpresa NVARCHAR(200),
            @bdQuoted NVARCHAR(270),
            @objGva12 INT,
            @objGva53 INT,
            @hasGva14 BIT,
            @found BIT = 0;

    DECLARE @colTComp     SYSNAME,
            @colNComp     SYSNAME,
            @colCodClient SYSNAME,
            @colFecha     SYSNAME,
            @colImporte   SYSNAME,
            @colImpGr     SYSNAME,
            @colImpEx     SYSNAME,
            @colImpIv     SYSNAME,
            @colEstado    SYSNAME,
            @colRazon     SYSNAME,
            @colDetTComp  SYSNAME,
            @colDetNComp  SYSNAME,
            @colDetArt    SYSNAME,
            @colDetCant   SYSNAME,
            @colDetPrecio SYSNAME,
            @colDetImpNet SYSNAME,
            @colDetDto    SYSNAME,
            @colDetIva    SYSNAME;

    DECLARE @sql NVARCHAR(MAX),
            @colsSql NVARCHAR(MAX),
            @joinCli NVARCHAR(MAX),
            @selRazon NVARCHAR(MAX),
            @selFecha NVARCHAR(MAX),
            @selImpTot NVARCHAR(MAX),
            @selImpGr NVARCHAR(MAX),
            @selImpEx NVARCHAR(MAX),
            @selImpIv NVARCHAR(MAX),
            @selEstado NVARCHAR(MAX),
            @selCant NVARCHAR(MAX),
            @selPrecio NVARCHAR(MAX),
            @selImpNet NVARCHAR(MAX),
            @selDto NVARCHAR(MAX),
            @selIva NVARCHAR(MAX),
            @whereExtra NVARCHAR(MAX);

    DECLARE @o_tComp NVARCHAR(10),
            @o_nComp NVARCHAR(50),
            @o_codClient NVARCHAR(20),
            @o_razonSocial NVARCHAR(200),
            @o_fechaEmision DATETIME,
            @o_impGr DECIMAL(18, 2),
            @o_impEx DECIMAL(18, 2),
            @o_impIv DECIMAL(18, 2),
            @o_impTot DECIMAL(18, 2),
            @o_estado NVARCHAR(10),
            @rowCount INT;

    DECLARE @prefGr SYSNAME,
            @prefEx SYSNAME,
            @prefIv SYSNAME,
            @prefDp SYSNAME,
            @prefDi SYSNAME,
            @prefDd SYSNAME,
            @prefDv SYSNAME;

    WHILE @i <= @max AND @found = 0
    BEGIN
        SELECT @nombreBd = nombreBd, @nombreEmpresa = nombreEmpresa
        FROM #empresas WHERE rn = @i;
        SET @bdQuoted = QUOTENAME(@nombreBd);

        SET @objGva12 = OBJECT_ID(@bdQuoted + N'.dbo.GVA12');
        SET @objGva53 = OBJECT_ID(@bdQuoted + N'.dbo.GVA53');
        IF @objGva12 IS NULL OR @objGva53 IS NULL
        BEGIN
            SET @i += 1;
            CONTINUE;
        END

        SET @hasGva14 = CASE WHEN OBJECT_ID(@bdQuoted + N'.dbo.GVA14') IS NOT NULL THEN 1 ELSE 0 END;

        SET @colTComp = NULL; SET @colNComp = NULL; SET @colCodClient = NULL;
        SET @colFecha = NULL; SET @colImporte = NULL; SET @colImpGr = NULL;
        SET @colImpEx = NULL; SET @colImpIv = NULL; SET @colEstado = NULL; SET @colRazon = NULL;
        SET @colDetTComp = NULL; SET @colDetNComp = NULL; SET @colDetArt = NULL;
        SET @colDetCant = NULL; SET @colDetPrecio = NULL; SET @colDetImpNet = NULL;
        SET @colDetDto = NULL; SET @colDetIva = NULL;
        SET @whereExtra = N'';

        SET @colsSql = N'
            SELECT
                @o_t = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''t_comp'' THEN COLUMN_NAME END),
                @o_n = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''n_comp'' THEN COLUMN_NAME END),
                @o_cli = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''cod_client'' THEN COLUMN_NAME END),
                @o_fec = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''fecha_emis'' THEN COLUMN_NAME END),
                @o_imp = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''importe_tot'' THEN COLUMN_NAME END),
                @o_gr = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) IN (N''importe_gr'', N''importe_gravado'') THEN COLUMN_NAME END),
                @o_ex = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) IN (N''importe_ex'', N''importe_exento'') THEN COLUMN_NAME END),
                @o_iv = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) IN (N''importe_iv'', N''importe_impuestos'') THEN COLUMN_NAME END),
                @o_est = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''estado'' THEN COLUMN_NAME END),
                @o_raz = MAX(CASE WHEN TABLE_NAME = N''GVA14'' AND LOWER(COLUMN_NAME) = N''razon_soci'' THEN COLUMN_NAME END),
                @o_dt = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''t_comp'' THEN COLUMN_NAME END),
                @o_dn = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''n_comp'' THEN COLUMN_NAME END),
                @o_da = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''cod_articu'' THEN COLUMN_NAME END),
                @o_dc = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''cantidad'' THEN COLUMN_NAME END),
                @o_dp = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) IN (N''precio_net'', N''precio_neto'') THEN COLUMN_NAME END),
                @o_di = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''imp_neto_p'' THEN COLUMN_NAME END),
                @o_dd = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''porc_dto'' THEN COLUMN_NAME END),
                @o_dv = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''porc_iva'' THEN COLUMN_NAME END)
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = N''dbo''
              AND TABLE_NAME IN (N''GVA12'', N''GVA14'', N''GVA53'');';

        EXEC sp_executesql @colsSql,
            N'@o_t SYSNAME OUTPUT, @o_n SYSNAME OUTPUT, @o_cli SYSNAME OUTPUT, @o_fec SYSNAME OUTPUT,
              @o_imp SYSNAME OUTPUT, @o_gr SYSNAME OUTPUT, @o_ex SYSNAME OUTPUT, @o_iv SYSNAME OUTPUT,
              @o_est SYSNAME OUTPUT, @o_raz SYSNAME OUTPUT,
              @o_dt SYSNAME OUTPUT, @o_dn SYSNAME OUTPUT, @o_da SYSNAME OUTPUT, @o_dc SYSNAME OUTPUT,
              @o_dp SYSNAME OUTPUT, @o_di SYSNAME OUTPUT, @o_dd SYSNAME OUTPUT, @o_dv SYSNAME OUTPUT',
            @o_t = @colTComp OUTPUT,
            @o_n = @colNComp OUTPUT,
            @o_cli = @colCodClient OUTPUT,
            @o_fec = @colFecha OUTPUT,
            @o_imp = @colImporte OUTPUT,
            @o_gr = @colImpGr OUTPUT,
            @o_ex = @colImpEx OUTPUT,
            @o_iv = @colImpIv OUTPUT,
            @o_est = @colEstado OUTPUT,
            @o_raz = @colRazon OUTPUT,
            @o_dt = @colDetTComp OUTPUT,
            @o_dn = @colDetNComp OUTPUT,
            @o_da = @colDetArt OUTPUT,
            @o_dc = @colDetCant OUTPUT,
            @o_dp = @colDetPrecio OUTPUT,
            @o_di = @colDetImpNet OUTPUT,
            @o_dd = @colDetDto OUTPUT,
            @o_dv = @colDetIva OUTPUT;

        -- Prefer short Tango names when both aliases exist (importe_gr over importe_gravado, etc.)
        SET @prefGr = NULL; SET @prefEx = NULL; SET @prefIv = NULL;
        SET @prefDp = NULL; SET @prefDi = NULL; SET @prefDd = NULL; SET @prefDv = NULL;

        SET @colsSql = N'
            SELECT
                @o_gr = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''importe_gr'' THEN COLUMN_NAME END),
                @o_ex = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''importe_ex'' THEN COLUMN_NAME END),
                @o_iv = MAX(CASE WHEN TABLE_NAME = N''GVA12'' AND LOWER(COLUMN_NAME) = N''importe_iv'' THEN COLUMN_NAME END),
                @o_dp = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''precio_net'' THEN COLUMN_NAME END),
                @o_di = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''imp_neto_p'' THEN COLUMN_NAME END),
                @o_dd = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''porc_dto'' THEN COLUMN_NAME END),
                @o_dv = MAX(CASE WHEN TABLE_NAME = N''GVA53'' AND LOWER(COLUMN_NAME) = N''porc_iva'' THEN COLUMN_NAME END)
            FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = N''dbo''
              AND TABLE_NAME IN (N''GVA12'', N''GVA53'');';

        EXEC sp_executesql @colsSql,
            N'@o_gr SYSNAME OUTPUT, @o_ex SYSNAME OUTPUT, @o_iv SYSNAME OUTPUT,
              @o_dp SYSNAME OUTPUT, @o_di SYSNAME OUTPUT, @o_dd SYSNAME OUTPUT, @o_dv SYSNAME OUTPUT',
            @o_gr = @prefGr OUTPUT,
            @o_ex = @prefEx OUTPUT,
            @o_iv = @prefIv OUTPUT,
            @o_dp = @prefDp OUTPUT,
            @o_di = @prefDi OUTPUT,
            @o_dd = @prefDd OUTPUT,
            @o_dv = @prefDv OUTPUT;

        IF @prefGr IS NOT NULL SET @colImpGr = @prefGr;
        IF @prefEx IS NOT NULL SET @colImpEx = @prefEx;
        IF @prefIv IS NOT NULL SET @colImpIv = @prefIv;
        IF @prefDp IS NOT NULL SET @colDetPrecio = @prefDp;
        IF @prefDi IS NOT NULL SET @colDetImpNet = @prefDi;
        IF @prefDd IS NOT NULL SET @colDetDto = @prefDd;
        IF @prefDv IS NOT NULL SET @colDetIva = @prefDv;

        IF @colDetPrecio IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o_dp = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA53''
                  AND LOWER(COLUMN_NAME) = N''precio_neto'';';
            EXEC sp_executesql @colsSql, N'@o_dp SYSNAME OUTPUT', @o_dp = @colDetPrecio OUTPUT;
        END

        IF @colImpGr IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o_gr = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA12''
                  AND LOWER(COLUMN_NAME) = N''importe_gravado'';';
            EXEC sp_executesql @colsSql, N'@o_gr SYSNAME OUTPUT', @o_gr = @colImpGr OUTPUT;
        END

        IF @colImpEx IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o_ex = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA12''
                  AND LOWER(COLUMN_NAME) = N''importe_exento'';';
            EXEC sp_executesql @colsSql, N'@o_ex SYSNAME OUTPUT', @o_ex = @colImpEx OUTPUT;
        END

        IF @colImpIv IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o_iv = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA12''
                  AND LOWER(COLUMN_NAME) = N''importe_impuestos'';';
            EXEC sp_executesql @colsSql, N'@o_iv SYSNAME OUTPUT', @o_iv = @colImpIv OUTPUT;
        END

        IF @colImporte IS NULL
        BEGIN
            SET @colsSql = N'
                SELECT @o_imp = COLUMN_NAME
                FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''GVA12''
                  AND LOWER(COLUMN_NAME) = N''importe'';';
            EXEC sp_executesql @colsSql, N'@o_imp SYSNAME OUTPUT', @o_imp = @colImporte OUTPUT;
        END

        IF @colTComp IS NULL OR @colNComp IS NULL
           OR @colDetTComp IS NULL OR @colDetNComp IS NULL OR @colDetArt IS NULL
        BEGIN
            SET @i += 1;
            CONTINUE;
        END

        SET @selFecha = CASE WHEN @colFecha IS NOT NULL
            THEN N'cab.' + QUOTENAME(@colFecha) ELSE N'CAST(NULL AS DATETIME)' END;
        SET @selImpTot = CASE WHEN @colImporte IS NOT NULL
            THEN N'CAST(COALESCE(cab.' + QUOTENAME(@colImporte) + N', 0) AS DECIMAL(18,2))'
            ELSE N'CAST(0 AS DECIMAL(18,2))' END;
        SET @selImpGr = CASE WHEN @colImpGr IS NOT NULL
            THEN N'CAST(COALESCE(cab.' + QUOTENAME(@colImpGr) + N', 0) AS DECIMAL(18,2))'
            ELSE N'CAST(0 AS DECIMAL(18,2))' END;
        SET @selImpEx = CASE WHEN @colImpEx IS NOT NULL
            THEN N'CAST(COALESCE(cab.' + QUOTENAME(@colImpEx) + N', 0) AS DECIMAL(18,2))'
            ELSE N'CAST(0 AS DECIMAL(18,2))' END;
        SET @selImpIv = CASE WHEN @colImpIv IS NOT NULL
            THEN N'CAST(COALESCE(cab.' + QUOTENAME(@colImpIv) + N', 0) AS DECIMAL(18,2))'
            ELSE N'CAST(0 AS DECIMAL(18,2))' END;
        SET @selEstado = CASE WHEN @colEstado IS NOT NULL
            THEN N'CAST(cab.' + QUOTENAME(@colEstado) + N' AS NVARCHAR(10))'
            ELSE N'CAST(NULL AS NVARCHAR(10))' END;

        IF @hasGva14 = 1 AND @colCodClient IS NOT NULL
        BEGIN
            SET @joinCli = N'LEFT JOIN ' + @bdQuoted + N'.dbo.GVA14 AS cli
                ON cli.COD_CLIENT = cab.' + QUOTENAME(@colCodClient);
            SET @selRazon = CASE WHEN @colRazon IS NOT NULL
                THEN N'CAST(cli.' + QUOTENAME(@colRazon) + N' AS NVARCHAR(200))'
                ELSE N'CAST(NULL AS NVARCHAR(200))' END;
        END
        ELSE
        BEGIN
            SET @joinCli = N'';
            SET @selRazon = N'CAST(NULL AS NVARCHAR(200))';
        END

        SET @o_tComp = NULL; SET @o_nComp = NULL; SET @o_codClient = NULL;
        SET @o_razonSocial = NULL; SET @o_fechaEmision = NULL;
        SET @o_impGr = NULL; SET @o_impEx = NULL; SET @o_impIv = NULL;
        SET @o_impTot = NULL; SET @o_estado = NULL;

        SET @sql = N'
            SELECT TOP 1
                @o_tComp = CAST(cab.' + QUOTENAME(@colTComp) + N' AS NVARCHAR(10)),
                @o_nComp = CAST(cab.' + QUOTENAME(@colNComp) + N' AS NVARCHAR(50)),
                @o_codClient = ' + CASE WHEN @colCodClient IS NOT NULL
                    THEN N'CAST(cab.' + QUOTENAME(@colCodClient) + N' AS NVARCHAR(20))'
                    ELSE N'CAST(NULL AS NVARCHAR(20))' END + N',
                @o_razonSocial = ' + @selRazon + N',
                @o_fechaEmision = ' + @selFecha + N',
                @o_impGr = ' + @selImpGr + N',
                @o_impEx = ' + @selImpEx + N',
                @o_impIv = ' + @selImpIv + N',
                @o_impTot = ' + @selImpTot + N',
                @o_estado = ' + @selEstado + N'
            FROM ' + @bdQuoted + N'.dbo.GVA12 AS cab
            ' + @joinCli + N'
            WHERE cab.' + QUOTENAME(@colTComp) + N' = @p_t
              AND cab.' + QUOTENAME(@colNComp) + N' = @p_n
              AND EXISTS (
                    SELECT 1
                    FROM ' + @bdQuoted + N'.dbo.GVA53 AS det
                    WHERE det.' + QUOTENAME(@colDetTComp) + N' = cab.' + QUOTENAME(@colTComp) + N'
                      AND det.' + QUOTENAME(@colDetNComp) + N' = cab.' + QUOTENAME(@colNComp) + N'
                      AND det.' + QUOTENAME(@colDetArt) + N' LIKE @p_prefijo + N''%''
              )
              ' + @whereExtra + N';';

        EXEC sp_executesql @sql,
            N'@p_t NVARCHAR(10), @p_n NVARCHAR(50), @p_prefijo NVARCHAR(200),
              @o_tComp NVARCHAR(10) OUTPUT, @o_nComp NVARCHAR(50) OUTPUT,
              @o_codClient NVARCHAR(20) OUTPUT, @o_razonSocial NVARCHAR(200) OUTPUT,
              @o_fechaEmision DATETIME OUTPUT,
              @o_impGr DECIMAL(18,2) OUTPUT, @o_impEx DECIMAL(18,2) OUTPUT,
              @o_impIv DECIMAL(18,2) OUTPUT, @o_impTot DECIMAL(18,2) OUTPUT,
              @o_estado NVARCHAR(10) OUTPUT',
            @p_t = @t_comp,
            @p_n = @n_comp,
            @p_prefijo = @prefijo_escaped,
            @o_tComp = @o_tComp OUTPUT,
            @o_nComp = @o_nComp OUTPUT,
            @o_codClient = @o_codClient OUTPUT,
            @o_razonSocial = @o_razonSocial OUTPUT,
            @o_fechaEmision = @o_fechaEmision OUTPUT,
            @o_impGr = @o_impGr OUTPUT,
            @o_impEx = @o_impEx OUTPUT,
            @o_impIv = @o_impIv OUTPUT,
            @o_impTot = @o_impTot OUTPUT,
            @o_estado = @o_estado OUTPUT;

        SET @rowCount = @@ROWCOUNT;
        IF @rowCount = 0
        BEGIN
            SET @i += 1;
            CONTINUE;
        END

        SET @found = 1;

        INSERT INTO #cabecera (
            empresaBd, empresaOrigen, tComp, nComp, codClient, razonSocial,
            fechaEmision, importeGravado, importeExento, importeImpuestos, importeTotal, estado)
        VALUES (
            @nombreBd, @nombreEmpresa, @o_tComp, @o_nComp, @o_codClient, @o_razonSocial,
            @o_fechaEmision, @o_impGr, @o_impEx, @o_impIv, @o_impTot, @o_estado);

        SET @selCant = CASE WHEN @colDetCant IS NOT NULL
            THEN N'CAST(COALESCE(det.' + QUOTENAME(@colDetCant) + N', 0) AS DECIMAL(18,4))'
            ELSE N'CAST(0 AS DECIMAL(18,4))' END;
        SET @selPrecio = CASE WHEN @colDetPrecio IS NOT NULL
            THEN N'CAST(det.' + QUOTENAME(@colDetPrecio) + N' AS DECIMAL(18,4))'
            ELSE N'CAST(NULL AS DECIMAL(18,4))' END;
        SET @selImpNet = CASE WHEN @colDetImpNet IS NOT NULL
            THEN N'CAST(COALESCE(det.' + QUOTENAME(@colDetImpNet) + N', 0) AS DECIMAL(18,2))'
            ELSE N'CAST(0 AS DECIMAL(18,2))' END;
        SET @selDto = CASE WHEN @colDetDto IS NOT NULL
            THEN N'CAST(det.' + QUOTENAME(@colDetDto) + N' AS DECIMAL(18,4))'
            ELSE N'CAST(NULL AS DECIMAL(18,4))' END;
        SET @selIva = CASE WHEN @colDetIva IS NOT NULL
            THEN N'CAST(det.' + QUOTENAME(@colDetIva) + N' AS DECIMAL(18,4))'
            ELSE N'CAST(NULL AS DECIMAL(18,4))' END;

        SET @sql = N'
            INSERT INTO #renglones (codArticu, cantidad, precioNeto, importeNeto, descuento, porcIva)
            SELECT
                CAST(det.' + QUOTENAME(@colDetArt) + N' AS NVARCHAR(50)),
                ' + @selCant + N',
                ' + @selPrecio + N',
                ' + @selImpNet + N',
                ' + @selDto + N',
                ' + @selIva + N'
            FROM ' + @bdQuoted + N'.dbo.GVA53 AS det
            WHERE det.' + QUOTENAME(@colDetTComp) + N' = @p_t
              AND det.' + QUOTENAME(@colDetNComp) + N' = @p_n
              AND det.' + QUOTENAME(@colDetArt) + N' LIKE @p_prefijo + N''%'';';

        EXEC sp_executesql @sql,
            N'@p_t NVARCHAR(10), @p_n NVARCHAR(50), @p_prefijo NVARCHAR(200)',
            @p_t = @t_comp,
            @p_n = @n_comp,
            @p_prefijo = @prefijo_escaped;

        BREAK;
    END

    SELECT
        empresaBd, empresaOrigen, tComp, nComp, codClient, razonSocial,
        fechaEmision, importeGravado, importeExento, importeImpuestos, importeTotal, estado
    FROM #cabecera;

    SELECT
        codArticu, cantidad, precioNeto, importeNeto, descuento, porcIva
    FROM #renglones
    ORDER BY codArticu;
END
