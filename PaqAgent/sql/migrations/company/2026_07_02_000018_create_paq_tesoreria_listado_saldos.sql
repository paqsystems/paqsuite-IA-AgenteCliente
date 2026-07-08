CREATE OR ALTER PROCEDURE dbo.PAQ_Tesoreria_ListadoSaldos
    @fecha_referencia   DATETIME,
    @ignorar_saldo_cero BIT          = 0,
    @cod_cuen           NVARCHAR(50) = NULL,
    @tipo_cuenta        NVARCHAR(20) = NULL,
    @empresa            NVARCHAR(100)= NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasMonto   BIT=0, @hasIdSba01  BIT=0,
            @hasSba01   BIT=0, @hasCodCta   BIT=0,
            @hasTipo    BIT=0;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='SBA05' AND COLUMN_NAME='MONTO')
        SET @hasMonto=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='SBA05' AND COLUMN_NAME='ID_SBA01')
        SET @hasIdSba01=1;
    IF OBJECT_ID(N'dbo.SBA01',N'U') IS NOT NULL SET @hasSba01=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='SBA05' AND COLUMN_NAME='COD_CTA')
        SET @hasCodCta=1;
    IF @hasSba01=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='SBA01' AND COLUMN_NAME='TIPO')
        SET @hasTipo=1;

    DECLARE @montoExpr  NVARCHAR(100),
            @saldoCase  NVARCHAR(300),
            @joinSba01  NVARCHAR(200),
            @codExpr    NVARCHAR(100),
            @descExpr   NVARCHAR(200);

    SET @montoExpr = CASE WHEN @hasMonto=1
        THEN N'COALESCE(s.MONTO,0)' ELSE N'0' END;
    SET @saldoCase = N'CASE UPPER(LTRIM(RTRIM(COALESCE(s.D_H,''''))))
        WHEN ''D'' THEN  ' + @montoExpr + N'
        WHEN ''H'' THEN -' + @montoExpr + N'
        ELSE 0 END';
    SET @joinSba01 = CASE WHEN @hasIdSba01=1 AND @hasSba01=1
        THEN N'LEFT JOIN SBA01 s1 ON s.ID_SBA01=s1.ID_SBA01'
        ELSE N''
    END;
    SET @codExpr = CASE WHEN @hasCodCta=1
        THEN N's.COD_CTA' ELSE N'CAST(s.ID_SBA01 AS NVARCHAR(50))' END;
    SET @descExpr = CASE WHEN @hasSba01=1
        THEN N'COALESCE(s1.DESCRIPCIO,s1.NOM_CUENTA,CAST(' + @codExpr + N' AS VARCHAR(50)))'
        ELSE N'CAST(' + @codExpr + N' AS VARCHAR(50))' END;

    DECLARE @where NVARCHAR(500) = N's.FECHA <= @p_fr';

    IF @cod_cuen IS NOT NULL AND @cod_cuen <> N''
        SET @where += N' AND ' + @codExpr + N'=@p_cc';
    IF @tipo_cuenta IS NOT NULL AND @tipo_cuenta <> N'' AND @hasTipo=1
        SET @where += N' AND s1.TIPO=@p_tp';

    DECLARE @having NVARCHAR(100) = CASE WHEN @ignorar_saldo_cero=1
        THEN N'HAVING ABS(SUM(' + @saldoCase + N')) > 0.0001' ELSE N'' END;

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            ' + @codExpr  + N' AS cod_cuen,
            MAX(' + @descExpr + N') AS descripcio,
            CAST(ROUND(SUM(' + @saldoCase + N'),2) AS DECIMAL(18,2)) AS saldo,
            @p_emp AS empresa
        FROM SBA05 s
        ' + @joinSba01 + N'
        WHERE ' + @where + N'
        GROUP BY ' + @codExpr + N'
        ' + @having;

    EXEC sp_executesql @sql,
        N'@p_fr DATETIME, @p_cc NVARCHAR(50), @p_tp NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fr=@fecha_referencia, @p_cc=@cod_cuen,
        @p_tp=@tipo_cuenta, @p_emp=@empresa;
END
