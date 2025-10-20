<?php
/**
 * send_verification_code.php
 *
 * Expects POST { "driver_id": <id> }
 * - Generates a random 6-digit numeric code
 * - Stores the code and expiry (5 minutes) in `drivers` table
 * - Sends the code to the driver's email using PHPMailer + Hostinger SMTP
 * - Returns JSON { success: true } or { success: false, message: '...' }
 */

// CORS handled by server-level .htaccess (per-file header() removed)

// Follow the working sample: accept POST form data, use mailer wrapper, and store OTP
header('Content-Type: application/json');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); echo json_encode(['ok'=>false,'error'=>'Method not allowed']); exit; }

require_once __DIR__ . '/../db_config.php';
require_once __DIR__ . '/mailer.php';

// Accept both form-encoded POST and application/json body
$email = trim($_POST['email'] ?? '');
$name  = trim($_POST['name'] ?? '');
$driverIdFromForm = isset($_POST['driver_id']) ? (int)$_POST['driver_id'] : null;

// If request sent JSON (common from fetch), decode and use those fields as fallback
$raw = trim(file_get_contents('php://input') ?: '');
if ($raw !== '') {
    $contentType = $_SERVER['CONTENT_TYPE'] ?? '';
    if (stripos($contentType, 'application/json') !== false) {
        $json = json_decode($raw, true);
        if (is_array($json)) {
            if (empty($email) && isset($json['email'])) $email = trim($json['email']);
            if (empty($name) && isset($json['name'])) $name = trim($json['name']);
            if ($driverIdFromForm === null && isset($json['driver_id'])) $driverIdFromForm = (int)$json['driver_id'];
        }
    }
}

if ($email === '' && $driverIdFromForm === null) { http_response_code(400); echo json_encode(['ok'=>false,'error'=>'Missing email or driver_id']); exit; }

$mysqli = new mysqli($config['host'], $config['user'], $config['pass'], $config['db'], (int)$config['port']);
if ($mysqli->connect_errno) { http_response_code(500); echo json_encode(['ok'=>false,'error'=>'DB connect failed']); exit; }
$mysqli->set_charset($config['charset']);

// Resolve driver by id or email
if ($driverIdFromForm !== null) {
    $stmt = $mysqli->prepare('SELECT id, Name, Gmail, is_verified FROM drivers WHERE id = ? LIMIT 1');
    $stmt->bind_param('i', $driverIdFromForm);
} else {
    $stmt = $mysqli->prepare('SELECT id, Name, Gmail, is_verified FROM drivers WHERE Gmail = ? LIMIT 1');
    $stmt->bind_param('s', $email);
}
if (!$stmt) { http_response_code(500); echo json_encode(['ok'=>false,'error'=>'DB prepare failed']); exit; }
$stmt->execute();
$res = $stmt->get_result();
if (!$res || $res->num_rows === 0) { http_response_code(404); echo json_encode(['ok'=>false,'error'=>'Email/Driver not found']); exit; }
$user = $res->fetch_assoc();
$stmt->close();

$driverId = (int)$user['id'];
$driverEmail = $user['Gmail'];
$driverName = $user['Name'];
$already = ((int)($user['is_verified'] ?? 0) === 1);
if ($already) { echo json_encode(['ok'=>true,'already'=>true]); exit; }

// Generate OTP and store
$code = str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
$expires = (new DateTime('+5 minutes'))->format('Y-m-d H:i:s');
$update = $mysqli->prepare('UPDATE drivers SET verification_code = ?, code_expires_at = ?, is_verified = 0 WHERE id = ?');
if (!$update) { http_response_code(500); echo json_encode(['ok'=>false,'error'=>'DB prepare failed']); exit; }
$update->bind_param('ssi', $code, $expires, $driverId);
if (!$update->execute()) { http_response_code(500); echo json_encode(['ok'=>false,'error'=>'Failed to save code']); exit; }
$update->close();

// Send OTP via shared mailer
$send = send_verification_email_simple($driverEmail, $driverName, $code);
if ($send === true) {
    echo json_encode(['ok'=>true]);
    exit;
} else {
    http_response_code(500);
    echo json_encode(['ok'=>false,'error'=> (string)$send]);
    exit;
}
