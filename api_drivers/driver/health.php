<?php
header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json');
require_once __DIR__ . '/../connection.php';

$started = microtime(true);
try {
    // Try a quick DB connect
    $db = new Database();
    $pdo = $db->openCon();
    // Simple query to verify connectivity quickly
    $pdo->query('SELECT 1');
    $ok = true;
    $err = null;
} catch (Throwable $e) {
    $ok = false;
    $err = $e->getMessage();
}
$elapsed = round((microtime(true) - $started) * 1000);

echo json_encode([
    'db_ok' => $ok,
    'ms' => $elapsed,
    // Keep the error brief to avoid leaking details
    'error' => $ok ? null : 'db_connect_failed',
]);
