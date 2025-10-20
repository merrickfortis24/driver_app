<?php
/**
 * verify_code.php
 *
 * Expects POST { "driver_id": <id>, "code": "123456" }
 * - Checks driver exists
 * - Verifies code matches and has not expired
 * - If valid: sets is_verified = 1 and clears verification_code and code_expires_at
 * - Returns JSON with success/failure and message
 */

// CORS handled by server-level .htaccess (per-file header() and preflight handling removed)
header('Content-Type: application/json');
require_once __DIR__ . '/../db_config.php';

function json_error($msg, $code = 400) {
  http_response_code($code);
  echo json_encode(['success' => false, 'message' => $msg]);
  exit;
}

$payload = json_decode(file_get_contents('php://input'), true);
if (!$payload || empty($payload['driver_id']) || !isset($payload['code'])) {
  json_error('Missing driver_id or code');
}
$driver_id = (int)$payload['driver_id'];
$code = trim((string)$payload['code']);

$config = require __DIR__ . '/../db_config.php';
$mysqli = new mysqli($config['host'], $config['user'], $config['pass'], $config['db'], (int)$config['port']);
if ($mysqli->connect_errno) json_error('DB connection failed', 500);
$mysqli->set_charset($config['charset']);

$stmt = $mysqli->prepare('SELECT verification_code, code_expires_at FROM drivers WHERE Driver_ID = ? LIMIT 1');
if (!$stmt) json_error('DB prepare failed', 500);
$stmt->bind_param('i', $driver_id);
$stmt->execute();
$res = $stmt->get_result();
if (!$res || $res->num_rows === 0) {
  json_error('Driver not found', 404);
}
$row = $res->fetch_assoc();
$stmt->close();

$stored = $row['verification_code'];
$expires = $row['code_expires_at'];

if (empty($stored)) {
  json_error('No verification code set for this driver', 400);
}

// Check expiry
if (!empty($expires)) {
  $now = new DateTime('now');
  $exp = new DateTime($expires);
  if ($now > $exp) {
    json_error('Code expired', 400);
  }
}

// Compare codes securely
if (!hash_equals($stored, $code)) {
  json_error('Invalid code', 400);
}

// Mark verified and clear fields
$upd = $mysqli->prepare('UPDATE drivers SET is_verified = 1, verification_code = NULL, code_expires_at = NULL WHERE Driver_ID = ?');
if (!$upd) json_error('DB prepare failed', 500);
$upd->bind_param('i', $driver_id);
if (!$upd->execute()) {
  json_error('Failed to update verification status', 500);
}
$upd->close();

echo json_encode(['success' => true, 'message' => 'Driver verified']);
exit;
