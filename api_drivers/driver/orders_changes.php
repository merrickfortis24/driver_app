<?php
// Lightweight endpoint to return order changes since a given timestamp.
// GET params:
//  - since: optional ISO8601 UTC timestamp, e.g. 2025-10-21T01:00:00Z
// Authentication: expects same token mechanism used by other endpoints (Authorization header or token param)

require_once __DIR__ . '/connection.php';

header('Content-Type: application/json');

// Simple auth: reuse token logic from existing endpoints (token param or Authorization header)
$token = null;
if (!empty($_SERVER['HTTP_AUTHORIZATION'])) {
    $auth = $_SERVER['HTTP_AUTHORIZATION'];
    if (preg_match('/Bearer\s+(.*)$/i', $auth, $m)) $token = $m[1];
}
if (!$token && isset($_GET['token'])) $token = $_GET['token'];

if (!$token) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'message' => 'Missing token']);
    exit;
}

// Validate token and get driver id. Assumes a drivers table with Api_Token or similar.
try {
    $db = get_db();
    $stmt = $db->prepare('SELECT Driver_ID FROM drivers WHERE Api_Token = ? LIMIT 1');
    $stmt->execute([$token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        http_response_code(401);
        echo json_encode(['ok' => false, 'message' => 'Invalid token']);
        exit;
    }
    $driverId = $row['Driver_ID'];
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'message' => 'DB error']);
    exit;
}

$since = isset($_GET['since']) ? $_GET['since'] : null;

// Normalize since -> MySQL datetime. Expect ISO8601 UTC or fallback to null.
$sinceDt = null;
if ($since) {
    // Accept both with and without Z
    $t = date_create($since);
    if ($t) $sinceDt = $t->format('Y-m-d H:i:s');
}

try {
    if ($sinceDt) {
        // Return rows updated after since
        $q = 'SELECT id, customerName, customerPhone, deliveryAddress, totalAmount, status, paymentMethod, updated_at FROM orders WHERE driver_id = ? AND updated_at > ? ORDER BY updated_at ASC';
        $stmt = $db->prepare($q);
        $stmt->execute([$driverId, $sinceDt]);
    } else {
        // No since provided: return last_update and count of recent (last 24h)
        $q = 'SELECT id, customerName, customerPhone, deliveryAddress, totalAmount, status, paymentMethod, updated_at FROM orders WHERE driver_id = ? AND updated_at >= (NOW() - INTERVAL 1 DAY) ORDER BY updated_at DESC LIMIT 10';
        $stmt = $db->prepare($q);
        $stmt->execute([$driverId]);
    }

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $newCount = count($rows);
    $lastUpdate = $newCount ? $rows[$newCount - 1]['updated_at'] : gmdate('Y-m-d\TH:i:s\Z');

    // Convert updated_at to ISO8601 Z format
    foreach ($rows as &$r) {
        if (!empty($r['updated_at'])) {
            $dt = date_create($r['updated_at']);
            if ($dt) $r['updated_at'] = gmdate('Y-m-d\TH:i:s\Z', strtotime($r['updated_at']));
        }
    }

    echo json_encode([
        'ok' => true,
        'last_update' => $lastUpdate,
        'new_count' => $newCount,
        'orders' => $rows,
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'message' => 'DB query error']);
}

?>