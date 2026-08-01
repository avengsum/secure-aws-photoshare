output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "bucket_name" {
  value = aws_s3_bucket.photos.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.photos.arn
}

output "quarantine_bucket_name" {
  value = aws_s3_bucket.quarantine.bucket
}

output "quarantine_bucket_arn" {
  value = aws_s3_bucket.quarantine.arn
}

output "db_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "db_identifier" {
  value = aws_db_instance.mysql.identifier
}

output "db_name" {
  value = aws_db_instance.mysql.db_name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "flask_session_secret_arn" {
  value = aws_secretsmanager_secret.flask_session.arn
}
