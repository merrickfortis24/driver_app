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
$db->exec("CREATE TABLE IF NOT EXISTS order_proof_photo (
  Photo_ID INT AUTO_INCREMENT PRIMARY KEY,
  Order_ID INT NOT NULL,
  Path VARCHAR(255) NOT NULL,
  Uploaded_At DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  Uploaded_By INT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

$uploadDir = __DIR__ . '/../../uploads/proofs';
if (!is_dir($uploadDir)) { @mkdir($uploadDir, 0777, true); }

$stored = [];
try {
  $db->beginTransaction();
  // Support either multiple files under photos[] or a single 'photos'
  $files = [];
  if (!empty($_FILES['photos'])) {
    $f = $_FILES['photos'];
    if (is_array($f['name'])) {
      $count = count($f['name']);
      for ($i=0; $i<$count; $i++) {
        $files[] = [
          'name'=>$f['name'][$i],
          'tmp_name'=>$f['tmp_name'][$i],
        ];
      }
    } else {
      $files[] = ['name'=>$f['name'], 'tmp_name'=>$f['tmp_name']];
    }
  } elseif (!empty($_FILES['photo'])) { // alias
    $files[] = ['name'=>$_FILES['photo']['name'], 'tmp_name'=>$_FILES['photo']['tmp_name']];
  }

  foreach ($files as $idx => $fi) {
    if (empty($fi['tmp_name'])) continue;
    $ext = pathinfo($fi['name'], PATHINFO_EXTENSION) ?: 'jpg';
    $ext = preg_replace('/[^a-zA-Z0-9]/','', $ext);
    $fname = 'order_' . $orderId . '_' . time() . '_' . $idx . '.' . $ext;
    $dest = $uploadDir . '/' . $fname;
    if (@move_uploaded_file($fi['tmp_name'], $dest)) {
      $rel = 'uploads/proofs/' . $fname;
      $ins = $db->prepare('INSERT INTO order_proof_photo (Order_ID, Path, Uploaded_By) VALUES (?, ?, ?)');
      $ins->execute([$orderId, $rel, $driver['Driver_ID']]);
      $stored[] = $rel;
    }
  }

  // Also update the legacy/single proof field for admin visibility
  if (!empty($stored)) {
    $first = $stored[0];
    // Try update existing receipt row
    $upr = $db->prepare("UPDATE order_payment_receipt
                         SET payment_received_at = COALESCE(payment_received_at, NOW()),
                             payment_received_by = COALESCE(payment_received_by, ?),
                             Proof_Photo = ?
                         WHERE Order_ID = ?");
    $by = "Driver #{$driver['Driver_ID']} - {$driver['Name']}";
    $upr->execute([$by, $first, $orderId]);
    if ($upr->rowCount() === 0) {
      // Insert minimal record if not exists (keep 'verified' to mirror delivered flow)
      $insr = $db->prepare("INSERT INTO order_payment_receipt (Order_ID, payment_received_at, payment_received_by, Proof_Photo, Status)
                             VALUES (?, NOW(), ?, ?, 'verified')");
      $insr->execute([$orderId, $by, $first]);
    }
  }

  $db->commit();
  echo json_encode(['ok'=>true, 'orderId'=>(string)$orderId, 'paths'=>$stored]);
} catch (Throwable $e) {
  $db->rollBack();
  http_response_code(500);
  echo json_encode(['error'=>'upload_failed','details'=>$e->getMessage()]);
}
