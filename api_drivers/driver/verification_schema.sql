-- SQL to add verification columns to the `drivers` table
-- Run this once on your Hostinger database (via phpMyAdmin or mysql client)

ALTER TABLE `drivers`
  ADD COLUMN `verification_code` VARCHAR(255) NULL AFTER `Api_Token`,
  ADD COLUMN `code_expires_at` DATETIME NULL AFTER `verification_code`,
  ADD COLUMN `is_verified` TINYINT(1) NOT NULL DEFAULT 0 AFTER `code_expires_at`;

-- Optional index for lookups by code expiry
CREATE INDEX idx_drivers_code_expires_at ON `drivers` (`code_expires_at`);
