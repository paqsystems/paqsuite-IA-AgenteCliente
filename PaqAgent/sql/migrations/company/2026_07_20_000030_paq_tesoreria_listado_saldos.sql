CREATE OR ALTER PROCEDURE dbo.PAQ_Tesoreria_ListadoSaldos
    @fecha_referencia   NVARCHAR(10),
    @ignorar_saldo_cero BIT           = 0,
    @cod_cuen           NVARCHAR(20)  = NULL,
    @tipo_cuenta        NVARCHAR(10)  = NULL,
    @empresa            NVARCHAR(100) = NULL,
    @page               INT           = 1,
    @page_size          INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.SBA05', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(20)) AS cod_cuen,
            CAST(NULL AS NVARCHAR(200)) AS descripcio,
            CAST(NULL AS DECIMAL(18, 2)) AS saldo,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasSba01        BIT = 0,
            @hasIdSba01      BIT = 0,
            @hasCodCtaS05    BIT = 0,
            @hasCodCuentaS05 BIT = 0,
            @hasFecha        BIT = 0,
            @hasFechaAsiento BIT = 0,
            @hasDh           BIT = 0,
            @hasMonto        BIT = 0,
            @hasCodCtaS01    BIT = 0,
            @hasCodCuentaS01 BIT = 0,
            @hasDescripcio   BIT = 0,
            @hasDescripcion  BIT = 0,
            @hasNomCta       BIT = 0,
            @hasTipo         BIT = 0;

    IF OBJECT_ID(N'dbo.SBA01', N'U') IS NOT NULL SET @hasSba01 = 1;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA05' AND COLUMN_NAME = N'ID_SBA01')
        SET @hasIdSba01 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA05' AND COLUMN_NAME = N'COD_CTA')
        SET @hasCodCtaS05 = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA05' AND COLUMN_NAME = N'COD_CUENTA')
        SET @hasCodCuentaS05 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA05' AND COLUMN_NAME = N'FECHA')
        SET @hasFecha = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA05' AND COLUMN_NAME = N'FECHA_ASIENTO')
        SET @hasFechaAsiento = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA05' AND COLUMN_NAME = N'D_H')
        SET @hasDh = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA05' AND COLUMN_NAME = N'MONTO')
        SET @hasMonto = 1;

    IF @hasSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA01' AND COLUMN_NAME = N'COD_CTA')
        SET @hasCodCtaS01 = 1;
    ELSE IF @hasSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA01' AND COLUMN_NAME = N'COD_CUENTA')
        SET @hasCodCuentaS01 = 1;
    IF @hasSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA01' AND COLUMN_NAME = N'DESCRIPCIO')
        SET @hasDescripcio = 1;
    ELSE IF @hasSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA01' AND COLUMN_NAME = N'DESCRIPCION')
        SET @hasDescripcion = 1;
    ELSE IF @hasSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA01' AND COLUMN_NAME = N'NOM_CTA')
        SET @hasNomCta = 1;
    IF @hasSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'SBA01' AND COLUMN_NAME = N'TIPO')
        SET @hasTipo = 1;

    DECLARE @codExpr       NVARCHAR(MAX),
            @fechaExpr     NVARCHAR(MAX),
            @montoExpr     NVARCHAR(MAX),
            @saldoCase     NVARCHAR(MAX),
            @joinSba01     NVARCHAR(MAX),
            @outerApply    NVARCHAR(MAX),
            @descS1        NVARCHAR(MAX),
            @descX         NVARCHAR(MAX),
            @descExpr      NVARCHAR(MAX),
            @codJoinS01    NVARCHAR(MAX),
            @where         NVARCHAR(MAX),
            @having        NVARCHAR(MAX),
            @grouped       NVARCHAR(MAX),
            @sqlTotal      NVARCHAR(MAX),
            @sqlPaged      NVARCHAR(MAX);

    SET @codExpr = CASE
        WHEN @hasCodCtaS05 = 1 THEN N's.COD_CTA'
        WHEN @hasCodCuentaS05 = 1 THEN N's.COD_CUENTA'
        WHEN @hasIdSba01 = 1 THEN N'CAST(s.ID_SBA01 AS NVARCHAR(50))'
        ELSE N'CAST(NULL AS NVARCHAR(50))'
    END;

    SET @fechaExpr = CASE
        WHEN @hasFecha = 1 THEN N's.FECHA'
        WHEN @hasFechaAsiento = 1 THEN N's.FECHA_ASIENTO'
        ELSE N'CAST(''1900-01-01'' AS DATETIME)'
    END;

    SET @montoExpr = CASE
        WHEN @hasMonto = 1 THEN N'COALESCE(s.MONTO, 0)'
        ELSE N'0'
    END;

    IF @hasDh = 1
        SET @saldoCase = N'CASE UPPER(LTRIM(RTRIM(COALESCE(s.D_H, ''''))))
            WHEN ''D'' THEN (' + @montoExpr + N')
            WHEN ''H'' THEN -(' + @montoExpr + N')
            ELSE 0
        END';
    ELSE
        SET @saldoCase = @montoExpr;

    SET @joinSba01 = CASE
        WHEN @hasSba01 = 1 AND @hasIdSba01 = 1
            THEN N'LEFT JOIN SBA01 s1 ON s.ID_SBA01 = s1.ID_SBA01'
        ELSE N''
    END;

    SET @descS1 = CASE
        WHEN @hasSba01 = 1 AND @hasIdSba01 = 1 AND @hasDescripcio = 1
            THEN N's1.DESCRIPCIO'
        WHEN @hasSba01 = 1 AND @hasIdSba01 = 1 AND @hasDescripcion = 1
            THEN N's1.DESCRIPCION'
        WHEN @hasSba01 = 1 AND @hasIdSba01 = 1 AND @hasNomCta = 1
            THEN N's1.NOM_CTA'
        ELSE N'NULL'
    END;

    SET @descX = CASE
        WHEN @hasDescripcio = 1 THEN N'x.DESCRIPCIO'
        WHEN @hasDescripcion = 1 THEN N'x.DESCRIPCION'
        WHEN @hasNomCta = 1 THEN N'x.NOM_CTA'
        ELSE N'NULL'
    END;

    SET @codJoinS01 = CASE
        WHEN @hasCodCtaS01 = 1 THEN N'COD_CTA'
        WHEN @hasCodCuentaS01 = 1 THEN N'COD_CUENTA'
        ELSE NULL
    END;

    IF @hasSba01 = 1 AND @codJoinS01 IS NOT NULL
        AND (@hasCodCtaS05 = 1 OR @hasCodCuentaS05 = 1)
        SET @outerApply = N'
        OUTER APPLY (
            SELECT TOP 1 *
            FROM SBA01 x
            WHERE x.' + @codJoinS01 + N' = ' + @codExpr + N'
        ) x';
    ELSE
        SET @outerApply = N'';

    IF @hasSba01 = 1
        SET @descExpr = N'COALESCE(' + @descS1 + N', ' + @descX + N', CAST(' + @codExpr + N' AS NVARCHAR(200)))';
    ELSE
        SET @descExpr = N'CAST(' + @codExpr + N' AS NVARCHAR(200))';

    SET @where = @fechaExpr + N' <= CONVERT(DATETIME, @p_fr, 120)';

    IF @cod_cuen IS NOT NULL AND @cod_cuen <> N''
        SET @where += N' AND ' + @codExpr + N' = @p_cc';

    IF @tipo_cuenta IS NOT NULL AND @tipo_cuenta <> N'' AND @hasTipo = 1 AND @hasSba01 = 1 AND @hasIdSba01 = 1
        SET @where += N' AND s1.TIPO = @p_tp';

    SET @having = CASE
        WHEN @ignorar_saldo_cero = 1
        THEN N'HAVING ABS(SUM(' + @saldoCase + N')) > 0.0001'
        ELSE N''
    END;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;

    SET @grouped = N'
        SELECT
            ' + @codExpr + N' AS cod_cuen,
            ' + @descExpr + N' AS descripcio,
            CAST(ROUND(SUM(' + @saldoCase + N'), 2) AS DECIMAL(18, 2)) AS saldo,
            @p_emp AS empresa
        FROM SBA05 s
        ' + @joinSba01 + N'
        ' + @outerApply + N'
        WHERE ' + @where + N'
        GROUP BY ' + @codExpr + N', ' + @descExpr + N'
        ' + @having;

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM (' + @grouped + N') sub';

    EXEC sp_executesql @sqlTotal,
        N'@p_fr NVARCHAR(10), @p_cc NVARCHAR(20), @p_tp NVARCHAR(10), @p_emp NVARCHAR(100)',
        @p_fr = @fecha_referencia, @p_cc = @cod_cuen,
        @p_tp = @tipo_cuenta, @p_emp = @empresa;

    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            sub.cod_cuen,
            sub.descripcio,
            sub.saldo,
            sub.empresa
        FROM (' + @grouped + N') sub
        ORDER BY sub.cod_cuen ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fr NVARCHAR(10), @p_cc NVARCHAR(20), @p_tp NVARCHAR(10), @p_emp NVARCHAR(100),
          @p_offset INT, @p_page_size INT',
        @p_fr = @fecha_referencia, @p_cc = @cod_cuen,
        @p_tp = @tipo_cuenta, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
