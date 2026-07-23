CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_FacturaAcopioCreate
    @t_comp            NVARCHAR(10),
    @n_comp            NVARCHAR(50),
    @cod_client        NVARCHAR(20),
    @fecha_vigencia    DATETIME,
    @lista_precios_id  INT,
    @descuento         DECIMAL(5, 2),
    @importe_neto      DECIMAL(18, 2),
    @importe_impuestos DECIMAL(18, 2),
    @importe_total     DECIMAL(18, 2),
    @fecha_umo_acopio  DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.PQ_ACOPIOS_FACTURAS', N'U') IS NULL
    BEGIN
        SELECT CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
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
            @colGva10Id       SYSNAME = NULL,
            @colGva10Hab      SYSNAME = NULL,
            @colGva10Desde    SYSNAME = NULL,
            @colGva10Hasta    SYSNAME = NULL;

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
        @colGva10Id = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) IN (N'id_gva10', N'idgva10') THEN COLUMN_NAME END),
        @colGva10Hab = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) = N'habilitada' THEN COLUMN_NAME END),
        @colGva10Desde = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) = N'fec_desde' THEN COLUMN_NAME END),
        @colGva10Hasta = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) = N'fec_hasta' THEN COLUMN_NAME END)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = N'dbo'
      AND TABLE_NAME IN (N'PQ_ACOPIOS_FACTURAS', N'GVA10');

    IF @colTComp IS NULL OR @colNComp IS NULL OR @colCodClient IS NULL
       OR @colFechaVig IS NULL OR @colListaPrecios IS NULL OR @colDescuento IS NULL
       OR @colImpNeto IS NULL OR @colImpImpuestos IS NULL OR @colImpTotal IS NULL
       OR @colFechaUmo IS NULL OR @colSaldoAnt IS NULL OR @colEstado IS NULL
    BEGIN
        SELECT CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

    -- assertPriceListExists
    DECLARE @listaOk INT = 0,
            @sqlLista NVARCHAR(MAX),
            @whereLista NVARCHAR(MAX);

    IF OBJECT_ID(N'dbo.GVA10', N'U') IS NULL OR @colGva10Id IS NULL
    BEGIN
        SELECT CAST(N'listaPreciosInvalida' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

    SET @whereLista = N'lis.' + QUOTENAME(@colGva10Id) + N' = @p_lista';
    IF @colGva10Hab IS NOT NULL
        SET @whereLista += N' AND lis.' + QUOTENAME(@colGva10Hab) + N' = 1';
    IF @colGva10Desde IS NOT NULL
        SET @whereLista += N' AND (lis.' + QUOTENAME(@colGva10Desde) + N' IS NULL
            OR CAST(lis.' + QUOTENAME(@colGva10Desde) + N' AS DATE) <= CAST(GETDATE() AS DATE))';
    IF @colGva10Hasta IS NOT NULL
        SET @whereLista += N' AND (lis.' + QUOTENAME(@colGva10Hasta) + N' IS NULL
            OR CAST(lis.' + QUOTENAME(@colGva10Hasta) + N' AS DATE) <= CAST(N''1900-01-01'' AS DATE)
            OR CAST(lis.' + QUOTENAME(@colGva10Hasta) + N' AS DATE) >= CAST(GETDATE() AS DATE))';

    SET @sqlLista = N'
        SELECT @o_cnt = COUNT(*)
        FROM dbo.GVA10 AS lis
        WHERE ' + @whereLista + N';';

    EXEC sp_executesql @sqlLista,
        N'@p_lista INT, @o_cnt INT OUTPUT',
        @p_lista = @lista_precios_id,
        @o_cnt = @listaOk OUTPUT;

    IF @listaOk IS NULL OR @listaOk = 0
    BEGIN
        SELECT CAST(N'listaPreciosInvalida' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

    -- existsConfiguredFactura
    DECLARE @dupCnt INT = 0,
            @sqlDup NVARCHAR(MAX) = N'
        SELECT @o_cnt = COUNT(*)
        FROM dbo.PQ_ACOPIOS_FACTURAS AS fac
        WHERE fac.' + QUOTENAME(@colTComp) + N' = @p_t
          AND fac.' + QUOTENAME(@colNComp) + N' = @p_n;';

    EXEC sp_executesql @sqlDup,
        N'@p_t NVARCHAR(10), @p_n NVARCHAR(50), @o_cnt INT OUTPUT',
        @p_t = @t_comp,
        @p_n = @n_comp,
        @o_cnt = @dupCnt OUTPUT;

    IF @dupCnt > 0
    BEGIN
        SELECT CAST(N'facturaYaConfigurada' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

    DECLARE @newId INT = NULL,
            @sqlIns NVARCHAR(MAX) = N'
        INSERT INTO dbo.PQ_ACOPIOS_FACTURAS (
            ' + QUOTENAME(@colTComp) + N',
            ' + QUOTENAME(@colNComp) + N',
            ' + QUOTENAME(@colCodClient) + N',
            ' + QUOTENAME(@colFechaVig) + N',
            ' + QUOTENAME(@colListaPrecios) + N',
            ' + QUOTENAME(@colDescuento) + N',
            ' + QUOTENAME(@colImpNeto) + N',
            ' + QUOTENAME(@colImpImpuestos) + N',
            ' + QUOTENAME(@colImpTotal) + N',
            ' + QUOTENAME(@colFechaUmo) + N',
            ' + QUOTENAME(@colSaldoAnt) + N',
            ' + QUOTENAME(@colEstado) + N'
        )
        VALUES (
            @p_t, @p_n, @p_cli, @p_fv, @p_lista, @p_dto,
            @p_neto, @p_imp, @p_tot, @p_fumo, @p_neto, 0
        );
        SET @o_id = CAST(SCOPE_IDENTITY() AS INT);';

    EXEC sp_executesql @sqlIns,
        N'@p_t NVARCHAR(10), @p_n NVARCHAR(50), @p_cli NVARCHAR(20),
          @p_fv DATETIME, @p_lista INT, @p_dto DECIMAL(5,2),
          @p_neto DECIMAL(18,2), @p_imp DECIMAL(18,2), @p_tot DECIMAL(18,2),
          @p_fumo DATETIME, @o_id INT OUTPUT',
        @p_t = @t_comp,
        @p_n = @n_comp,
        @p_cli = @cod_client,
        @p_fv = @fecha_vigencia,
        @p_lista = @lista_precios_id,
        @p_dto = @descuento,
        @p_neto = @importe_neto,
        @p_imp = @importe_impuestos,
        @p_tot = @importe_total,
        @p_fumo = @fecha_umo_acopio,
        @o_id = @newId OUTPUT;

    SELECT CAST(N'OK' AS NVARCHAR(50)) AS resultCode, @newId AS id;
END
