CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_AsociacionCreate
    @t_comp           NVARCHAR(10),
    @n_comp           NVARCHAR(50),
    @talon_ped        INT,
    @nro_pedido       NVARCHAR(50),
    @cod_client_ped   NVARCHAR(20),
    @dictionary_db    NVARCHAR(260) = NULL,
    @grupo_id         INT = NULL,
    @renglones_json   NVARCHAR(MAX),
    @saldo_disponible DECIMAL(18, 2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Contrato Gateway: Laravel ya resolvió renglones/saldo; params cross-DB no se usan aquí.
    SET @dictionary_db = @dictionary_db;
    SET @grupo_id = @grupo_id;

    IF OBJECT_ID(N'dbo.PQ_ACOPIOS_FACTURAS', N'U') IS NULL
       OR OBJECT_ID(N'dbo.PQ_ACOPIOS_PEDIDOS', N'U') IS NULL
    BEGIN
        SELECT
            CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    IF @renglones_json IS NULL OR LTRIM(RTRIM(@renglones_json)) = N''
    BEGIN
        SELECT
            CAST(N'pedidoSinRenglones' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    DECLARE @colAfId       SYSNAME = NULL,
            @colAfTComp    SYSNAME = NULL,
            @colAfNComp    SYSNAME = NULL,
            @colAfClient   SYSNAME = NULL,
            @colAfLista    SYSNAME = NULL,
            @colAfDesc     SYSNAME = NULL,
            @colAfSaldo    SYSNAME = NULL,
            @colAfEstado   SYSNAME = NULL,
            @colApTComp    SYSNAME = NULL,
            @colApNComp    SYSNAME = NULL,
            @colApTalon    SYSNAME = NULL,
            @colApNro      SYSNAME = NULL,
            @colApClient   SYSNAME = NULL,
            @colApEstado   SYSNAME = NULL,
            @colGva10Id    SYSNAME = NULL,
            @colGva10Nro   SYSNAME = NULL,
            @colGva17Art   SYSNAME = NULL,
            @colGva17Lista SYSNAME = NULL,
            @colGva17Prec  SYSNAME = NULL;

    SELECT
        @colAfId = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'id', N'acopio_id', N'id_acopio') THEN COLUMN_NAME END),
        @colAfTComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N't_comp' THEN COLUMN_NAME END),
        @colAfNComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'n_comp' THEN COLUMN_NAME END),
        @colAfClient = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'cod_client' THEN COLUMN_NAME END),
        @colAfLista = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'lista_precios', N'nro_lista', N'lista_precios_id') THEN COLUMN_NAME END),
        @colAfDesc = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) IN (N'descuento', N'dto') THEN COLUMN_NAME END),
        @colAfSaldo = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'saldo_anterior' THEN COLUMN_NAME END),
        @colAfEstado = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_FACTURAS'
            AND LOWER(COLUMN_NAME) = N'estado' THEN COLUMN_NAME END),
        @colApTComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) = N't_comp' THEN COLUMN_NAME END),
        @colApNComp = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) = N'n_comp' THEN COLUMN_NAME END),
        @colApTalon = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) IN (N'talon_ped', N'talonped') THEN COLUMN_NAME END),
        @colApNro = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) IN (N'nro_pedido', N'nropedido') THEN COLUMN_NAME END),
        @colApClient = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) = N'cod_client' THEN COLUMN_NAME END),
        @colApEstado = MAX(CASE WHEN TABLE_NAME = N'PQ_ACOPIOS_PEDIDOS'
            AND LOWER(COLUMN_NAME) = N'estado' THEN COLUMN_NAME END),
        @colGva10Id = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) IN (N'id_gva10', N'idgva10') THEN COLUMN_NAME END),
        @colGva10Nro = MAX(CASE WHEN TABLE_NAME = N'GVA10'
            AND LOWER(COLUMN_NAME) IN (N'nro_de_lis', N'nro_lista') THEN COLUMN_NAME END),
        @colGva17Art = MAX(CASE WHEN TABLE_NAME = N'GVA17'
            AND LOWER(COLUMN_NAME) = N'cod_articu' THEN COLUMN_NAME END),
        @colGva17Lista = MAX(CASE WHEN TABLE_NAME = N'GVA17'
            AND LOWER(COLUMN_NAME) IN (N'nro_de_lis', N'nro_lista') THEN COLUMN_NAME END),
        @colGva17Prec = MAX(CASE WHEN TABLE_NAME = N'GVA17'
            AND LOWER(COLUMN_NAME) = N'precio_neto' THEN COLUMN_NAME END)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = N'dbo'
      AND TABLE_NAME IN (N'PQ_ACOPIOS_FACTURAS', N'PQ_ACOPIOS_PEDIDOS', N'GVA10', N'GVA17');

    IF @colGva17Prec IS NULL
        SELECT @colGva17Prec = COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = N'dbo' AND TABLE_NAME = N'GVA17'
          AND LOWER(COLUMN_NAME) = N'precio';

    IF @colAfTComp IS NULL OR @colAfNComp IS NULL OR @colAfClient IS NULL
       OR @colAfLista IS NULL OR @colAfDesc IS NULL OR @colAfEstado IS NULL
       OR @colApTComp IS NULL OR @colApNComp IS NULL OR @colApTalon IS NULL
       OR @colApNro IS NULL OR @colApClient IS NULL OR @colApEstado IS NULL
    BEGIN
        SELECT
            CAST(N'tablaNoExiste' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    BEGIN TRAN;

    DECLARE @acopioId INT = NULL,
            @acopioCodClient NVARCHAR(20) = NULL,
            @acopioListaId INT = NULL,
            @acopioDescuento DECIMAL(5, 2) = NULL,
            @acopioEstado INT = NULL,
            @found BIT = 0,
            @sqlAcopio NVARCHAR(MAX);

    SET @sqlAcopio = N'
        SELECT TOP (1)
            @o_found = 1,
            @o_id = ' + CASE WHEN @colAfId IS NOT NULL
                THEN N'CAST(fac.' + QUOTENAME(@colAfId) + N' AS INT)'
                ELSE N'CAST(NULL AS INT)' END + N',
            @o_cli = CAST(fac.' + QUOTENAME(@colAfClient) + N' AS NVARCHAR(20)),
            @o_lista = CAST(fac.' + QUOTENAME(@colAfLista) + N' AS INT),
            @o_dto = CAST(COALESCE(fac.' + QUOTENAME(@colAfDesc) + N', 0) AS DECIMAL(5,2)),
            @o_est = CAST(fac.' + QUOTENAME(@colAfEstado) + N' AS INT)
        FROM dbo.PQ_ACOPIOS_FACTURAS AS fac WITH (UPDLOCK)
        WHERE fac.' + QUOTENAME(@colAfTComp) + N' = @p_t
          AND fac.' + QUOTENAME(@colAfNComp) + N' = @p_n;';

    EXEC sp_executesql @sqlAcopio,
        N'@p_t NVARCHAR(10), @p_n NVARCHAR(50),
          @o_found BIT OUTPUT, @o_id INT OUTPUT, @o_cli NVARCHAR(20) OUTPUT,
          @o_lista INT OUTPUT, @o_dto DECIMAL(5,2) OUTPUT, @o_est INT OUTPUT',
        @p_t = @t_comp,
        @p_n = @n_comp,
        @o_found = @found OUTPUT,
        @o_id = @acopioId OUTPUT,
        @o_cli = @acopioCodClient OUTPUT,
        @o_lista = @acopioListaId OUTPUT,
        @o_dto = @acopioDescuento OUTPUT,
        @o_est = @acopioEstado OUTPUT;

    IF @found = 0 OR @found IS NULL
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'acopioNotFound' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    IF @acopioEstado <> 0
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'acopioCerrado' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    IF UPPER(LTRIM(RTRIM(ISNULL(@cod_client_ped, N''))))
       <> UPPER(LTRIM(RTRIM(ISNULL(@acopioCodClient, N''))))
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'clienteIncompatible' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(@cod_client_ped AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(@acopioCodClient AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    DECLARE @dupCnt INT = 0,
            @sqlDup NVARCHAR(MAX) = N'
        SELECT @o_cnt = COUNT(*)
        FROM dbo.PQ_ACOPIOS_PEDIDOS AS ap
        WHERE ap.' + QUOTENAME(@colApTalon) + N' = @p_talon
          AND LTRIM(RTRIM(ap.' + QUOTENAME(@colApNro) + N')) = LTRIM(RTRIM(@p_nro));';

    EXEC sp_executesql @sqlDup,
        N'@p_talon INT, @p_nro NVARCHAR(50), @o_cnt INT OUTPUT',
        @p_talon = @talon_ped,
        @p_nro = @nro_pedido,
        @o_cnt = @dupCnt OUTPUT;

    IF @dupCnt > 0
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'pedidoYaAsociado' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    IF OBJECT_ID(N'dbo.GVA10', N'U') IS NULL OR @colGva10Id IS NULL OR @colGva10Nro IS NULL
       OR OBJECT_ID(N'dbo.GVA17', N'U') IS NULL OR @colGva17Art IS NULL
       OR @colGva17Lista IS NULL OR @colGva17Prec IS NULL
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'listaPreciosNoEncontrada' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    DECLARE @nroLista INT = NULL,
            @sqlLista NVARCHAR(MAX) = N'
        SELECT TOP (1) @o_nro = CAST(lis.' + QUOTENAME(@colGva10Nro) + N' AS INT)
        FROM dbo.GVA10 AS lis
        WHERE lis.' + QUOTENAME(@colGva10Id) + N' = @p_lista;';

    EXEC sp_executesql @sqlLista,
        N'@p_lista INT, @o_nro INT OUTPUT',
        @p_lista = @acopioListaId,
        @o_nro = @nroLista OUTPUT;

    IF @nroLista IS NULL
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'listaPreciosNoEncontrada' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    CREATE TABLE #renglones (
        codArticu NVARCHAR(50) NOT NULL,
        cantidad  DECIMAL(18, 4) NOT NULL
    );
    CREATE TABLE #precios (
        codArticu NVARCHAR(50) NOT NULL,
        precio    DECIMAL(18, 4) NOT NULL
    );

    INSERT INTO #renglones (codArticu, cantidad)
    SELECT
        LTRIM(RTRIM(j.codArticu)),
        j.cantidad
    FROM OPENJSON(@renglones_json)
    WITH (
        codArticu NVARCHAR(50) '$.codArticu',
        cantidad  DECIMAL(18, 4) '$.cantidad'
    ) AS j
    WHERE j.codArticu IS NOT NULL
      AND LTRIM(RTRIM(j.codArticu)) <> N''
      AND j.cantidad IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM #renglones)
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'pedidoSinRenglones' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    DECLARE @sqlPrec NVARCHAR(MAX) = N'
        INSERT INTO #precios (codArticu, precio)
        SELECT
            LTRIM(RTRIM(CAST(g.' + QUOTENAME(@colGva17Art) + N' AS NVARCHAR(50)))),
            CAST(COALESCE(g.' + QUOTENAME(@colGva17Prec) + N', 0) AS DECIMAL(18,4))
        FROM dbo.GVA17 AS g
        INNER JOIN #renglones AS r
            ON LTRIM(RTRIM(CAST(g.' + QUOTENAME(@colGva17Art) + N' AS NVARCHAR(50)))) = r.codArticu
        WHERE g.' + QUOTENAME(@colGva17Lista) + N' = @p_nro;';

    EXEC sp_executesql @sqlPrec, N'@p_nro INT', @p_nro = @nroLista;

    IF EXISTS (
        SELECT 1
        FROM #renglones AS r
        WHERE NOT EXISTS (
            SELECT 1 FROM #precios AS p WHERE p.codArticu = r.codArticu
        )
    )
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'precioFaltante' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(NULL AS DECIMAL(18,2)) AS importeValorizado,
            CAST(NULL AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    DECLARE @factor DECIMAL(18, 6) =
            CAST(1.0 AS DECIMAL(18, 6))
            - (CAST(ISNULL(@acopioDescuento, 0) AS DECIMAL(18, 6)) / CAST(100.0 AS DECIMAL(18, 6)));
    DECLARE @importeValorizado DECIMAL(18, 2) = 0;

    SELECT @importeValorizado = CAST(SUM(ROUND(p.precio * r.cantidad * @factor, 2)) AS DECIMAL(18, 2))
    FROM #renglones AS r
    INNER JOIN #precios AS p ON p.codArticu = r.codArticu;

    SET @importeValorizado = ISNULL(@importeValorizado, 0);

    IF @importeValorizado > @saldo_disponible
    BEGIN
        ROLLBACK TRAN;
        SELECT
            CAST(N'saldoInsuficiente' AS NVARCHAR(50)) AS resultCode,
            CAST(NULL AS INT) AS id,
            CAST(@importeValorizado AS DECIMAL(18,2)) AS importeValorizado,
            CAST(@saldo_disponible AS DECIMAL(18,2)) AS saldoDisponible,
            CAST(NULL AS DECIMAL(18,2)) AS saldoRestante,
            CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
            CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
        RETURN;
    END

    DECLARE @newId INT = NULL,
            @sqlIns NVARCHAR(MAX) = N'
        INSERT INTO dbo.PQ_ACOPIOS_PEDIDOS (
            ' + QUOTENAME(@colApTComp) + N',
            ' + QUOTENAME(@colApNComp) + N',
            ' + QUOTENAME(@colApTalon) + N',
            ' + QUOTENAME(@colApNro) + N',
            ' + QUOTENAME(@colApClient) + N',
            ' + QUOTENAME(@colApEstado) + N'
        )
        VALUES (@p_t, @p_n, @p_talon, @p_nro, @p_cli, 0);
        SET @o_id = CAST(SCOPE_IDENTITY() AS INT);';

    EXEC sp_executesql @sqlIns,
        N'@p_t NVARCHAR(10), @p_n NVARCHAR(50), @p_talon INT, @p_nro NVARCHAR(50),
          @p_cli NVARCHAR(20), @o_id INT OUTPUT',
        @p_t = @t_comp,
        @p_n = @n_comp,
        @p_talon = @talon_ped,
        @p_nro = @nro_pedido,
        @p_cli = @cod_client_ped,
        @o_id = @newId OUTPUT;

    COMMIT TRAN;

    SELECT
        CAST(N'OK' AS NVARCHAR(50)) AS resultCode,
        @newId AS id,
        @importeValorizado AS importeValorizado,
        @saldo_disponible AS saldoDisponible,
        CAST(ROUND(@saldo_disponible - @importeValorizado, 2) AS DECIMAL(18, 2)) AS saldoRestante,
        CAST(NULL AS NVARCHAR(20)) AS pedidoCodClient,
        CAST(NULL AS NVARCHAR(20)) AS acopioCodClient;
END
