CREATE OR ALTER PROCEDURE dbo.PAQ_Comprobantes_Recientes
    @codigoCliente NVARCHAR(20),
    @dias          INT = 30,
    @limit         INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@limit)
        LTRIM(RTRIM(T_COMP))      AS tipoComprobante,
        LTRIM(RTRIM(N_COMP))      AS nroComprobante,
        LTRIM(RTRIM(COD_CLIENT))  AS codigoCliente,
        FECHA_EMIS                AS fechaEmision,
        IMPORTE                   AS importe,
        LTRIM(RTRIM(ESTADO))      AS estado,
        LTRIM(RTRIM(COD_VENDED))  AS codigoVendedor
    FROM dbo.GVA12
    WHERE LTRIM(RTRIM(COD_CLIENT)) = LTRIM(RTRIM(@codigoCliente))
      AND FECHA_EMIS >= DATEADD(day, -@dias, GETDATE())
      AND FECHA_ANU IS NULL
    ORDER BY FECHA_EMIS DESC;
END
