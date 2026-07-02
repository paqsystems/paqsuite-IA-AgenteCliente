CREATE OR ALTER PROCEDURE dbo.PAQ_Pedidos_Pendientes
    @codigoCliente NVARCHAR(20),
    @limit         INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@limit)
        LTRIM(RTRIM(NRO_PEDIDO))  AS nroPedido,
        LTRIM(RTRIM(COD_CLIENT))  AS codigoCliente,
        FECHA_PEDI                AS fechaPedido,
        FECHA_ENTR                AS fechaEntrega,
        ESTADO                    AS estado,
        TOTAL_PEDI                AS totalPedido,
        LTRIM(RTRIM(COD_VENDED))  AS codigoVendedor
    FROM dbo.GVA21
    WHERE LTRIM(RTRIM(COD_CLIENT)) = LTRIM(RTRIM(@codigoCliente))
      AND ESTADO NOT IN (3, 5)
    ORDER BY FECHA_PEDI DESC;
END
