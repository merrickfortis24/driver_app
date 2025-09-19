<?php
// Always emit JSON (avoid HTML errors that break mobile JSON parsing)
header('Access-Control-Allow-Origin: *'); // dev only
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Content-Type: application/json');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); echo json_encode(['ok'=>true]); exit; }

// Avoid leaking notices/warnings to the client
if (function_exists('ini_set')) { @ini_set('display_errors', '0'); @ini_set('log_errors', '1'); }

try {
    require_once __DIR__ . '/../connection.php';
    try {
        $db = (new Database())->openCon();
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        // quick sanity check that DB responds
        $db->query('SELECT 1');
    } catch (Throwable $e) {
        error_log('driver/login db connect error: ' . $e->getMessage());
        http_response_code(503);
        echo json_encode(['error' => 'db_unavailable']);
        exit;
    }

    // accept JSON or form
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    $email = isset($data['email']) ? $data['email'] : ($_POST['email'] ?? '');
    $password = isset($data['password']) ? $data['password'] : ($_POST['password'] ?? '');

    $email = trim(strtolower($email ?? ''));
    $password = (string)($password ?? '');

    if ($email === '' || $password === '') {
        http_response_code(400);
        echo json_encode(['error' => 'missing_fields']);
        exit;
    }

    // Determine available columns once (more reliable than repeated SHOW COLUMNS calls)
    $columns = [];
    try {
        $colsStmt = $db->query("SHOW COLUMNS FROM `drivers`");
        $colsRows = $colsStmt->fetchAll(PDO::FETCH_ASSOC);
        $columns = array_column($colsRows, 'Field');
    } catch (Throwable $e) {
        // If SHOW COLUMNS fails for any reason, fall back to a conservative minimal set
        error_log('driver/login SHOW COLUMNS failed: ' . $e->getMessage());
        $columns = ['Driver_ID','Name','Gmail'];
    }

    $hasPwdHash = in_array('Password_Hash', $columns, true);
    $hasPwd = in_array('Password', $columns, true);
    $cols = ['Driver_ID','Name','Gmail'];
    if ($hasPwdHash) $cols[] = 'Password_Hash';
    if ($hasPwd) $cols[] = 'Password';
    if (in_array('Api_Token', $columns, true)) $cols[] = 'Api_Token';
    if (in_array('Token_Expires', $columns, true)) $cols[] = 'Token_Expires';

    $colList = implode(', ', array_map(fn($c)=>"`$c`", $cols));

    try {
        $stmt = $db->prepare("SELECT $colList FROM drivers WHERE LOWER(Gmail) = ? LIMIT 1");
        $stmt->execute([$email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];
        // Debug: log whether a user was found (no sensitive data)
        if (!empty($user)) {
            $preview = [];
            $preview['Driver_ID'] = $user['Driver_ID'] ?? null;
            $preview['Gmail'] = $user['Gmail'] ?? null;
            // show a short preview of password field (do NOT log full password)
            $storedPreview = '';
            if (!empty($user['Password_Hash'] ?? '')) {
                $storedPreview = substr($user['Password_Hash'], 0, 20);
            } elseif (!empty($user['Password'] ?? '')) {
                $storedPreview = substr($user['Password'], 0, 20);
            }
            $preview['pwd_preview'] = $storedPreview;
            error_log('driver/login fetched user: ' . json_encode($preview));
        } else {
            error_log('driver/login: no user found for ' . $email);
        }
    } catch (Throwable $e) {
        error_log('driver/login query error: ' . $e->getMessage());
        http_response_code(500);
        echo json_encode(['error' => 'query_failed']);
        exit;
    }

    // Verify password across possible storage formats
    $pwdOk = false;
    if ($user) {
        $stored = $user['Password_Hash'] ?? $user['Password'] ?? '';
        if (is_string($stored) && $stored !== '') {
            // If it's a modern hash (bcrypt/argon), password_verify will work
            $isModernHash = (strpos($stored, '$2') === 0) || (strpos($stored, '$argon') === 0);
            if ($isModernHash) {
                $pwdOk = password_verify($password, $stored);
            } else {
                // Try password_verify anyway (in case column name differs but value is hashed)
                $pwdOk = password_verify($password, $stored);
                if (!$pwdOk) {
                    // Try MD5 fallback
                    if (preg_match('/^[a-f0-9]{32}$/i', $stored)) {
                        $pwdOk = (md5($password) === strtolower($stored));
                    } else {
                        // Plaintext fallback (only if needed for legacy)
                        $pwdOk = hash_equals($stored, $password);
                    }
                }
            }
        }
    }

    // Debug: log password verification steps (no plaintext)
    try {
        $stored = $user['Password_Hash'] ?? $user['Password'] ?? '';
        $storedType = '';
        if ($stored === '') {
            $storedType = 'none';
        } elseif (strpos($stored, '$2') === 0 || strpos($stored, '$argon') === 0) {
            $storedType = 'modern_hash';
        } elseif (preg_match('/^[a-f0-9]{32}$/i', $stored)) {
            $storedType = 'md5';
        } else {
            $storedType = 'plain_or_other';
        }
        error_log('driver/login verify: email=' . $email . ' stored_type=' . $storedType . ' pwdOk=' . ($pwdOk ? '1' : '0'));
    } catch (Throwable $e) {
        error_log('driver/login debug log failed: ' . $e->getMessage());
    }

    if (!$user || !$pwdOk) {
        http_response_code(401);
        echo json_encode(['error' => 'invalid_credentials']);
        exit;
    }

    // issue or refresh token
    $expired = isset($user['Token_Expires']) && $user['Token_Expires'] && strtotime($user['Token_Expires']) < time();
    $token = $user['Api_Token'] ?? '';
    if (!$token || $expired) {
        $token = bin2hex(random_bytes(32));
        $expires = date('Y-m-d H:i:s', time() + 30*24*60*60); // 30 days
        // Update only if columns exist (use $columns gathered earlier)
        if (in_array('Api_Token', $columns, true)) {
            try {
                if (in_array('Token_Expires', $columns, true)) {
                    $upd = $db->prepare('UPDATE drivers SET Api_Token=?, Token_Expires=? WHERE Driver_ID=?');
                    $upd->execute([$token, $expires, $user['Driver_ID']]);
                } else {
                    $upd = $db->prepare('UPDATE drivers SET Api_Token=? WHERE Driver_ID=?');
                    $upd->execute([$token, $user['Driver_ID']]);
                }
            } catch (Throwable $e) {
                error_log('driver/login token update failed: ' . $e->getMessage());
                // proceed without failing the login response
            }
        }
    }

    echo json_encode([
        'token' => $token,
        'user' => [
            'id' => (int)$user['Driver_ID'],
            'name' => $user['Name'],
            'gmail' => $user['Gmail'],
        ],
    ]);
} catch (Throwable $e) {
    // Log server-side, return clean JSON to client
    error_log('driver/login error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['error' => 'server_error']);
}