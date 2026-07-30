CREATE OR ALTER PROCEDURE dbo.PAQ_PartesProduccion_InformesGestion
    @Database       NVARCHAR(MAX) = NULL,
    @FechaDesde     NVARCHAR(MAX) = NULL,
    @FechaHasta     NVARCHAR(MAX) = NULL,
    @IdTurno        NVARCHAR(MAX) = NULL,
    @IdOperario     NVARCHAR(MAX) = NULL,
    @IdAsignacion   NVARCHAR(MAX) = NULL,
    @IdOrdenTrabajo NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Guard: tablas principales no existen → tres RS vacíos y salir
    IF OBJECT_ID(N'dbo.PQ_PRD_PARTES_ENTRADAS', N'U') IS NULL
       OR OBJECT_ID(N'dbo.PQ_PRD_PARTES_OPERARIO', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS INT) AS total_filas;

        SELECT
            CAST(NULL AS INT)            AS id_parte_entrada,
            CAST(NULL AS DATETIME)       AS fecha_parte,
            CAST(NULL AS INT)            AS id_turno,
            CAST(NULL AS NVARCHAR(50))   AS turno_codigo,
            CAST(NULL AS INT)            AS id_operario,
            CAST(NULL AS NVARCHAR(200))  AS operario_nombre,
            CAST(NULL AS INT)            AS id_orden_trabajo,
            CAST(NULL AS NVARCHAR(50))   AS codigo_ot,
            CAST(NULL AS INT)            AS id_articulo,
            CAST(NULL AS INT)            AS id_operacion,
            CAST(NULL AS NVARCHAR(50))   AS operacion_codigo,
            CAST(NULL AS INT)            AS id_maquina,
            CAST(NULL AS NVARCHAR(50))   AS maquina_codigo,
            CAST(NULL AS NVARCHAR(200))  AS unidad_negocio,
            CAST(NULL AS INT)            AS id_tipo_tarea,
            CAST(NULL AS INT)            AS id_concepto_tiempo,
            CAST(NULL AS NVARCHAR(50))   AS concepto_codigo,
            CAST(NULL AS INT)            AS productive_minutes,
            CAST(NULL AS INT)            AS non_productive_minutes,
            CAST(NULL AS DECIMAL(18,4))  AS units_done,
            CAST(NULL AS DECIMAL(18,4))  AS std_units_per_hour,
            CAST(NULL AS DECIMAL(18,4))  AS theoretical_units,
            CAST(NULL AS DECIMAL(18,2))  AS efficiency_pct
        WHERE 1 = 0;

        SELECT
            CAST(NULL AS INT)           AS total_productive_minutes,
            CAST(NULL AS INT)           AS total_non_productive_minutes,
            CAST(NULL AS DECIMAL(18,4)) AS total_theoretical_units,
            CAST(NULL AS DECIMAL(18,4)) AS total_units_done
        WHERE 1 = 0;

        RETURN;
    END

    DECLARE @hasSta11          BIT =
                CASE WHEN OBJECT_ID(N'dbo.STA11', N'U') IS NOT NULL THEN 1 ELSE 0 END,
            @hasArticuloCuenta BIT =
                CASE WHEN OBJECT_ID(N'dbo.ARTICULO_CUENTA', N'U') IS NOT NULL THEN 1 ELSE 0 END,
            @hasCuenta         BIT =
                CASE WHEN OBJECT_ID(N'dbo.CUENTA', N'U') IS NOT NULL THEN 1 ELSE 0 END;

    DECLARE @joinOptional NVARCHAR(MAX) = N'';
    DECLARE @unidadNegocioExpr NVARCHAR(MAX) = N'CAST(NULL AS NVARCHAR(200))';

    IF @hasSta11 = 1
    BEGIN
        SET @joinOptional = @joinOptional + N'
            LEFT JOIN dbo.' + QUOTENAME(N'STA11') + N' AS sta11
                ON sta11.ID_STA11 = COALESCE(e.ID_ARTICULO, ai.ID_ARTICULO)';
    END

    IF @hasSta11 = 1 AND @hasArticuloCuenta = 1
    BEGIN
        SET @joinOptional = @joinOptional + N'
            LEFT JOIN dbo.' + QUOTENAME(N'ARTICULO_CUENTA') + N' AS articulo_cuenta
                ON articulo_cuenta.COD_STA11 COLLATE DATABASE_DEFAULT
                 = sta11.COD_STA11 COLLATE DATABASE_DEFAULT';
    END

    IF @hasSta11 = 1 AND @hasArticuloCuenta = 1 AND @hasCuenta = 1
    BEGIN
        SET @joinOptional = @joinOptional + N'
            LEFT JOIN dbo.' + QUOTENAME(N'CUENTA') + N' AS cuenta
                ON cuenta.ID_CUENTA = articulo_cuenta.ID_CUENTA_VENTAS';
        SET @unidadNegocioExpr = N'cuenta.DESC_CUENTA';
    END

    DECLARE @fromJoins NVARCHAR(MAX) = N'
        FROM dbo.PQ_PRD_PARTES_ENTRADAS AS e
        INNER JOIN dbo.PQ_PRD_PARTES_OPERARIO AS p
            ON e.ID_PARTE_OPERARIO = p.ID_PARTE_OPERARIO
        INNER JOIN dbo.PQ_PRD_CONCEPTOS_TIEMPO AS c
            ON e.ID_CONCEPTO_TIEMPO = c.ID_CONCEPTO_TIEMPO
        LEFT JOIN dbo.PQ_PRD_ASIGNACIONES_ITEMS AS ai
            ON e.ID_ASIGNACION_ITEM = ai.ID_ASIGNACION_ITEM
        LEFT JOIN dbo.PQ_PRD_ORDENES_TRABAJO AS ot
            ON ot.ID_ORDEN_TRABAJO = COALESCE(e.ID_ORDEN_TRABAJO, ai.ID_ORDEN_TRABAJO)
        LEFT JOIN dbo.PQ_PRD_OPERACIONES AS op
            ON op.ID_OPERACION = COALESCE(e.ID_OPERACION, ot.ID_OPERACION, ai.ID_OPERACION)
        LEFT JOIN dbo.PQ_PRD_MAQUINAS AS m
            ON m.ID_MAQUINA = COALESCE(e.ID_MAQUINA, ai.ID_MAQUINA)
        LEFT JOIN dbo.PQ_PRD_TIPOS_TAREA AS tt
            ON tt.ID_TIPO_TAREA = COALESCE(e.ID_TIPO_TAREA, ai.ID_TIPO_TAREA)
        LEFT JOIN dbo.PQ_PRD_TURNOS AS t
            ON p.ID_TURNO = t.ID_TURNO
        LEFT JOIN dbo.PQ_SUELD_LEGAJOS AS leg
            ON p.ID_OPERARIO = leg.ID'
        + @joinOptional;

    DECLARE @where NVARCHAR(MAX) = N'
        WHERE 1 = 1';

    IF @FechaDesde IS NOT NULL AND LTRIM(RTRIM(@FechaDesde)) <> N''
        SET @where = @where + N'
          AND p.FECHA_PARTE >= TRY_CONVERT(DATE, @p_fecha_desde)';

    IF @FechaHasta IS NOT NULL AND LTRIM(RTRIM(@FechaHasta)) <> N''
        SET @where = @where + N'
          AND p.FECHA_PARTE <= TRY_CONVERT(DATE, @p_fecha_hasta)';

    IF @IdTurno IS NOT NULL AND LTRIM(RTRIM(@IdTurno)) <> N''
        SET @where = @where + N'
          AND p.ID_TURNO = TRY_CONVERT(INT, @p_id_turno)';

    IF @IdOperario IS NOT NULL AND LTRIM(RTRIM(@IdOperario)) <> N''
        SET @where = @where + N'
          AND p.ID_OPERARIO = TRY_CONVERT(INT, @p_id_operario)';

    IF @IdAsignacion IS NOT NULL AND LTRIM(RTRIM(@IdAsignacion)) <> N''
        SET @where = @where + N'
          AND ai.ID_ASIGNACION = TRY_CONVERT(INT, @p_id_asignacion)';

    IF @IdOrdenTrabajo IS NOT NULL AND LTRIM(RTRIM(@IdOrdenTrabajo)) <> N''
        SET @where = @where + N'
          AND (e.ID_ORDEN_TRABAJO = TRY_CONVERT(INT, @p_id_orden_trabajo)
               OR ai.ID_ORDEN_TRABAJO = TRY_CONVERT(INT, @p_id_orden_trabajo))';

    DECLARE @paramDef NVARCHAR(MAX) = N'
        @p_fecha_desde     NVARCHAR(MAX),
        @p_fecha_hasta     NVARCHAR(MAX),
        @p_id_turno        NVARCHAR(MAX),
        @p_id_operario     NVARCHAR(MAX),
        @p_id_asignacion   NVARCHAR(MAX),
        @p_id_orden_trabajo NVARCHAR(MAX)';

    DECLARE @countSql NVARCHAR(MAX) = N'
        SELECT COUNT(*) AS total_filas'
        + @fromJoins
        + @where;

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            e.ID_PARTE_ENTRADA AS id_parte_entrada,
            p.FECHA_PARTE AS fecha_parte,
            p.ID_TURNO AS id_turno,
            t.CODIGO_TURNO AS turno_codigo,
            p.ID_OPERARIO AS id_operario,
            LTRIM(RTRIM(ISNULL(leg.APELLIDO, N'''') + N'' '' + ISNULL(leg.NOMBRE, N''''))) AS operario_nombre,
            COALESCE(e.ID_ORDEN_TRABAJO, ai.ID_ORDEN_TRABAJO) AS id_orden_trabajo,
            ot.CODIGO_OT AS codigo_ot,
            COALESCE(e.ID_ARTICULO, ai.ID_ARTICULO) AS id_articulo,
            COALESCE(e.ID_OPERACION, ot.ID_OPERACION, ai.ID_OPERACION) AS id_operacion,
            op.CODIGO_OPERACION AS operacion_codigo,
            COALESCE(e.ID_MAQUINA, ai.ID_MAQUINA) AS id_maquina,
            m.CODIGO_MAQUINA AS maquina_codigo,
            ' + @unidadNegocioExpr + N' AS unidad_negocio,
            COALESCE(e.ID_TIPO_TAREA, ai.ID_TIPO_TAREA) AS id_tipo_tarea,
            c.ID_CONCEPTO_TIEMPO AS id_concepto_tiempo,
            c.CODIGO_CONCEPTO AS concepto_codigo,
            CASE WHEN c.ES_PRODUCTIVO = 1 THEN COALESCE(e.MINUTOS, 0) ELSE 0 END AS productive_minutes,
            CASE WHEN c.ES_PRODUCTIVO = 0 THEN COALESCE(e.MINUTOS, 0) ELSE 0 END AS non_productive_minutes,
            e.UNIDADES_HECHAS AS units_done,
            ai.UNIDADES_HORA_STD AS std_units_per_hour,
            CASE WHEN ISNULL(ai.UNIDADES_HORA_STD, 0) > 0
                 THEN ROUND(
                        (CAST(CASE WHEN c.ES_PRODUCTIVO = 1 THEN COALESCE(e.MINUTOS, 0) ELSE 0 END AS FLOAT) / 60.0)
                        * CAST(ai.UNIDADES_HORA_STD AS FLOAT), 4)
                 ELSE NULL
            END AS theoretical_units,
            CASE WHEN ISNULL(ai.UNIDADES_HORA_STD, 0) > 0
                      AND CASE WHEN c.ES_PRODUCTIVO = 1 THEN COALESCE(e.MINUTOS, 0) ELSE 0 END > 0
                      AND e.UNIDADES_HECHAS IS NOT NULL
                 THEN ROUND(
                        100.0 * CAST(e.UNIDADES_HECHAS AS FLOAT)
                        / ((CAST(CASE WHEN c.ES_PRODUCTIVO = 1 THEN COALESCE(e.MINUTOS, 0) ELSE 0 END AS FLOAT) / 60.0)
                           * CAST(ai.UNIDADES_HORA_STD AS FLOAT)), 2)
                 ELSE NULL
            END AS efficiency_pct'
        + @fromJoins
        + @where
        + N'
        ORDER BY p.FECHA_PARTE DESC, e.ID_PARTE_ENTRADA ASC';

    DECLARE @resumenSql NVARCHAR(MAX) = N'
        SELECT
            SUM(CASE WHEN c.ES_PRODUCTIVO = 1 THEN COALESCE(e.MINUTOS, 0) ELSE 0 END)
                AS total_productive_minutes,
            SUM(CASE WHEN c.ES_PRODUCTIVO = 0 THEN COALESCE(e.MINUTOS, 0) ELSE 0 END)
                AS total_non_productive_minutes,
            ROUND(SUM(
                CASE WHEN ISNULL(ai.UNIDADES_HORA_STD, 0) > 0
                     THEN (CAST(CASE WHEN c.ES_PRODUCTIVO = 1 THEN COALESCE(e.MINUTOS, 0) ELSE 0 END AS FLOAT) / 60.0)
                          * CAST(ai.UNIDADES_HORA_STD AS FLOAT)
                     ELSE 0
                END), 4) AS total_theoretical_units,
            SUM(e.UNIDADES_HECHAS) AS total_units_done'
        + @fromJoins
        + @where;

    -- RS0: total_filas
    EXEC sp_executesql
        @countSql,
        @paramDef,
        @p_fecha_desde = @FechaDesde,
        @p_fecha_hasta = @FechaHasta,
        @p_id_turno = @IdTurno,
        @p_id_operario = @IdOperario,
        @p_id_asignacion = @IdAsignacion,
        @p_id_orden_trabajo = @IdOrdenTrabajo;

    -- RS1: filas
    EXEC sp_executesql
        @sql,
        @paramDef,
        @p_fecha_desde = @FechaDesde,
        @p_fecha_hasta = @FechaHasta,
        @p_id_turno = @IdTurno,
        @p_id_operario = @IdOperario,
        @p_id_asignacion = @IdAsignacion,
        @p_id_orden_trabajo = @IdOrdenTrabajo;

    -- RS2: resumen
    EXEC sp_executesql
        @resumenSql,
        @paramDef,
        @p_fecha_desde = @FechaDesde,
        @p_fecha_hasta = @FechaHasta,
        @p_id_turno = @IdTurno,
        @p_id_operario = @IdOperario,
        @p_id_asignacion = @IdAsignacion,
        @p_id_orden_trabajo = @IdOrdenTrabajo;
END
