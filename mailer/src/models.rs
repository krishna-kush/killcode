use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

/// Email job in the queue
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailJob {
    pub id: String,
    pub to: String,
    pub subject: String,
    pub template: EmailTemplate,
    pub data: serde_json::Value,
    pub status: EmailStatus,
    pub created_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
    pub retries: u32,
    pub max_retries: u32,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum EmailStatus {
    Pending,
    Processing,
    Sent,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EmailTemplate {
    Otp,
    Otp2FA,
    Welcome,
    PasswordReset,
    LicenseCreated,
    Custom,
}

/// Request to send an OTP email (signup)
#[derive(Debug, Deserialize)]
pub struct SendOtpRequest {
    pub email: String,
    pub otp: String,
}

/// Request to send a 2FA OTP email
#[derive(Debug, Deserialize)]
pub struct SendOtp2FARequest {
    pub email: String,
    pub otp: String,
}

/// Request to send a generic email
#[derive(Debug, Deserialize)]
pub struct SendEmailRequest {
    pub to: String,
    pub subject: String,
    pub template: EmailTemplate,
    #[serde(default)]
    pub data: serde_json::Value,
}

/// Response for email operations
#[derive(Debug, Serialize)]
pub struct EmailResponse {
    pub success: bool,
    pub job_id: Option<String>,
    pub message: String,
}

/// Queue stats response
#[derive(Debug, Serialize)]
pub struct QueueStats {
    pub pending: u64,
    pub processing: u64,
    pub sent: u64,
    pub failed: u64,
}
