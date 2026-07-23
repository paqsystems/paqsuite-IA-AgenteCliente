CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_FacturaAcopioClose
    @id               INT,
    @fecha_umo_acopio DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.PQ_ACOPIOS_FACTURAS', N'U') IS NULL
    BEGIN
        SELECT CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode, CAST(NULL AS INT) AS id;
        RETURN;
    END

    DECLARE @colId       SYSNAME = NULL,
            @colEstado   SYSNAME = NULL,
            @colFechaUmo SYSNAME = NULL;

    SELECT
        @colId = MAX(CASE WHEN LOWER(COLUMN_NAME) IN (N'id', N'acopio_id', N'id_acopio') THEN COLUMN_NAME END),
        @colEstado = MAX(CASE WHEN LOWER(COLUMN_NAME) = N'estado' THEN COLUMN_NAME END),
        @colFechaUmo = MAX(CASE WHEN LOWER(COLUMN_NAME) = N'fecha_umo_acopio' THEN COLUMN_NAME END)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = N'dbo'
      AND TABLE_NAME = N'PQ_ACOPIOS_FACTURAS';

    IF @colId IS NULL OR @colEstado IS NULL OR @colFechaUmo IS NULL
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

    IF @estado = 1
    BEGIN
        SELECT CAST(N'yaFinalizado' AS NVARCHAR(50)) AS resultCode, @id AS id;
        RETURN;
    END

    DECLARE @sqlUpd NVARCHAR(MAX) = N'
        UPDATE dbo.PQ_ACOPIOS_FACTURAS
        SET
            ' + QUOTENAME(@colEstado) + N' = 1,
            ' + QUOTENAME(@colFechaUmo) + N' = @p_fumo
        WHERE ' + QUOTENAME(@colId) + N' = @p_id;';

    EXEC sp_executesql @sqlUpd,
        N'@p_id INT, @p_fumo DATETIME',
        @p_id = @id,
        @p_fumo = @fecha_umo_acopio;

    SELECT CAST(N'OK' AS NVARCHAR(50)) AS resultCode, @id AS id;
END
