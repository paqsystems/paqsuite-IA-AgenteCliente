CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_AsociacionDelete
    @id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF OBJECT_ID(N'dbo.PQ_ACOPIOS_PEDIDOS', N'U') IS NULL
    BEGIN
        SELECT
            CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS NVARCHAR(10)) AS tComp,
            CAST(NULL AS NVARCHAR(50)) AS nComp,
            CAST(NULL AS INT) AS talonPed,
            CAST(NULL AS NVARCHAR(50)) AS nroPedido;
        RETURN;
    END

    DECLARE @colApId    SYSNAME = NULL,
            @colApTComp SYSNAME = NULL,
            @colApNComp SYSNAME = NULL,
            @colApTalon SYSNAME = NULL,
            @colApNro   SYSNAME = NULL,
            @colAfTComp SYSNAME = NULL,
            @colAfNComp SYSNAME = NULL,
            @colAfEstado SYSNAME = NULL;

    SELECT
        @colApId = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) IN (N'id', N'pedido_id') THEN COLUMN_NAME END),
        @colApTComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) = N't_comp' THEN COLUMN_NAME END),
        @colApNComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) = N'n_comp' THEN COLUMN_NAME END),
        @colApTalon = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) IN (N'talon_ped', N'talonped') THEN COLUMN_NAME END),
        @colApNro = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) IN (N'nro_pedido', N'nropedido') THEN COLUMN_NAME END),
        @colAfTComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N't_comp' THEN COLUMN_NAME END),
        @colAfNComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'n_comp' THEN COLUMN_NAME END),
        @colAfEstado = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'estado' THEN COLUMN_NAME END)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = N'dbo'
      AND TABLE_NAME IN (N'PQ_ACOPIOS_PEDIDOS', N'PQ_ACOPIOS_FACTURAS');

    IF @colApId IS NULL OR @colApTComp IS NULL OR @colApNComp IS NULL
       OR @colApTalon IS NULL OR @colApNro IS NULL
    BEGIN
        SELECT
            CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS NVARCHAR(10)) AS tComp,
            CAST(NULL AS NVARCHAR(50)) AS nComp,
            CAST(NULL AS INT) AS talonPed,
            CAST(NULL AS NVARCHAR(50)) AS nroPedido;
        RETURN;
    END

    BEGIN TRAN;

    DECLARE @found BIT = 0,
            @tComp NVARCHAR(10) = NULL,
            @nComp NVARCHAR(50) = NULL,
            @talonPed INT = NULL,
            @nroPedido NVARCHAR(50) = NULL,
            @sqlGet NVARCHAR(MAX) = N'
        SELECT TOP (1)
            @o_found = 1,
            @o_t = CAST(ap.' + QUOTENAME(@colApTComp) + N' AS NVARCHAR(10)),
            @o_n = CAST(ap.' + QUOTENAME(@colApNComp) + N' AS NVARCHAR(50)),
            @o_talon = CAST(ap.' + QUOTENAME(@colApTalon) + N' AS INT),
            @o_nro = CAST(ap.' + QUOTENAME(@colApNro) + N' AS NVARCHAR(50))
        FROM dbo.PQ_ACOPIOS_PEDIDOS AS ap WITH (UPDLOCK)
        WHERE ap.' + QUOTENAME(@colApId) + N' = @p_id;';

    EXEC sp_executesql @sqlGet,
        N'@p_id INT, @o_found BIT OUTPUT, @o_t NVARCHAR(10) OUTPUT, @o_n NVARCHAR(50) OUTPUT,
          @o_talon INT OUTPUT, @o_nro NVARCHAR(50) OUTPUT',
        @p_id = @id,
        @o_found = @found OUTPUT,
        @o_t = @tComp OUTPUT,
        @o_n = @nComp OUTPUT,
        @o_talon = @talonPed OUTPUT,
        @o_nro = @nroPedido OUTPUT;

    IF @found = 0 OR @found IS NULL
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'notFound' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS NVARCHAR(10)) AS tComp,
            CAST(NULL AS NVARCHAR(50)) AS nComp,
            CAST(NULL AS INT) AS talonPed,
            CAST(NULL AS NVARCHAR(50)) AS nroPedido;
        RETURN;
    END

    IF OBJECT_ID(N'dbo.PQ_ACOPIOS_FACTURAS', N'U') IS NULL
       OR @colAfTComp IS NULL OR @colAfNComp IS NULL OR @colAfEstado IS NULL
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'acopioNotFound' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS NVARCHAR(10)) AS tComp,
            CAST(NULL AS NVARCHAR(50)) AS nComp,
            CAST(NULL AS INT) AS talonPed,
            CAST(NULL AS NVARCHAR(50)) AS nroPedido;
        RETURN;
    END

    DECLARE @acopioFound BIT = 0,
            @acopioEstado INT = NULL,
            @sqlFac NVARCHAR(MAX) = N'
        SELECT TOP (1)
            @o_found = 1,
            @o_est = CAST(fac.' + QUOTENAME(@colAfEstado) + N' AS INT)
        FROM dbo.PQ_ACOPIOS_FACTURAS AS fac
        WHERE fac.' + QUOTENAME(@colAfTComp) + N' = @p_t
          AND fac.' + QUOTENAME(@colAfNComp) + N' = @p_n;';

    EXEC sp_executesql @sqlFac,
        N'@p_t NVARCHAR(10), @p_n NVARCHAR(50), @o_found BIT OUTPUT, @o_est INT OUTPUT',
        @p_t = @tComp,
        @p_n = @nComp,
        @o_found = @acopioFound OUTPUT,
        @o_est = @acopioEstado OUTPUT;

    IF @acopioFound = 0 OR @acopioFound IS NULL
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'acopioNotFound' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS NVARCHAR(10)) AS tComp,
            CAST(NULL AS NVARCHAR(50)) AS nComp,
            CAST(NULL AS INT) AS talonPed,
            CAST(NULL AS NVARCHAR(50)) AS nroPedido;
        RETURN;
    END

    IF @acopioEstado <> 0
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'acopioCerrado' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS NVARCHAR(10)) AS tComp,
            CAST(NULL AS NVARCHAR(50)) AS nComp,
            CAST(NULL AS INT) AS talonPed,
            CAST(NULL AS NVARCHAR(50)) AS nroPedido;
        RETURN;
    END

    DECLARE @sqlDel NVARCHAR(MAX) = N'
        DELETE FROM dbo.PQ_ACOPIOS_PEDIDOS
        WHERE ' + QUOTENAME(@colApId) + N' = @p_id;';

    EXEC sp_executesql @sqlDel, N'@p_id INT', @p_id = @id;

    COMMIT TRAN;

    SELECT
        CAST(N'OK' AS NVARCHAR(50)) AS resultCode,
        @id AS id,
        @tComp AS tComp,
        @nComp AS nComp,
        @talonPed AS talonPed,
        @nroPedido AS nroPedido;
END
