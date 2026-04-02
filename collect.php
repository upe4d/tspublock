<?php
/**
 * collect.php — Приём RST IP от внешних участников
 * @version 1.0.0
 * POST { "ips": ["1.2.3.4", ...], "token": "..." }
 */
header('Content-Type: application/json');

define('TOKEN',      'upe4d_rst_2026');   // простой токен защиты
define('SUBMIT_LOG', '/etc/rst_submitted.txt');
define('ADDED_FILE', '/etc/rst_added.txt');
define('IPSET_NAME', 'TSPUIPS');

// Whitelist — эти IP никогда не добавляем
define('WHITELIST', [
    '149.154.', '91.108.', '91.105.', '95.161.',  // Telegram DC
    '89.22.227.9',  // наш сервер
]);

$body = json_decode(file_get_contents('php://input'), true);

if (($body['token'] ?? '') !== TOKEN) {
    http_response_code(403);
    echo json_encode(['error' => 'bad token']);
    exit;
}

$submitted = array_filter($body['ips'] ?? [], function($ip) {
    if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) return false;
    foreach (WHITELIST as $wl) {
        if (str_starts_with($ip, $wl)) return false;
    }
    return true;
});

if (empty($submitted)) {
    echo json_encode(['added' => 0, 'msg' => 'no valid IPs']);
    exit;
}

$added = 0;
$ts    = date('Y-m-d H:i:s');
$src   = $_SERVER['REMOTE_ADDR'] ?? 'unknown';

foreach (array_unique($submitted) as $ip) {
    // Проверяем нет ли уже в ipset
    $exists = shell_exec("ipset test TSPUIPS " . escapeshellarg($ip) . " 2>&1");
    if (str_contains($exists ?? '', 'is in set')) continue;

    // Добавляем
    $result = shell_exec("sudo ipset add TSPUIPS " . escapeshellarg($ip) . " 2>/dev/null");
    file_put_contents(ADDED_FILE,   "$ts $ip\n", FILE_APPEND);
    file_put_contents(SUBMIT_LOG,   "$ts $ip from=$src\n", FILE_APPEND);
    $added++;
}

if ($added > 0) {
    shell_exec('sudo ipset save > /etc/ipset.conf');
}

echo json_encode([
    'added'     => $added,
    'received'  => count($submitted),
    'msg'       => "Спасибо! Добавлено $added новых IP в базу",
]);
