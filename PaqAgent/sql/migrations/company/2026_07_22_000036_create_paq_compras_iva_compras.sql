CREATE OR ALTER PROCEDURE dbo.PAQ_Compras_IvaCompras
    @fecha_desde    DATETIME,
    @fecha_hasta    DATETIME,
    @criterio_fecha NVARCHAR(10)  = N'contable',
    @empresa        NVARCHAR(100) = NULL,
    @page           INT           = 1,
    @page_size      INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.CPA04', N'U') IS NULL
        OR OBJECT_ID(N'dbo.CPA21', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS DATETIME)      AS fecha_cont,
            CAST(NULL AS DATETIME)      AS fecha_emis,
            CAST(NULL AS NVARCHAR(10))  AS t_comp,
            CAST(NULL AS NVARCHAR(20))  AS n_comp,
            CAST(NULL AS NVARCHAR(20))  AS cod_provee,
            CAST(NULL AS NVARCHAR(200)) AS razon_soci,
            CAST(NULL AS NVARCHAR(50))  AS iva,
            CAST(NULL AS DECIMAL(18,2)) AS importe_cpa18,
            CAST(NULL AS DECIMAL(18,2)) AS neto,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasImporteTo   BIT = 0,
            @hasImporte     BIT = 0,
            @hasNomProvee   BIT = 0,
            @hasFechaCont   BIT = 0,
            @hasAnulado     BIT = 0,
            @hasEstado      BIT = 0,
            @hasIvaComC21   BIT = 0,
            @hasImpIva1     BIT = 0,
            @hasImpIva2     BIT = 0,
            @hasImpIva3     BIT = 0,
            @hasImpIva4     BIT = 0,
            @hasImpIva5     BIT = 0,
            @hasCpa18       BIT = 0,
            @hasCpa18Join   BIT = 0,
            @hasCpa01       BIT = 0;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'IMPORTE_TO')
        SET @hasImporteTo = 1;
    IF @hasImporteTo = 0 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'IMPORTE')
        SET @hasImporte = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'FECHA_CONT')
        SET @hasFechaCont = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'ANULADO')
        SET @hasAnulado = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'ESTADO')
        SET @hasEstado = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'IMP_IVA1')
        SET @hasImpIva1 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'IMP_IVA2')
        SET @hasImpIva2 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'IMP_IVA3')
        SET @hasImpIva3 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'IMP_IVA4')
        SET @hasImpIva4 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'IMP_IVA5')
        SET @hasImpIva5 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA21' AND COLUMN_NAME = 'IVA_COM')
        SET @hasIvaComC21 = 1;
    IF OBJECT_ID(N'dbo.CPA01', N'U') IS NOT NULL SET @hasCpa01 = 1;
    IF @hasCpa01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'CPA01' AND COLUMN_NAME = 'NOM_PROVEE')
        SET @hasNomProvee = 1;
    IF OBJECT_ID(N'dbo.CPA18', N'U') IS NOT NULL SET @hasCpa18 = 1;
    IF @hasCpa18 = 1
        AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'CPA18' AND COLUMN_NAME = 'IMPORTE')
        AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'CPA18' AND COLUMN_NAME = 'TCOMP_IN_C')
        AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'CPA18' AND COLUMN_NAME = 'NCOMP_IN_C')
        AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'TCOMP_IN_C')
        AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'CPA04' AND COLUMN_NAME = 'NCOMP_IN_C')
        SET @hasCpa18Join = 1;

    DECLARE @importNeto     NVARCHAR(MAX),
            @joinCpa01      NVARCHAR(MAX),
            @razonExpr      NVARCHAR(MAX),
            @joinCpa18      NVARCHAR(MAX),
            @importeCpa18   NVARCHAR(MAX),
            @ivaMontoExpr   NVARCHAR(MAX),
            @ivaComFilter   NVARCHAR(MAX),
            @fechaExpr      NVARCHAR(MAX),
            @fechaContSel   NVARCHAR(MAX),
            @where          NVARCHAR(MAX),
            @sqlTotal       NVARCHAR(MAX),
            @sqlPaged       NVARCHAR(MAX);

    SET @importNeto = CASE
        WHEN @hasImporteTo = 1 THEN N'c.IMPORTE_TO'
        WHEN @hasImporte = 1   THEN N'c.IMPORTE'
        ELSE N'0'
    END;

    SET @joinCpa01 = CASE WHEN @hasCpa01 = 1
        THEN N'LEFT JOIN CPA01 p ON c.COD_PROVEE = p.COD_PROVEE'
        ELSE N''
    END;

    SET @razonExpr = CASE WHEN @hasNomProvee = 1
        THEN N'p.NOM_PROVEE' ELSE N'CAST('''' AS NVARCHAR(1))' END;

    SET @joinCpa18 = CASE WHEN @hasCpa18Join = 1
        THEN N'LEFT JOIN (
            SELECT TCOMP_IN_C, NCOMP_IN_C,
                CAST(SUM(COALESCE(IMPORTE, 0)) AS DECIMAL(18,2)) AS importe_sum
            FROM CPA18
            GROUP BY TCOMP_IN_C, NCOMP_IN_C
        ) c18 ON c18.TCOMP_IN_C = c.TCOMP_IN_C AND c18.NCOMP_IN_C = c.NCOMP_IN_C'
        ELSE N''
    END;

    SET @importeCpa18 = CASE WHEN @hasCpa18Join = 1
        THEN N'CAST(COALESCE(c18.importe_sum, 0) AS DECIMAL(18,2))'
        ELSE N'CAST(0 AS DECIMAL(18,2))'
    END;

    -- Suma dinámica IMP_IVA1..5
    DECLARE @ivaParts NVARCHAR(MAX) = N'';
    IF @hasImpIva1 = 1 SET @ivaParts += N'COALESCE(c.IMP_IVA1, 0)';
    IF @hasImpIva2 = 1 SET @ivaParts += CASE WHEN @ivaParts = N'' THEN N'' ELSE N' + ' END + N'COALESCE(c.IMP_IVA2, 0)';
    IF @hasImpIva3 = 1 SET @ivaParts += CASE WHEN @ivaParts = N'' THEN N'' ELSE N' + ' END + N'COALESCE(c.IMP_IVA3, 0)';
    IF @hasImpIva4 = 1 SET @ivaParts += CASE WHEN @ivaParts = N'' THEN N'' ELSE N' + ' END + N'COALESCE(c.IMP_IVA4, 0)';
    IF @hasImpIva5 = 1 SET @ivaParts += CASE WHEN @ivaParts = N'' THEN N'' ELSE N' + ' END + N'COALESCE(c.IMP_IVA5, 0)';
    SET @ivaMontoExpr = CASE WHEN @ivaParts = N''
        THEN N'CAST(0 AS DECIMAL(18,2))'
        ELSE N'CAST(' + @ivaParts + N' AS DECIMAL(18,2))'
    END;

    SET @ivaComFilter = CASE WHEN @hasIvaComC21 = 1
        THEN N'AND (c21.IVA_COM = 1)'
        ELSE N''
    END;

    SET @fechaExpr = CASE
        WHEN LOWER(LTRIM(RTRIM(ISNULL(@criterio_fecha, N'')))) = N'emision'
            THEN N'c.FECHA_EMIS'
        WHEN @hasFechaCont = 1
            THEN N'COALESCE(c.FECHA_CONT, c.FECHA_EMIS)'
        ELSE N'c.FECHA_EMIS'
    END;

    SET @fechaContSel = CASE WHEN @hasFechaCont = 1
        THEN N'c.FECHA_CONT AS fecha_cont'
        ELSE N'CAST(NULL AS DATETIME) AS fecha_cont'
    END;

    SET @where =
        @fechaExpr + N' BETWEEN @p_fd AND @p_fh
          AND c.T_COMP <> ''O/P''
          ' + @ivaComFilter;

    IF @hasEstado = 1
        SET @where += N' AND (COALESCE(LTRIM(RTRIM(c.ESTADO)), '''') <> ''ANU'')';
    IF @hasAnulado = 1
        SET @where += N' AND (c.ANULADO = 0 OR c.ANULADO IS NULL)';

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM CPA04 c
        ' + @joinCpa01 + N'
        INNER JOIN CPA21 c21 ON c21.T_COMP = c.T_COMP
        ' + @joinCpa18 + N'
        WHERE ' + @where;

    EXEC sp_executesql @sqlTotal,
        N'@p_fd DATETIME, @p_fh DATETIME',
        @p_fd = @fecha_desde, @p_fh = @fecha_hasta;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;
    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            ' + @fechaContSel + N',
            c.FECHA_EMIS    AS fecha_emis,
            c.T_COMP        AS t_comp,
            c.N_COMP        AS n_comp,
            c.COD_PROVEE    AS cod_provee,
            ' + @razonExpr + N' AS razon_soci,
            ' + @ivaMontoExpr + N' AS iva,
            ' + @importeCpa18 + N' AS importe_cpa18,
            CAST(ROUND(COALESCE(' + @importNeto + N', 0), 2) AS DECIMAL(18,2)) AS neto,
            @p_emp AS empresa
        FROM CPA04 c
        ' + @joinCpa01 + N'
        INNER JOIN CPA21 c21 ON c21.T_COMP = c.T_COMP
        ' + @joinCpa18 + N'
        WHERE ' + @where + N'
        ORDER BY ' + @fechaExpr + N' DESC, c.N_COMP ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_emp NVARCHAR(100),
          @p_offset INT, @p_page_size INT',
        @p_fd = @fecha_desde, @p_fh = @fecha_hasta, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
