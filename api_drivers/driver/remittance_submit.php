<?php
header('Access-Control-Allow-Origin: *'); // dev only
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }

require_once __DIR__ . '/../connection.php';
$db = (new Database())->openCon();
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
header('Content-Type: application/json');

function bearerToken(): ?string {
  $headers = function_exists('getallheaders') ? getallheaders() : [];
  $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
  if (stripos($auth, 'Bearer ') === 0) return substr($auth, 7);
  return null;
}

$token = bearerToken();
if (!$token) { http_response_code(401); echo json_encode(['error'=>'missing_token']); exit; }

// auth driver
$stmt = $db->prepare('SELECT Driver_ID, Name FROM drivers WHERE Api_Token=? AND (Token_Expires IS NULL OR Token_Expires > NOW()) LIMIT 1');
$stmt->execute([$token]);
$driver = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$driver) { http_response_code(401); echo json_encode(['error'=>'invalid_token']); exit; }
$driverId = (int)$driver['Driver_ID'];

$amount = isset($_POST['amount']) ? floatval($_POST['amount']) : 0;
$note = $_POST['note'] ?? null;
if ($amount <= 0) { http_response_code(400); echo json_encode(['error'=>'invalid_amount']); exit; }

// ensure table exists
$db->exec("CREATE TABLE IF NOT EXISTS driver_cash_remittance (
  Remittance_ID INT AUTO_INCREMENT PRIMARY KEY,
  Driver_ID INT NOT NULL,
  Amount DECIMAL(10,2) NOT NULL,
  Note TEXT NULL,
  Proof_Path VARCHAR(255) NULL,
  Created_At DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

$proof = null;
$uploadDir = __DIR__ . '/../../uploads/remittances';
if (!is_dir($uploadDir)) { @mkdir($uploadDir, 0777, true); }
if (!empty($_FILES['proof']['tmp_name'])) {
  $ext = pathinfo($_FILES['proof']['name'], PATHINFO_EXTENSION) ?: 'jpg';
  $ext = preg_replace('/[^a-zA-Z0-9]/','', $ext);
  $fname = 'remit_' . $driverId . '_' . time() . '.' . $ext;
  $dest = $uploadDir . '/' . $fname;
  if (@move_uploaded_file($_FILES['proof']['tmp_name'], $dest)) {
    $proof = 'uploads/remittances/' . $fname;
  }
}

$ins = $db->prepare('INSERT INTO driver_cash_remittance (Driver_ID, Amount, Note, Proof_Path) VALUES (?, ?, ?, ?)');
$ins->execute([$driverId, $amount, $note, $proof]);

// response with updated summary
require __DIR__ . '/cash_summary.php';
