CREATE OR ALTER PROCEDURE dbo.PAQ_Tesoreria_MayorCuenta
    @fecha_desde  DATETIME,
    @fecha_hasta  DATETIME,
    @cod_cuen     NVARCHAR(50)  = NULL,
    @empresa      NVARCHAR(100) = NULL,
    @page         INT           = 1,
    @page_size    INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.SBA05', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS DATETIME)      AS fecha,
            CAST(NULL AS NVARCHAR(50))  AS cod_cuen,
            CAST(NULL AS NVARCHAR(255)) AS descripcio,
            CAST(NULL AS NVARCHAR(10))  AS t_comp,
            CAST(NULL AS NVARCHAR(20))  AS n_comp,
            CAST(NULL AS NVARCHAR(1))   AS d_h,
            CAST(NULL AS DECIMAL(18,2)) AS monto,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'FECHA')
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS DATETIME)      AS fecha,
            CAST(NULL AS NVARCHAR(50))  AS cod_cuen,
            CAST(NULL AS NVARCHAR(255)) AS descripcio,
            CAST(NULL AS NVARCHAR(10))  AS t_comp,
            CAST(NULL AS NVARCHAR(20))  AS n_comp,
            CAST(NULL AS NVARCHAR(1))   AS d_h,
            CAST(NULL AS DECIMAL(18,2)) AS monto,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasSba01        BIT = 0,
            @hasIdSba01      BIT = 0,
            @hasCodCtaS05    BIT = 0,
            @hasCodCuenS05   BIT = 0,
            @hasTComp        BIT = 0,
            @hasCodComp      BIT = 0,
            @hasNComp        BIT = 0,
            @hasDh           BIT = 0,
            @hasMonto        BIT = 0,
            @hasDescS01      BIT = 0,
            @hasDescContS01  BIT = 0,
            @hasDescS05      BIT = 0,
            @hasLeyenda      BIT = 0,
            @hasCodCtaS01    BIT = 0;

    IF OBJECT_ID(N'dbo.SBA01', N'U') IS NOT NULL SET @hasSba01 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'ID_SBA01')
        SET @hasIdSba01 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'COD_CTA')
        SET @hasCodCtaS05 = 1;
    IF @hasCodCtaS05 = 0 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'COD_CUEN')
        SET @hasCodCuenS05 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'T_COMP')
        SET @hasTComp = 1;
    IF @hasTComp = 0 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'COD_COMP')
        SET @hasCodComp = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'N_COMP')
        SET @hasNComp = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'D_H')
        SET @hasDh = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'MONTO')
        SET @hasMonto = 1;
    IF @hasSba01 = 1 AND @hasIdSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA01' AND COLUMN_NAME = 'DESCRIPCIO')
        SET @hasDescS01 = 1;
    IF @hasSba01 = 1 AND @hasIdSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA01' AND COLUMN_NAME = 'DESC_CONT')
        SET @hasDescContS01 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'DESCRIPCIO')
        SET @hasDescS05 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA05' AND COLUMN_NAME = 'LEYENDA')
        SET @hasLeyenda = 1;
    IF @hasSba01 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'SBA01' AND COLUMN_NAME = 'COD_CTA')
        SET @hasCodCtaS01 = 1;

    DECLARE @codExpr      NVARCHAR(MAX),
            @joinSba01    NVARCHAR(MAX),
            @outerApply   NVARCHAR(MAX),
            @tCompExpr    NVARCHAR(MAX),
            @nCompExpr    NVARCHAR(MAX),
            @montoExpr    NVARCHAR(MAX),
            @dhExpr       NVARCHAR(MAX),
            @codKey       NVARCHAR(MAX),
            @descParts    NVARCHAR(MAX),
            @descExpr     NVARCHAR(MAX),
            @where        NVARCHAR(MAX),
            @sqlTotal     NVARCHAR(MAX),
            @sqlPaged     NVARCHAR(MAX);

    -- Expresión del código de cuenta
    SET @codExpr = CASE
        WHEN @hasCodCtaS05 = 1 THEN N'CAST(s.COD_CTA AS VARCHAR(40))'
        WHEN @hasCodCuenS05 = 1 THEN N'CAST(s.COD_CUEN AS VARCHAR(40))'
        WHEN @hasIdSba01 = 1 THEN N'CAST(s.ID_SBA01 AS VARCHAR(40))'
        ELSE N'CAST(NULL AS VARCHAR(40))'
    END;

    -- JOIN a SBA01 por ID
    SET @joinSba01 = CASE
        WHEN @hasSba01 = 1 AND @hasIdSba01 = 1
            THEN N'LEFT JOIN SBA01 s1 ON s.ID_SBA01 = s1.ID_SBA01'
        ELSE N''
    END;

    -- OUTER APPLY para lookup por COD_CTA en SBA01
    SET @outerApply = N'';
    IF @hasSba01 = 1 AND @hasCodCtaS01 = 1
        AND (@hasCodCtaS05 = 1 OR @hasCodCuenS05 = 1)
    BEGIN
        DECLARE @orderCol NVARCHAR(MAX) = CASE
            WHEN @hasIdSba01 = 1 THEN N'x.ID_SBA01'
            ELSE N'x.COD_CTA'
        END;
        SET @outerApply = N'
        OUTER APPLY (
            SELECT TOP 1 *
            FROM SBA01 x
            WHERE x.COD_CTA = ' + @codExpr + N'
            ORDER BY ' + @orderCol + N'
        ) acc';
    END

    -- T_COMP / N_COMP / D_H / MONTO
    SET @tCompExpr = CASE
        WHEN @hasTComp = 1 THEN N's.T_COMP'
        WHEN @hasCodComp = 1 THEN N's.COD_COMP'
        ELSE N'CAST('''' AS VARCHAR(3))'
    END;
    SET @nCompExpr = CASE WHEN @hasNComp = 1 THEN N's.N_COMP' ELSE N'CAST('''' AS VARCHAR(14))' END;
    SET @dhExpr    = CASE WHEN @hasDh = 1 THEN N's.D_H' ELSE N'CAST('''' AS VARCHAR(1))' END;
    SET @montoExpr = CASE WHEN @hasMonto = 1 THEN N's.MONTO' ELSE N'0' END;

    -- Descripción: cascada de fuentes
    SET @descParts = N'';
    IF @hasDescS01 = 1
        SET @descParts += N'NULLIF(LTRIM(RTRIM(s1.DESCRIPCIO)), ''''), ';
    IF @hasDescContS01 = 1
        SET @descParts += N'NULLIF(LTRIM(RTRIM(s1.DESC_CONT)), ''''), ';
    IF @hasDescS05 = 1
        SET @descParts += N'NULLIF(LTRIM(RTRIM(s.DESCRIPCIO)), ''''), ';
    IF @hasLeyenda = 1
        SET @descParts += N'NULLIF(LTRIM(RTRIM(s.LEYENDA)), ''''), ';
    -- OUTER APPLY acc
    IF @outerApply <> N''
    BEGIN
        IF @hasDescS01 = 1
            SET @descParts += N'NULLIF(LTRIM(RTRIM(acc.DESCRIPCIO)), ''''), ';
        IF @hasDescContS01 = 1
            SET @descParts += N'NULLIF(LTRIM(RTRIM(acc.DESC_CONT)), ''''), ';
    END

    SET @descExpr = CASE
        WHEN @descParts <> N''
            THEN N'CAST(COALESCE(' + LEFT(@descParts, LEN(@descParts) - 2) + N', '''') AS VARCHAR(255))'
        ELSE N'CAST('''' AS VARCHAR(255))'
    END;

    -- WHERE
    SET @where = N's.FECHA BETWEEN @p_fd AND @p_fh';
    IF @cod_cuen IS NOT NULL AND @cod_cuen <> N''
        SET @where += N' AND LTRIM(RTRIM(CAST(' + @codExpr + N' AS VARCHAR(60)))) = LTRIM(RTRIM(@p_cc))';

    -- RS0: total
    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM SBA05 s
        ' + @joinSba01 + N'
        ' + @outerApply + N'
        WHERE ' + @where;

    EXEC sp_executesql @sqlTotal,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_cc NVARCHAR(50)',
        @p_fd = @fecha_desde, @p_fh = @fecha_hasta, @p_cc = @cod_cuen;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;
    DECLARE @offset INT = (@page - 1) * @page_size;

    -- RS1: filas paginadas
    SET @sqlPaged = N'
        SELECT
            s.FECHA                   AS fecha,
            ' + @codExpr + N'         AS cod_cuen,
            ' + @descExpr + N'        AS descripcio,
            ' + @tCompExpr + N'       AS t_comp,
            ' + @nCompExpr + N'       AS n_comp,
            ' + @dhExpr + N'          AS d_h,
            CAST(ROUND(COALESCE(' + @montoExpr + N', 0), 2) AS DECIMAL(18,2)) AS monto,
            @p_emp                    AS empresa
        FROM SBA05 s
        ' + @joinSba01 + N'
        ' + @outerApply + N'
        WHERE ' + @where + N'
        ORDER BY s.FECHA ASC, ' + @codExpr + N' ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_cc NVARCHAR(50),
          @p_emp NVARCHAR(100), @p_offset INT, @p_page_size INT',
        @p_fd = @fecha_desde, @p_fh = @fecha_hasta, @p_cc = @cod_cuen,
        @p_emp = @empresa, @p_offset = @offset, @p_page_size = @page_size;
END
