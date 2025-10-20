<?php
// mailer.php - simple wrapper to create configured PHPMailer instances
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

// Try common locations for PHPMailer sources (composer vendor is preferred)
$candidates = [
    __DIR__ . '/../../vendor/phpmailer/phpmailer/src',
    __DIR__ . '/../vendor/phpmailer/phpmailer/src',
    __DIR__ . '/PHPMailer-master/src',
    __DIR__ . '/../../PHPMailer-master/src',
];
$found = null;
foreach ($candidates as $dir) {
    if (is_dir($dir)) { $found = $dir; break; }
}
if ($found === null) {
    // If composer autoload is available, include it instead
    if (is_file(__DIR__ . '/../../vendor/autoload.php')) {
        require_once __DIR__ . '/../../vendor/autoload.php';
    } else {
        throw new \RuntimeException('PHPMailer sources not found. Install via Composer or place PHPMailer sources in one of: ' . implode(', ', $candidates));
    }
} else {
    require_once $found . '/Exception.php';
    require_once $found . '/PHPMailer.php';
    require_once $found . '/SMTP.php';
}

function mailer_instance(): PHPMailer {
    // allow configuration via environment or a small .mail.env.php file
    $envCandidates = [
        __DIR__ . '/../.mail.env.php',
        __DIR__ . '/../mail.env.php',
        __DIR__ . '/../config/.mail.env.php',
        __DIR__ . '/../config/mail.env.php',
    ];
    foreach ($envCandidates as $envFile) {
        if (is_file($envFile)) { include $envFile; break; }
    }

    $mail = new PHPMailer(true);
    $mail->CharSet = 'UTF-8';
    $mail->isSMTP();
    $mail->Timeout = (int)(getenv('MAIL_TIMEOUT') ?: 20);
    $mail->SMTPAutoTLS = true;

    $mail->Host     = getenv('SMTP_HOST') ?: 'smtp.hostinger.com';
    $mail->Port     = (int)(getenv('SMTP_PORT') ?: 587);
    $mail->Username = getenv('SMTP_USER') ?: 'hello@naitsa.online';
    $mail->Password = getenv('SMTP_PASS') ?: 'Naitsa@123';
    if ($mail->Username === '' || $mail->Password === '') {
        throw new \RuntimeException('SMTP_USER/SMTP_PASS not set. Create mail.env.php with your mailbox credentials.');
    }
    $mail->SMTPAuth = true;

    $secure = strtolower((string)getenv('SMTP_SECURE'));
    if ($secure === 'ssl') {
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_SMTPS;
    } elseif ($secure === 'tls' || $secure === '') {
        $mail->SMTPSecure = ($mail->Port === 465) ? PHPMailer::ENCRYPTION_SMTPS : PHPMailer::ENCRYPTION_STARTTLS;
    } else {
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
    }

    $fromAddress = getenv('MAIL_FROM') ?: ($mail->Username ?: 'no-reply@example.com');
    $fromName = getenv('MAIL_FROM_NAME') ?: 'Nai Tsa';
    $mail->setFrom($fromAddress, $fromName);
    $mail->Sender = $fromAddress;

    if (getenv('MAIL_DEBUG')) {
        $mail->SMTPDebug  = 2;
        $mail->Debugoutput = 'error_log';
    }

    return $mail;
}

function send_verification_email_simple(string $toEmail, string $toName, string $code) {
    try {
        $mail = mailer_instance();
        $mail->addAddress($toEmail, $toName ?: '');
        $mail->isHTML(true);
        $mail->Subject = 'Your Nai Tsa verification code';
        $safeName = htmlspecialchars($toName ?: 'there', ENT_QUOTES, 'UTF-8');
        $codeEsc = htmlspecialchars($code, ENT_QUOTES, 'UTF-8');
        $mail->Body = '<p>Hi ' . $safeName . ',</p>' .
                      '<p>Your verification code is:</p>' .
                      '<p style="font-size:22px;font-weight:700;letter-spacing:3px">' . $codeEsc . '</p>' .
                      '<p>This code expires in 5 minutes.</p>';
        $mail->AltBody = "Your verification code is: {$code} (valid for 5 minutes)";
        $mail->send();
        return true;
    } catch (Exception $e) {
        return $e->getMessage();
    }
}
