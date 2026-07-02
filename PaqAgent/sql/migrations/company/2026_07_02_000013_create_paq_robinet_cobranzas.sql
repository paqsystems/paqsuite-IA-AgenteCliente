CREATE OR ALTER PROCEDURE dbo.PAQ_Robinet_Cobranzas
    @fecha_desde       DATETIME,
    @fecha_hasta       DATETIME,
    @prefijo_acopio    NVARCHAR(50)  = NULL,
    @cod_client        NVARCHAR(20)  = NULL,
    @vendedor          NVARCHAR(20)  = NULL,
    @zona              NVARCHAR(20)  = NULL,
    @rubro             NVARCHAR(20)  = NULL,
    @transporte        NVARCHAR(20)  = NULL,
    @provincia         NVARCHAR(20)  = NULL,
    @condicion_venta   NVARCHAR(20)  = NULL,
    @empresa           NVARCHAR(20)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hasItc BIT=0, @hasFld BIT=0,
            @hasGva07 BIT=0, @hasGva53 BIT=0, @hasImporteTot BIT=0;
    IF OBJECT_ID(N'dbo.GVA14ITC',N'U') IS NOT NULL SET @hasItc=1;
    IF OBJECT_ID(N'dbo.GVA14FLD',N'U') IS NOT NULL SET @hasFld=1;
    IF OBJECT_ID(N'dbo.GVA07',   N'U') IS NOT NULL SET @hasGva07=1;
    IF OBJECT_ID(N'dbo.GVA53',   N'U') IS NOT NULL SET @hasGva53=1;
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='GVA12' AND COLUMN_NAME='IMPORTE_TOT')
        SET @hasImporteTot=1;

    DECLARE @canalExpr   NVARCHAR(200),
            @segExpr     NVARCHAR(200),
            @joinClassif NVARCHAR(400),
            @acopioExpr  NVARCHAR(500),
            @importeCol  NVARCHAR(50);

    SET @canalExpr = CASE WHEN @hasItc=1 AND @hasFld=1
        THEN N'CAST(ISNULL(fld.DESCRIP,'''') AS VARCHAR(200))'
        ELSE N'CAST('''' AS VARCHAR(200))' END;
    SET @segExpr = CASE WHEN @hasItc=1 AND @hasFld=1
        THEN N'CAST(ISNULL(itc.DESCRIP,'''') AS VARCHAR(200))'
        ELSE N'CAST('''' AS VARCHAR(200))' END;
    SET @joinClassif = CASE WHEN @hasItc=1 AND @hasFld=1
        THEN N'LEFT JOIN GVA14ITC itc ON cl.ID_GVA14=itc.ID_GVA14
               LEFT JOIN GVA14FLD fld ON itc.IDFOLDER=fld.IDFOLDER'
        ELSE N'' END;
    SET @acopioExpr = CASE WHEN @hasGva07=1 AND @hasGva53=1
        THEN N'CASE WHEN EXISTS (
                SELECT 1 FROM GVA07 j
                INNER JOIN GVA12 inv ON inv.T_COMP=j.T_COMP AND inv.N_COMP=j.N_COMP
                INNER JOIN GVA53 r53 ON r53.T_COMP=inv.T_COMP AND r53.N_COMP=inv.N_COMP
                WHERE j.T_COMP_CAN=rec.T_COMP AND j.N_COMP_CAN=rec.N_COMP
                AND r53.COD_ARTICU LIKE CONCAT(@p_pref,''%'')
            ) THEN ''SI'' ELSE ''NO'' END'
        ELSE N'''NO''' END;
    SET @importeCol = CASE WHEN @hasImporteTot=1
        THEN N'rec.IMPORTE_TOT' ELSE N'rec.IMPORTE' END;

    DECLARE @where NVARCHAR(1000) =
        N'rec.T_COMP=''REC''
          AND (rec.ESTADO IS NULL OR UPPER(LTRIM(RTRIM(rec.ESTADO)))<>''ANU'')
          AND rec.FECHA_EMIS>=@p_fd AND rec.FECHA_EMIS<=@p_fh';

    IF @cod_client      IS NOT NULL AND @cod_client      <> N'' SET @where += N' AND rec.COD_CLIENT=@p_cc';
    IF @vendedor        IS NOT NULL AND @vendedor        <> N'' SET @where += N' AND cl.COD_VENDED=@p_ve';
    IF @zona            IS NOT NULL AND @zona            <> N'' SET @where += N' AND cl.COD_ZONA=@p_zo';
    IF @rubro           IS NOT NULL AND @rubro           <> N'' SET @where += N' AND cl.COD_RUBRO=@p_ru';
    IF @transporte      IS NOT NULL AND @transporte      <> N'' SET @where += N' AND cl.COD_TRANSP=@p_tr';
    IF @provincia       IS NOT NULL AND @provincia       <> N'' SET @where += N' AND cl.COD_PROVIN=@p_pr';
    IF @condicion_venta IS NOT NULL AND @condicion_venta <> N'' SET @where += N' AND cl.COND_VTA=@p_cv';

    DECLARE @sql NVARCHAR(MAX) = N'
        SELECT
            rec.FECHA_EMIS  AS fecha_emis,
            ' + @canalExpr  + N' AS canal,
            ' + @segExpr    + N' AS segmento,
            rec.COD_CLIENT  AS cod_client,
            cl.RAZON_SOCI   AS razon_soci,
            rec.T_COMP      AS t_comp,
            rec.N_COMP      AS n_comp,
            ' + @acopioExpr + N' AS acopio,
            ' + @importeCol + N' AS importe_tot,
            @p_emp          AS empresa
        FROM GVA12 rec
        INNER JOIN GVA14 cl ON rec.COD_CLIENT=cl.COD_CLIENT
        ' + @joinClassif + N'
        WHERE ' + @where;

    EXEC sp_executesql @sql,
        N'@p_fd DATETIME, @p_fh DATETIME, @p_pref NVARCHAR(50),
          @p_cc NVARCHAR(20), @p_ve NVARCHAR(20), @p_zo NVARCHAR(20),
          @p_ru NVARCHAR(20), @p_tr NVARCHAR(20), @p_pr NVARCHAR(20),
          @p_cv NVARCHAR(20), @p_emp NVARCHAR(20)',
        @p_fd=@fecha_desde, @p_fh=@fecha_hasta, @p_pref=@prefijo_acopio,
        @p_cc=@cod_client,  @p_ve=@vendedor,    @p_zo=@zona,
        @p_ru=@rubro,       @p_tr=@transporte,  @p_pr=@provincia,
        @p_cv=@condicion_venta, @p_emp=@empresa;
END
