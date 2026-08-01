CREATE DATABASE IF NOT EXISTS photoshare CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE photoshare;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(30) NOT NULL UNIQUE,
    password_hash VARCHAR(256) NOT NULL,
    created_at DATETIME NOT NULL,
    INDEX idx_username (username)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS uploads (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    s3_key VARCHAR(512) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    sha256_hash CHAR(64) NOT NULL,
    uploaded_at DATETIME NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_uploads (user_id, uploaded_at DESC)
) ENGINE=InnoDB;
