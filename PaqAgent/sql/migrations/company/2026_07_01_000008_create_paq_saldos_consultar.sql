CREATE OR ALTER PROCEDURE dbo.PAQ_Saldos_Consultar
    @codigoCliente NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1
        LTRIM(RTRIM(COD_CLIENT))  AS codigoCliente,
        LTRIM(RTRIM(RAZON_SOCI))  AS razonSocial,
        SALDO_CC                  AS saldoCuentaCorriente,
        SALDO_DOC                 AS saldoDocumentos,
        SALDO_ANT                 AS saldoAnterior,
        SALDO_D_UN                AS saldoMonedaExtranjera
    FROM dbo.GVA14
    WHERE HABILITADO = 1
      AND LTRIM(RTRIM(COD_CLIENT)) = LTRIM(RTRIM(@codigoCliente));
END
