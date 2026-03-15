-- Creates both databases on first postgres start.
-- Runs automatically from /docker-entrypoint-initdb.d/

SELECT 'CREATE DATABASE pet_shelter'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'pet_shelter')\gexec

SELECT 'CREATE DATABASE vet_clinic'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'vet_clinic')\gexec
