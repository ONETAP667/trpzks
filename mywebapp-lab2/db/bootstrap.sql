DO
$$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'mywebapp'
    ) THEN
        CREATE ROLE mywebapp LOGIN PASSWORD 'mywebapp_password';
    END IF;
END
$$;

SELECT 'CREATE DATABASE mywebapp OWNER mywebapp'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'mywebapp'
)
\gexec