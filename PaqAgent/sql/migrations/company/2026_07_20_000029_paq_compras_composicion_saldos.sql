CREATE OR ALTER PROCEDURE dbo.PAQ_Compras_ComposicionSaldos
    @fecha_referencia NVARCHAR(10),
    @cod_provee       NVARCHAR(20)  = NULL,
    @empresa          NVARCHAR(100) = NULL,
    @sort             NVARCHAR(50)  = N'fecha_emis',
    @sort_dir         NVARCHAR(4)   = N'desc',
    @page             INT           = 1,
    @page_size        INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.CPA04', N'U') IS NULL
       OR OBJECT_ID(N'dbo.CPA01', N'U') IS NULL
       OR OBJECT_ID(N'dbo.CPA54', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(20)) AS cod_provee,
            CAST(NULL AS NVARCHAR(200)) AS razon_soci,
            CAST(NULL AS NVARCHAR(10)) AS t_comp,
            CAST(NULL AS NVARCHAR(20)) AS n_comp,
            CAST(NULL AS DATETIME) AS fecha_emis,
            CAST(NULL AS DATETIME) AS fecha_vencimiento,
            CAST(NULL AS DECIMAL(18, 2)) AS importe_cuota,
            CAST(NULL AS DECIMAL(18, 2)) AS saldo_cuota,
            CAST(NULL AS NVARCHAR(100)) AS empresa
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasCpa05          BIT = 0,
            @hasIdCpa04        BIT = 0,
            @hasFechaVto       BIT = 0,
            @hasFechaVenc      BIT = 0,
            @hasImportVto      BIT = 0,
            @hasImporteCuota   BIT = 0,
            @hasAnulado        BIT = 0,
            @hasNomProvee      BIT = 0,
            @hasRazonSoci      BIT = 0,
            @hasTCompCan       BIT = 0,
            @hasNCompCan       BIT = 0,
            @hasImportCan      BIT = 0,
            @hasCpa05FechaVto  BIT = 0;

    IF OBJECT_ID(N'dbo.CPA05', N'U') IS NOT NULL SET @hasCpa05 = 1;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA54' AND COLUMN_NAME = N'ID_CPA04')
        SET @hasIdCpa04 = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA54' AND COLUMN_NAME = N'FECHA_VTO')
        SET @hasFechaVto = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA54' AND COLUMN_NAME = N'FECHA_VENCIMIENTO')
        SET @hasFechaVenc = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA54' AND COLUMN_NAME = N'IMPORT_VTO')
        SET @hasImportVto = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA54' AND COLUMN_NAME = N'IMPORTE')
        SET @hasImporteCuota = 1;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA04' AND COLUMN_NAME = N'ANULADO')
        SET @hasAnulado = 1;

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA01' AND COLUMN_NAME = N'NOM_PROVEE')
        SET @hasNomProvee = 1;
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA01' AND COLUMN_NAME = N'RAZON_SOCI')
        SET @hasRazonSoci = 1;

    IF @hasCpa05 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA05' AND COLUMN_NAME = N'T_COMP_CAN')
        SET @hasTCompCan = 1;
    IF @hasCpa05 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA05' AND COLUMN_NAME = N'N_COMP_CAN')
        SET @hasNCompCan = 1;
    IF @hasCpa05 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA05' AND COLUMN_NAME = N'IMPORT_CAN')
        SET @hasImportCan = 1;
    IF @hasCpa05 = 1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'CPA05' AND COLUMN_NAME = N'FECHA_VTO')
        SET @hasCpa05FechaVto = 1;

    DECLARE @joinCpa54        NVARCHAR(MAX),
            @fechaVtoExpr     NVARCHAR(MAX),
            @importeCuotaExpr NVARCHAR(MAX),
            @razonExpr        NVARCHAR(MAX),
            @cancelSql        NVARCHAR(MAX),
            @saldoExpr        NVARCHAR(MAX),
            @where            NVARCHAR(MAX),
            @baseSelect       NVARCHAR(MAX),
            @orderCol         NVARCHAR(MAX),
            @orderDir         NVARCHAR(MAX),
            @sqlTotal         NVARCHAR(MAX),
            @sqlPaged         NVARCHAR(MAX);

    SET @joinCpa54 = CASE
        WHEN @hasIdCpa04 = 1
            THEN N'INNER JOIN CPA54 c54 ON c54.ID_CPA04 = c.ID_CPA04'
        ELSE N'INNER JOIN CPA54 c54 ON c54.T_COMP = c.T_COMP AND c54.N_COMP = c.N_COMP'
    END;

    SET @fechaVtoExpr = CASE
        WHEN @hasFechaVto = 1 THEN N'COALESCE(c54.FECHA_VTO, c.FECHA_EMIS)'
        WHEN @hasFechaVenc = 1 THEN N'COALESCE(c54.FECHA_VENCIMIENTO, c.FECHA_EMIS)'
        ELSE N'c.FECHA_EMIS'
    END;

    SET @importeCuotaExpr = CASE
        WHEN @hasImportVto = 1 THEN N'ISNULL(c54.IMPORT_VTO, 0)'
        WHEN @hasImporteCuota = 1 THEN N'ISNULL(c54.IMPORTE, 0)'
        ELSE N'0'
    END;

    SET @razonExpr = CASE
        WHEN @hasNomProvee = 1 THEN N'p.NOM_PROVEE'
        WHEN @hasRazonSoci = 1 THEN N'p.RAZON_SOCI'
        ELSE N''''''
    END;

    IF @hasCpa05 = 1 AND @hasTCompCan = 1 AND @hasNCompCan = 1 AND @hasImportCan = 1
    BEGIN
        IF @hasCpa05FechaVto = 1 AND (@hasFechaVto = 1 OR @hasFechaVenc = 1)
            SET @cancelSql = N'ISNULL((SELECT SUM(j.IMPORT_CAN) FROM CPA05 j
              WHERE j.T_COMP_CAN = c.T_COMP AND j.N_COMP_CAN = c.N_COMP
              AND (j.FECHA_VTO = ' + CASE WHEN @hasFechaVto = 1 THEN N'c54.FECHA_VTO' ELSE N'c54.FECHA_VENCIMIENTO' END + N'
                   OR (j.FECHA_VTO IS NULL AND '
                   + CASE WHEN @hasFechaVto = 1 THEN N'c54.FECHA_VTO' ELSE N'c54.FECHA_VENCIMIENTO' END
                   + N' IS NULL))), 0)';
        ELSE
            SET @cancelSql = N'ISNULL((SELECT SUM(j.IMPORT_CAN) FROM CPA05 j
              WHERE j.T_COMP_CAN = c.T_COMP AND j.N_COMP_CAN = c.N_COMP), 0)';
    END
    ELSE
        SET @cancelSql = N'0';

    SET @saldoExpr = N'(' + @importeCuotaExpr + N' - ' + @cancelSql + N')';

    SET @where =
        N'c.FECHA_EMIS <= CONVERT(DATETIME, @p_fr, 120)
          AND c.COD_PROVEE <> ''***''
          AND c.T_COMP <> ''ANU''
          AND ' + @saldoExpr + N' <> 0';

    IF @hasAnulado = 1
        SET @where += N' AND (c.ANULADO = 0 OR c.ANULADO IS NULL)';

    IF @cod_provee IS NOT NULL AND @cod_provee <> N''
        SET @where += N' AND c.COD_PROVEE = @p_cp';

    SET @orderCol = CASE LOWER(LTRIM(RTRIM(ISNULL(@sort, N''))))
        WHEN N'cod_provee' THEN N'cod_provee'
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
            c.COD_PROVEE AS cod_provee,
            ' + @razonExpr + N' AS razon_soci,
            c.T_COMP AS t_comp,
            c.N_COMP AS n_comp,
            c.FECHA_EMIS AS fecha_emis,
            ' + @fechaVtoExpr + N' AS fecha_vencimiento,
            CAST(ROUND(' + @importeCuotaExpr + N', 2) AS DECIMAL(18,2)) AS importe_cuota,
            CAST(ROUND(' + @saldoExpr + N', 2) AS DECIMAL(18,2)) AS saldo_cuota,
            @p_emp AS empresa
        FROM CPA04 c
        INNER JOIN CPA01 p ON p.COD_PROVEE = c.COD_PROVEE
        ' + @joinCpa54 + N'
        WHERE ' + @where;

    SET @sqlTotal = N'
        SELECT COUNT(*) AS total_filas
        FROM (' + @baseSelect + N') sub';

    EXEC sp_executesql @sqlTotal,
        N'@p_fr NVARCHAR(10), @p_cp NVARCHAR(20), @p_emp NVARCHAR(100)',
        @p_fr = @fecha_referencia, @p_cp = @cod_provee, @p_emp = @empresa;

    DECLARE @offset INT = (@page - 1) * @page_size;

    SET @sqlPaged = N'
        SELECT
            sub.cod_provee,
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
        N'@p_fr NVARCHAR(10), @p_cp NVARCHAR(20), @p_emp NVARCHAR(100),
          @p_offset INT, @p_page_size INT',
        @p_fr = @fecha_referencia, @p_cp = @cod_provee, @p_emp = @empresa,
        @p_offset = @offset, @p_page_size = @page_size;
END
