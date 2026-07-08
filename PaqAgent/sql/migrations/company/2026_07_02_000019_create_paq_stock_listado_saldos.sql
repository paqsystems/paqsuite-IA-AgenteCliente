CREATE OR ALTER PROCEDURE dbo.PAQ_Stock_ListadoSaldos
    @fecha_referencia   DATETIME,
    @ignorar_saldo_cero BIT          = 0,
    @cod_articu         NVARCHAR(30) = NULL,
    @cod_deposi         NVARCHAR(20) = NULL,
    @empresa            NVARCHAR(100)= NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasSta11   BIT=0, @hasIdSta14  BIT=0,
            @hasDescSta11 BIT=0, @hasAnulado BIT=0;

    IF OBJECT_ID(N'dbo.STA11',N'U') IS NOT NULL SET @hasSta11=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='STA20' AND COLUMN_NAME='ID_STA14')
        SET @hasIdSta14=1;
    IF @hasSta11=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='STA11' AND COLUMN_NAME='DESCRIPCIO')
        SET @hasDescSta11=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='STA14' AND COLUMN_NAME='ANULADO')
        SET @hasAnulado=1;

    DECLARE @joinSta11  NVARCHAR(200),
            @descSelect NVARCHAR(200),
            @saldoCase  NVARCHAR(300),
            @estadoExcl NVARCHAR(200);

    SET @joinSta11 = CASE WHEN @hasSta11=1
        THEN N'LEFT JOIN STA11 sta11 ON sta20.COD_ARTICU=sta11.COD_ARTICU'
        ELSE N''
    END;
    SET @descSelect = CASE WHEN @hasDescSta11=1
        THEN N'MAX(sta11.DESCRIPCIO) AS descripcio'
        ELSE N'CAST('''' AS VARCHAR(1)) AS descripcio'
    END;
    SET @saldoCase = N'CASE UPPER(LTRIM(RTRIM(COALESCE(sta14.TIPO_MOV,''''))))
        WHEN ''E'' THEN  sta20.CANT_MOV
        WHEN ''S'' THEN -sta20.CANT_MOV
        ELSE 0 END';
    SET @estadoExcl = CASE WHEN @hasAnulado=1
        THEN N'AND (sta14.ANULADO=0 OR sta14.ANULADO IS NULL)'
        ELSE N''
    END;

    DECLARE @where NVARCHAR(500) =
        N'sta20.FECHA_MOV <= @p_fr
          AND (sta14.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(sta14.ESTADO))) <> ''ANU'')
          ' + @estadoExcl;

    IF @cod_articu IS NOT NULL AND @cod_articu <> N''
        SET @where += N' AND sta20.COD_ARTICU=@p_ca';
    IF @cod_deposi IS NOT NULL AND @cod_deposi <> N''
        SET @where += N' AND sta20.COD_DEPOSI=@p_cd';

    DECLARE @having NVARCHAR(100) = CASE WHEN @ignorar_saldo_cero=1
        THEN N'HAVING ABS(SUM(' + @saldoCase + N')) > 0.0001' ELSE N'' END;

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            sta20.COD_ARTICU AS cod_articu,
            ' + @descSelect + N',
            sta20.COD_DEPOSI AS cod_deposi,
            SUM(' + @saldoCase + N') AS saldo,
            @p_emp AS empresa
        FROM STA20 sta20
        INNER JOIN STA14 sta14 ON sta20.ID_STA14=sta14.ID_STA14
        ' + @joinSta11 + N'
        WHERE ' + @where + N'
        GROUP BY sta20.COD_ARTICU, sta20.COD_DEPOSI
        ' + @having;

    EXEC sp_executesql @sql,
        N'@p_fr DATETIME, @p_ca NVARCHAR(30), @p_cd NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fr=@fecha_referencia, @p_ca=@cod_articu,
        @p_cd=@cod_deposi, @p_emp=@empresa;
END
