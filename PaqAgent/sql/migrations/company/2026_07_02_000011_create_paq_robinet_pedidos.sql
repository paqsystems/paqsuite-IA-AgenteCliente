CREATE OR ALTER PROCEDURE dbo.PAQ_Robinet_Pedidos
    @fecha_desde    DATETIME,
    @fecha_hasta    DATETIME,
    @cod_client     NVARCHAR(20)  = NULL,
    @talon_ped      NVARCHAR(20)  = NULL,
    @cod_articu     NVARCHAR(30)  = NULL,
    @empresa        NVARCHAR(20)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Detectar tablas/columnas opcionales
    DECLARE @hasItc      BIT = 0, @hasFld      BIT = 0,
            @hasG45      BIT = 0, @hasSta11    BIT = 0,
            @hasIdParentFld BIT = 0, @hasIdParentItc BIT = 0,
            @hasCantPedid BIT = 0, @hasCantPenF  BIT = 0,
            @hasPrecio    BIT = 0, @hasMonCte    BIT = 0;

    IF OBJECT_ID(N'dbo.GVA14ITC', N'U') IS NOT NULL SET @hasItc = 1;
    IF OBJECT_ID(N'dbo.GVA14FLD', N'U') IS NOT NULL SET @hasFld = 1;
    IF OBJECT_ID(N'dbo.GVA45',    N'U') IS NOT NULL SET @hasG45  = 1;
    IF OBJECT_ID(N'dbo.STA11',    N'U') IS NOT NULL SET @hasSta11 = 1;
    IF @hasFld = 1 AND EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA14FLD' AND COLUMN_NAME='IDPARENT')
        SET @hasIdParentFld = 1;
    IF @hasItc = 1 AND EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA14ITC' AND COLUMN_NAME='IDPARENT')
        SET @hasIdParentItc = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA03' AND COLUMN_NAME='CANT_PEDID')
        SET @hasCantPedid = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA03' AND COLUMN_NAME='CANT_PEN_F')
        SET @hasCantPenF = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA03' AND COLUMN_NAME='PRECIO')
        SET @hasPrecio = 1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA21' AND COLUMN_NAME='MON_CTE')
        SET @hasMonCte = 1;

    -- Construir expresiones dinámicas
    DECLARE @canalExpr   NVARCHAR(500),
            @articuloCol NVARCHAR(200),
            @leyendaCol  NVARCHAR(200),
            @cantPed     NVARCHAR(100),
            @cantPend    NVARCHAR(200),
            @precioUni   NVARCHAR(100),
            @monedaExpr  NVARCHAR(200),
            @joinCanal   NVARCHAR(500),
            @joinSta     NVARCHAR(200),
            @joinG45     NVARCHAR(300);

    SET @canalExpr = CASE
        WHEN @hasItc=1 AND @hasFld=1 AND @hasIdParentFld=1
            THEN N'CASE WHEN fld.IDPARENT=1 THEN CAST(ISNULL(fld.DESCRIP,'''') AS VARCHAR(200)) ELSE ''DISTRIBUIDORES'' END'
        WHEN @hasItc=1 AND @hasFld=1
            THEN N'CAST(ISNULL(fld.DESCRIP,'''') AS VARCHAR(200))'
        ELSE N'CAST('''' AS VARCHAR(200))'
    END;

    SET @joinCanal = CASE
        WHEN @hasItc=1 AND @hasFld=1 AND @hasIdParentItc=1
            THEN N'LEFT JOIN GVA14ITC itc ON cl.ID_GVA14=itc.ID_GVA14 AND itc.IDPARENT=1
                   LEFT JOIN GVA14FLD fld ON itc.IDFOLDER=fld.IDFOLDER'
        WHEN @hasItc=1 AND @hasFld=1
            THEN N'LEFT JOIN GVA14ITC itc ON cl.ID_GVA14=itc.ID_GVA14
                   LEFT JOIN GVA14FLD fld ON itc.IDFOLDER=fld.IDFOLDER'
        ELSE N''
    END;

    SET @articuloCol = CASE WHEN @hasSta11=1
        THEN N'CAST(ISNULL(sta11.DESCRIP,'''') AS VARCHAR(200))'
        ELSE N'CAST('''' AS VARCHAR(200))' END;
    SET @joinSta = CASE WHEN @hasSta11=1
        THEN N'LEFT JOIN STA11 sta11 ON g03.COD_ARTICU=sta11.COD_ARTICU'
        ELSE N'' END;
    SET @joinG45 = CASE WHEN @hasG45=1
        THEN N'LEFT JOIN GVA45 g45 ON g45.T_COMP=''PED'' AND g45.N_COMP=g03.NRO_PEDIDO AND g45.N_RENGLON=g03.N_RENGLON'
        ELSE N'' END;
    SET @leyendaCol = CASE WHEN @hasG45=1 THEN N'g45.DESC_ADIC' ELSE N'CAST(NULL AS VARCHAR(200))' END;
    SET @cantPed    = CASE WHEN @hasCantPedid=1 THEN N'g03.CANT_PEDID' ELSE N'CAST(0 AS DECIMAL(18,4))' END;
    SET @cantPend   = CASE WHEN @hasCantPenF=1
        THEN N'ISNULL(g03.CANT_PEN_F,ISNULL(g03.CANT_PEN_D,0))'
        ELSE N'CAST(0 AS DECIMAL(18,4))' END;
    SET @precioUni  = CASE WHEN @hasPrecio=1 THEN N'g03.PRECIO' ELSE N'CAST(0 AS DECIMAL(18,4))' END;
    SET @monedaExpr = CASE WHEN @hasMonCte=1
        THEN N'CASE WHEN g21.MON_CTE=1 THEN ''PESOS'' ELSE ''DOLARES'' END'
        ELSE N'CAST('''' AS VARCHAR(20))' END;

    -- Construir WHERE dinámico
    DECLARE @where    NVARCHAR(1000) = N'g21.ESTADO<>5 AND g21.FECHA_PEDI>=@p_fd AND g21.FECHA_PEDI<=@p_fh';
    IF @cod_client IS NOT NULL AND @cod_client <> N''
        SET @where += N' AND g21.COD_CLIENT=@p_cc';
    IF @talon_ped  IS NOT NULL AND @talon_ped  <> N''
        SET @where += N' AND g21.TALON_PED=@p_tp';
    IF @cod_articu IS NOT NULL AND @cod_articu <> N''
        SET @where += N' AND g03.COD_ARTICU=@p_ca';

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            g21.FECHA_PEDI      AS fecha_pedi,
            g21.TALON_PED       AS talon_ped,
            g21.NRO_PEDIDO      AS nro_pedido,
            g21.COD_CLIENT      AS cod_client,
            cl.RAZON_SOCI       AS razon_soci,
            ' + @canalExpr   + N' AS canal,
            g03.COD_ARTICU      AS cod_articu,
            ' + @articuloCol + N' AS articulo,
            ' + @leyendaCol  + N' AS leyenda,
            ' + @cantPed     + N' AS cant_ped,
            ' + @cantPend    + N' AS cant_pend,
            ' + @precioUni   + N' AS precio_uni,
            ' + @precioUni   + N' AS precio_convertido,
            ' + @monedaExpr  + N' AS moneda,
            @p_emp              AS empresa
        FROM GVA21 g21
        INNER JOIN GVA14 cl  ON g21.COD_CLIENT=cl.COD_CLIENT
        INNER JOIN GVA03 g03 ON g21.TALON_PED=g03.TALON_PED AND g21.NRO_PEDIDO=g03.NRO_PEDIDO
        ' + @joinSta   + N'
        ' + @joinG45   + N'
        ' + @joinCanal + N'
        WHERE ' + @where;

    EXEC sp_executesql @sql,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_cc NVARCHAR(20),
          @p_tp NVARCHAR(20), @p_ca NVARCHAR(30), @p_emp NVARCHAR(20)',
        @p_fd=@fecha_desde, @p_fh=@fecha_hasta,
        @p_cc=@cod_client,  @p_tp=@talon_ped,
        @p_ca=@cod_articu,  @p_emp=@empresa;
END
