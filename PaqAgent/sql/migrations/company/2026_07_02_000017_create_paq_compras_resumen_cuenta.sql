CREATE OR ALTER PROCEDURE dbo.PAQ_Compras_ResumenCuenta
    @fecha_desde  DATETIME,
    @fecha_hasta  DATETIME,
    @cod_provee   NVARCHAR(20)  = NULL,
    @empresa      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasCpa21      BIT=0, @hasIdentComp BIT=0,
            @hasDescripcio BIT=0, @hasDescComp  BIT=0,
            @hasImporteTo  BIT=0, @hasImporte   BIT=0,
            @hasNomProvee  BIT=0, @hasAnulado   BIT=0;

    IF OBJECT_ID(N'dbo.CPA21',N'U') IS NOT NULL SET @hasCpa21=1;
    IF @hasCpa21=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA21' AND COLUMN_NAME='IDENT_COMP')
        SET @hasIdentComp=1;
    IF @hasCpa21=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA21' AND COLUMN_NAME='DESCRIPCIO')
        SET @hasDescripcio=1;
    IF @hasCpa21=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA21' AND COLUMN_NAME='DESC_COMP') AND @hasDescripcio=0
        SET @hasDescComp=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA04' AND COLUMN_NAME='IMPORTE_TO')
        SET @hasImporteTo=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA04' AND COLUMN_NAME='IMPORTE') AND @hasImporteTo=0
        SET @hasImporte=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA01' AND COLUMN_NAME='NOM_PROVEE')
        SET @hasNomProvee=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='CPA04' AND COLUMN_NAME='ANULADO')
        SET @hasAnulado=1;

    DECLARE @importExpr  NVARCHAR(50),
            @joinC21     NVARCHAR(200),
            @tipoDesc    NVARCHAR(100),
            @razonExpr   NVARCHAR(100);

    SET @importExpr = CASE
        WHEN @hasImporteTo=1 THEN N'c.IMPORTE_TO'
        WHEN @hasImporte=1   THEN N'c.IMPORTE'
        ELSE N'0'
    END;
    SET @joinC21 = CASE
        WHEN @hasCpa21=1 AND @hasIdentComp=1
            THEN N'LEFT JOIN CPA21 c21 ON c21.IDENT_COMP=c.T_COMP'
        WHEN @hasCpa21=1
            THEN N'LEFT JOIN CPA21 c21 ON c21.T_COMP=c.T_COMP'
        ELSE N''
    END;
    SET @tipoDesc = CASE
        WHEN @hasDescripcio=1 THEN N'c21.DESCRIPCIO'
        WHEN @hasDescComp=1   THEN N'c21.DESC_COMP'
        ELSE N'CAST('''' AS VARCHAR(1))'
    END;
    SET @razonExpr = CASE WHEN @hasNomProvee=1
        THEN N'p.NOM_PROVEE' ELSE N'CAST('''' AS VARCHAR(1))' END;

    DECLARE @where NVARCHAR(500) =
        N'c.FECHA_EMIS BETWEEN @p_fd AND @p_fh
          AND c.COD_PROVEE <> ''***''
          AND (c.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(c.ESTADO))) NOT IN (''ANU'',''ANUL''))';

    IF @hasAnulado=1
        SET @where += N' AND (c.ANULADO=0 OR c.ANULADO IS NULL)';
    IF @cod_provee IS NOT NULL AND @cod_provee <> N''
        SET @where += N' AND c.COD_PROVEE=@p_cp';

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            c.COD_PROVEE  AS cod_provee,
            MAX(' + @razonExpr + N') AS razon_soci,
            c.T_COMP      AS t_comp,
            MAX(' + @tipoDesc + N') AS tipo_descripcion,
            COUNT(*)      AS cantidad,
            CAST(ROUND(SUM(' + @importExpr + N'),2) AS DECIMAL(18,2)) AS total,
            @p_emp        AS empresa
        FROM CPA04 c
        INNER JOIN CPA01 p ON c.COD_PROVEE=p.COD_PROVEE
        ' + @joinC21 + N'
        WHERE ' + @where + N'
        GROUP BY c.COD_PROVEE, c.T_COMP';

    EXEC sp_executesql @sql,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_cp NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fd=@fecha_desde, @p_fh=@fecha_hasta,
        @p_cp=@cod_provee, @p_emp=@empresa;
END
