-- Grant replication privileges so we can check for the status in the replica:check command
CREATE USER IF NOT EXISTS 'laravel'@'%' IDENTIFIED WITH mysql_native_password BY 'password';
GRANT ALL PRIVILEGES ON `laravel`.* TO 'laravel'@'%';
GRANT REPLICATION CLIENT ON *.* TO 'laravel'@'%';

-- Apply changes
FLUSH PRIVILEGES;
