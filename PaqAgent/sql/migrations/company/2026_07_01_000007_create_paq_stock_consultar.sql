CREATE OR ALTER PROCEDURE dbo.PAQ_Stock_Consultar
    @codigoArticulo NVARCHAR(50),
    @deposito       NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        LTRIM(RTRIM(s.COD_ARTICU))  AS codigoArticulo,
        LTRIM(RTRIM(s.COD_DEPOSI))  AS codigoDeposito,
        LTRIM(RTRIM(d.NOMBRE_SUC))  AS nombreDeposito,
        s.CANT_STOCK                AS cantStock,
        s.CANT_PEND                 AS cantPendiente,
        s.CANT_COMP                 AS cantComprometido
    FROM dbo.STA19 s
    LEFT JOIN dbo.STA22 d ON d.ID_STA22 = s.ID_STA22
    WHERE s.COD_ARTICU = @codigoArticulo
      AND (@deposito IS NULL OR s.COD_DEPOSI = @deposito)
    ORDER BY s.COD_DEPOSI;
END
