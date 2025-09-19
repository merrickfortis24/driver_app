<?php
// Lightweight debug helper: show table columns and a single driver row for a given email
// Usage: debug_driver_row.php?email=someone@example.com

header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json');

try {
    require_once __DIR__ . '/connection.php';
    $db = (new Database())->openCon();
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    $email = trim(strtolower((string)($_GET['email'] ?? '')));
    if ($email === '') {
        echo json_encode(['ok' => false, 'error' => 'missing_email', 'usage' => 'debug_driver_row.php?email=someone@example.com']);
        exit;
    }

    // List columns
    $colsStmt = $db->prepare('SHOW COLUMNS FROM `drivers`');
    $colsStmt->execute();
    $columns = $colsStmt->fetchAll(PDO::FETCH_ASSOC);

    // Build selectable column list (safe): take Field names only
    $colNames = array_map(fn($r) => $r['Field'], $columns);
    $colList = implode(', ', array_map(fn($c) => "`$c`", $colNames));

    // Fetch row
    $stmt = $db->prepare("SELECT $colList FROM `drivers` WHERE LOWER(Gmail) = ? LIMIT 1");
    $stmt->execute([$email]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    // Prepare a preview of password fields (don't show full secret)
    $pwdPreview = null;
    foreach (['Password_Hash','Password'] as $pc) {
        if (!empty($row[$pc] ?? '')) {
            $pwdPreview = substr($row[$pc], 0, 40);
            break;
        }
    }

    echo json_encode([
        'ok' => true,
        'email' => $email,
        'columns' => array_values($colNames),
        'row_exists' => $row ? true : false,
        'row' => $row ?: null,
        'pwd_preview' => $pwdPreview,
    ], JSON_PRETTY_PRINT);
} catch (Throwable $e) {
    http_response_code(500);
    error_log('debug_driver_row error: ' . $e->getMessage());
    echo json_encode(['ok' => false, 'error' => 'server_error']);
}
