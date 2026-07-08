CREATE OR ALTER PROCEDURE dbo.PAQ_Robinet_Deudas
    @cod_client     NVARCHAR(20)  = NULL,
    @prefijo_acopio NVARCHAR(50)  = NULL,
    @empresa        NVARCHAR(20)  = NULL,
    @page           INT           = 1,
    @page_size      INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasGva46 BIT=0, @hasGva53 BIT=0, @hasGva07 BIT=0, @hasImporteTot BIT=0;
    IF OBJECT_ID(N'dbo.GVA46',N'U') IS NOT NULL SET @hasGva46=1;
    IF OBJECT_ID(N'dbo.GVA53',N'U') IS NOT NULL SET @hasGva53=1;
    IF OBJECT_ID(N'dbo.GVA07',N'U') IS NOT NULL SET @hasGva07=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA12' AND COLUMN_NAME='IMPORTE_TOT')
        SET @hasImporteTot=1;

    DECLARE @hasIdGva46 BIT=0;
    IF @hasGva46=1 AND EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA46' AND COLUMN_NAME='ID_GVA46')
        SET @hasIdGva46=1;

    DECLARE @importeCab      NVARCHAR(50),
            @cancelSql       NVARCHAR(1000),
            @joinGva46       NVARCHAR(200),
            @fechaVtoExpr    NVARCHAR(100),
            @importeCuotaExpr NVARCHAR(200),
            @acopioNot       NVARCHAR(300);

    SET @importeCab = CASE WHEN @hasImporteTot=1 THEN N'c.IMPORTE_TOT' ELSE N'c.IMPORTE' END;

    SET @cancelSql = CASE
        WHEN @hasGva07=1 AND @hasGva46=1 THEN
            N'ISNULL((SELECT SUM(j.IMPORT_CAN) FROM GVA07 j
              WHERE j.T_COMP=g46.T_COMP AND j.N_COMP=g46.N_COMP
              AND (j.FECHA_VTO=g46.FECHA_VTO OR (j.FECHA_VTO IS NULL AND g46.FECHA_VTO IS NULL))),0)'
        WHEN @hasGva07=1 THEN
            N'ISNULL((SELECT SUM(j.IMPORT_CAN) FROM GVA07 j
              WHERE j.T_COMP=c.T_COMP AND j.N_COMP=c.N_COMP),0)'
        ELSE N'0'
    END;

    SET @joinGva46       = CASE WHEN @hasGva46=1
        THEN N'LEFT JOIN GVA46 g46 ON c.T_COMP=g46.T_COMP AND c.N_COMP=g46.N_COMP'
        ELSE N'' END;
    SET @fechaVtoExpr    = CASE WHEN @hasGva46=1
        THEN N'COALESCE(g46.FECHA_VTO,c.FECHA_EMIS)' ELSE N'c.FECHA_EMIS' END;
    SET @importeCuotaExpr = CASE WHEN @hasGva46=1
        THEN N'ISNULL(g46.IMPORTE_VT,' + @importeCab + N')' ELSE @importeCab END;
    SET @acopioNot = CASE WHEN @hasGva53=1
        THEN N'NOT EXISTS (SELECT 1 FROM GVA53 r53
               WHERE r53.T_COMP=c.T_COMP AND r53.N_COMP=c.N_COMP
               AND r53.COD_ARTICU LIKE CONCAT(@p_pref,''%''))'
        ELSE N'1=1' END;

    DECLARE @saldoExpr NVARCHAR(1500) = N'(' + @importeCuotaExpr + N' - ' + @cancelSql + N')';
    DECLARE @where NVARCHAR(2000) =
        N'(c.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(c.ESTADO)))<>''ANU'')
          AND ' + @acopioNot + N'
          AND ' + @saldoExpr + N' > 0.0001';

    IF @cod_client IS NOT NULL AND @cod_client <> N''
        SET @where += N' AND c.COD_CLIENT=@p_cc';

    IF @page < 1 SET @page = 1;
    IF @page_size < 1 SET @page_size = 200;

    DECLARE @sqlTotal NVARCHAR(MAX) = N'
        SELECT
            COUNT(*) AS total_filas,
            CAST(ROUND(SUM(' + @saldoExpr + N'), 2) AS DECIMAL(18,2)) AS total_general
        FROM GVA12 c
        INNER JOIN GVA14 cl ON c.COD_CLIENT=cl.COD_CLIENT
        ' + @joinGva46 + N'
        WHERE ' + @where;

    EXEC sp_executesql @sqlTotal,
        N'@p_cc NVARCHAR(20), @p_pref NVARCHAR(50), @p_emp NVARCHAR(20)',
        @p_cc=@cod_client, @p_pref=@prefijo_acopio, @p_emp=@empresa;

    DECLARE @offset INT = (@page - 1) * @page_size;
    DECLARE @orderBy NVARCHAR(300) = @fechaVtoExpr + N', c.T_COMP, c.N_COMP'
        + CASE WHEN @hasIdGva46=1 THEN N', g46.ID_GVA46' ELSE N'' END;
    DECLARE @sqlPaged NVARCHAR(MAX) = N'
        SELECT
            ' + @fechaVtoExpr + N' AS fecha_vencimiento,
            c.T_COMP AS t_comp,
            c.N_COMP AS n_comp,
            c.COD_CLIENT AS cod_client,
            cl.RAZON_SOCI AS razon_soci,
            ' + @importeCab + N' AS importe_tot,
            ' + @saldoExpr + N' AS saldo_pendiente,
            @p_emp AS empresa
        FROM GVA12 c
        INNER JOIN GVA14 cl ON c.COD_CLIENT=cl.COD_CLIENT
        ' + @joinGva46 + N'
        WHERE ' + @where + N'
        ORDER BY ' + @orderBy + N'
        OFFSET @p_offset ROWS FETCH NEXT @p_page_size ROWS ONLY';

    EXEC sp_executesql @sqlPaged,
        N'@p_cc NVARCHAR(20), @p_pref NVARCHAR(50), @p_emp NVARCHAR(20),
          @p_offset INT, @p_page_size INT',
        @p_cc=@cod_client, @p_pref=@prefijo_acopio, @p_emp=@empresa,
        @p_offset=@offset, @p_page_size=@page_size;
END
