/*
  SP de prueba TEMPORAL — NO es producción.
  Replica el bloque CATCH de PAQ_Auth_Login (RAISERROR severity 0 + result sets).
  Fuerza error real en TRY (división por cero).
*/
CREATE OR ALTER PROCEDURE dbo.PAQ_Auth_Login_CatchTest
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @ForceError INT = 1 / 0;
    END TRY
    BEGIN CATCH
        DECLARE @InternalError NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @InternalNumber INT = ERROR_NUMBER();

        RAISERROR(
            N'PAQ_Auth_Login error %d: %s',
            0, 1,
            @InternalNumber,
            @InternalError
        ) WITH LOG;

        SELECT
            N'SQL_ERROR'                                         AS [status],
            CAST(NULL AS INT)                                    AS [user_id],
            CAST(NULL AS NVARCHAR(100))                          AS [codigo],
            CAST(NULL AS NVARCHAR(255))                          AS [name_user],
            CAST(NULL AS NVARCHAR(255))                          AS [email],
            CAST(NULL AS NVARCHAR(255))                          AS [password_hash],
            CAST(NULL AS NVARCHAR(10))                           AS [locale],
            CAST(NULL AS BIT)                                    AS [menu_abrir_nueva_pestana],
            CAST(NULL AS BIT)                                    AS [sidebar_collapsed],
            CAST(0 AS BIT)                                       AS [es_admin],
            CAST(NULL AS NVARCHAR(20))                           AS [redirectTo],
            N'Error interno al procesar la solicitud de autenticación.' AS [error_message];

        SELECT
            CAST(NULL AS INT)           AS [id],
            CAST(NULL AS NVARCHAR(100)) AS [nombreEmpresa],
            CAST(NULL AS NVARCHAR(100)) AS [nombreBd],
            CAST(NULL AS NVARCHAR(100)) AS [theme],
            CAST(NULL AS NVARCHAR(100)) AS [imagen]
        WHERE 1 = 0;
    END CATCH
END
GO
