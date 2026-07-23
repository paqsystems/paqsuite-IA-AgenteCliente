CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_SaldosList
    @cliente     NVARCHAR(100) = NULL,
    @fecha_desde DATE          = NULL,
    @fecha_hasta DATE          = NULL,
    @comprobante NVARCHAR(60)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.PQ_ACOPIOS_FACTURAS', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS INT)           AS id,
            CAST(NULL AS NVARCHAR(10))  AS tComp,
            CAST(NULL AS NVARCHAR(50))  AS nComp,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaVigencia,
            CAST(NULL AS INT)           AS listaPreciosId,
            CAST(NULL AS NVARCHAR(50))  AS listaPreciosNumero,
            CAST(NULL AS NVARCHAR(200)) AS listaPreciosNombre,
            CAST(NULL AS DECIMAL(5,2))  AS descuento,
            CAST(NULL AS DECIMAL(18,2)) AS importeNeto,
            CAST(NULL AS DECIMAL(18,2)) AS importeImpuestos,
            CAST(NULL AS DECIMAL(18,2)) AS importeTotal,
            CAST(NULL AS DATETIME)      AS fechaUmoAcopio,
            CAST(NULL AS DECIMAL(18,2)) AS saldoAnterior,
            CAST(NULL AS INT)           AS estado
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @colId            SYSNAME = NULL,
            @colTComp         SYSNAME = NULL,
            @colNComp         SYSNAME = NULL,
            @colCodClient     SYSNAME = NULL,
            @colFechaVig      SYSNAME = NULL,
            @colListaPrecios  SYSNAME = NULL,
            @colDescuento     SYSNAME = NULL,
            @colImpNeto       SYSNAME = NULL,
            @colImpImpuestos  SYSNAME = NULL,
            @colImpTotal      SYSNAME = NULL,
            @colFechaUmo      SYSNAME = NULL,
            @colSaldoAnt      SYSNAME = NULL,
            @colEstado        SYSNAME = NULL,
            @colGva14Client   SYSNAME = NULL,
            @colGva14Razon    SYSNAME = NULL,
            @colGva10Id       SYSNAME = NULL,
            @colGva10NroLis   SYSNAME = NULL,
            @colGva10Nombre   SYSNAME = NULL,
            @hasGva14         BIT = 0,
            @hasGva10         BIT = 0;

    SELECT
        @colId = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'id', N'acopio_id', N'id_acopio') THEN COLUMN_NAME END),
        @colTComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N't_comp' THEN COLUMN_NAME END),
        @colNComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'n_comp' THEN COLUMN_NAME END),
        @colCodClient = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'cod_client' THEN COLUMN_NAME END),
        @colFechaVig = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'fecha_vigencia', N'fecha_vig') THEN COLUMN_NAME END),
        @colListaPrecios = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'lista_precios', N'nro_lista', N'lista_precios_id') THEN COLUMN_NAME END),
        @colDescuento = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'descuento', N'dto') THEN COLUMN_NAME END),
        @colImpNeto = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'importe_neto' THEN COLUMN_NAME END),
        @colImpImpuestos = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'importe_impuestos' THEN COLUMN_NAME END),
        @colImpTotal = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'importe_total' THEN COLUMN_NAME END),
        @colFechaUmo = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'fecha_umo_acopio' THEN COLUMN_NAME END),
        @colSaldoAnt = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'saldo_anterior' THEN COLUMN_NAME END),
        @colEstado = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'estado' THEN COLUMN_NAME END),
        @colGva14Client = MAX(CASE WHEN TABLE_NAME = N'GVA14'
            AND LOWER(COLUMN_NAME) = N'cod_client' THEN COLUMN_NAME END),
        @colGva14Razon = MAX(CASE WHEN TABLE_NAME = N'GVA14'
            AND LOWER(COLUMN_NAME) = N'razon_soci' THEN COLUMN_NAME END),
        @colGva10Id = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) IN (N'id_gva10', N'idgva10') THEN COLUMN_NAME END),
        @colGva10NroLis = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) IN (N'nro_de_lis', N'nro_lista') THEN COLUMN_NAME END),
        @colGva10Nombre = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) = N'nombre_lis' THEN COLUMN_NAME END)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = N'dbo'
      AND TABLE_NAME IN (N'PQ_ACOPIOS_FACTURAS', N'GVA14', N'GVA10');

    IF @colId IS NULL OR @colTComp IS NULL OR @colNComp IS NULL OR @colCodClient IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS INT)           AS id,
            CAST(NULL AS NVARCHAR(10))  AS tComp,
            CAST(NULL AS NVARCHAR(50))  AS nComp,
            CAST(NULL AS NVARCHAR(20))  AS codClient,
            CAST(NULL AS NVARCHAR(200)) AS razonSocial,
            CAST(NULL AS DATETIME)      AS fechaVigencia,
            CAST(NULL AS INT)           AS listaPreciosId,
            CAST(NULL AS NVARCHAR(50))  AS listaPreciosNumero,
            CAST(NULL AS NVARCHAR(200)) AS listaPreciosNombre,
            CAST(NULL AS DECIMAL(5,2))  AS descuento,
            CAST(NULL AS DECIMAL(18,2)) AS importeNeto,
            CAST(NULL AS DECIMAL(18,2)) AS importeImpuestos,
            CAST(NULL AS DECIMAL(18,2)) AS importeTotal,
            CAST(NULL AS DATETIME)      AS fechaUmoAcopio,
            CAST(NULL AS DECIMAL(18,2)) AS saldoAnterior,
            CAST(NULL AS INT)           AS estado
        WHERE 1 = 0;
        RETURN;
    END

    SET @hasGva14 = CASE
        WHEN OBJECT_ID(N'dbo.GVA14', N'U') IS NOT NULL
         AND @colGva14Client IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasGva10 = CASE
        WHEN OBJECT_ID(N'dbo.GVA10', N'U') IS NOT NULL
         AND @colGva10Id IS NOT NULL AND @colListaPrecios IS NOT NULL THEN 1 ELSE 0 END;

    CREATE TABLE #resultados (
        id                 INT            NULL,
        tComp              NVARCHAR(10)   NULL,
        nComp              NVARCHAR(50)   NULL,
        codClient          NVARCHAR(20)   NULL,
        razonSocial        NVARCHAR(200)  NULL,
        fechaVigencia      DATETIME       NULL,
        listaPreciosId     INT            NULL,
        listaPreciosNumero NVARCHAR(50)   NULL,
        listaPreciosNombre NVARCHAR(200)  NULL,
        descuento          DECIMAL(5, 2)  NULL,
        importeNeto        DECIMAL(18, 2) NULL,
        importeImpuestos   DECIMAL(18, 2) NULL,
        importeTotal       DECIMAL(18, 2) NULL,
        fechaUmoAcopio     DATETIME       NULL,
        saldoAnterior      DECIMAL(18, 2) NULL,
        estado             INT            NULL
    );

    DECLARE @joinCli NVARCHAR(MAX) = N'',
            @joinLis NVARCHAR(MAX) = N'',
            @selRazon NVARCHAR(MAX) = N'CAST(NULL AS NVARCHAR(200))',
            @selLisNro NVARCHAR(MAX) = N'CAST(NULL AS NVARCHAR(50))',
            @selLisNom NVARCHAR(MAX) = N'CAST(NULL AS NVARCHAR(200))',
            @whereExtra NVARCHAR(MAX) = N'';

    IF @hasGva14 = 1
    BEGIN
        SET @joinCli = N'LEFT JOIN dbo.GVA14 AS cli
            ON cli.' + QUOTENAME(@colGva14Client) + N' = ac.' + QUOTENAME(@colCodClient);
        IF @colGva14Razon IS NOT NULL
            SET @selRazon = N'CAST(cli.' + QUOTENAME(@colGva14Razon) + N' AS NVARCHAR(200))';
    END

    IF @hasGva10 = 1
    BEGIN
        SET @joinLis = N'LEFT JOIN dbo.GVA10 AS lis
            ON lis.' + QUOTENAME(@colGva10Id) + N' = ac.' + QUOTENAME(@colListaPrecios);
        IF @colGva10NroLis IS NOT NULL
            SET @selLisNro = N'CAST(lis.' + QUOTENAME(@colGva10NroLis) + N' AS NVARCHAR(50))';
        IF @colGva10Nombre IS NOT NULL
            SET @selLisNom = N'CAST(lis.' + QUOTENAME(@colGva10Nombre) + N' AS NVARCHAR(200))';
    END

    IF @cliente IS NOT NULL AND LTRIM(RTRIM(@cliente)) <> N''
    BEGIN
        IF @hasGva14 = 1 AND @colGva14Razon IS NOT NULL
            SET @whereExtra += N'
              AND (
                    ac.' + QUOTENAME(@colCodClient) + N' LIKE N''%'' + @p_cliente + N''%''
                 OR cli.' + QUOTENAME(@colGva14Razon) + N' LIKE N''%'' + @p_cliente + N''%''
              )';
        ELSE
            SET @whereExtra += N'
              AND ac.' + QUOTENAME(@colCodClient) + N' LIKE N''%'' + @p_cliente + N''%''';
    END

    IF @fecha_desde IS NOT NULL AND @colFechaVig IS NOT NULL
        SET @whereExtra += N'
          AND CAST(ac.' + QUOTENAME(@colFechaVig) + N' AS DATE) >= @p_fd';
    IF @fecha_hasta IS NOT NULL AND @colFechaVig IS NOT NULL
        SET @whereExtra += N'
          AND CAST(ac.' + QUOTENAME(@colFechaVig) + N' AS DATE) <= @p_fh';

    IF @comprobante IS NOT NULL AND LTRIM(RTRIM(@comprobante)) <> N''
        SET @whereExtra += N'
          AND REPLACE(CONCAT(ac.' + QUOTENAME(@colTComp) + N', ac.' + QUOTENAME(@colNComp) + N'), N'' '', N'''')
              LIKE N''%'' + @p_comp + N''%''';

    DECLARE @sql NVARCHAR(MAX) = N'
        INSERT INTO #resultados (
            id, tComp, nComp, codClient, razonSocial, fechaVigencia,
            listaPreciosId, listaPreciosNumero, listaPreciosNombre,
            descuento, importeNeto, importeImpuestos, importeTotal,
            fechaUmoAcopio, saldoAnterior, estado)
        SELECT
            CAST(ac.' + QUOTENAME(@colId) + N' AS INT),
            CAST(ac.' + QUOTENAME(@colTComp) + N' AS NVARCHAR(10)),
            CAST(ac.' + QUOTENAME(@colNComp) + N' AS NVARCHAR(50)),
            CAST(ac.' + QUOTENAME(@colCodClient) + N' AS NVARCHAR(20)),
            ' + @selRazon + N',
            ' + CASE WHEN @colFechaVig IS NOT NULL
                THEN N'ac.' + QUOTENAME(@colFechaVig)
                ELSE N'CAST(NULL AS DATETIME)' END + N',
            ' + CASE WHEN @colListaPrecios IS NOT NULL
                THEN N'CAST(ac.' + QUOTENAME(@colListaPrecios) + N' AS INT)'
                ELSE N'CAST(NULL AS INT)' END + N',
            ' + @selLisNro + N',
            ' + @selLisNom + N',
            ' + CASE WHEN @colDescuento IS NOT NULL
                THEN N'CAST(COALESCE(ac.' + QUOTENAME(@colDescuento) + N', 0) AS DECIMAL(5,2))'
                ELSE N'CAST(0 AS DECIMAL(5,2))' END + N',
            ' + CASE WHEN @colImpNeto IS NOT NULL
                THEN N'CAST(COALESCE(ac.' + QUOTENAME(@colImpNeto) + N', 0) AS DECIMAL(18,2))'
                ELSE N'CAST(0 AS DECIMAL(18,2))' END + N',
            ' + CASE WHEN @colImpImpuestos IS NOT NULL
                THEN N'CAST(COALESCE(ac.' + QUOTENAME(@colImpImpuestos) + N', 0) AS DECIMAL(18,2))'
                ELSE N'CAST(0 AS DECIMAL(18,2))' END + N',
            ' + CASE WHEN @colImpTotal IS NOT NULL
                THEN N'CAST(COALESCE(ac.' + QUOTENAME(@colImpTotal) + N', 0) AS DECIMAL(18,2))'
                ELSE N'CAST(0 AS DECIMAL(18,2))' END + N',
            ' + CASE WHEN @colFechaUmo IS NOT NULL
                THEN N'ac.' + QUOTENAME(@colFechaUmo)
                ELSE N'CAST(NULL AS DATETIME)' END + N',
            ' + CASE WHEN @colSaldoAnt IS NOT NULL
                THEN N'CAST(COALESCE(ac.' + QUOTENAME(@colSaldoAnt) + N', 0) AS DECIMAL(18,2))'
                ELSE N'CAST(0 AS DECIMAL(18,2))' END + N',
            ' + CASE WHEN @colEstado IS NOT NULL
                THEN N'CAST(ac.' + QUOTENAME(@colEstado) + N' AS INT)'
                ELSE N'CAST(NULL AS INT)' END + N'
        FROM dbo.PQ_ACOPIOS_FACTURAS AS ac
        ' + @joinCli + N'
        ' + @joinLis + N'
        WHERE 1 = 1
          ' + @whereExtra + N';';

    EXEC sp_executesql @sql,
        N'@p_cliente NVARCHAR(100), @p_fd DATE, @p_fh DATE, @p_comp NVARCHAR(60)',
        @p_cliente = @cliente,
        @p_fd = @fecha_desde,
        @p_fh = @fecha_hasta,
        @p_comp = @comprobante;

    SELECT COUNT(*) AS total_filas FROM #resultados;

    SELECT
        id, tComp, nComp, codClient, razonSocial, fechaVigencia,
        listaPreciosId, listaPreciosNumero, listaPreciosNombre,
        descuento, importeNeto, importeImpuestos, importeTotal,
        fechaUmoAcopio, saldoAnterior, estado
    FROM #resultados;
END
