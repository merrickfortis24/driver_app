Verification endpoints for Driver App

Files added:
- send_verification_code.php  — generates a 6-digit code, stores it in `drivers` table, emails via PHPMailer
- verify_code.php             — verifies submitted code, marks driver as verified
- verification_schema.sql     — SQL to add columns to `drivers` table

Setup notes:
1) Install PHPMailer via Composer in your project root:
   composer require phpmailer/phpmailer

2) Update SMTP credentials inside `send_verification_code.php` (Username, Password, setFrom)

3) Run `verification_schema.sql` once to add the columns to your `drivers` table.

4) Call `send_verification_code.php` with POST JSON { "driver_id": <id> }
   It returns JSON { success: true } on success.

5) Call `verify_code.php` with POST JSON { "driver_id": <id>, "code": "123456" }

Security notes:
- For production, consider storing a hashed code instead of plaintext and comparing hash using timing-safe comparisons.
- Use TLS for SMTP (STARTTLS) and avoid hardcoding credentials in files; use env vars when possible.
