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

$orderId = $_POST['orderId'] ?? null;
if (!$orderId) { http_response_code(400); echo json_encode(['error'=>'missing_fields']); exit; }
$token = bearerToken();
if (!$token) { http_response_code(401); echo json_encode(['error'=>'missing_token']); exit; }

// auth driver
$stmt = $db->prepare('SELECT Driver_ID, Name FROM drivers WHERE Api_Token=? AND (Token_Expires IS NULL OR Token_Expires > NOW()) LIMIT 1');
$stmt->execute([$token]);
$driver = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$driver) { http_response_code(401); echo json_encode(['error'=>'invalid_token']); exit; }

// ensure order exists
$chk = $db->prepare('SELECT Order_ID FROM orders WHERE Order_ID=? LIMIT 1');
$chk->execute([$orderId]);
if (!$chk->fetch()) { http_response_code(404); echo json_encode(['error'=>'order_not_found']); exit; }

// create table if not exists
$db->exec("CREATE TABLE IF NOT EXISTS order_signature (
  Order_ID INT PRIMARY KEY,
  Path VARCHAR(255) NOT NULL,
  Signed_At DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  Signed_By INT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

$uploadDir = __DIR__ . '/../../uploads/signatures';
if (!is_dir($uploadDir)) { @mkdir($uploadDir, 0777, true); }

try {
  $path = null;
  if (!empty($_FILES['signature']['tmp_name'])) {
    $fname = 'order_' . $orderId . '_' . time() . '.png';
    $dest = $uploadDir . '/' . $fname;
    if (@move_uploaded_file($_FILES['signature']['tmp_name'], $dest)) {
      $path = 'uploads/signatures/' . $fname;
    }
  } elseif (!empty($_POST['signatureBase64'])) {
    $img = base64_decode(preg_replace('#^data:image/\w+;base64,#', '', $_POST['signatureBase64']));
    if ($img) {
      $fname = 'order_' . $orderId . '_' . time() . '.png';
      $dest = $uploadDir . '/' . $fname;
      if (@file_put_contents($dest, $img) !== false) { $path = 'uploads/signatures/' . $fname; }
    }
  }
  if (!$path) { http_response_code(400); echo json_encode(['error'=>'no_signature']); exit; }

  // upsert signature
  $upd = $db->prepare('UPDATE order_signature SET Path=?, Signed_At=NOW(), Signed_By=? WHERE Order_ID=?');
  $upd->execute([$path, $driver['Driver_ID'], $orderId]);
  if ($upd->rowCount() === 0) {
    $ins = $db->prepare('INSERT INTO order_signature (Order_ID, Path, Signed_By) VALUES (?, ?, ?)');
    $ins->execute([$orderId, $path, $driver['Driver_ID']]);
  }

  echo json_encode(['ok'=>true, 'orderId'=>(string)$orderId, 'path'=>$path]);
} catch (Throwable $e) {
  http_response_code(500);
  echo json_encode(['error'=>'upload_failed','details'=>$e->getMessage()]);
}
