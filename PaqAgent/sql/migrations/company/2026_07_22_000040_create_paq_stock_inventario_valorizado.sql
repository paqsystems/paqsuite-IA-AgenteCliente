CREATE OR ALTER PROCEDURE dbo.PAQ_Stock_InventarioValorizado
    @fecha_referencia   DATETIME,
    @ignorar_saldo_cero BIT           = 1,
    @cod_articu         NVARCHAR(20)  = NULL,
    @cod_deposi         NVARCHAR(20)  = NULL,
    @empresa            NVARCHAR(100) = NULL,
    @page               INT           = 1,
    @page_size          INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.STA20', N'U') IS NULL
        OR OBJECT_ID(N'dbo.STA14', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(20))  AS cod_articu,
            CAST(NULL AS NVARCHAR(200)) AS articulo,
            CAST(NULL AS NVARCHAR(20))  AS cod_deposi,
            CAST(NULL AS DECIMAL(18,4)) AS stock_actual,
            CAST(NULL AS DECIMAL(18,4)) AS precio_promedio,
            CAST(NULL AS DECIMAL(18,4)) AS valor_total,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'ID_STA14')
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(20))  AS cod_articu,
            CAST(NULL AS NVARCHAR(200)) AS articulo,
            CAST(NULL AS NVARCHAR(20))  AS cod_deposi,
            CAST(NULL AS DECIMAL(18,4)) AS stock_actual,
            CAST(NULL AS DECIMAL(18,4)) AS precio_promedio,
            CAST(NULL AS DECIMAL(18,4)) AS valor_total,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasSta11          BIT = 0,
            @hasCodArticuS20   BIT = 0,
            @hasCodArticuloS20 BIT = 0,
            @hasCodDeposi      BIT = 0,
            @hasCodDeposito    BIT = 0,
            @hasFecha          BIT = 0,
            @hasFechaMov       BIT = 0,
            @hasCantidad       BIT = 0,
            @hasCant           BIT = 0,
            @hasTipoMov        BIT = 0,
            @hasPrecio         BIT = 0,
            @hasEstado         BIT = 0,
            @hasEstadoMov      BIT = 0,
            @hasCodArticuS11   BIT = 0,
            @hasCodArticuloS11 BIT = 0,
            @hasDescripcio     BIT = 0,
            @hasDescripcion    BIT = 0;

    IF OBJECT_ID(N'dbo.STA11', N'U') IS NOT NULL SET @hasSta11 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'COD_ARTICU')
        SET @hasCodArticuS20 = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'COD_ARTICULO')
        SET @hasCodArticuloS20 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'COD_DEPOSI')
        SET @hasCodDeposi = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'COD_DEPOSITO')
        SET @hasCodDeposito = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'FECHA')
        SET @hasFecha = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'FECHA_MOV')
        SET @hasFechaMov = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'CANTIDAD')
        SET @hasCantidad = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'CANT')
        SET @hasCant = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'TIPO_MOV')
        SET @hasTipoMov = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'PRECIO')
        SET @hasPrecio = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA14' AND COLUMN_NAME = 'ESTADO')
        SET @hasEstado = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA14' AND COLUMN_NAME = 'ESTADO_MOV')
        SET @hasEstadoMov = 1;
    IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA11' AND COLUMN_NAME = 'COD_ARTICU')
        SET @hasCodArticuS11 = 1;
    ELSE IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA11' AND COLUMN_NAME = 'COD_ARTICULO')
        SET @hasCodArticuloS11 = 1;
    IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA11' AND COLUMN_NAME = 'DESCRIPCIO')
        SET @hasDescripcio = 1;
    ELSE IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA11' AND COLUMN_NAME = 'DESCRIPCION')
        SET @hasDescripcion = 1;

    DECLARE @codArticuExpr NVARCHAR(MAX),
            @codDeposiExpr NVARCHAR(MAX),
            @fechaExpr     NVARCHAR(MAX),
            @cantExpr      NVARCHAR(MAX),
            @precioExpr    NVARCHAR(MAX),
            @saldoCase     NVARCHAR(MAX),
            @joinSta11     NVARCHAR(MAX),
            @articuloExpr  NVARCHAR(MAX),
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
        WHEN @hasFecha = 1 THEN N'COALESCE(sta20.FECHA, sta20.FECHA_MOV, sta14.FECHA_MOV)'
        WHEN @hasFechaMov = 1 THEN N'COALESCE(sta20.FECHA_MOV, sta14.FECHA_MOV)'
        ELSE N'sta14.FECHA_MOV'
    END;
    SET @cantExpr = CASE
        WHEN @hasCantidad = 1 THEN N'COALESCE(sta20.CANTIDAD, 0)'
        WHEN @hasCant = 1 THEN N'COALESCE(sta20.CANT, 0)'
        ELSE N'0'
    END;
    SET @precioExpr = CASE WHEN @hasPrecio = 1 THEN N'COALESCE(sta20.PRECIO, 0)' ELSE N'0' END;
    SET @saldoCase = CASE
        WHEN @hasTipoMov = 1
            THEN N'CASE UPPER(LTRIM(RTRIM(COALESCE(sta20.TIPO_MOV, ''''))))
                WHEN ''E'' THEN (' + @cantExpr + N')
                WHEN ''S'' THEN -(' + @cantExpr + N')
                ELSE 0
            END'
        ELSE @cantExpr
    END;
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
    SET @articuloExpr = CASE
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

    SET @where = @fechaExpr + N' <= @p_fr ' + @estadoExcl;
    IF @cod_articu IS NOT NULL AND @cod_articu <> N''
        SET @where += N' AND ' + @codArticuExpr + N' = @p_ca';
    IF @cod_deposi IS NOT NULL AND @cod_deposi <> N''
        SET @where += N' AND ' + @codDeposiExpr + N' = @p_cd';

    SET @having = CASE WHEN @ignorar_saldo_cero = 1
        THEN N'HAVING ABS(SUM(' + @saldoCase + N')) > 0.0001'
        ELSE N''
    END;

    SET @grouped = N'
        SELECT
            ' + @codArticuExpr + N' AS cod_articu,
            ' + @articuloExpr + N' AS articulo,
            ' + @codDeposiExpr + N' AS cod_deposi,
            CAST(ROUND(SUM(' + @saldoCase + N'), 4) AS DECIMAL(18,4)) AS stock_actual,
            CAST(ROUND(AVG(' + @precioExpr + N'), 4) AS DECIMAL(18,4)) AS precio_promedio,
            CAST(ROUND(SUM(' + @saldoCase + N') * AVG(' + @precioExpr + N'), 4) AS DECIMAL(18,4)) AS valor_total,
            @p_emp AS empresa
        FROM STA20 sta20
        INNER JOIN STA14 sta14 ON sta20.ID_STA14 = sta14.ID_STA14
        ' + @joinSta11 + N'
        WHERE ' + @where + N'
        GROUP BY ' + @codArticuExpr + N', ' + @codDeposiExpr + N'
        ' + @having;

    SET @sqlTotal = N'SELECT COUNT(*) AS total_filas FROM (' + @grouped + N') sub';

    EXEC sp_executesql @sqlTotal,
        N'@p_fr DATETIME, @p_ca NVARCHAR(20), @p_cd NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fr = @fecha_referencia, @p_ca = @cod_articu,
        @p_cd = @cod_deposi, @p_emp = @empresa;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;
    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT sub.cod_articu, sub.articulo, sub.cod_deposi,
               sub.stock_actual, sub.precio_promedio, sub.valor_total, sub.empresa
        FROM (' + @grouped + N') sub
        ORDER BY sub.cod_articu ASC, sub.cod_deposi ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fr DATETIME, @p_ca NVARCHAR(20), @p_cd NVARCHAR(20),
          @p_emp NVARCHAR(100), @p_offset INT, @p_page_size INT',
        @p_fr = @fecha_referencia, @p_ca = @cod_articu,
        @p_cd = @cod_deposi, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
