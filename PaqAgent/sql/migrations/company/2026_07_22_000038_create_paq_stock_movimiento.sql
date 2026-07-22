CREATE OR ALTER PROCEDURE dbo.PAQ_Stock_Movimiento
    @fecha_desde  DATETIME,
    @fecha_hasta  DATETIME,
    @cod_articu   NVARCHAR(20)  = NULL,
    @cod_deposi   NVARCHAR(20)  = NULL,
    @tipo_mov     NVARCHAR(1)   = NULL,
    @empresa      NVARCHAR(100) = NULL,
    @page         INT           = 1,
    @page_size    INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.STA20', N'U') IS NULL
        OR OBJECT_ID(N'dbo.STA14', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS DATETIME)      AS fecha,
            CAST(NULL AS NVARCHAR(20))  AS cod_articu,
            CAST(NULL AS NVARCHAR(200)) AS articulo,
            CAST(NULL AS NVARCHAR(20))  AS cod_deposi,
            CAST(NULL AS NVARCHAR(1))   AS tipo_mov,
            CAST(NULL AS DECIMAL(18,4)) AS cantidad,
            CAST(NULL AS DECIMAL(18,4)) AS precio,
            CAST(NULL AS NVARCHAR(10))  AS t_comp,
            CAST(NULL AS NVARCHAR(20))  AS n_comp,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'ID_STA14')
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS DATETIME)      AS fecha,
            CAST(NULL AS NVARCHAR(20))  AS cod_articu,
            CAST(NULL AS NVARCHAR(200)) AS articulo,
            CAST(NULL AS NVARCHAR(20))  AS cod_deposi,
            CAST(NULL AS NVARCHAR(1))   AS tipo_mov,
            CAST(NULL AS DECIMAL(18,4)) AS cantidad,
            CAST(NULL AS DECIMAL(18,4)) AS precio,
            CAST(NULL AS NVARCHAR(10))  AS t_comp,
            CAST(NULL AS NVARCHAR(20))  AS n_comp,
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
            @hasTCompS20       BIT = 0,
            @hasNCompS20       BIT = 0,
            @hasEstado         BIT = 0,
            @hasEstadoMov      BIT = 0,
            @hasCodArticuS11   BIT = 0,
            @hasCodArticuloS11 BIT = 0,
            @hasDescripcio     BIT = 0,
            @hasDescripcion    BIT = 0,
            @hasIdSta11        BIT = 0;

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
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'T_COMP')
        SET @hasTCompS20 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA20' AND COLUMN_NAME = 'N_COMP')
        SET @hasNCompS20 = 1;
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
    IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STA11' AND COLUMN_NAME = 'ID_STA11')
        SET @hasIdSta11 = 1;

    DECLARE @codArticuExpr NVARCHAR(MAX),
            @codDeposiExpr NVARCHAR(MAX),
            @fechaExpr     NVARCHAR(MAX),
            @cantExpr      NVARCHAR(MAX),
            @precioExpr    NVARCHAR(MAX),
            @tCompExpr     NVARCHAR(MAX),
            @nCompExpr     NVARCHAR(MAX),
            @tipoMovExpr   NVARCHAR(MAX),
            @joinSta11     NVARCHAR(MAX),
            @articuloExpr  NVARCHAR(MAX),
            @estadoExcl    NVARCHAR(MAX),
            @where         NVARCHAR(MAX),
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
        WHEN @hasCantidad = 1 THEN N'sta20.CANTIDAD'
        WHEN @hasCant = 1 THEN N'sta20.CANT'
        ELSE N'0'
    END;
    SET @precioExpr = CASE WHEN @hasPrecio = 1 THEN N'COALESCE(sta20.PRECIO, 0)' ELSE N'0' END;
    SET @tipoMovExpr = CASE WHEN @hasTipoMov = 1 THEN N'sta20.TIPO_MOV' ELSE N'CAST(NULL AS NVARCHAR(1))' END;
    SET @tCompExpr = CASE
        WHEN @hasTCompS20 = 1
            THEN N'COALESCE(NULLIF(LTRIM(RTRIM(sta20.T_COMP)), ''''), sta14.T_COMP)'
        ELSE N'sta14.T_COMP'
    END;
    SET @nCompExpr = CASE
        WHEN @hasNCompS20 = 1
            THEN N'COALESCE(NULLIF(LTRIM(RTRIM(sta20.N_COMP)), ''''), sta14.N_COMP)'
        ELSE N'sta14.N_COMP'
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
        WHEN @joinSta11 <> N'' AND @hasDescripcio = 1 THEN N'sta11.DESCRIPCIO'
        WHEN @joinSta11 <> N'' AND @hasDescripcion = 1 THEN N'sta11.DESCRIPCION'
        ELSE N'CAST('''' AS NVARCHAR(200))'
    END;
    SET @estadoExcl = CASE
        WHEN @hasEstado = 1
            THEN N'AND (sta14.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(sta14.ESTADO))) <> ''A'')'
        WHEN @hasEstadoMov = 1
            THEN N'AND (sta14.ESTADO_MOV IS NULL OR UPPER(LTRIM(RTRIM(sta14.ESTADO_MOV))) <> ''A'')'
        ELSE N''
    END;

    SET @where = @fechaExpr + N' BETWEEN @p_fd AND @p_fh ' + @estadoExcl;
    IF @cod_articu IS NOT NULL AND @cod_articu <> N''
        SET @where += N' AND ' + @codArticuExpr + N' = @p_ca';
    IF @cod_deposi IS NOT NULL AND @cod_deposi <> N''
        SET @where += N' AND ' + @codDeposiExpr + N' = @p_cd';
    IF @tipo_mov IS NOT NULL AND @tipo_mov <> N'' AND @hasTipoMov = 1
        SET @where += N' AND sta20.TIPO_MOV = @p_tm';

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM STA20 sta20
        INNER JOIN STA14 sta14 ON sta20.ID_STA14 = sta14.ID_STA14
        ' + @joinSta11 + N'
        WHERE ' + @where;

    EXEC sp_executesql @sqlTotal,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_ca NVARCHAR(20), @p_cd NVARCHAR(20), @p_tm NVARCHAR(1)',
        @p_fd = @fecha_desde, @p_fh = @fecha_hasta,
        @p_ca = @cod_articu, @p_cd = @cod_deposi, @p_tm = @tipo_mov;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;
    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            ' + @fechaExpr + N' AS fecha,
            ' + @codArticuExpr + N' AS cod_articu,
            ' + @articuloExpr + N' AS articulo,
            ' + @codDeposiExpr + N' AS cod_deposi,
            ' + @tipoMovExpr + N' AS tipo_mov,
            ' + @cantExpr + N' AS cantidad,
            ' + @precioExpr + N' AS precio,
            ' + @tCompExpr + N' AS t_comp,
            ' + @nCompExpr + N' AS n_comp,
            @p_emp AS empresa
        FROM STA20 sta20
        INNER JOIN STA14 sta14 ON sta20.ID_STA14 = sta14.ID_STA14
        ' + @joinSta11 + N'
        WHERE ' + @where + N'
        ORDER BY ' + @fechaExpr + N' ASC, ' + @codArticuExpr + N' ASC, ' + @codDeposiExpr + N' ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_ca NVARCHAR(20), @p_cd NVARCHAR(20),
          @p_tm NVARCHAR(1), @p_emp NVARCHAR(100), @p_offset INT, @p_page_size INT',
        @p_fd = @fecha_desde, @p_fh = @fecha_hasta,
        @p_ca = @cod_articu, @p_cd = @cod_deposi, @p_tm = @tipo_mov,
        @p_emp = @empresa, @p_offset = @offset, @p_page_size = @page_size;
END
