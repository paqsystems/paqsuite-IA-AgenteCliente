CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_ListaPreciosOpciones
    @_database NVARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #resultado (
        id     INT            NOT NULL,
        numero NVARCHAR(20)   NOT NULL,
        nombre NVARCHAR(200)  NOT NULL,
        label  NVARCHAR(230)  NOT NULL
    );

    -- Guard: @_database nulo/vacío o DB inexistente → RS0(0) + RS1 vacío
    IF @_database IS NULL OR LTRIM(RTRIM(@_database)) = N''
       OR DB_ID(@_database) IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT id, numero, nombre, label FROM #resultado;
        RETURN;
    END

    DECLARE @bdQuoted NVARCHAR(270) = QUOTENAME(LTRIM(RTRIM(@_database)));

    -- Guard: GVA10 no existe en la company DB
    IF OBJECT_ID(@bdQuoted + N'.dbo.GVA10', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT id, numero, nombre, label FROM #resultado;
        RETURN;
    END

    DECLARE @colId     SYSNAME = NULL,
            @colNro    SYSNAME = NULL,
            @colNombre SYSNAME = NULL,
            @colHab    SYSNAME = NULL,
            @colDesde  SYSNAME = NULL,
            @colHasta  SYSNAME = NULL,
            @hasGva10  BIT     = 0;

    DECLARE @detectSql NVARCHAR(MAX) = N'
        SELECT
            @o_id     = MAX(CASE WHEN LOWER(c.COLUMN_NAME) IN (N''id_gva10'', N''idgva10'')
                            THEN c.COLUMN_NAME END),
            @o_nro    = MAX(CASE WHEN LOWER(c.COLUMN_NAME) IN (N''nro_de_lis'', N''nro_lista'')
                            THEN c.COLUMN_NAME END),
            @o_nombre = MAX(CASE WHEN LOWER(c.COLUMN_NAME) = N''nombre_lis''
                            THEN c.COLUMN_NAME END),
            @o_hab    = MAX(CASE WHEN LOWER(c.COLUMN_NAME) = N''habilitada''
                            THEN c.COLUMN_NAME END),
            @o_desde  = MAX(CASE WHEN LOWER(c.COLUMN_NAME) = N''fec_desde''
                            THEN c.COLUMN_NAME END),
            @o_hasta  = MAX(CASE WHEN LOWER(c.COLUMN_NAME) = N''fec_hasta''
                            THEN c.COLUMN_NAME END),
            @o_has    = MAX(CASE WHEN t.TABLE_NAME = N''GVA10'' THEN 1 ELSE 0 END)
        FROM ' + @bdQuoted + N'.INFORMATION_SCHEMA.TABLES t
        LEFT JOIN ' + @bdQuoted + N'.INFORMATION_SCHEMA.COLUMNS c
            ON c.TABLE_SCHEMA = t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT
           AND c.TABLE_NAME   = t.TABLE_NAME   COLLATE DATABASE_DEFAULT
        WHERE t.TABLE_SCHEMA = N''dbo''
          AND t.TABLE_NAME   = N''GVA10'';';

    EXEC sp_executesql @detectSql,
        N'@o_id SYSNAME OUTPUT, @o_nro SYSNAME OUTPUT, @o_nombre SYSNAME OUTPUT,
          @o_hab SYSNAME OUTPUT, @o_desde SYSNAME OUTPUT, @o_hasta SYSNAME OUTPUT,
          @o_has BIT OUTPUT',
        @o_id     = @colId     OUTPUT,
        @o_nro    = @colNro    OUTPUT,
        @o_nombre = @colNombre OUTPUT,
        @o_hab    = @colHab    OUTPUT,
        @o_desde  = @colDesde  OUTPUT,
        @o_hasta  = @colHasta  OUTPUT,
        @o_has    = @hasGva10  OUTPUT;

    -- Guard: tabla o columnas obligatorias no encontradas
    IF @hasGva10 = 0 OR @colId IS NULL OR @colNro IS NULL OR @colNombre IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT id, numero, nombre, label FROM #resultado;
        RETURN;
    END

    DECLARE @idQuoted  NVARCHAR(260) = QUOTENAME(@colId);
    DECLARE @nroQuoted NVARCHAR(260) = QUOTENAME(@colNro);
    DECLARE @nomQuoted NVARCHAR(260) = QUOTENAME(@colNombre);

    DECLARE @whereExtra NVARCHAR(MAX) = N'';
    IF @colHab IS NOT NULL
        SET @whereExtra += N' AND lis.' + QUOTENAME(@colHab) + N' = 1';
    IF @colDesde IS NOT NULL
        SET @whereExtra += N' AND (lis.' + QUOTENAME(@colDesde) + N' IS NULL
            OR CAST(lis.' + QUOTENAME(@colDesde) + N' AS DATE) <= CAST(GETDATE() AS DATE))';
    -- Tango usa 1800-01-01 / 1900-01-01 como "sin vencimiento": excluir solo fechas futuras reales
    IF @colHasta IS NOT NULL
        SET @whereExtra += N' AND (lis.' + QUOTENAME(@colHasta) + N' IS NULL
            OR CAST(lis.' + QUOTENAME(@colHasta) + N' AS DATE) <= CAST(N''1900-01-01'' AS DATE)
            OR CAST(lis.' + QUOTENAME(@colHasta) + N' AS DATE) >= CAST(GETDATE() AS DATE))';

    DECLARE @sql NVARCHAR(MAX) = N'
        INSERT INTO #resultado (id, numero, nombre, label)
        SELECT
            CAST(lis.' + @idQuoted + N' AS INT),
            ISNULL(LTRIM(RTRIM(CAST(lis.' + @nroQuoted + N' AS NVARCHAR(20)))), N'''')
                COLLATE DATABASE_DEFAULT,
            ISNULL(LTRIM(RTRIM(CAST(lis.' + @nomQuoted + N' AS NVARCHAR(200)))), N'''')
                COLLATE DATABASE_DEFAULT,
            CASE
                WHEN LTRIM(RTRIM(ISNULL(CAST(lis.' + @nroQuoted + N' AS NVARCHAR(20)), N''''))) <> N''''
                 AND LTRIM(RTRIM(ISNULL(CAST(lis.' + @nomQuoted + N' AS NVARCHAR(200)), N''''))) <> N''''
                    THEN LTRIM(RTRIM(CAST(lis.' + @nroQuoted + N' AS NVARCHAR(20))))
                       + N'' - ''
                       + LTRIM(RTRIM(CAST(lis.' + @nomQuoted + N' AS NVARCHAR(200))))
                WHEN LTRIM(RTRIM(ISNULL(CAST(lis.' + @nroQuoted + N' AS NVARCHAR(20)), N''''))) <> N''''
                    THEN LTRIM(RTRIM(CAST(lis.' + @nroQuoted + N' AS NVARCHAR(20))))
                WHEN LTRIM(RTRIM(ISNULL(CAST(lis.' + @nomQuoted + N' AS NVARCHAR(200)), N''''))) <> N''''
                    THEN LTRIM(RTRIM(CAST(lis.' + @nomQuoted + N' AS NVARCHAR(200))))
                ELSE N''''
            END COLLATE DATABASE_DEFAULT
        FROM ' + @bdQuoted + N'.dbo.GVA10 AS lis
        WHERE CAST(lis.' + @idQuoted + N' AS INT) > 0
        ' + @whereExtra + N'
        ORDER BY lis.' + @nroQuoted + N';';

    EXEC sp_executesql @sql;

    -- RS0
    SELECT CAST(COUNT(*) AS INT) AS total_filas FROM #resultado;

    -- RS1
    SELECT id, numero, nombre, label
    FROM #resultado
    ORDER BY numero;
END
