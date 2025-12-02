use actix_web::{web, HttpResponse};
use serde_json::json;

use crate::{EmailQueue, SmtpClient, TemplateEngine};
use crate::models::{SendOtpRequest, SendOtp2FARequest, SendEmailRequest, EmailResponse, EmailTemplate};

pub struct AppState {
    pub queue: EmailQueue,
    pub smtp: SmtpClient,
    pub templates: TemplateEngine,
}

/// Health check endpoint
pub async fn health() -> HttpResponse {
    HttpResponse::Ok().json(json!({
        "status": "healthy",
        "service": "mailer"
    }))
}

/// Send OTP email for signup (queued)
pub async fn send_otp(
    state: web::Data<AppState>,
    req: web::Json<SendOtpRequest>,
) -> HttpResponse {
    let data = json!({
        "otp": req.otp,
        "email": req.email
    });

    match state.queue.enqueue(
        req.email.clone(),
        "Your KillCode Verification Code".to_string(),
        EmailTemplate::Otp,
        data,
    ).await {
        Ok(job_id) => HttpResponse::Ok().json(EmailResponse {
            success: true,
            job_id: Some(job_id),
            message: "OTP email queued successfully".to_string(),
        }),
        Err(e) => {
            log::error!("Failed to queue OTP email: {}", e);
            HttpResponse::InternalServerError().json(EmailResponse {
                success: false,
                job_id: None,
                message: format!("Failed to queue email: {}", e),
            })
        }
    }
}

/// Send 2FA OTP email (queued)
pub async fn send_otp_2fa(
    state: web::Data<AppState>,
    req: web::Json<SendOtp2FARequest>,
) -> HttpResponse {
    let data = json!({
        "otp": req.otp,
        "email": req.email
    });

    match state.queue.enqueue(
        req.email.clone(),
        "KillCode Login Verification".to_string(),
        EmailTemplate::Otp2FA,
        data,
    ).await {
        Ok(job_id) => HttpResponse::Ok().json(EmailResponse {
            success: true,
            job_id: Some(job_id),
            message: "2FA OTP email queued successfully".to_string(),
        }),
        Err(e) => {
            log::error!("Failed to queue 2FA OTP email: {}", e);
            HttpResponse::InternalServerError().json(EmailResponse {
                success: false,
                job_id: None,
                message: format!("Failed to queue email: {}", e),
            })
        }
    }
}

/// Send generic email (queued)
pub async fn send_email(
    state: web::Data<AppState>,
    req: web::Json<SendEmailRequest>,
) -> HttpResponse {
    match state.queue.enqueue(
        req.to.clone(),
        req.subject.clone(),
        req.template.clone(),
        req.data.clone(),
    ).await {
        Ok(job_id) => HttpResponse::Ok().json(EmailResponse {
            success: true,
            job_id: Some(job_id),
            message: "Email queued successfully".to_string(),
        }),
        Err(e) => {
            log::error!("Failed to queue email: {}", e);
            HttpResponse::InternalServerError().json(EmailResponse {
                success: false,
                job_id: None,
                message: format!("Failed to queue email: {}", e),
            })
        }
    }
}

/// Get queue statistics
pub async fn queue_stats(state: web::Data<AppState>) -> HttpResponse {
    match state.queue.stats().await {
        Ok(stats) => HttpResponse::Ok().json(stats),
        Err(e) => {
            log::error!("Failed to get queue stats: {}", e);
            HttpResponse::InternalServerError().json(json!({
                "error": format!("Failed to get queue stats: {}", e)
            }))
        }
    }
}

/// Get job status by ID
pub async fn job_status(
    state: web::Data<AppState>,
    path: web::Path<String>,
) -> HttpResponse {
    let job_id = path.into_inner();
    
    match state.queue.get_job(&job_id).await {
        Ok(Some(job)) => HttpResponse::Ok().json(job),
        Ok(None) => HttpResponse::NotFound().json(json!({
            "error": "Job not found"
        })),
        Err(e) => {
            log::error!("Failed to get job status: {}", e);
            HttpResponse::InternalServerError().json(json!({
                "error": format!("Failed to get job status: {}", e)
            }))
        }
    }
}
