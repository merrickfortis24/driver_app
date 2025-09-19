<?php
// Dev-only helper: verify password server-side for a given email.
// Usage: test_verify.php?email=john@gmail.com&password=Test1234
header('Content-Type: application/json');
try {
    require_once __DIR__ . '/connection.php';
    $db = (new Database())->openCon();

    $email = trim(strtolower((string)($_GET['email'] ?? '')));
    $password = (string)($_GET['password'] ?? '');
    if ($email === '' || $password === '') {
        echo json_encode(['ok' => false, 'error' => 'missing_email_or_password']);
        exit;
    }

    $stmt = $db->prepare('SELECT Password_Hash FROM drivers WHERE LOWER(Gmail)=? LIMIT 1');
    $stmt->execute([$email]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        echo json_encode(['ok' => false, 'error' => 'no_user']);
        exit;
    }

    $stored = $row['Password_Hash'] ?? '';
    $storedPreview = substr($stored, 0, 64);
    $storedType = '';
    if ($stored === '') $storedType = 'none';
    elseif (strpos($stored, '$2') === 0 || strpos($stored, '$argon') === 0) $storedType = 'modern_hash';
    elseif (preg_match('/^[a-f0-9]{32}$/i', $stored)) $storedType = 'md5';
    else $storedType = 'plain_or_other';

    $pwdOk = false;
    // If bcrypt/argon, verify
    if ($storedType === 'modern_hash') {
        $pwdOk = password_verify($password, $stored);
    } elseif ($storedType === 'md5') {
        $pwdOk = (md5($password) === strtolower($stored));
    } else {
        $pwdOk = hash_equals($stored, $password);
    }

    echo json_encode([
        'ok' => true,
        'email' => $email,
        'stored_type' => $storedType,
        'pwd_preview' => $storedPreview,
        'pwdOk' => $pwdOk ? true : false,
    ], JSON_PRETTY_PRINT);
} catch (Throwable $e) {
    error_log('test_verify error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'server_error']);
}
