CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_FacturaAcopioUpdate
    @id               INT,
    @lista_precios_id INT,
    @fecha_vigencia   DATETIME,
    @descuento        DECIMAL(5, 2),
    @fecha_umo_acopio DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.PQ_ACOPIOS_FACTURAS', N'U') IS NULL
    BEGIN
        SELECT CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

    DECLARE @colId            SYSNAME = NULL,
            @colFechaVig      SYSNAME = NULL,
            @colListaPrecios  SYSNAME = NULL,
            @colDescuento     SYSNAME = NULL,
            @colFechaUmo      SYSNAME = NULL,
            @colEstado        SYSNAME = NULL,
            @colGva10Id       SYSNAME = NULL,
            @colGva10Hab      SYSNAME = NULL,
            @colGva10Desde    SYSNAME = NULL,
            @colGva10Hasta    SYSNAME = NULL;

    SELECT
        @colId = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'id', N'acopio_id', N'id_acopio') THEN COLUMN_NAME END),
        @colFechaVig = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'fecha_vigencia', N'fecha_vig') THEN COLUMN_NAME END),
        @colListaPrecios = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'lista_precios', N'nro_lista', N'lista_precios_id') THEN COLUMN_NAME END),
        @colDescuento = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'descuento', N'dto') THEN COLUMN_NAME END),
        @colFechaUmo = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'fecha_umo_acopio' THEN COLUMN_NAME END),
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

    IF @colId IS NULL OR @colFechaVig IS NULL OR @colListaPrecios IS NULL
       OR @colDescuento IS NULL OR @colFechaUmo IS NULL OR @colEstado IS NULL
    BEGIN
        SELECT CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

    DECLARE @estado INT = NULL,
            @sqlGet NVARCHAR(MAX) = N'
        SELECT @o_est = CAST(fac.' + QUOTENAME(@colEstado) + N' AS INT)
        FROM dbo.PQ_ACOPIOS_FACTURAS AS fac
        WHERE fac.' + QUOTENAME(@colId) + N' = @p_id;';

    EXEC sp_executesql @sqlGet,
        N'@p_id INT, @o_est INT OUTPUT',
        @p_id = @id,
        @o_est = @estado OUTPUT;

    IF @estado IS NULL
    BEGIN
        SELECT CAST(N'notFound' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

    IF @estado <> 0
    BEGIN
        SELECT CAST(N'acopioCerrado' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

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

    DECLARE @sqlUpd NVARCHAR(MAX) = N'
        UPDATE dbo.PQ_ACOPIOS_FACTURAS
        SET
            ' + QUOTENAME(@colListaPrecios) + N' = @p_lista,
            ' + QUOTENAME(@colFechaVig) + N' = @p_fv,
            ' + QUOTENAME(@colDescuento) + N' = @p_dto,
            ' + QUOTENAME(@colFechaUmo) + N' = @p_fumo
        WHERE ' + QUOTENAME(@colId) + N' = @p_id;';

    EXEC sp_executesql @sqlUpd,
        N'@p_id INT, @p_lista INT, @p_fv DATETIME, @p_dto DECIMAL(5,2), @p_fumo DATETIME',
        @p_id = @id,
        @p_lista = @lista_precios_id,
        @p_fv = @fecha_vigencia,
        @p_dto = @descuento,
        @p_fumo = @fecha_umo_acopio;

    SELECT CAST(N'OK' AS NVARCHAR(50)) AS resultCode, @id AS id;
END
