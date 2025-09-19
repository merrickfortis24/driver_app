<?php
header('Access-Control-Allow-Origin: *'); // dev only
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }

require_once __DIR__ . '/../connection.php';
$db = (new Database())->openCon();
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
header('Content-Type: application/json');

// Debug: log incoming Authorization header for troubleshooting (dev only)
try {
  $dbg_headers = function_exists('getallheaders') ? getallheaders() : [];
  $dbg_auth = $dbg_headers['Authorization'] ?? $dbg_headers['authorization'] ?? '';
  error_log('orders/debug auth header: ' . json_encode(['auth' => $dbg_auth, 'remote' => ($_SERVER['REMOTE_ADDR'] ?? '')]));
} catch (Throwable $e) {
  // ignore debug logging failures
}

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

// fetch orders (no assignment field in DB yet -> show Pending/Processing)

$colsOrders = [];
$colsAddress = [];
// Helper: get columns for a table
$getCols = function($table) use ($db) {
  $st = $db->prepare("SHOW COLUMNS FROM `" . str_replace('`','', $table) . "`");
  try {
    $st->execute();
    $res = $st->fetchAll(PDO::FETCH_COLUMN, 0);
    return $res ?: [];
  } catch (Throwable $e) {
    return [];
  }
};

$colsOrders = $getCols('orders');
$colsAddress = $getCols('order_address');

// Build select list using existing columns or NULL aliases
$select = [];
// always include these base fields if present or alias them to NULL
$want = [
  'Order_ID','Order_Date','Order_Amount','Contact_Number','order_status','Driver_Status',
  'payment_received_at','payment_received_by','Assigned_Driver_ID','Picked_Up_At',
  'customer_lat','customer_lng'
];
foreach ($want as $w) {
  if (in_array($w, $colsOrders, true)) {
    $select[] = "o.`$w`";
  } else {
    $select[] = "NULL AS `$w`";
  }
}

// address fields may be in orders or in order_address table
$addrWant = ['Street','Barangay','City'];
foreach ($addrWant as $a) {
  if (in_array($a, $colsOrders, true)) {
    $select[] = "o.`$a`";
  } elseif (in_array($a, $colsAddress, true)) {
    $select[] = "addr.`$a`";
  } else {
    $select[] = "NULL AS `$a`";
  }
}

// customer name from customer table
if (in_array('Customer_ID', $colsOrders, true)) {
  $select[] = "c.Customer_Name";
} else {
  $select[] = "NULL AS Customer_Name";
}

$selectList = implode(', ', $select);

$sql = "SELECT $selectList
  FROM orders o
  LEFT JOIN order_address addr ON addr.Order_ID = o.Order_ID
  LEFT JOIN customer c ON c.Customer_ID = o.Customer_ID
  WHERE (
      o.order_status IN ('Pending','Processing','Ready to deliver','On the way','Delivered')
    )
    AND (
      (" . (in_array('Street', $colsOrders, true) || in_array('Street', $colsAddress, true) ? "(o.Street IS NOT NULL OR addr.Street IS NOT NULL) OR " : "") .
      (in_array('City', $colsOrders, true) || in_array('City', $colsAddress, true) ? "(o.City IS NOT NULL OR addr.City IS NOT NULL) OR " : "") .
      (in_array('Contact_Number', $colsOrders, true) ? "o.Contact_Number IS NOT NULL OR " : "") .
      "(o.customer_lat IS NOT NULL AND o.customer_lng IS NOT NULL)
    )
  ORDER BY o.Order_Date DESC
  LIMIT 30";

$orders = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);

// load items for each order
$itemStmt = $db->prepare("SELECT oi.Order_Item_ID, oi.Product_ID, p.Product_Name, oi.Quantity, oi.Price
                          FROM order_item oi
                          JOIN product p ON p.Product_ID = oi.Product_ID
                          WHERE oi.Order_ID=?");
$addonStmt = $db->prepare("SELECT Addon_Name, Addon_Price, Quantity
                           FROM order_item_addons
                           WHERE Order_ID=? AND Order_Item_ID=?");

$out = [];
foreach ($orders as $o) {
  $itemStmt->execute([$o['Order_ID']]);
  $items = [];
  while ($it = $itemStmt->fetch(PDO::FETCH_ASSOC)) {
    // addons (optional)
    $addonStmt->execute([$o['Order_ID'], $it['Order_Item_ID']]);
    $addons = $addonStmt->fetchAll(PDO::FETCH_ASSOC);

    $addonOut = [];
    foreach ($addons as $a) {
      $addonOut[] = [
        'name' => $a['Addon_Name'],
        'price' => (float)$a['Addon_Price'],
        'quantity' => (int)$a['Quantity'],
      ];
    }

    $items[] = [
      'id' => (string)$it['Order_Item_ID'],
      'name' => $it['Product_Name'],
      'quantity' => (int)$it['Quantity'],
      'price' => (float)$it['Price'],
      'addons' => $addonOut,
    ];
  }

  // driver-first mapping for mobile "status"
  $driverFirst = $o['Driver_Status'];
  // Map DB order_status -> prototype driver status when Driver_Status is empty
  $fallbackMap = [
    'Pending'          => 'assigned',
    'Processing'       => 'assigned',
    'Ready to deliver' => 'assigned',
    'On the way'       => 'on_the_way',
    'Delivered'        => 'delivered',
    'Cancelled'        => 'rejected'
  ];
  $protoStatus = $driverFirst ?: ($fallbackMap[$o['order_status']] ?? 'assigned');

  // computed display status for user/admin
  $displayStatus = $o['order_status'];
  if ($o['order_status'] === 'On the way' || in_array($o['Driver_Status'], ['on_the_way','picked_up'], true)) {
    $displayStatus = 'Out for delivery';
  } elseif ($o['order_status'] === 'Processing') {
    $displayStatus = 'Preparing';
  } elseif ($o['order_status'] === 'Ready to deliver') {
    $displayStatus = 'Ready to deliver';
  }

  $out[] = [
    'id' => (string)$o['Order_ID'],
    'customerName' => $o['Customer_Name'],
    'customerPhone' => $o['Contact_Number'],
    'deliveryAddress' => trim(implode(', ', array_filter([$o['Street'], $o['Barangay'], $o['City']]))),
  // Provide coordinates when available
  'lat' => isset($o['customer_lat']) && $o['customer_lat'] !== '' ? (float)$o['customer_lat'] : null,
  'lng' => isset($o['customer_lng']) && $o['customer_lng'] !== '' ? (float)$o['customer_lng'] : null,
    'items' => $items,
    'totalAmount' => (float)$o['Order_Amount'],
    'estimatedTime' => '', // not stored in DB
    'status' => $protoStatus,        // used by the driver app
    'driverStatus' => $o['Driver_Status'], // extra for other UIs
    'displayStatus' => $displayStatus,     // human label for user/admin
    'paymentStatus' => ($o['payment_received_at'] ? 'paid' : 'unpaid'),
    'createdAt' => $o['Order_Date'],
    'pickedUpAt' => $o['Picked_Up_At'] ?? null,
    'deliveredAt' => $o['payment_received_at'],
  ];
}

echo json_encode(['orders' => $out]);
