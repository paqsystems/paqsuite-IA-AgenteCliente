CREATE OR ALTER PROCEDURE dbo.PAQ_Articulos_Obtener
    @codigo NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1
        LTRIM(RTRIM(COD_ARTICU))  AS codigo,
        LTRIM(RTRIM(DESCRIPCIO))  AS descripcion,
        LTRIM(RTRIM(SINONIMO))    AS sinonimo,
        LTRIM(RTRIM(COD_BARRA))   AS codigoBarra,
        LTRIM(RTRIM(DESC_ADIC))   AS descAdicional
    FROM dbo.STA11
    WHERE LTRIM(RTRIM(COD_ARTICU)) = LTRIM(RTRIM(@codigo));
END
