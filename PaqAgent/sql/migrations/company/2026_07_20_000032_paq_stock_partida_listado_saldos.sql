CREATE OR ALTER PROCEDURE dbo.PAQ_Stock_PartidaListadoSaldos
    @fecha_referencia   NVARCHAR(10),
    @ignorar_saldo_cero BIT           = 0,
    @cod_articu         NVARCHAR(20)  = NULL,
    @cod_deposi         NVARCHAR(20)  = NULL,
    @nro_parti          NVARCHAR(30)  = NULL,
    @empresa            NVARCHAR(100) = NULL,
    @page               INT           = 1,
    @page_size          INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasSta09 BIT = 0,
            @hasSta20 BIT = 0,
            @hasSta14 BIT = 0,
            @hasSta11 BIT = 0;

    IF OBJECT_ID(N'dbo.STA09', N'U') IS NOT NULL SET @hasSta09 = 1;
    IF OBJECT_ID(N'dbo.STA20', N'U') IS NOT NULL SET @hasSta20 = 1;
    IF OBJECT_ID(N'dbo.STA14', N'U') IS NOT NULL SET @hasSta14 = 1;
    IF OBJECT_ID(N'dbo.STA11', N'U') IS NOT NULL SET @hasSta11 = 1;

    IF @hasSta09 = 0 OR @hasSta20 = 0 OR @hasSta14 = 0
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(20)) AS cod_articu,
            CAST(NULL AS NVARCHAR(200)) AS articulo,
            CAST(NULL AS NVARCHAR(20)) AS cod_deposi,
            CAST(NULL AS NVARCHAR(30)) AS nro_parti,
            CAST(NULL AS DECIMAL(18, 2)) AS saldo,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasNroParti       BIT = 0,
            @hasNroPartida     BIT = 0,
            @hasPartida        BIT = 0,
            @hasCodArticuS09   BIT = 0,
            @hasCodArticuloS09 BIT = 0,
            @hasCodDeposiS09   BIT = 0,
            @hasCodDepositoS09 BIT = 0,
            @hasIdSta09        BIT = 0,
            @hasIdSta09S20     BIT = 0,
            @hasCodPartiS20    BIT = 0,
            @hasIdSta14        BIT = 0,
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
            @hasDescripcion    BIT = 0,
            @hasIdSta11        BIT = 0;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA09' AND COLUMN_NAME = N'NRO_PARTI')
        SET @hasNroParti = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA09' AND COLUMN_NAME = N'NRO_PARTIDA')
        SET @hasNroPartida = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA09' AND COLUMN_NAME = N'PARTIDA')
        SET @hasPartida = 1;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA09' AND COLUMN_NAME = N'COD_ARTICU')
        SET @hasCodArticuS09 = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA09' AND COLUMN_NAME = N'COD_ARTICULO')
        SET @hasCodArticuloS09 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA09' AND COLUMN_NAME = N'COD_DEPOSI')
        SET @hasCodDeposiS09 = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA09' AND COLUMN_NAME = N'COD_DEPOSITO')
        SET @hasCodDepositoS09 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA09' AND COLUMN_NAME = N'ID_STA09')
        SET @hasIdSta09 = 1;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'ID_STA09')
        SET @hasIdSta09S20 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'COD_PARTI')
        SET @hasCodPartiS20 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA20' AND COLUMN_NAME = N'ID_STA14')
        SET @hasIdSta14 = 1;
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
    IF @hasSta11 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'STA11' AND COLUMN_NAME = N'ID_STA11')
        SET @hasIdSta11 = 1;

    DECLARE @nroPartiCol NVARCHAR(MAX) = CASE
        WHEN @hasNroParti = 1 THEN N'sta09.NRO_PARTI'
        WHEN @hasNroPartida = 1 THEN N'sta09.NRO_PARTIDA'
        WHEN @hasPartida = 1 THEN N'sta09.PARTIDA'
        ELSE NULL
    END;

    DECLARE @joinSta20 NVARCHAR(MAX) = CASE
        WHEN @hasIdSta09S20 = 1 AND @hasIdSta09 = 1
            THEN N'INNER JOIN STA20 sta20 ON sta20.ID_STA09 = sta09.ID_STA09'
        WHEN @hasCodPartiS20 = 1 AND @nroPartiCol IS NOT NULL
            THEN N'INNER JOIN STA20 sta20 ON sta20.COD_PARTI = ' + @nroPartiCol
        ELSE NULL
    END;

    IF @joinSta20 IS NULL OR @hasIdSta14 = 0 OR @nroPartiCol IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(20)) AS cod_articu,
            CAST(NULL AS NVARCHAR(200)) AS articulo,
            CAST(NULL AS NVARCHAR(20)) AS cod_deposi,
            CAST(NULL AS NVARCHAR(30)) AS nro_parti,
            CAST(NULL AS DECIMAL(18, 2)) AS saldo,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @codArticuExpr NVARCHAR(MAX),
            @codDeposiExpr NVARCHAR(MAX),
            @nroPartiExpr  NVARCHAR(MAX),
            @fechaExpr     NVARCHAR(MAX),
            @cantExpr      NVARCHAR(MAX),
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
        WHEN @hasCodArticuS09 = 1 THEN N'sta09.COD_ARTICU'
        WHEN @hasCodArticuloS09 = 1 THEN N'sta09.COD_ARTICULO'
        ELSE N'CAST(NULL AS NVARCHAR(20))'
    END;

    SET @codDeposiExpr = CASE
        WHEN @hasCodDeposiS09 = 1 THEN N'sta09.COD_DEPOSI'
        WHEN @hasCodDepositoS09 = 1 THEN N'sta09.COD_DEPOSITO'
        ELSE N'CAST(NULL AS NVARCHAR(20))'
    END;

    SET @nroPartiExpr = @nroPartiCol;

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
        WHEN @hasSta11 = 1 AND @hasCodArticuS11 = 1 AND @hasCodArticuS09 = 1
            THEN N'LEFT JOIN STA11 sta11 ON sta09.COD_ARTICU = sta11.COD_ARTICU'
        WHEN @hasSta11 = 1 AND @hasCodArticuloS11 = 1 AND @hasCodArticuloS09 = 1
            THEN N'LEFT JOIN STA11 sta11 ON sta09.COD_ARTICULO = sta11.COD_ARTICULO'
        WHEN @hasSta11 = 1 AND @hasCodArticuS11 = 1 AND @hasCodArticuloS09 = 1
            THEN N'LEFT JOIN STA11 sta11 ON sta09.COD_ARTICULO = sta11.COD_ARTICU'
        WHEN @hasSta11 = 1 AND @hasCodArticuloS11 = 1 AND @hasCodArticuS09 = 1
            THEN N'LEFT JOIN STA11 sta11 ON sta09.COD_ARTICU = sta11.COD_ARTICULO'
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

    SET @where =
        @fechaExpr + N' <= CONVERT(DATETIME, @p_fr, 120)
          ' + @estadoExcl;

    IF @cod_articu IS NOT NULL AND @cod_articu <> N''
        SET @where += N' AND ' + @codArticuExpr + N' = @p_ca';

    IF @cod_deposi IS NOT NULL AND @cod_deposi <> N''
        SET @where += N' AND ' + @codDeposiExpr + N' = @p_cd';

    IF @nro_parti IS NOT NULL AND @nro_parti <> N''
        SET @where += N' AND ' + @nroPartiExpr + N' = @p_np';

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
            ' + @articuloExpr + N' AS articulo,
            ' + @codDeposiExpr + N' AS cod_deposi,
            ' + @nroPartiExpr + N' AS nro_parti,
            CAST(ROUND(SUM(' + @saldoCase + N'), 2) AS DECIMAL(18, 2)) AS saldo,
            @p_emp AS empresa
        FROM STA09 sta09
        ' + @joinSta20 + N'
        INNER JOIN STA14 sta14 ON sta20.ID_STA14 = sta14.ID_STA14
        ' + @joinSta11 + N'
        WHERE ' + @where + N'
        GROUP BY ' + @codArticuExpr + N', ' + @codDeposiExpr + N', ' + @nroPartiExpr + N'
        ' + @having;

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM (' + @grouped + N') sub';

    EXEC sp_executesql @sqlTotal,
        N'@p_fr NVARCHAR(10), @p_ca NVARCHAR(20), @p_cd NVARCHAR(20),
          @p_np NVARCHAR(30), @p_emp NVARCHAR(100)',
        @p_fr = @fecha_referencia, @p_ca = @cod_articu,
        @p_cd = @cod_deposi, @p_np = @nro_parti, @p_emp = @empresa;

    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            sub.cod_articu,
            sub.articulo,
            sub.cod_deposi,
            sub.nro_parti,
            sub.saldo,
            sub.empresa
        FROM (' + @grouped + N') sub
        ORDER BY sub.cod_articu ASC, sub.cod_deposi ASC, sub.nro_parti ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fr NVARCHAR(10), @p_ca NVARCHAR(20), @p_cd NVARCHAR(20),
          @p_np NVARCHAR(30), @p_emp NVARCHAR(100), @p_offset INT, @p_page_size INT',
        @p_fr = @fecha_referencia, @p_ca = @cod_articu,
        @p_cd = @cod_deposi, @p_np = @nro_parti, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
