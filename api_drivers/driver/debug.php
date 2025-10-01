<?php
header('Content-Type: application/json');
// Minimal debug endpoint to show GET/headers/server info (dev only)
$out = [
  'method' => $_SERVER['REQUEST_METHOD'] ?? null,
  'request_uri' => $_SERVER['REQUEST_URI'] ?? null,
  'query' => $_GET,
  'headers' => function_exists('getallheaders') ? getallheaders() : (function() {
      $h = [];
      foreach ($_SERVER as $k => $v) {
        if (strpos($k, 'HTTP_') === 0) {
          $h[$k] = $v;
        }
      }
      return $h;
  })(),
  'server' => [
    'REMOTE_ADDR' => $_SERVER['REMOTE_ADDR'] ?? null,
    'SERVER_SOFTWARE' => $_SERVER['SERVER_SOFTWARE'] ?? null,
  ],
];
echo json_encode($out, JSON_PRETTY_PRINT);
