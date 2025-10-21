<?php
// .mail.env.php (DEV placeholder) — DO NOT commit with real credentials.
// Drop this file into api_drivers/driver/ to provide SMTP credentials for mailer.php.
// mailer.php includes this file (via include) and then uses getenv() to read variables.

// Example values — replace with your real SMTP settings before testing.
putenv('SMTP_HOST=smtp.hostinger.com');
putenv('SMTP_PORT=465');            // 465 for SMTPS, 587 for STARTTLS
putenv('SMTP_USER=hello@naitsa.online');
putenv('SMTP_PASS=Fortismerrick@24');
putenv('SMTP_SECURE=ssl');         // 'ssl' or 'tls'
putenv('MAIL_FROM=hello@naitsa.online');
putenv('MAIL_FROM_NAME=Nai Tsa');
putenv('MAIL_DEBUG=1');            // enable PHPMailer debug -> error_log for troubleshooting
putenv('MAIL_TIMEOUT=30');         // seconds

// Notes:
// - For security, add this file to .gitignore (do not commit credentials).
// - If using STARTTLS, set SMTP_PORT=587 and SMTP_SECURE=tls.
// - After editing with real credentials, re-run the POST test to try sending mail.

return true;
