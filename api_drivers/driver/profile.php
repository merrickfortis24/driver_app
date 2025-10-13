<?php
header('Access-Control-Allow-Origin: *'); // dev only
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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

try {
  // Select columns that are present in current schema; tolerate missing optional ones
  $cols = [];
  try {
    $stmt = $db->query("SHOW COLUMNS FROM `drivers`");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $cols = array_column($rows, 'Field');
  } catch (Throwable $e) { $cols = ['Driver_ID','Name','Gmail']; }

  $hasStatus = in_array('Status', $cols, true);
  $hasCreated = in_array('Created_At', $cols, true);
  $hasLastLogin = in_array('Last_Login', $cols, true);
  $hasTokenExp = in_array('Token_Expires', $cols, true);

  $sel = ['Driver_ID','Name','Gmail'];
  if ($hasStatus) $sel[] = 'Status';
  if ($hasCreated) $sel[] = 'Created_At';
  if ($hasLastLogin) $sel[] = 'Last_Login';
  if ($hasTokenExp) $sel[] = 'Token_Expires';
  $list = implode(', ', array_map(fn($c)=>"`$c`", $sel));

  $q = $db->prepare("SELECT $list FROM drivers WHERE Api_Token=? AND (Token_Expires IS NULL OR Token_Expires > NOW()) LIMIT 1");
  $q->execute([$token]);
  $u = $q->fetch(PDO::FETCH_ASSOC);
  if (!$u) { http_response_code(401); echo json_encode(['error'=>'invalid_token']); exit; }

  echo json_encode([
    'driver' => [
      'id' => (int)($u['Driver_ID'] ?? 0),
      'name' => $u['Name'] ?? null,
      'email' => $u['Gmail'] ?? null,
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
