<?php
header('Access-Control-Allow-Origin: *'); // dev only
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Content-Type: application/json');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); echo json_encode(['ok'=>true]); exit; }

require_once __DIR__ . '/../connection.php';

function bearerToken(): ?string {
  $headers = function_exists('getallheaders') ? getallheaders() : [];
  $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
  if (stripos($auth, 'Bearer ') === 0) return substr($auth, 7);
  return null;
}

try {
  $db = (new Database())->openCon();
  $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (Throwable $e) {
  http_response_code(503);
  echo json_encode(['error' => 'db_unavailable']);
  exit;
}

$token = bearerToken();
if (!$token) { http_response_code(401); echo json_encode(['error'=>'missing_token']); exit; }

// Expect JSON body or form-encoded POST
$input = json_decode(file_get_contents('php://input'), true) ?: $_POST;
$name = trim((string)($input['name'] ?? '')) ?: null;
$email = trim((string)($input['email'] ?? '')) ?: null;
$phone = trim((string)($input['phone'] ?? '')) ?: null;
$address = trim((string)($input['address'] ?? '')) ?: null;

try {
  // Ensure token maps to a driver
  $q = $db->prepare("SELECT Driver_ID FROM drivers WHERE Api_Token=? LIMIT 1");
  $q->execute([$token]);
  $u = $q->fetch(PDO::FETCH_ASSOC);
  if (!$u) { http_response_code(401); echo json_encode(['error'=>'invalid_token']); exit; }
  $driverId = (int)$u['Driver_ID'];

  $fields = [];
  $params = [];
  if ($name !== null) { $fields[] = "`Name` = ?"; $params[] = $name; }
  if ($email !== null) { $fields[] = "`Gmail` = ?"; $params[] = $email; }
  if ($phone !== null && in_array('Phone', array_column($db->query("SHOW COLUMNS FROM `drivers`")->fetchAll(PDO::FETCH_ASSOC), 'Field'), true)) { $fields[] = "`Phone` = ?"; $params[] = $phone; }
  if ($address !== null && in_array('Address', array_column($db->query("SHOW COLUMNS FROM `drivers`")->fetchAll(PDO::FETCH_ASSOC), 'Field'), true)) { $fields[] = "`Address` = ?"; $params[] = $address; }

  if (count($fields) > 0) {
    $params[] = $driverId;
    $sql = "UPDATE drivers SET " . implode(', ', $fields) . " WHERE Driver_ID = ? LIMIT 1";
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
  }

  // Return updated profile (reuse existing profile logic)
  $stmt = $db->prepare("SELECT * FROM drivers WHERE Driver_ID = ? LIMIT 1");
  $stmt->execute([$driverId]);
  $u = $stmt->fetch(PDO::FETCH_ASSOC);
  if (!$u) { http_response_code(500); echo json_encode(['error'=>'not_found']); exit; }

  echo json_encode([
    'driver' => [
      'id' => (int)($u['Driver_ID'] ?? 0),
      'name' => $u['Name'] ?? null,
      'email' => $u['Gmail'] ?? null,
      'phone' => $u['Phone'] ?? null,
      'address' => $u['Address'] ?? null,
      'status' => $u['Status'] ?? null,
      'createdAt' => $u['Created_At'] ?? null,
      'lastLogin' => $u['Last_Login'] ?? null,
      'tokenExpires' => $u['Token_Expires'] ?? null,
    ]
  ]);
} catch (Throwable $e) {
  http_response_code(500);
  echo json_encode(['error'=>'server_error']);
}
