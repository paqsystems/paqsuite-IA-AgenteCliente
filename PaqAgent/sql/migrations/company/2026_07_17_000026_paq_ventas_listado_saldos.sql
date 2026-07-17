CREATE OR ALTER PROCEDURE dbo.PAQ_Ventas_ListadoSaldos
    @fecha_referencia   NVARCHAR(10),
    @ignorar_saldo_cero BIT           = 0,
    @cod_client         NVARCHAR(20)  = NULL,
    @vendedor           NVARCHAR(20)  = NULL,
    @zona               NVARCHAR(20)  = NULL,
    @rubro              NVARCHAR(20)  = NULL,
    @provincia          NVARCHAR(20)  = NULL,
    @empresa            NVARCHAR(100) = NULL,
    @page               INT           = 1,
    @page_size          INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    -- Detectar columnas/tablas opcionales
    DECLARE @hasImporteTot  BIT = 0,
            @hasGva15       BIT = 0,
            @hasIdentComp   BIT = 0,
            @hasDhExpr      NVARCHAR(50) = N'NULL',
            @hasAnulado     BIT = 0,
            @hasCodProvin   BIT = 0,
            @hasCodProvEnt  BIT = 0;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA12' AND COLUMN_NAME='IMPORTE_TOT')
        SET @hasImporteTot = 1;
    IF OBJECT_ID(N'dbo.GVA15', N'U') IS NOT NULL SET @hasGva15 = 1;
    IF @hasGva15=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA15' AND COLUMN_NAME='IDENT_COMP')
        SET @hasIdentComp = 1;
    IF @hasGva15=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA15' AND COLUMN_NAME='DEBHAB')
        SET @hasDhExpr = N'g15.DEBHAB';
    ELSE IF @hasGva15=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA15' AND COLUMN_NAME='D_H')
        SET @hasDhExpr = N'g15.D_H';
    ELSE IF @hasGva15=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA15' AND COLUMN_NAME='TIPO_COMP')
        SET @hasDhExpr = N'g15.TIPO_COMP';
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA12' AND COLUMN_NAME='ANULADO')
        SET @hasAnulado = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA14' AND COLUMN_NAME='COD_PROVIN')
        SET @hasCodProvin = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA14' AND COLUMN_NAME='COD_PROVINCIA_ENTREGA')
        SET @hasCodProvEnt = 1;

    -- Construir expresiones dinámicas
    DECLARE @importeExpr NVARCHAR(50),
            @joinGva15   NVARCHAR(200),
            @dhExpr      NVARCHAR(100),
            @saldoCase   NVARCHAR(500),
            @provCol     NVARCHAR(50);

    SET @importeExpr = CASE WHEN @hasImporteTot=1 THEN N'g12.IMPORTE_TOT' ELSE N'g12.IMPORTE' END;
    SET @joinGva15 = CASE
        WHEN @hasGva15=1 AND @hasIdentComp=1
            THEN N'LEFT JOIN GVA15 g15 ON g15.IDENT_COMP = g12.T_COMP'
        WHEN @hasGva15=1
            THEN N'LEFT JOIN GVA15 g15 ON g15.T_COMP = g12.T_COMP'
        ELSE N''
    END;
    SET @dhExpr = @hasDhExpr;
    SET @saldoCase = N'CASE
        WHEN g12.T_COMP = ''REC'' THEN -(' + @importeExpr + N')
        WHEN ' + @dhExpr + N' = ''D'' THEN (' + @importeExpr + N')
        ELSE -(' + @importeExpr + N')
    END';
    SET @provCol = CASE
        WHEN @hasCodProvin=1  THEN N'cl.COD_PROVIN'
        WHEN @hasCodProvEnt=1 THEN N'cl.COD_PROVINCIA_ENTREGA'
        ELSE NULL
    END;

    -- WHERE dinámico
    DECLARE @where NVARCHAR(2000) =
        N'g12.FECHA_EMIS <= CONVERT(DATETIME, @p_fr, 120)
          AND g12.COD_CLIENT <> ''***''
          AND g12.T_COMP <> ''ANU''
          AND (g12.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(g12.ESTADO))) NOT IN (''ANU'',''ANUL''))';

    IF @hasAnulado=1
        SET @where += N' AND (g12.ANULADO=0 OR g12.ANULADO IS NULL)';
    IF @cod_client IS NOT NULL AND @cod_client <> N''
        SET @where += N' AND g12.COD_CLIENT=@p_cc';
    IF @vendedor IS NOT NULL AND @vendedor <> N''
        SET @where += N' AND cl.COD_VENDED=@p_ve';
    IF @zona IS NOT NULL AND @zona <> N''
        SET @where += N' AND cl.VENT_ZONA=@p_zo';
    IF @rubro IS NOT NULL AND @rubro <> N''
        SET @where += N' AND cl.COD_RUBRO=@p_ru';
    IF @provincia IS NOT NULL AND @provincia <> N'' AND @provCol IS NOT NULL
        SET @where += N' AND ' + @provCol + N'=@p_pr';

    DECLARE @having NVARCHAR(100) = CASE
        WHEN @ignorar_saldo_cero=1
        THEN N'HAVING ABS(SUM(' + @saldoCase + N')) > 0.0001'
        ELSE N''
    END;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;

    DECLARE @grouped NVARCHAR(MAX) = N'
        SELECT
            g12.COD_CLIENT AS cod_client,
            cl.RAZON_SOCI  AS razon_soci,
            CAST(ROUND(SUM(' + @saldoCase + N'),2) AS DECIMAL(18,2)) AS saldo,
            @p_emp         AS empresa
        FROM GVA12 g12
        ' + @joinGva15 + N'
        INNER JOIN GVA14 cl ON g12.COD_CLIENT=cl.COD_CLIENT
        WHERE ' + @where + N'
        GROUP BY g12.COD_CLIENT, cl.RAZON_SOCI
        ' + @having;

    DECLARE @sqlTotal NVARCHAR(MAX) = N'
        SELECT
            COUNT(*) AS total_filas,
            CAST(ROUND(SUM(sub.saldo), 2) AS DECIMAL(18,2)) AS total_general
        FROM (' + @grouped + N') sub';

    EXEC sp_executesql @sqlTotal,
        N'@p_fr NVARCHAR(10), @p_cc NVARCHAR(20), @p_ve NVARCHAR(20),
          @p_zo NVARCHAR(20), @p_ru NVARCHAR(20), @p_pr NVARCHAR(20),
          @p_emp NVARCHAR(100)',
        @p_fr=@fecha_referencia, @p_cc=@cod_client, @p_ve=@vendedor,
        @p_zo=@zona, @p_ru=@rubro, @p_pr=@provincia, @p_emp=@empresa;

    DECLARE @offset INT = (@page - 1) * @page_size;
    DECLARE @sqlPaged NVARCHAR(MAX) = N'
        SELECT
            sub.cod_client,
            sub.razon_soci,
            sub.saldo,
            sub.empresa
        FROM (' + @grouped + N') sub
        ORDER BY sub.cod_client ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fr NVARCHAR(10), @p_cc NVARCHAR(20), @p_ve NVARCHAR(20),
          @p_zo NVARCHAR(20), @p_ru NVARCHAR(20), @p_pr NVARCHAR(20),
          @p_emp NVARCHAR(100), @p_offset INT, @p_page_size INT',
        @p_fr=@fecha_referencia, @p_cc=@cod_client, @p_ve=@vendedor,
        @p_zo=@zona, @p_ru=@rubro, @p_pr=@provincia, @p_emp=@empresa,
        @p_offset=@offset, @p_page_size=@page_size;
END
