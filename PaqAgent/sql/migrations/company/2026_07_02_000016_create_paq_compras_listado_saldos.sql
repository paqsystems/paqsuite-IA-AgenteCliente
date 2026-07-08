CREATE OR ALTER PROCEDURE dbo.PAQ_Compras_ListadoSaldos
    @fecha_referencia   DATETIME,
    @criterio_fecha     NVARCHAR(20)  = N'emision',
    @ignorar_saldo_cero BIT           = 0,
    @cod_provee         NVARCHAR(20)  = NULL,
    @comprador          NVARCHAR(20)  = NULL,
    @provincia          NVARCHAR(20)  = NULL,
    @empresa            NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasCpa21    BIT=0, @hasCpa01   BIT=0,
            @hasDebhab   BIT=0, @hasDh      BIT=0,
            @hasAnulado  BIT=0, @hasRazon   BIT=0,
            @hasComprador NVARCHAR(50) = NULL;

    IF OBJECT_ID(N'dbo.CPA21',N'U') IS NOT NULL SET @hasCpa21=1;
    IF OBJECT_ID(N'dbo.CPA01',N'U') IS NOT NULL SET @hasCpa01=1;
    IF @hasCpa21=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA21' AND COLUMN_NAME='DEBHAB')
        SET @hasDebhab=1;
    IF @hasCpa21=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA21' AND COLUMN_NAME='D_H') AND @hasDebhab=0
        SET @hasDh=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA04' AND COLUMN_NAME='ANULADO')
        SET @hasAnulado=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA04' AND COLUMN_NAME='RAZON_SOCI')
        SET @hasRazon=1;
    -- Detectar columna comprador
    IF @hasCpa01=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA01' AND COLUMN_NAME='COD_COMPRADOR')
        SET @hasComprador = N'p.COD_COMPRADOR';
    ELSE IF @hasCpa01=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA01' AND COLUMN_NAME='COD_COMPRAD')
        SET @hasComprador = N'p.COD_COMPRAD';

    DECLARE @fechaExpr NVARCHAR(100),
            @joinCpa21 NVARCHAR(100),
            @dhExpr    NVARCHAR(100),
            @saldoCase NVARCHAR(500),
            @joinCpa01 NVARCHAR(100),
            @razonExpr NVARCHAR(200);

    SET @fechaExpr = CASE WHEN @criterio_fecha=N'contable'
        THEN N'COALESCE(c.FECHA_CONT,c.FECHA_EMIS)' ELSE N'c.FECHA_EMIS' END;
    SET @joinCpa21 = CASE WHEN @hasCpa21=1
        THEN N'LEFT JOIN CPA21 c21 ON c21.T_COMP=c.T_COMP' ELSE N'' END;
    SET @dhExpr = CASE
        WHEN @hasDebhab=1 THEN N'c21.DEBHAB'
        WHEN @hasDh=1     THEN N'c21.D_H'
        ELSE N'CAST(NULL AS VARCHAR(1))'
    END;
    SET @saldoCase = N'CASE
        WHEN c.T_COMP IN (''FAC'',''LIQ'') THEN c.IMPORTE_TO
        WHEN c.T_COMP IN (''O/P'',''OP'')  THEN -c.IMPORTE_TO
        WHEN ' + @dhExpr + N' = ''H''       THEN c.IMPORTE_TO
        ELSE -c.IMPORTE_TO
    END';
    SET @joinCpa01 = CASE WHEN @hasCpa01=1
        THEN N'LEFT JOIN CPA01 p ON p.COD_PROVEE=c.COD_PROVEE' ELSE N'' END;
    SET @razonExpr = CASE
        WHEN @hasRazon=1 AND @hasCpa01=1
            THEN N'COALESCE(NULLIF(LTRIM(RTRIM(c.RAZON_SOCI)),''''),p.NOM_PROVEE)'
        WHEN @hasCpa01=1 THEN N'p.NOM_PROVEE'
        WHEN @hasRazon=1 THEN N'c.RAZON_SOCI'
        ELSE N''''''
    END;

    DECLARE @where NVARCHAR(1000) =
        N'' + @fechaExpr + N' <= @p_fr
          AND c.COD_PROVEE <> ''***''
          AND (c.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(c.ESTADO))) NOT IN (''ANU'',''ANUL''))';

    IF @hasAnulado=1
        SET @where += N' AND (c.ANULADO=0 OR c.ANULADO IS NULL)';
    IF @cod_provee IS NOT NULL AND @cod_provee <> N''
        SET @where += N' AND c.COD_PROVEE=@p_cp';
    IF @provincia IS NOT NULL AND @provincia <> N'' AND @hasCpa01=1
        SET @where += N' AND p.PROVINCIA=@p_pr';
    IF @comprador IS NOT NULL AND @comprador <> N'' AND @hasComprador IS NOT NULL
        SET @where += N' AND ' + @hasComprador + N'=@p_co';

    DECLARE @having NVARCHAR(100) = CASE WHEN @ignorar_saldo_cero=1
        THEN N'HAVING ABS(SUM(' + @saldoCase + N')) > 0.0001' ELSE N'' END;

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            c.COD_PROVEE AS cod_provee,
            MAX(' + @razonExpr + N') AS razon_soci,
            CAST(ROUND(SUM(' + @saldoCase + N'),2) AS DECIMAL(18,2)) AS saldo,
            @p_emp AS empresa
        FROM CPA04 c
        ' + @joinCpa21 + N'
        ' + @joinCpa01 + N'
        WHERE ' + @where + N'
        GROUP BY c.COD_PROVEE
        ' + @having;

    EXEC sp_executesql @sql,
        N'@p_fr DATETIME, @p_cp NVARCHAR(20), @p_pr NVARCHAR(20),
          @p_co NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fr=@fecha_referencia, @p_cp=@cod_provee,
        @p_pr=@provincia, @p_co=@comprador, @p_emp=@empresa;
END
