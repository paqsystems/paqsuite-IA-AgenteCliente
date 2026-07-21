CREATE OR ALTER PROCEDURE dbo.PAQ_Stock_ListadoSaldos
    @fecha_referencia   NVARCHAR(10),
    @ignorar_saldo_cero BIT           = 0,
    @cod_articu         NVARCHAR(20)  = NULL,
    @cod_deposi         NVARCHAR(20)  = NULL,
    @empresa            NVARCHAR(100) = NULL,
    @page               INT           = 1,
    @page_size          INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasSta14        BIT = 0,
            @hasSta11        BIT = 0,
            @hasIdSta14      BIT = 0;

    IF OBJECT_ID(N'dbo.STA14', N'U') IS NOT NULL SET @hasSta14 = 1;
    IF OBJECT_ID(N'dbo.STA11', N'U') IS NOT NULL SET @hasSta11 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'ID_STA14')
        SET @hasIdSta14 = 1;

    IF OBJECT_ID(N'dbo.STA20', N'U') IS NULL
       OR @hasSta14 = 0
       OR @hasIdSta14 = 0
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(20)) AS cod_articu,
            CAST(NULL AS NVARCHAR(200)) AS descripcio,
            CAST(NULL AS NVARCHAR(20)) AS cod_deposi,
            CAST(NULL AS DECIMAL(18, 2)) AS saldo,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasCodArticuS20   BIT = 0,
            @hasCodArticuloS20 BIT = 0,
            @hasCodDeposi      BIT = 0,
            @hasCodDeposito    BIT = 0,
            @hasFecha          BIT = 0,
            @hasFechaMov       BIT = 0,
            @hasCantidad       BIT = 0,
            @hasCant           BIT = 0,
            @hasTipoMov        BIT = 0,
            @hasEstado         BIT = 0,
            @hasEstadoMov      BIT = 0,
            @hasCodArticuS11   BIT = 0,
            @hasCodArticuloS11 BIT = 0,
            @hasDescripcio     BIT = 0,
            @hasDescripcion    BIT = 0;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'COD_ARTICU')
        SET @hasCodArticuS20 = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'COD_ARTICULO')
        SET @hasCodArticuloS20 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'COD_DEPOSI')
        SET @hasCodDeposi = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'COD_DEPOSITO')
        SET @hasCodDeposito = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'FECHA')
        SET @hasFecha = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'FECHA_MOV')
        SET @hasFechaMov = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'CANTIDAD')
        SET @hasCantidad = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'CANT')
        SET @hasCant = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'TIPO_MOV')
        SET @hasTipoMov = 1;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA14' AND COLUMN_NAME = N'ESTADO')
        SET @hasEstado = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA14' AND COLUMN_NAME = N'ESTADO_MOV')
        SET @hasEstadoMov = 1;

    IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA11' AND COLUMN_NAME = N'COD_ARTICU')
        SET @hasCodArticuS11 = 1;
    ELSE IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA11' AND COLUMN_NAME = N'COD_ARTICULO')
        SET @hasCodArticuloS11 = 1;
    IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA11' AND COLUMN_NAME = N'DESCRIPCIO')
        SET @hasDescripcio = 1;
    ELSE IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA11' AND COLUMN_NAME = N'DESCRIPCION')
        SET @hasDescripcion = 1;

    DECLARE @codArticuExpr NVARCHAR(MAX),
            @codDeposiExpr NVARCHAR(MAX),
            @fechaExpr     NVARCHAR(MAX),
            @cantExpr      NVARCHAR(MAX),
            @saldoCase     NVARCHAR(MAX),
            @joinSta11     NVARCHAR(MAX),
            @descExpr      NVARCHAR(MAX),
            @estadoExcl    NVARCHAR(MAX),
            @where         NVARCHAR(MAX),
            @having        NVARCHAR(MAX),
            @grouped       NVARCHAR(MAX),
            @sqlTotal      NVARCHAR(MAX),
            @sqlPaged      NVARCHAR(MAX);

    SET @codArticuExpr = CASE
        WHEN @hasCodArticuS20 = 1 THEN N'sta20.COD_ARTICU'
        WHEN @hasCodArticuloS20 = 1 THEN N'sta20.COD_ARTICULO'
        ELSE N'CAST(NULL AS NVARCHAR(20))'
    END;

    SET @codDeposiExpr = CASE
        WHEN @hasCodDeposi = 1 THEN N'sta20.COD_DEPOSI'
        WHEN @hasCodDeposito = 1 THEN N'sta20.COD_DEPOSITO'
        ELSE N'CAST(NULL AS NVARCHAR(20))'
    END;

    SET @fechaExpr = CASE
        WHEN @hasFecha = 1 THEN N'sta20.FECHA'
        WHEN @hasFechaMov = 1 THEN N'sta20.FECHA_MOV'
        ELSE N'CAST(''1900-01-01'' AS DATETIME)'
    END;

    SET @cantExpr = CASE
        WHEN @hasCantidad = 1 THEN N'COALESCE(sta20.CANTIDAD, 0)'
        WHEN @hasCant = 1 THEN N'COALESCE(sta20.CANT, 0)'
        ELSE N'0'
    END;

    IF @hasTipoMov = 1
        SET @saldoCase = N'CASE UPPER(LTRIM(RTRIM(COALESCE(sta20.TIPO_MOV, ''''))))
            WHEN ''E'' THEN (' + @cantExpr + N')
            WHEN ''S'' THEN -(' + @cantExpr + N')
            ELSE 0
        END';
    ELSE
        SET @saldoCase = @cantExpr;

    SET @joinSta11 = CASE
        WHEN @hasSta11 = 1 AND @hasCodArticuS11 = 1 AND @hasCodArticuS20 = 1
            THEN N'LEFT JOIN STA11 sta11 ON sta20.COD_ARTICU = sta11.COD_ARTICU'
        WHEN @hasSta11 = 1 AND @hasCodArticuloS11 = 1 AND @hasCodArticuloS20 = 1
            THEN N'LEFT JOIN STA11 sta11 ON sta20.COD_ARTICULO = sta11.COD_ARTICULO'
        WHEN @hasSta11 = 1 AND @hasCodArticuS11 = 1 AND @hasCodArticuloS20 = 1
            THEN N'LEFT JOIN STA11 sta11 ON sta20.COD_ARTICULO = sta11.COD_ARTICU'
        WHEN @hasSta11 = 1 AND @hasCodArticuloS11 = 1 AND @hasCodArticuS20 = 1
            THEN N'LEFT JOIN STA11 sta11 ON sta20.COD_ARTICU = sta11.COD_ARTICULO'
        ELSE N''
    END;

    SET @descExpr = CASE
        WHEN @joinSta11 <> N'' AND @hasDescripcio = 1 THEN N'MAX(sta11.DESCRIPCIO)'
        WHEN @joinSta11 <> N'' AND @hasDescripcion = 1 THEN N'MAX(sta11.DESCRIPCION)'
        ELSE N'CAST('''' AS NVARCHAR(200))'
    END;

    SET @estadoExcl = CASE
        WHEN @hasEstado = 1
            THEN N'AND (sta14.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(sta14.ESTADO))) <> ''A'')'
        WHEN @hasEstadoMov = 1
            THEN N'AND (sta14.ESTADO_MOV IS NULL OR UPPER(LTRIM(RTRIM(sta14.ESTADO_MOV))) <> ''A'')'
        ELSE N''
    END;

    SET @where =
        @fechaExpr + N' <= CONVERT(DATETIME, @p_fr, 120)
          ' + @estadoExcl;

    IF @cod_articu IS NOT NULL AND @cod_articu <> N''
        SET @where += N' AND ' + @codArticuExpr + N' = @p_ca';

    IF @cod_deposi IS NOT NULL AND @cod_deposi <> N''
        SET @where += N' AND ' + @codDeposiExpr + N' = @p_cd';

    SET @having = CASE
        WHEN @ignorar_saldo_cero = 1
        THEN N'HAVING ABS(SUM(' + @saldoCase + N')) > 0.0001'
        ELSE N''
    END;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;

    SET @grouped = N'
        SELECT
            ' + @codArticuExpr + N' AS cod_articu,
            ' + @descExpr + N' AS descripcio,
            ' + @codDeposiExpr + N' AS cod_deposi,
            CAST(ROUND(SUM(' + @saldoCase + N'), 2) AS DECIMAL(18, 2)) AS saldo,
            @p_emp AS empresa
        FROM STA20 sta20
        INNER JOIN STA14 sta14 ON sta20.ID_STA14 = sta14.ID_STA14
        ' + @joinSta11 + N'
        WHERE ' + @where + N'
        GROUP BY ' + @codArticuExpr + N', ' + @codDeposiExpr + N'
        ' + @having;

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM (' + @grouped + N') sub';

    EXEC sp_executesql @sqlTotal,
        N'@p_fr NVARCHAR(10), @p_ca NVARCHAR(20), @p_cd NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fr = @fecha_referencia, @p_ca = @cod_articu,
        @p_cd = @cod_deposi, @p_emp = @empresa;

    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            sub.cod_articu,
            sub.descripcio,
            sub.cod_deposi,
            sub.saldo,
            sub.empresa
        FROM (' + @grouped + N') sub
        ORDER BY sub.cod_articu ASC, sub.cod_deposi ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fr NVARCHAR(10), @p_ca NVARCHAR(20), @p_cd NVARCHAR(20), @p_emp NVARCHAR(100),
          @p_offset INT, @p_page_size INT',
        @p_fr = @fecha_referencia, @p_ca = @cod_articu,
        @p_cd = @cod_deposi, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
