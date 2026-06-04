-- Medplum Sandbox: Database initialization
-- Creates the test database and grants permissions

-- The main 'medplum' database is created by POSTGRES_DB env var.
-- This script creates the test database for running the test suite.

CREATE DATABASE medplum_test OWNER medplum;

-- Grant all privileges
GRANT ALL PRIVILEGES ON DATABASE medplum TO medplum;
GRANT ALL PRIVILEGES ON DATABASE medplum_test TO medplum;

-- Connect to medplum_test and set up permissions
\c medplum_test
GRANT ALL ON SCHEMA public TO medplum;

-- Connect back to medplum and set up permissions
\c medplum
GRANT ALL ON SCHEMA public TO medplum;
