<?php
// CORS handled by server-level .htaccess
header('Content-Type: application/json');
echo json_encode([
  'ok' => true,
  'time' => date('c'),
  'server' => 'driver_api',
]);
