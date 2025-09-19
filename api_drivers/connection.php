<?php

// Allow CORS for browser-based clients (Flutter Web / JS fetch).
// For production, consider restricting Access-Control-Allow-Origin to your domain.
if (isset($_SERVER['HTTP_ORIGIN'])) {
    // Allow the requesting origin (useful for multiple environments).
    header('Access-Control-Allow-Origin: ' . $_SERVER['HTTP_ORIGIN']);
} else {
    header('Access-Control-Allow-Origin: *');
}
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Origin, Content-Type, Accept, Authorization, X-Requested-With');
header('Access-Control-Allow-Credentials: true');

// Handle preflight requests quickly
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

class Database {
    private string $host;
    private string $port = '3306';
    private string $db;
    private string $user;
    private string $pass;
    private string $charset = 'utf8mb4';
    private bool $ssl = false;
    private ?string $sslCa = null;
    private bool $debug = false;

    private static ?PDO $pdo = null;

    public function __construct() {
        // Defaults (fallback to prior values to avoid breaking existing setups)
        $this->host = 'mysql.hostinger.com';
        $this->port = '3306';
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
                if (!empty($cfg['port'])) { $this->port = (string)$cfg['port']; }
                $this->db = $cfg['db'] ?? $this->db;
                $this->user = $cfg['user'] ?? $this->user;
                $this->pass = $cfg['pass'] ?? $this->pass;
                $this->charset = $cfg['charset'] ?? $this->charset;
                // optional flags
                $this->ssl = (bool)($cfg['ssl'] ?? false);
                $this->sslCa = $cfg['ssl_ca'] ?? null;
                $this->debug = (bool)($cfg['debug'] ?? false);
            }
        }
    }

    public function openCon(): PDO {
        if (self::$pdo instanceof PDO) return self::$pdo;

        $dsn = "mysql:host={$this->host};port={$this->port};dbname={$this->db};charset={$this->charset}";
        $opts = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            PDO::ATTR_PERSISTENT         => false,
            PDO::ATTR_TIMEOUT            => 5, // fail fast to avoid hanging HTTP requests
        ];
        // Optional SSL
        if ($this->ssl) {
            // Only add SSL CA if provided
            if ($this->sslCa && is_readable($this->sslCa)) {
                $opts[PDO::MYSQL_ATTR_SSL_CA] = $this->sslCa;
            } else {
                // If SSL requested but no CA provided, still attempt SSL without verification
                if (defined('PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT')) {
                    $opts[PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;
                }
            }
        }
        try {
            self::$pdo = new PDO($dsn, $this->user, $this->pass, $opts);
        } catch (PDOException $e) {
            error_log('DB connect error: ' . $e->getMessage());
            if ($this->debug) {
                throw new RuntimeException('Database connection failed: ' . $e->getMessage());
            }
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