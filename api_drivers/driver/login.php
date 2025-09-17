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
    $db = (new Database())->openCon();
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

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

    $stmt = $db->prepare('SELECT Driver_ID, Name, Gmail, Password_Hash, Api_Token, Token_Expires FROM drivers WHERE LOWER(Gmail) = ? LIMIT 1');
    $stmt->execute([$email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user || !password_verify($password, $user['Password_Hash'])) {
        http_response_code(401);
        echo json_encode(['error' => 'invalid_credentials']);
        exit;
    }

    // issue or refresh token
    $expired = $user['Token_Expires'] && strtotime($user['Token_Expires']) < time();
    $token = $user['Api_Token'];
    if (!$token || $expired) {
        $token = bin2hex(random_bytes(32));
        $expires = date('Y-m-d H:i:s', time() + 30*24*60*60); // 30 days
        $upd = $db->prepare('UPDATE drivers SET Api_Token=?, Token_Expires=? WHERE Driver_ID=?');
        $upd->execute([$token, $expires, $user['Driver_ID']]);
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