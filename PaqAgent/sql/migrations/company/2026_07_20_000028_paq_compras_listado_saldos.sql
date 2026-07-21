CREATE OR ALTER PROCEDURE dbo.PAQ_Compras_ListadoSaldos
    @fecha_referencia   NVARCHAR(10),
    @criterio_fecha     NVARCHAR(10)  = N'emision',
    @ignorar_saldo_cero BIT           = 0,
    @cod_provee         NVARCHAR(20)  = NULL,
    @comprador          NVARCHAR(20)  = NULL,
    @provincia          NVARCHAR(20)  = NULL,
    @empresa            NVARCHAR(100) = NULL,
    @page               INT           = 1,
    @page_size          INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.CPA04', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(20)) AS cod_provee,
            CAST(NULL AS NVARCHAR(200)) AS razon_soci,
            CAST(NULL AS DECIMAL(18, 2)) AS saldo,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasCpa21       BIT = 0,
            @hasCpa01       BIT = 0,
            @hasImporteTot  BIT = 0,
            @hasFechaCont   BIT = 0,
            @hasAnulado     BIT = 0,
            @hasEstado      BIT = 0,
            @hasNomProvee   BIT = 0,
            @hasRazonSoci   BIT = 0,
            @hasCodProvin   BIT = 0,
            @hasCodProvincia BIT = 0,
            @hasCodCompra   BIT = 0,
            @hasCodComprador BIT = 0,
            @hasDhExpr      NVARCHAR(50) = N'NULL';

    IF OBJECT_ID(N'dbo.CPA21', N'U') IS NOT NULL SET @hasCpa21 = 1;
    IF OBJECT_ID(N'dbo.CPA01', N'U') IS NOT NULL SET @hasCpa01 = 1;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA04' AND COLUMN_NAME = N'IMPORTE_TOT')
        SET @hasImporteTot = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA04' AND COLUMN_NAME = N'FECHA_CONT')
        SET @hasFechaCont = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA04' AND COLUMN_NAME = N'ANULADO')
        SET @hasAnulado = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA04' AND COLUMN_NAME = N'ESTADO')
        SET @hasEstado = 1;

    IF @hasCpa21 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA21' AND COLUMN_NAME = N'DEBHAB')
        SET @hasDhExpr = N'c21.DEBHAB';
    ELSE IF @hasCpa21 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA21' AND COLUMN_NAME = N'D_H')
        SET @hasDhExpr = N'c21.D_H';

    IF @hasCpa01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA01' AND COLUMN_NAME = N'NOM_PROVEE')
        SET @hasNomProvee = 1;
    IF @hasCpa01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA01' AND COLUMN_NAME = N'RAZON_SOCI')
        SET @hasRazonSoci = 1;
    IF @hasCpa01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA01' AND COLUMN_NAME = N'COD_PROVIN')
        SET @hasCodProvin = 1;
    ELSE IF @hasCpa01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA01' AND COLUMN_NAME = N'COD_PROVINCIA')
        SET @hasCodProvincia = 1;
    IF @hasCpa01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA01' AND COLUMN_NAME = N'COD_COMPRA')
        SET @hasCodCompra = 1;
    ELSE IF @hasCpa01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA01' AND COLUMN_NAME = N'COD_COMPRADOR')
        SET @hasCodComprador = 1;

    DECLARE @importeExpr   NVARCHAR(MAX),
            @joinCpa21     NVARCHAR(MAX),
            @joinCpa01     NVARCHAR(MAX),
            @dhExpr        NVARCHAR(MAX),
            @saldoCase     NVARCHAR(MAX),
            @razonExpr     NVARCHAR(MAX),
            @provCol       NVARCHAR(MAX),
            @compradorCol  NVARCHAR(MAX),
            @fechaExpr     NVARCHAR(MAX),
            @where         NVARCHAR(MAX),
            @having        NVARCHAR(MAX),
            @grouped       NVARCHAR(MAX),
            @sqlTotal      NVARCHAR(MAX),
            @sqlPaged      NVARCHAR(MAX);

    SET @importeExpr = CASE
        WHEN @hasImporteTot = 1 THEN N'c.IMPORTE_TOT'
        ELSE N'c.IMPORTE'
    END;

    SET @joinCpa21 = CASE
        WHEN @hasCpa21 = 1 THEN N'LEFT JOIN CPA21 c21 ON c21.T_COMP = c.T_COMP'
        ELSE N''
    END;

    SET @joinCpa01 = CASE
        WHEN @hasCpa01 = 1 THEN N'LEFT JOIN CPA01 p ON p.COD_PROVEE = c.COD_PROVEE'
        ELSE N''
    END;

    SET @dhExpr = @hasDhExpr;
    IF @dhExpr = N'NULL'
        SET @saldoCase = N'CASE
            WHEN c.T_COMP = ''REC'' THEN -(' + @importeExpr + N')
            ELSE -(' + @importeExpr + N')
        END';
    ELSE
        SET @saldoCase = N'CASE
            WHEN c.T_COMP = ''REC'' THEN -(' + @importeExpr + N')
            WHEN ' + @dhExpr + N' = ''D'' THEN (' + @importeExpr + N')
            ELSE -(' + @importeExpr + N')
        END';

    SET @razonExpr = CASE
        WHEN @hasNomProvee = 1 THEN N'p.NOM_PROVEE'
        WHEN @hasRazonSoci = 1 THEN N'p.RAZON_SOCI'
        ELSE N''''''
    END;

    SET @provCol = CASE
        WHEN @hasCodProvin = 1 THEN N'p.COD_PROVIN'
        WHEN @hasCodProvincia = 1 THEN N'p.COD_PROVINCIA'
        ELSE NULL
    END;

    SET @compradorCol = CASE
        WHEN @hasCodCompra = 1 THEN N'p.COD_COMPRA'
        WHEN @hasCodComprador = 1 THEN N'p.COD_COMPRADOR'
        ELSE NULL
    END;

    SET @fechaExpr = CASE
        WHEN LOWER(LTRIM(RTRIM(ISNULL(@criterio_fecha, N'')))) = N'contable'
             AND @hasFechaCont = 1
            THEN N'COALESCE(c.FECHA_CONT, c.FECHA_EMIS)'
        ELSE N'c.FECHA_EMIS'
    END;

    SET @where =
        @fechaExpr + N' <= CONVERT(DATETIME, @p_fr, 120)
          AND c.COD_PROVEE <> ''***''
          AND c.T_COMP <> ''ANU''';

    IF @hasEstado = 1
        SET @where += N'
          AND (c.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(c.ESTADO))) NOT IN (''ANU'',''ANUL''))';

    IF @hasAnulado = 1
        SET @where += N' AND (c.ANULADO = 0 OR c.ANULADO IS NULL)';

    IF @cod_provee IS NOT NULL AND @cod_provee <> N''
        SET @where += N' AND c.COD_PROVEE = @p_cp';

    IF @comprador IS NOT NULL AND @comprador <> N'' AND @compradorCol IS NOT NULL
        SET @where += N' AND ' + @compradorCol + N' = @p_co';

    IF @provincia IS NOT NULL AND @provincia <> N'' AND @provCol IS NOT NULL
        SET @where += N' AND ' + @provCol + N' = @p_pr';

    SET @having = CASE
        WHEN @ignorar_saldo_cero = 1
        THEN N'HAVING ABS(SUM(' + @saldoCase + N')) > 0.0001'
        ELSE N''
    END;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;

    SET @grouped = N'
        SELECT
            c.COD_PROVEE AS cod_provee,
            ' + @razonExpr + N' AS razon_soci,
            CAST(ROUND(SUM(' + @saldoCase + N'), 2) AS DECIMAL(18, 2)) AS saldo,
            @p_emp AS empresa
        FROM CPA04 c
        ' + @joinCpa21 + N'
        ' + @joinCpa01 + N'
        WHERE ' + @where + N'
        GROUP BY c.COD_PROVEE, ' + @razonExpr + N'
        ' + @having;

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM (' + @grouped + N') sub';

    EXEC sp_executesql @sqlTotal,
        N'@p_fr NVARCHAR(10), @p_cp NVARCHAR(20), @p_co NVARCHAR(20),
          @p_pr NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fr = @fecha_referencia, @p_cp = @cod_provee,
        @p_co = @comprador, @p_pr = @provincia, @p_emp = @empresa;

    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            sub.cod_provee,
            sub.razon_soci,
            sub.saldo,
            sub.empresa
        FROM (' + @grouped + N') sub
        ORDER BY sub.cod_provee ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fr NVARCHAR(10), @p_cp NVARCHAR(20), @p_co NVARCHAR(20),
          @p_pr NVARCHAR(20), @p_emp NVARCHAR(100), @p_offset INT, @p_page_size INT',
        @p_fr = @fecha_referencia, @p_cp = @cod_provee,
        @p_co = @comprador, @p_pr = @provincia, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
