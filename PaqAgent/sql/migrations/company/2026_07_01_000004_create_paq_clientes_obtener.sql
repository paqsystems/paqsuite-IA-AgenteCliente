CREATE OR ALTER PROCEDURE dbo.PAQ_Clientes_Obtener
    @codigo NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1
        LTRIM(RTRIM(COD_CLIENT))  AS codigo,
        LTRIM(RTRIM(RAZON_SOCI))  AS razonSocial,
        LTRIM(RTRIM(NOM_COM))     AS nomComercial,
        LTRIM(RTRIM(CUIT))        AS cuit,
        LTRIM(RTRIM(E_MAIL))      AS email,
        LTRIM(RTRIM(DOMICILIO))   AS domicilio,
        LTRIM(RTRIM(LOCALIDAD))   AS localidad,
        LTRIM(RTRIM(TELEFONO_1))  AS telefono
    FROM dbo.GVA14
    WHERE HABILITADO = 1
      AND LTRIM(RTRIM(COD_CLIENT)) = LTRIM(RTRIM(@codigo));
END
