CREATE OR ALTER PROCEDURE dbo.PAQ_Ventas_IvaVentas
    @fecha_desde  DATETIME,
    @fecha_hasta  DATETIME,
    @empresa      NVARCHAR(100) = NULL,
    @page         INT           = 1,
    @page_size    INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.GVA12', N'U') IS NULL
        OR OBJECT_ID(N'dbo.GVA14', N'U') IS NULL
        OR OBJECT_ID(N'dbo.GVA15', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS DATETIME)      AS fecha_emis,
            CAST(NULL AS NVARCHAR(10))  AS t_comp,
            CAST(NULL AS NVARCHAR(20))  AS n_comp,
            CAST(NULL AS NVARCHAR(20))  AS cod_client,
            CAST(NULL AS NVARCHAR(200)) AS razon_soci,
            CAST(NULL AS NVARCHAR(50))  AS iva,
            CAST(NULL AS DECIMAL(18,2)) AS neto,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasImporteTot  BIT = 0,
            @hasIdentComp   BIT = 0,
            @hasIvaVtas     BIT = 0,
            @hasAnulado     BIT = 0;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'GVA12' AND COLUMN_NAME = 'IMPORTE_TOT')
        SET @hasImporteTot = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'GVA15' AND COLUMN_NAME = 'IDENT_COMP')
        SET @hasIdentComp = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'GVA15' AND COLUMN_NAME = 'IVA_VTAS')
        SET @hasIvaVtas = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'GVA12' AND COLUMN_NAME = 'ANULADO')
        SET @hasAnulado = 1;

    DECLARE @importNeto NVARCHAR(MAX),
            @joinGva15  NVARCHAR(MAX),
            @ivaCol     NVARCHAR(MAX),
            @where      NVARCHAR(MAX),
            @sqlTotal   NVARCHAR(MAX),
            @sqlPaged   NVARCHAR(MAX);

    SET @importNeto = CASE WHEN @hasImporteTot = 1
        THEN N'g12.IMPORTE_TOT' ELSE N'g12.IMPORTE' END;

    SET @joinGva15 = CASE WHEN @hasIdentComp = 1
        THEN N'INNER JOIN GVA15 g15 ON g15.IDENT_COMP = g12.T_COMP'
        ELSE N'INNER JOIN GVA15 g15 ON g15.T_COMP = g12.T_COMP'
    END;

    SET @ivaCol = CASE WHEN @hasIvaVtas = 1
        THEN N'g15.IVA_VTAS' ELSE N'CAST('''' AS VARCHAR(1))' END;

    SET @where =
        N'g12.FECHA_EMIS BETWEEN @p_fd AND @p_fh
          AND g12.T_COMP <> ''REC''
          AND g12.T_COMP <> ''ANU''
          AND (g12.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(g12.ESTADO))) NOT IN (''ANU'',''ANUL''))';

    IF @hasAnulado = 1
        SET @where += N' AND (g12.ANULADO = 0 OR g12.ANULADO IS NULL)';

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM GVA12 g12
        INNER JOIN GVA14 cl ON g12.COD_CLIENT = cl.COD_CLIENT
        ' + @joinGva15 + N'
        WHERE ' + @where;

    EXEC sp_executesql @sqlTotal,
        N'@p_fd DATETIME, @p_fh DATETIME',
        @p_fd = @fecha_desde, @p_fh = @fecha_hasta;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;
    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            g12.FECHA_EMIS AS fecha_emis,
            g12.T_COMP     AS t_comp,
            g12.N_COMP     AS n_comp,
            g12.COD_CLIENT AS cod_client,
            cl.RAZON_SOCI  AS razon_soci,
            ' + @ivaCol + N' AS iva,
            CAST(ROUND(COALESCE(' + @importNeto + N', 0), 2) AS DECIMAL(18,2)) AS neto,
            @p_emp AS empresa
        FROM GVA12 g12
        INNER JOIN GVA14 cl ON g12.COD_CLIENT = cl.COD_CLIENT
        ' + @joinGva15 + N'
        WHERE ' + @where + N'
        ORDER BY g12.FECHA_EMIS DESC, g12.N_COMP ASC
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_emp NVARCHAR(100),
          @p_offset INT, @p_page_size INT',
        @p_fd = @fecha_desde, @p_fh = @fecha_hasta, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
