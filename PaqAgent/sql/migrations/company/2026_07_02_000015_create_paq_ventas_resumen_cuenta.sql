CREATE OR ALTER PROCEDURE dbo.PAQ_Ventas_ResumenCuenta
    @fecha_desde  DATETIME,
    @fecha_hasta  DATETIME,
    @cod_client   NVARCHAR(20)  = NULL,
    @empresa      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasImporteTot BIT=0, @hasGva15 BIT=0,
            @hasIdentComp  BIT=0, @hasDescripcio BIT=0,
            @hasAnulado    BIT=0;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA12' AND COLUMN_NAME='IMPORTE_TOT')
        SET @hasImporteTot=1;
    IF OBJECT_ID(N'dbo.GVA15',N'U') IS NOT NULL SET @hasGva15=1;
    IF @hasGva15=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA15' AND COLUMN_NAME='IDENT_COMP')
        SET @hasIdentComp=1;
    IF @hasGva15=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA15' AND COLUMN_NAME='DESCRIPCIO')
        SET @hasDescripcio=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA12' AND COLUMN_NAME='ANULADO')
        SET @hasAnulado=1;

    DECLARE @importExpr  NVARCHAR(50),
            @joinGva15   NVARCHAR(200),
            @tipoDesc    NVARCHAR(100);

    SET @importExpr = CASE WHEN @hasImporteTot=1
        THEN N'g12.IMPORTE_TOT' ELSE N'g12.IMPORTE' END;
    SET @joinGva15 = CASE
        WHEN @hasGva15=1 AND @hasIdentComp=1
            THEN N'LEFT JOIN GVA15 g15 ON g15.IDENT_COMP=g12.T_COMP'
        WHEN @hasGva15=1
            THEN N'LEFT JOIN GVA15 g15 ON g15.T_COMP=g12.T_COMP'
        ELSE N''
    END;
    SET @tipoDesc = CASE WHEN @hasGva15=1 AND @hasDescripcio=1
        THEN N'g15.DESCRIPCIO' ELSE N'CAST('''' AS VARCHAR(1))' END;

    DECLARE @where NVARCHAR(1000) =
        N'g12.FECHA_EMIS BETWEEN @p_fd AND @p_fh
          AND g12.COD_CLIENT <> ''***''
          AND g12.T_COMP <> ''ANU''
          AND (g12.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(g12.ESTADO))) NOT IN (''ANU'',''ANUL''))';

    IF @hasAnulado=1
        SET @where += N' AND (g12.ANULADO=0 OR g12.ANULADO IS NULL)';
    IF @cod_client IS NOT NULL AND @cod_client <> N''
        SET @where += N' AND g12.COD_CLIENT=@p_cc';

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            g12.COD_CLIENT     AS cod_client,
            cl.RAZON_SOCI      AS razon_soci,
            g12.T_COMP         AS t_comp,
            MAX(' + @tipoDesc + N') AS tipo_descripcion,
            COUNT(*)           AS cantidad,
            CAST(ROUND(SUM(' + @importExpr + N'),2) AS DECIMAL(18,2)) AS total,
            @p_emp             AS empresa
        FROM GVA12 g12
        INNER JOIN GVA14 cl ON g12.COD_CLIENT=cl.COD_CLIENT
        ' + @joinGva15 + N'
        WHERE ' + @where + N'
        GROUP BY g12.COD_CLIENT, cl.RAZON_SOCI, g12.T_COMP';

    EXEC sp_executesql @sql,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_cc NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fd=@fecha_desde, @p_fh=@fecha_hasta,
        @p_cc=@cod_client, @p_emp=@empresa;
END
