CREATE OR ALTER PROCEDURE dbo.PAQ_Clientes_Buscar
    @texto NVARCHAR(100),
    @limit INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@limit)
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
      AND (
          RAZON_SOCI LIKE N'%' + @texto + N'%'
          OR COD_CLIENT LIKE N'%' + @texto + N'%'
          OR NOM_COM LIKE N'%' + @texto + N'%'
      )
    ORDER BY RAZON_SOCI;
END
