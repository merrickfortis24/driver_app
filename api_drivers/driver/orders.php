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
// dev helper: accept ?token=... when Authorization header isn't present (remove in prod)
if (!$token && isset($_GET['token'])) {
  $token = $_GET['token'];
}
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

// build lowercase->actual-name maps for robust, case-insensitive checks
$colsOrdersLower = array_map('strtolower', $colsOrders);
$colsAddressLower = array_map('strtolower', $colsAddress);
$colsOrdersMap = $colsOrders ? array_combine($colsOrdersLower, $colsOrders) : [];
$colsAddressMap = $colsAddress ? array_combine($colsAddressLower, $colsAddress) : [];

// Build select list using existing columns or NULL aliases
$select = [];
$want = [
  'Order_ID','Order_Date','Order_Amount','Contact_Number','order_status','Driver_Status',
  'payment_received_at','payment_received_by','Assigned_Driver_ID','Picked_Up_At',
  'customer_lat','customer_lng'
];
foreach ($want as $w) {
  $key = strtolower($w);
  if (isset($colsOrdersMap[$key])) {
    $col = $colsOrdersMap[$key];
    $select[] = "o.`$col`";
  } else {
    $select[] = "NULL AS `$w`";
  }
}

// address fields may be in orders or in order_address table
$addrWant = ['Street','Barangay','City'];
foreach ($addrWant as $a) {
  $key = strtolower($a);
  if (isset($colsOrdersMap[$key])) {
    $select[] = "o.`{$colsOrdersMap[$key]}`";
  } elseif (isset($colsAddressMap[$key])) {
    $select[] = "addr.`{$colsAddressMap[$key]}`";
  } else {
    $select[] = "NULL AS `$a`";
  }
}

// customer name from customer table
if (isset($colsOrdersMap['customer_id'])) {
  $select[] = "c.Customer_Name";
} else {
  $select[] = "NULL AS Customer_Name";
}

$selectList = implode(', ', $select);

// prefer a fixed set of statuses
$statusList = ['Pending','Processing','Ready to deliver','On the way','Delivered'];
$statusIn = "'" . implode("','", $statusList) . "'";

// Build address/availability conditions but only reference tables that actually have the columns
$addrConditions = [];
// check order_address (addr) for customer coords
if (isset($colsAddressMap['customer_lat']) && isset($colsAddressMap['customer_lng'])) {
  $addrConditions[] = "(addr.`{$colsAddressMap['customer_lat']}` IS NOT NULL AND addr.`{$colsAddressMap['customer_lng']}` IS NOT NULL)";
}
// contact number may be in orders
if (isset($colsOrdersMap['contact_number'])) {
  $addrConditions[] = "o.`{$colsOrdersMap['contact_number']}` IS NOT NULL";
} elseif (isset($colsAddressMap['contact_number'])) {
  $addrConditions[] = "addr.`{$colsAddressMap['contact_number']}` IS NOT NULL";
}
// street/city etc only reference addr if orders doesn't have them
if (isset($colsAddressMap['street']) || isset($colsAddressMap['city']) || isset($colsAddressMap['barangay'])) {
  $parts = [];
  if (isset($colsAddressMap['street'])) $parts[] = "addr.`{$colsAddressMap['street']}` IS NOT NULL";
  if (isset($colsAddressMap['barangay'])) $parts[] = "addr.`{$colsAddressMap['barangay']}` IS NOT NULL";
  if (isset($colsAddressMap['city'])) $parts[] = "addr.`{$colsAddressMap['city']}` IS NOT NULL";
  if (!empty($parts)) $addrConditions[] = '(' . implode(' OR ', $parts) . ')';
}

// always include status condition
$whereParts = [];
$orderStatusCol = $colsOrdersMap['order_status'] ?? 'order_status';
$whereParts[] = "o.`$orderStatusCol` IN ($statusIn)";
if (!empty($addrConditions)) {
  $whereParts[] = '(' . implode(' OR ', $addrConditions) . ')';
}

$whereSql = implode("\n    AND ", $whereParts);

// determine order by column safely
$orderColumn = isset($colsOrdersMap['order_date']) ? "o.`{$colsOrdersMap['order_date']}`" : "o.`Order_Date`";

// final SQL
$sql = "SELECT $selectList
  FROM `orders` o
  LEFT JOIN `order_address` addr ON addr.Order_ID = o.Order_ID
  LEFT JOIN `customer` c ON c.Customer_ID = o.Customer_ID
  WHERE $whereSql
  ORDER BY $orderColumn DESC
  LIMIT 30";

try {
  $stmt = $db->prepare($sql);
  $stmt->execute();
  $orders = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
  // log and return a JSON error so client doesn't get HTML
  error_log('orders/query failed: ' . $e->getMessage());
  http_response_code(500);
  echo json_encode(['error' => 'server_error', 'message' => 'Failed to fetch orders']);
  exit;
}

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
