CREATE OR ALTER PROCEDURE dbo.PAQ_Acopios_ParametrosList
AS
BEGIN
    SET NOCOUNT ON;

    -- Guard: tabla principal no existe → dual RS vacío y salir
    IF OBJECT_ID(N'dbo.PQ_PARAMETROS_GRAL', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(100)) AS Clave,
            CAST(NULL AS NVARCHAR(10))  AS Tipo_Valor,
            CAST(NULL AS BIT)           AS Valor_Bool,
            CAST(NULL AS INT)           AS Valor_Int,
            CAST(NULL AS DECIMAL(18,4)) AS Valor_Decimal,
            CAST(NULL AS NVARCHAR(MAX)) AS Valor_String,
            CAST(NULL AS DATETIME)      AS Valor_DateTime,
            CAST(NULL AS NVARCHAR(MAX)) AS Valor_Text
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @hasValorBool     BIT = 0,
            @hasValorInt      BIT = 0,
            @hasValorDecimal  BIT = 0,
            @hasValorString   BIT = 0,
            @hasValorDateTime BIT = 0,
            @hasValorText     BIT = 0,
            @hasTipoValor     BIT = 0,
            @hasClave         BIT = 0,
            @hasPrograma      BIT = 0;

    DECLARE @colValorBool     SYSNAME = NULL,
            @colValorInt      SYSNAME = NULL,
            @colValorDecimal  SYSNAME = NULL,
            @colValorString   SYSNAME = NULL,
            @colValorDateTime SYSNAME = NULL,
            @colValorText     SYSNAME = NULL,
            @colTipoValor     SYSNAME = NULL,
            @colClave         SYSNAME = NULL,
            @colPrograma      SYSNAME = NULL;

    SELECT
        @colClave = MAX(CASE WHEN LOWER(COLUMN_NAME) = N'clave' THEN COLUMN_NAME END),
        @colPrograma = MAX(CASE WHEN LOWER(COLUMN_NAME) = N'programa' THEN COLUMN_NAME END),
        @colTipoValor = MAX(CASE WHEN LOWER(COLUMN_NAME) IN (N'tipo_valor', N'tipovalor') THEN COLUMN_NAME END),
        @colValorBool = MAX(CASE WHEN LOWER(COLUMN_NAME) = N'valor_bool' THEN COLUMN_NAME END),
        @colValorInt = MAX(CASE WHEN LOWER(COLUMN_NAME) = N'valor_int' THEN COLUMN_NAME END),
        @colValorDecimal = MAX(CASE WHEN LOWER(COLUMN_NAME) IN (N'valor_decimal', N'valor_decimale') THEN COLUMN_NAME END),
        @colValorString = MAX(CASE WHEN LOWER(COLUMN_NAME) = N'valor_string' THEN COLUMN_NAME END),
        @colValorDateTime = MAX(CASE WHEN LOWER(COLUMN_NAME) IN (N'valor_datetime', N'valor_date_time') THEN COLUMN_NAME END),
        @colValorText = MAX(CASE WHEN LOWER(COLUMN_NAME) = N'valor_text' THEN COLUMN_NAME END)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = N'PQ_PARAMETROS_GRAL';

    SET @hasClave = CASE WHEN @colClave IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasPrograma = CASE WHEN @colPrograma IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasTipoValor = CASE WHEN @colTipoValor IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasValorBool = CASE WHEN @colValorBool IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasValorInt = CASE WHEN @colValorInt IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasValorDecimal = CASE WHEN @colValorDecimal IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasValorString = CASE WHEN @colValorString IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasValorDateTime = CASE WHEN @colValorDateTime IS NOT NULL THEN 1 ELSE 0 END;
    SET @hasValorText = CASE WHEN @colValorText IS NOT NULL THEN 1 ELSE 0 END;

    IF @hasClave = 0 OR @hasPrograma = 0
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;
        SELECT
            CAST(NULL AS NVARCHAR(100)) AS Clave,
            CAST(NULL AS NVARCHAR(10))  AS Tipo_Valor,
            CAST(NULL AS BIT)           AS Valor_Bool,
            CAST(NULL AS INT)           AS Valor_Int,
            CAST(NULL AS DECIMAL(18,4)) AS Valor_Decimal,
            CAST(NULL AS NVARCHAR(MAX)) AS Valor_String,
            CAST(NULL AS DATETIME)      AS Valor_DateTime,
            CAST(NULL AS NVARCHAR(MAX)) AS Valor_Text
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @claveQuoted NVARCHAR(260) = QUOTENAME(@colClave);
    DECLARE @programaQuoted NVARCHAR(260) = QUOTENAME(@colPrograma);

    DECLARE @countSql NVARCHAR(MAX) = N'
        SELECT COUNT(*) AS total_filas
        FROM dbo.PQ_PARAMETROS_GRAL
        WHERE LOWER(' + @programaQuoted + N') = LOWER(N''Acopios'')
          AND ISNULL(CAST(' + @claveQuoted + N' AS NVARCHAR(100)), N'''') <> N''''';

    -- RS0: total de filas (sin paginación; consistencia dual-RS)
    EXEC sp_executesql @countSql;

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            ISNULL(CAST(' + @claveQuoted + N' AS NVARCHAR(100)), N'''') AS Clave,
            ' + CASE WHEN @hasTipoValor = 1
                THEN N'CAST(' + QUOTENAME(@colTipoValor) + N' AS NVARCHAR(10))'
                ELSE N'CAST(NULL AS NVARCHAR(10))' END + N' AS Tipo_Valor,
            ' + CASE WHEN @hasValorBool = 1
                THEN N'CAST(' + QUOTENAME(@colValorBool) + N' AS BIT)'
                ELSE N'CAST(NULL AS BIT)' END + N' AS Valor_Bool,
            ' + CASE WHEN @hasValorInt = 1
                THEN N'CAST(' + QUOTENAME(@colValorInt) + N' AS INT)'
                ELSE N'CAST(NULL AS INT)' END + N' AS Valor_Int,
            ' + CASE WHEN @hasValorDecimal = 1
                THEN N'CAST(' + QUOTENAME(@colValorDecimal) + N' AS DECIMAL(18,4))'
                ELSE N'CAST(NULL AS DECIMAL(18,4))' END + N' AS Valor_Decimal,
            ' + CASE WHEN @hasValorString = 1
                THEN N'CAST(' + QUOTENAME(@colValorString) + N' AS NVARCHAR(MAX))'
                ELSE N'CAST(NULL AS NVARCHAR(MAX))' END + N' AS Valor_String,
            ' + CASE WHEN @hasValorDateTime = 1
                THEN N'CAST(' + QUOTENAME(@colValorDateTime) + N' AS DATETIME)'
                ELSE N'CAST(NULL AS DATETIME)' END + N' AS Valor_DateTime,
            ' + CASE WHEN @hasValorText = 1
                THEN N'CAST(' + QUOTENAME(@colValorText) + N' AS NVARCHAR(MAX))'
                ELSE N'CAST(NULL AS NVARCHAR(MAX))' END + N' AS Valor_Text
        FROM dbo.PQ_PARAMETROS_GRAL
        WHERE LOWER(' + @programaQuoted + N') = LOWER(N''Acopios'')
          AND ISNULL(CAST(' + @claveQuoted + N' AS NVARCHAR(100)), N'''') <> N''''
        ORDER BY ' + @claveQuoted;

    -- RS1: filas
    EXEC sp_executesql @sql;
END
