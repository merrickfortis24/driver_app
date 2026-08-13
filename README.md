# Driver App (Nai Tsa Driver)

Mobile driver application built with Flutter for managing delivery operations, order lifecycle updates, proof-of-delivery uploads, cash remittance, and driver profile management.

## Overview

This project contains:

- **Flutter client app** in `/home/runner/work/driver_app/driver_app/lib`
- **PHP backend API** in `/home/runner/work/driver_app/driver_app/api_drivers/driver`

The app is designed for delivery riders/drivers to:

- sign in and verify their account
- view active and historical orders
- update order statuses
- navigate to customer locations
- upload delivery proof photos and signatures
- track collected/remitted cash
- edit profile information

## Core Features

### 1) Authentication + Verification

- Login flow via API endpoint
- Email verification dialog for 6-digit code submission
- Resend verification code with cooldown
- Token persistence using `shared_preferences`
- Unauthorized handling clears token and redirects to login

### 2) Order Management

- Fetch order list from backend
- Supports top-level list or wrapped payload formats (`data`, `orders`)
- Status mapping:
  - `assigned`
  - `accepted`
  - `rejected`
  - `on_the_way`
  - `picked_up`
  - `delivered`
- Lightweight polling using `orders_changes.php` every 10 seconds
- Merge incoming changes into current list and highlight new/updated items

### 3) Delivery Completion / Proof

- Capture proof photos from camera or gallery (1 to 5 photos)
- Upload photos using multipart request
- Upload signature PNG
- Optional amount collection flow for COD/unpaid orders

### 4) Map + Location

- Current location stream via `geolocator`
- In-app map rendering via `flutter_map`
- Route drawing using OSRM API (`router.project-osrm.org`)
- Quick launch to external navigation apps

### 5) Cash and Remittance

- Fetch daily cash summary:
  - collected
  - remitted
  - cash in hand
- Submit remittance amount with optional note/proof
- UI pre-fills remittance amount from cash-in-hand value

### 6) Driver Profile

- Fetch profile from backend
- Tolerant parsing for multiple response shapes (`driver`, `user`, `data`)
- Inline profile edit and save
- Logout clears local token

### 7) Theming and UX

- Light/dark theme toggle with persistent preference
- Shared header components
- Global logging enabled for development

## Tech Stack

### Frontend

- **Flutter** (Dart SDK `^3.9.0`)
- `http` for REST calls
- `shared_preferences` for local session/settings
- `intl` for formatting
- `url_launcher` for deep links/navigation
- `flutter_map` + `latlong2` for map UI
- `geolocator` for GPS/location permissions
- `image_picker` for photo capture/select
- `signature` support for proof signing flows
- `logging` for app logs

### Backend

- **PHP** API endpoints (`/api_drivers/driver/*.php`)
- JSON + multipart endpoints
- Email verification support using **PHPMailer** (via Composer)

## Project Structure

```text
driver_app/
├── lib/
│   ├── api_connection/
│   │   └── api_connection.dart
│   ├── models/
│   │   └── delivery.dart
│   ├── pages/
│   │   ├── login.dart
│   │   ├── main_shell.dart
│   │   ├── home.dart
│   │   ├── history.dart
│   │   ├── cash_page.dart
│   │   ├── profile_page.dart
│   │   ├── map_page.dart
│   │   └── proof_capture_page.dart
│   ├── services/
│   │   ├── delivery_api.dart
│   │   ├── delivery_exceptions.dart
│   │   ├── theme_controller.dart
│   │   └── animation_controller.dart
│   ├── widgets/
│   │   └── header_icon.dart
│   └── main.dart
├── api_drivers/
│   └── driver/
│       ├── login.php
│       ├── orders.php
│       ├── orders_changes.php
│       ├── update_status.php
│       ├── profile.php
│       ├── update_profile.php
│       ├── upload_proofs.php
│       ├── upload_signature.php
│       ├── cash_summary.php
│       ├── remittance_submit.php
│       ├── send_verification_code.php
│       ├── resend_verification_code.php
│       ├── verify_code.php
│       └── verification_schema.sql
├── assets/
│   └── logo.jpg
└── test/
    └── widget_test.dart
```

## API Configuration

API base URLs are managed in:

- `/home/runner/work/driver_app/driver_app/lib/api_connection/api_connection.dart`

Current behavior:

- **Release mode** uses production base:
  - `https://naitsa.online/api_drivers`
- **Debug/Profile mode** uses emulator/LAN base:
  - `http://192.168.1.10/naitsa/driver_app/api_drivers`

Override at runtime:

```bash
flutter run --dart-define=API_BASE=https://your-domain.com/api_drivers
```

## Main Endpoints Used by App

- `POST /driver/login.php`
- `GET /driver/orders.php`
- `GET /driver/orders_changes.php`
- `POST /driver/update_status.php`
- `GET /driver/profile.php`
- `POST /driver/update_profile.php`
- `POST /driver/upload_proofs.php`
- `POST /driver/upload_signature.php`
- `GET /driver/cash_summary.php`
- `POST /driver/remittance_submit.php`
- `POST /driver/send_verification_code.php`
- `POST /driver/resend_verification_code.php`
- `POST /driver/verify_code.php`

## Verification Backend Notes

Reference: `/home/runner/work/driver_app/driver_app/api_drivers/driver/README_VERIFICATION.md`

Required setup:

1. Install PHPMailer:
   ```bash
   composer require phpmailer/phpmailer
   ```
2. Configure SMTP credentials in verification mailer implementation.
3. Run `verification_schema.sql` once on the `drivers` table.

## Local Development

### Prerequisites

- Flutter SDK installed
- Dart SDK (via Flutter)
- Android Studio / Xcode / VS Code setup
- PHP backend available locally or remotely

### Install dependencies

```bash
flutter pub get
```

### Run app

```bash
flutter run
```

### Run static analysis

```bash
flutter analyze
```

### Run tests

```bash
flutter test
```

## Notes and Limitations

- The default `test/widget_test.dart` is still Flutter template-style and may not reflect current app UI behavior.
- Some debug defaults point to LAN/local backend IPs; update base URL for your environment.
- Keep API auth tokens secure and avoid committing real credentials.

## Future Improvements (Suggested)

- Expand automated tests for login/order/cash flows
- Add stronger typed DTO mapping for all endpoint responses
- Improve offline behavior and retry/backoff strategy
- Move sensitive backend SMTP/auth config fully to environment variables

## License

Private/internal project (no public license declared in repository).
