<?php
header('Access-Control-Allow-Origin: *'); // dev only
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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

// fetch orders (no assignment field in DB yet -> show Pending/Processing)
$sql = "SELECT o.Order_ID, o.Order_Date, o.Order_Amount, o.Street, o.Barangay, o.City,
               o.Contact_Number, o.order_status, o.payment_received_at, o.payment_received_by,
               c.Customer_Name
        FROM orders o
        JOIN customer c ON c.Customer_ID = o.Customer_ID
        WHERE o.order_status IN ('Pending','Processing','Delivered')
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

  // map DB status -> prototype status
  $map = ['Pending'=>'assigned', 'Processing'=>'accepted', 'Delivered'=>'delivered', 'Cancelled'=>'rejected'];
  $protoStatus = $map[$o['order_status']] ?? 'assigned';

  $out[] = [
    'id' => (string)$o['Order_ID'],
    'customerName' => $o['Customer_Name'],
    'customerPhone' => $o['Contact_Number'],
    'deliveryAddress' => trim(implode(', ', array_filter([$o['Street'], $o['Barangay'], $o['City']]))),
    'items' => $items,
    'totalAmount' => (float)$o['Order_Amount'],
    'estimatedTime' => '', // not stored in DB
    'status' => $protoStatus,
    'paymentStatus' => ($o['payment_received_at'] ? 'paid' : 'unpaid'),
    'createdAt' => $o['Order_Date'],
    'pickedUpAt' => null,
    'deliveredAt' => $o['payment_received_at'],
  ];
}

echo json_encode(['orders' => $out]);
