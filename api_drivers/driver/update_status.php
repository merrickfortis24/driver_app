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
$collectedAmount = null;
if (isset($data['collectedAmount'])) {
  $collectedAmount = is_numeric($data['collectedAmount']) ? floatval($data['collectedAmount']) : null;
} elseif (isset($_POST['collectedAmount'])) {
  $collectedAmount = is_numeric($_POST['collectedAmount']) ? floatval($_POST['collectedAmount']) : null;
}

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

  // Direct status update (no claim logic)
  $assignAffected = 0; $statusAffected = 0;
  if ($dbStatus !== null) {
    $upd = $db->prepare("UPDATE orders SET order_status=?, Driver_Status=?, Driver_ID = COALESCE(Driver_ID, ?) WHERE Order_ID=?");
    $upd->execute([$dbStatus, $status, $driver['Driver_ID'], $orderId]);
    $statusAffected = $upd->rowCount();
  }

  if ($status === 'picked_up') {
    // Record picked_up event in history table (orders table has no Picked_Up_At column)
    $pu = $db->prepare("INSERT INTO order_status_history (Order_ID, Event_Type, Occurred_At) VALUES (?, 'picked_up', NOW())");
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

    // Persist delivered marker and optional proof in order_payment_receipt (orders table has no such columns)
    $by = "Driver #{$driver['Driver_ID']} - {$driver['Name']}";
    // Try update first
    $upr = $db->prepare("UPDATE order_payment_receipt
                         SET payment_received_at=NOW(), payment_received_by=?, Proof_Photo = COALESCE(Proof_Photo, ?)
                         WHERE Order_ID=?");
    $upr->execute([$by, $proofPath, $orderId]);
    if ($upr->rowCount() === 0) {
      // If no existing row, insert minimal record (default Status to 'verified')
      $ins = $db->prepare("INSERT INTO order_payment_receipt (Order_ID, payment_received_at, payment_received_by, Proof_Photo, Status)
                           VALUES (?, NOW(), ?, ?, 'verified')");
      $ins->execute([$orderId, $by, $proofPath]);
    }

    // Also record delivered event in history table
    $del = $db->prepare("INSERT INTO order_status_history (Order_ID, Event_Type, Occurred_At) VALUES (?, 'delivered', NOW())");
    $del->execute([$orderId]);

    $note = $db->prepare("INSERT INTO notifications (Type, Title, Message) VALUES ('', 'Payment Confirmed', ?)");
    $note->execute(["Driver {$driver['Name']} confirmed payment for Order #{$orderId}"]);

    // If a collectedAmount is provided, and the order payment method is COD, mark as Paid and set amount
    if ($collectedAmount !== null && $collectedAmount > 0) {
      $pm = $db->prepare('SELECT Payment_Method FROM payment WHERE Order_ID=? LIMIT 1');
      $pm->execute([$orderId]);
      $prow = $pm->fetch(PDO::FETCH_ASSOC);
      $method = strtolower($prow['Payment_Method'] ?? '');
      if ($method === 'cod' || $method === '') {
        $updPay = $db->prepare("UPDATE payment SET payment_status='Paid', Payment_Amount=? WHERE Order_ID=? AND (Payment_Method='COD' OR Payment_Method IS NULL OR Payment_Method='')");
        $updPay->execute([$collectedAmount, $orderId]);
      }
    }
  }

  // Fetch current persisted values regardless of whether MySQL returned 0 affected rows (could be same value)
  $cur = $db->prepare("SELECT Order_ID, order_status, Driver_Status, Driver_ID, order_type FROM orders WHERE Order_ID=?");
  $cur->execute([$orderId]);
  $currentRow = $cur->fetch(PDO::FETCH_ASSOC) ?: [];

  $db->commit();
  echo json_encode([
    'ok'=>true,
    'orderId'=>(string)$orderId,
    'requestedStatus'=>$status,
    'mappedOrderStatus'=>$dbStatus,
    'collectedAmount'=>$collectedAmount,
    'assignRows'=>$assignAffected,
    'statusRows'=>$statusAffected,
    'current'=>$currentRow,
  ]);
} catch (Throwable $e) {
  $db->rollBack();
  http_response_code(500);
  echo json_encode(['error'=>'update_failed','details'=>$e->getMessage(),'orderId'=>$orderId,'statusAttempt'=>$status]);
}