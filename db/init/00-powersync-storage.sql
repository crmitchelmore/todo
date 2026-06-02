-- PowerSync bucket storage database (kept separate from the source `postgres` db).
-- PowerSync creates and manages its own tables here.
SELECT 'CREATE DATABASE powersync'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'powersync')\gexec
