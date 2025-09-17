<?php

class Database {
    private string $host;
    private string $db;
    private string $user;
    private string $pass;
    private string $charset = 'utf8mb4';

    private static ?PDO $pdo = null;

    public function __construct() {
        // Defaults (fallback to prior values to avoid breaking existing setups)
        $this->host = 'mysql.hostinger.com';
        $this->db   = 'u677397674_naitsa';
        $this->user = 'u677397674_naitsa_user';
        $this->pass = 'Naitsa@123';

        // Optional override via an untracked file: api_drivers/db_config.php
        // File should: return ['host'=>'...','db'=>'...','user'=>'...','pass'=>'...','charset'=>'utf8mb4'];
        $cfgPath = __DIR__ . '/db_config.php';
        if (file_exists($cfgPath)) {
            $cfg = include $cfgPath;
            if (is_array($cfg)) {
                $this->host = $cfg['host'] ?? $this->host;
                $this->db = $cfg['db'] ?? $this->db;
                $this->user = $cfg['user'] ?? $this->user;
                $this->pass = $cfg['pass'] ?? $this->pass;
                $this->charset = $cfg['charset'] ?? $this->charset;
            }
        }
    }

    public function openCon(): PDO {
        if (self::$pdo instanceof PDO) return self::$pdo;

        $dsn = "mysql:host={$this->host};dbname={$this->db};charset={$this->charset}";
        $opts = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            PDO::ATTR_PERSISTENT         => false,
            PDO::ATTR_TIMEOUT            => 5, // fail fast to avoid hanging HTTP requests
        ];
        try {
            self::$pdo = new PDO($dsn, $this->user, $this->pass, $opts);
        } catch (PDOException $e) {
            error_log('DB connect error: ' . $e->getMessage());
            throw new RuntimeException('Database connection failed.');
        }
        return self::$pdo;
    }

    // Backward-compat alias (if any code calls opencon with lowercase c)
    // If some code used opencon() (lowercase c), keep a proxy only if the method name differs
    // Note: PHP method names are case-insensitive; so we cannot declare both.
    // Instead, rely on class_alias for old class names and standardize on openCon().
}

// Optional legacy class name alias (if some files used `new database()`)
if (!class_exists('database')) {
    class_alias(Database::class, 'database');
}