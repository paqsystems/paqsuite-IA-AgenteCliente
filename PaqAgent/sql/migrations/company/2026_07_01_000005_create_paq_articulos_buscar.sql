CREATE OR ALTER PROCEDURE dbo.PAQ_Articulos_Buscar
    @texto NVARCHAR(100),
    @limit INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@limit)
        LTRIM(RTRIM(COD_ARTICU))  AS codigo,
        LTRIM(RTRIM(DESCRIPCIO))  AS descripcion,
        LTRIM(RTRIM(SINONIMO))    AS sinonimo,
        LTRIM(RTRIM(COD_BARRA))   AS codigoBarra,
        LTRIM(RTRIM(DESC_ADIC))   AS descAdicional
    FROM dbo.STA11
    WHERE (
        DESCRIPCIO LIKE N'%' + @texto + N'%'
        OR COD_ARTICU LIKE N'%' + @texto + N'%'
        OR SINONIMO   LIKE N'%' + @texto + N'%'
    )
    ORDER BY DESCRIPCIO;
END
