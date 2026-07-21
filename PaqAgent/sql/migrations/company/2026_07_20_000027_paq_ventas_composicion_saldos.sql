CREATE OR ALTER PROCEDURE dbo.PAQ_Ventas_ComposicionSaldos
    @fecha_referencia NVARCHAR(10),
    @cod_client       NVARCHAR(20)  = NULL,
    @empresa          NVARCHAR(100) = NULL,
    @sort             NVARCHAR(50)  = N'fecha_emis',
    @sort_dir         NVARCHAR(4)   = N'desc',
    @page             INT           = 1,
    @page_size        INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasGva46      BIT = 0,
            @hasGva07      BIT = 0,
            @hasImporteTot BIT = 0,
            @hasAnulado    BIT = 0,
            @hasImporteVt  BIT = 0;

    IF OBJECT_ID(N'dbo.GVA46', N'U') IS NOT NULL SET @hasGva46 = 1;
    IF OBJECT_ID(N'dbo.GVA07', N'U') IS NOT NULL SET @hasGva07 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'GVA12' AND COLUMN_NAME = N'IMPORTE_TOT')
        SET @hasImporteTot = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'GVA12' AND COLUMN_NAME = N'ANULADO')
        SET @hasAnulado = 1;
    IF @hasGva46 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'GVA46' AND COLUMN_NAME = N'IMPORTE_VT')
        SET @hasImporteVt = 1;

    DECLARE @importeCab       NVARCHAR(MAX),
            @joinGva46        NVARCHAR(MAX),
            @fechaVtoExpr     NVARCHAR(MAX),
            @importeCuotaExpr NVARCHAR(MAX),
            @cancelSql        NVARCHAR(MAX),
            @saldoExpr        NVARCHAR(MAX),
            @where            NVARCHAR(MAX),
            @baseSelect       NVARCHAR(MAX),
            @orderCol         NVARCHAR(MAX),
            @orderDir         NVARCHAR(MAX),
            @sqlTotal         NVARCHAR(MAX),
            @sqlPaged         NVARCHAR(MAX);

    SET @importeCab = CASE
        WHEN @hasImporteTot = 1 THEN N'c.IMPORTE_TOT'
        ELSE N'c.IMPORTE'
    END;

    SET @joinGva46 = CASE
        WHEN @hasGva46 = 1
            THEN N'LEFT JOIN GVA46 g46 ON c.T_COMP = g46.T_COMP AND c.N_COMP = g46.N_COMP'
        ELSE N''
    END;

    SET @fechaVtoExpr = CASE
        WHEN @hasGva46 = 1 THEN N'COALESCE(g46.FECHA_VTO, c.FECHA_EMIS)'
        ELSE N'c.FECHA_EMIS'
    END;

    SET @importeCuotaExpr = CASE
        WHEN @hasGva46 = 1 AND @hasImporteVt = 1
            THEN N'ISNULL(g46.IMPORTE_VT, ' + @importeCab + N')'
        WHEN @hasGva46 = 1
            THEN @importeCab
        ELSE @importeCab
    END;

    SET @cancelSql = CASE
        WHEN @hasGva07 = 1 AND @hasGva46 = 1 THEN
            N'ISNULL((SELECT SUM(j.IMPORT_CAN) FROM GVA07 j
              WHERE j.T_COMP = g46.T_COMP AND j.N_COMP = g46.N_COMP
              AND (j.FECHA_VTO = g46.FECHA_VTO
                   OR (j.FECHA_VTO IS NULL AND g46.FECHA_VTO IS NULL))), 0)'
        WHEN @hasGva07 = 1 THEN
            N'ISNULL((SELECT SUM(j.IMPORT_CAN) FROM GVA07 j
              WHERE j.T_COMP = c.T_COMP AND j.N_COMP = c.N_COMP), 0)'
        ELSE N'0'
    END;

    SET @saldoExpr = N'(' + @importeCuotaExpr + N' - ' + @cancelSql + N')';

    SET @where =
        N'c.FECHA_EMIS <= CONVERT(DATETIME, @p_fr, 120)
          AND c.COD_CLIENT <> ''***''
          AND c.T_COMP <> ''ANU''
          AND (c.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(c.ESTADO))) NOT IN (''ANU'',''ANUL''))
          AND ' + @saldoExpr + N' <> 0';

    IF @hasAnulado = 1
        SET @where += N' AND (c.ANULADO = 0 OR c.ANULADO IS NULL)';

    IF @cod_client IS NOT NULL AND @cod_client <> N''
        SET @where += N' AND c.COD_CLIENT = @p_cc';

    SET @orderCol = CASE LOWER(LTRIM(RTRIM(ISNULL(@sort, N''))))
        WHEN N'cod_client' THEN N'cod_client'
        WHEN N'razon_soci' THEN N'razon_soci'
        WHEN N't_comp' THEN N't_comp'
        WHEN N'n_comp' THEN N'n_comp'
        WHEN N'fecha_emis' THEN N'fecha_emis'
        WHEN N'fecha_vencimiento' THEN N'fecha_vencimiento'
        WHEN N'importe_cuota' THEN N'importe_cuota'
        WHEN N'saldo_cuota' THEN N'saldo_cuota'
        WHEN N'empresa' THEN N'empresa'
        ELSE N'fecha_emis'
    END;

    SET @orderDir = CASE
        WHEN LOWER(LTRIM(RTRIM(ISNULL(@sort_dir, N'')))) = N'asc' THEN N'ASC'
        ELSE N'DESC'
    END;

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;

    SET @baseSelect = N'
        SELECT
            c.COD_CLIENT AS cod_client,
            cl.RAZON_SOCI AS razon_soci,
            c.T_COMP AS t_comp,
            c.N_COMP AS n_comp,
            c.FECHA_EMIS AS fecha_emis,
            ' + @fechaVtoExpr + N' AS fecha_vencimiento,
            CAST(ROUND(' + @importeCuotaExpr + N', 2) AS DECIMAL(18,2)) AS importe_cuota,
            CAST(ROUND(' + @saldoExpr + N', 2) AS DECIMAL(18,2)) AS saldo_cuota,
            @p_emp AS empresa
        FROM GVA12 c
        INNER JOIN GVA14 cl ON c.COD_CLIENT = cl.COD_CLIENT
        ' + @joinGva46 + N'
        WHERE ' + @where;

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM (' + @baseSelect + N') sub';

    EXEC sp_executesql @sqlTotal,
        N'@p_fr NVARCHAR(10), @p_cc NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fr = @fecha_referencia, @p_cc = @cod_client, @p_emp = @empresa;

    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            sub.cod_client,
            sub.razon_soci,
            sub.t_comp,
            sub.n_comp,
            sub.fecha_emis,
            sub.fecha_vencimiento,
            sub.importe_cuota,
            sub.saldo_cuota,
            sub.empresa
        FROM (' + @baseSelect + N') sub
        ORDER BY ' + @orderCol + N' ' + @orderDir + N', sub.t_comp, sub.n_comp
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_fr NVARCHAR(10), @p_cc NVARCHAR(20), @p_emp NVARCHAR(100),
          @p_offset INT, @p_page_size INT',
        @p_fr = @fecha_referencia, @p_cc = @cod_client, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
