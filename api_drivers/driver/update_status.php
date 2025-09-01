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

// accept JSON or form
$input = file_get_contents('php://input');
$data = json_decode($input, true);
$orderId = isset($data['orderId']) ? $data['orderId'] : ($_POST['orderId'] ?? null);
$status = isset($data['status']) ? $data['status'] : ($_POST['status'] ?? null);

if (!$orderId || !$status) { http_response_code(400); echo json_encode(['error'=>'missing_fields']); exit; }

$token = bearerToken();
if (!$token) { http_response_code(401); echo json_encode(['error'=>'missing_token']); exit; }

// auth driver
$stmt = $db->prepare('SELECT Driver_ID, Name FROM drivers WHERE Api_Token=? AND (Token_Expires IS NULL OR Token_Expires > NOW()) LIMIT 1');
$stmt->execute([$token]);
$driver = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$driver) { http_response_code(401); echo json_encode(['error'=>'invalid_token']); exit; }

$allowed = ['assigned','accepted','on_the_way','picked_up','delivered','rejected'];
if (!in_array($status, $allowed, true)) {
  http_response_code(400); echo json_encode(['error'=>'invalid_status']); exit;
}

// map prototype -> DB order_status AND persist Driver_Status + assignment
$map = [
  'assigned'   => 'Pending',
  'accepted'   => 'Processing',
  'on_the_way' => 'Processing',
  'picked_up'  => 'Processing',
  'delivered'  => 'Delivered',
  'rejected'   => 'Cancelled',
];
$dbStatus = $map[$status];

$db->beginTransaction();
try {
  // ensure order exists
  $chk = $db->prepare("SELECT Order_ID, Assigned_Driver_ID FROM orders WHERE Order_ID=? FOR UPDATE");
  $chk->execute([$orderId]);
  $order = $chk->fetch(PDO::FETCH_ASSOC);
  if (!$order) { throw new RuntimeException('order_not_found'); }

  // assign driver on first accept
  if (in_array($status, ['accepted','on_the_way','picked_up','delivered'], true)) {
    $assign = $db->prepare("UPDATE orders SET Assigned_Driver_ID = COALESCE(Assigned_Driver_ID, ?) WHERE Order_ID=?");
    $assign->execute([$driver['Driver_ID'], $orderId]);
  }

  // update order status + driver status
  $upd = $db->prepare("UPDATE orders SET order_status=?, Driver_Status=? WHERE Order_ID=?");
  $upd->execute([$dbStatus, $status, $orderId]);

  if ($status === 'picked_up') {
    $pu = $db->prepare("UPDATE orders SET Picked_Up_At = NOW() WHERE Order_ID=?");
    $pu->execute([$orderId]);
  }

  if ($status === 'delivered') {
    $stamp = $db->prepare("UPDATE orders
                           SET payment_received_at=NOW(), payment_received_by=?
                           WHERE Order_ID=?");
    $stamp->execute(["Driver #{$driver['Driver_ID']} - {$driver['Name']}", $orderId]);

    $note = $db->prepare("INSERT INTO notifications (Type, Title, Message) VALUES ('', 'Payment Confirmed', ?)");
    $note->execute(["Driver {$driver['Name']} confirmed payment for Order #{$orderId}"]);
  }

  $db->commit();
  echo json_encode(['ok'=>true, 'orderId'=>(string)$orderId, 'status'=>$status, 'dbStatus'=>$dbStatus]);
} catch (Throwable $e) {
  $db->rollBack();
  http_response_code(500);
  echo json_encode(['error'=>'update_failed','details'=>$e->getMessage()]);
}
