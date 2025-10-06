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
  'accepted'   => 'On the way',   // when driver accepts, admin sees On the way
  'on_the_way' => 'On the way',
  'picked_up'  => 'Processing',   // used internally; admin label may still show Preparing
  'delivered'  => 'Delivered',
  'rejected'   => null,            // reject should not change DB status here
];
$dbStatus = $map[$status];

$db->beginTransaction();
try {
  // ensure order exists and is a Delivery-type (has address or contact)
  // Determine pickup vs delivery by order_type (preferred) or presence of address row
  $chk = $db->prepare("SELECT o.Order_ID, o.order_type, oa.Order_ID AS addr_exists
                       FROM orders o
                       LEFT JOIN order_address oa ON oa.Order_ID = o.Order_ID
                       WHERE o.Order_ID=? FOR UPDATE");
  $chk->execute([$orderId]);
  $order = $chk->fetch(PDO::FETCH_ASSOC);
  if (!$order) { throw new RuntimeException('order_not_found'); }
  $rawType = $order['order_type'] ?? '';
  // Normalize order_type by stripping non-letters and lowering (so 'Pick Up', 'PICK-UP' all count)
  $normalizedType = strtolower(preg_replace('/[^a-z]/','', $rawType));
  $isPickup = $normalizedType === 'pickup';
  if ($isPickup) {
    throw new RuntimeException('pickup_order_not_applicable');
  }

  // If rejected by the driver, do not alter DB; driver UI will drop it.
  if ($status === 'rejected') {
    $db->commit();
    echo json_encode(['ok'=>true, 'orderId'=>(string)$orderId, 'status'=>'rejected', 'note'=>'no_change']);
    return;
  }

  // assign driver on first accept and onward transitions
  $assignAffected = 0;
  $statusAffected = 0;
  if (in_array($status, ['accepted','on_the_way','picked_up','delivered'], true)) {
    // Detect whether Assigned_Driver_ID column exists; fall back to Driver_ID if not
    static $assignCol = null;
    if ($assignCol === null) {
      try {
        $cols = $db->query("SHOW COLUMNS FROM `orders`")->fetchAll(PDO::FETCH_COLUMN, 0);
        $assignCol = in_array('Assigned_Driver_ID', $cols, true) ? 'Assigned_Driver_ID' : (in_array('Driver_ID', $cols, true) ? 'Driver_ID' : null);
      } catch (Throwable $e) {
        $assignCol = 'Driver_ID'; // best-effort fallback
      }
    }
    if ($assignCol) {
      $assign = $db->prepare("UPDATE orders SET `$assignCol` = COALESCE(`$assignCol`, ?) WHERE Order_ID=?");
      try { $assign->execute([$driver['Driver_ID'], $orderId]); $assignAffected = $assign->rowCount(); } catch (Throwable $e) { /* do not fail whole tx if assignment column absent */ }
    }
  }

  // update order status + driver status
  if ($dbStatus !== null) {
    $upd = $db->prepare("UPDATE orders SET order_status=?, Driver_Status=? WHERE Order_ID=?");
    $upd->execute([$dbStatus, $status, $orderId]);
    $statusAffected = $upd->rowCount();
  }

  if ($status === 'picked_up') {
    $pu = $db->prepare("UPDATE orders SET Picked_Up_At = NOW() WHERE Order_ID=?");
    $pu->execute([$orderId]);
  }

  if ($status === 'delivered') {
    // optional photo proof: accept multipart/form-data 'proof' or base64 in JSON data['photoBase64']
    $proofPath = null;
    $uploadDir = __DIR__ . '/../../uploads/proofs';
    if (!is_dir($uploadDir)) { @mkdir($uploadDir, 0777, true); }
    if (!empty($_FILES['proof']['tmp_name'])) {
      $ext = pathinfo($_FILES['proof']['name'], PATHINFO_EXTENSION) ?: 'jpg';
      $fname = 'order_' . $orderId . '_' . time() . '.' . preg_replace('/[^a-zA-Z0-9]/','', $ext);
      $dest = $uploadDir . '/' . $fname;
      if (@move_uploaded_file($_FILES['proof']['tmp_name'], $dest)) { $proofPath = $fname; }
    } elseif (!empty($data['photoBase64'])) {
      $img = base64_decode(preg_replace('#^data:image/\w+;base64,#', '', $data['photoBase64']));
      if ($img) {
        $fname = 'order_' . $orderId . '_' . time() . '.jpg';
        $dest = $uploadDir . '/' . $fname;
        if (@file_put_contents($dest, $img) !== false) { $proofPath = $fname; }
      }
    }

    // Persist payment received and optional proof filename if schema has column
    $stamp = $db->prepare("UPDATE orders
                           SET payment_received_at=NOW(), payment_received_by=?, Proof_Photo = COALESCE(Proof_Photo, ?)
                           WHERE Order_ID=?");
    try {
      $stamp->execute(["Driver #{$driver['Driver_ID']} - {$driver['Name']}", $proofPath, $orderId]);
    } catch (Throwable $e) {
      // Fallback when Proof_Photo column doesn't exist
      $stamp = $db->prepare("UPDATE orders SET payment_received_at=NOW(), payment_received_by=? WHERE Order_ID=?");
      $stamp->execute(["Driver #{$driver['Driver_ID']} - {$driver['Name']}", $orderId]);
    }

    $note = $db->prepare("INSERT INTO notifications (Type, Title, Message) VALUES ('', 'Payment Confirmed', ?)");
    $note->execute(["Driver {$driver['Name']} confirmed payment for Order #{$orderId}"]);
  }

  // Fetch current persisted values regardless of whether MySQL returned 0 affected rows (could be same value)
  $cur = $db->prepare("SELECT Order_ID, order_status, Driver_Status, Assigned_Driver_ID, Driver_ID, order_type FROM orders WHERE Order_ID=?");
  $cur->execute([$orderId]);
  $currentRow = $cur->fetch(PDO::FETCH_ASSOC) ?: [];

  $db->commit();
  echo json_encode([
    'ok'=>true,
    'orderId'=>(string)$orderId,
    'requestedStatus'=>$status,
    'mappedOrderStatus'=>$dbStatus,
    'assignRows'=>$assignAffected,
    'statusRows'=>$statusAffected,
    'current'=>$currentRow,
  ]);
} catch (Throwable $e) {
  $db->rollBack();
  http_response_code(500);
  echo json_encode(['error'=>'update_failed','details'=>$e->getMessage(),'orderId'=>$orderId,'statusAttempt'=>$status]);
}