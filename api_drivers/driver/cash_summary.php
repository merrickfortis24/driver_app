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
$driverId = (int)$driver['Driver_ID'];

// ensure remittance table exists
$db->exec("CREATE TABLE IF NOT EXISTS driver_cash_remittance (
  Remittance_ID INT AUTO_INCREMENT PRIMARY KEY,
  Driver_ID INT NOT NULL,
  Amount DECIMAL(10,2) NOT NULL,
  Note TEXT NULL,
  Proof_Path VARCHAR(255) NULL,
  Created_At DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

function sums($db, $driverId, $scope) {
  $dateFilter = '';
  if ($scope === 'today') {
    // Count collections based on when the driver marked payment received, not when the order/payment was created
    $dateFilter = " AND DATE(opr.payment_received_at) = CURRENT_DATE()";
  }
  // COD collected (paid) for this driver, optionally today by receipt time
  $sql = "SELECT COALESCE(SUM(p.Payment_Amount),0) AS total
          FROM payment p
          INNER JOIN orders o ON o.Order_ID = p.Order_ID
          LEFT JOIN order_payment_receipt opr ON opr.Order_ID = p.Order_ID
          WHERE p.Payment_Method='COD' AND p.payment_status='Paid'
            AND o.Driver_ID = ?
            AND (o.Driver_Status='delivered' OR o.order_status='Delivered')" . $dateFilter;
  $q = $db->prepare($sql);
  $q->execute([$driverId]);
  $row = $q->fetch(PDO::FETCH_ASSOC);
  $collected = (float)($row['total'] ?? 0);

  // Remitted sum
  $sql2 = "SELECT COALESCE(SUM(Amount),0) AS total FROM driver_cash_remittance WHERE Driver_ID=?" . ($scope==='today' ? " AND DATE(Created_At)=CURRENT_DATE()" : '');
  $q2 = $db->prepare($sql2);
  $q2->execute([$driverId]);
  $row2 = $q2->fetch(PDO::FETCH_ASSOC);
  $remitted = (float)($row2['total'] ?? 0);

  return [
    'collected' => $collected,
    'remitted' => $remitted,
    'cashInHand' => max($collected - $remitted, 0),
  ];
}

$today = sums($db, $driverId, 'today');
$all = sums($db, $driverId, 'all');

// recent remittances
$rec = $db->prepare('SELECT Remittance_ID, Amount, Note, Proof_Path, Created_At FROM driver_cash_remittance WHERE Driver_ID=? ORDER BY Created_At DESC LIMIT 10');
$rec->execute([$driverId]);
$rows = $rec->fetchAll(PDO::FETCH_ASSOC) ?: [];

echo json_encode([
  'ok' => true,
  'today' => $today,
  'allTime' => $all,
  'remittances' => array_map(function($r){
    return [
      'id' => (int)$r['Remittance_ID'],
      'amount' => (float)$r['Amount'],
      'note' => $r['Note'],
      'proof' => $r['Proof_Path'],
      'createdAt' => $r['Created_At'],
    ];
  }, $rows),
]);
