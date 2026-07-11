CREATE OR ALTER PROCEDURE dbo.PAQ_Auth_Session
    @token_id    INT,
    @token_hash  VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        pat.id,
        pat.tokenable_id AS user_id,
        u.codigo          AS user_code,
        u.activo,
        u.inhabilitado
    FROM personal_access_tokens pat
    INNER JOIN USERS u ON u.id = pat.tokenable_id
    WHERE pat.id = @token_id
      AND pat.token = @token_hash
      AND pat.tokenable_type LIKE '%User%'
      AND (pat.expires_at IS NULL OR pat.expires_at > GETDATE())
      AND u.activo = 1
      AND u.inhabilitado = 0;
END
