use actix_web::{web, App, HttpServer, middleware};
use std::env;
use std::sync::Arc;
use tokio::time::{interval, Duration};

use mailer::{EmailQueue, SmtpClient, TemplateEngine};
use mailer::handlers::{self, AppState};

/// Worker task that processes queued emails
async fn email_worker(state: Arc<AppState>) {
    log::info!("📧 Email worker started");
    
    let mut ticker = interval(Duration::from_secs(1));
    
    loop {
        ticker.tick().await;
        
        // Try to process a job
        match state.queue.dequeue().await {
            Ok(Some(job)) => {
                log::info!("📤 Processing email job: {} to {}", job.id, job.to);
                
                // Render template
                let html = match state.templates.render(&job.template, &job.data) {
                    Ok(h) => h,
                    Err(e) => {
                        log::error!("Failed to render template: {}", e);
                        let _ = state.queue.fail(&job.id, &e.to_string()).await;
                        continue;
                    }
                };
                
                // Send email
                match state.smtp.send(&job.to, &job.subject, &html).await {
                    Ok(()) => {
                        let _ = state.queue.complete(&job.id).await;
                    }
                    Err(e) => {
                        log::error!("Failed to send email: {}", e);
                        let _ = state.queue.fail(&job.id, &e.to_string()).await;
                    }
                }
            }
            Ok(None) => {
                // No jobs in queue, continue waiting
            }
            Err(e) => {
                log::error!("Failed to dequeue job: {}", e);
            }
        }
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Initialize logging
    env_logger::init_from_env(env_logger::Env::new().default_filter_or("info"));
    
    log::info!("🚀 Starting KillCode Mailer Service");
    
    // Load configuration from environment
    // Internal service - always binds to 0.0.0.0:8000
    let bind_addr = "0.0.0.0:8000";
    let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://redis:6379".to_string());
    
    let smtp_host = env::var("SMTP_HOST").expect("SMTP_HOST must be set");
    let smtp_port: u16 = env::var("SMTP_PORT")
        .unwrap_or_else(|_| "587".to_string())
        .parse()
        .expect("SMTP_PORT must be a valid port number");
    let smtp_user = env::var("SMTP_USER").expect("SMTP_USER must be set");
    let smtp_pass = env::var("SMTP_PASS").expect("SMTP_PASS must be set");
    let smtp_secure = env::var("SMTP_SECURE")
        .unwrap_or_else(|_| "true".to_string())
        .parse::<bool>()
        .unwrap_or(true);
    let smtp_accept_invalid_certs = env::var("SMTP_ACCEPT_INVALID_CERTS")
        .unwrap_or_else(|_| "false".to_string())
        .parse::<bool>()
        .unwrap_or(false);
    // Use implicit TLS (SMTPS/port 465) instead of STARTTLS (port 587)
    // Set to true if your SMTP server uses port 465 or expects TLS from the start
    let smtp_implicit_tls = env::var("SMTP_IMPLICIT_TLS")
        .unwrap_or_else(|_| "false".to_string())
        .parse::<bool>()
        .unwrap_or(false);
    
    log::info!("📫 SMTP: {}:{} (secure: {}, implicit_tls: {}, accept_invalid_certs: {})", 
        smtp_host, smtp_port, smtp_secure, smtp_implicit_tls, smtp_accept_invalid_certs);
    log::info!("📦 Redis: {}", redis_url);
    
    // Initialize components
    let queue = EmailQueue::new(&redis_url)
        .await
        .expect("Failed to connect to Redis");
    
    let smtp = SmtpClient::new(&smtp_host, smtp_port, &smtp_user, &smtp_pass, smtp_secure, smtp_accept_invalid_certs, smtp_implicit_tls)
        .expect("Failed to create SMTP client");
    
    let templates = TemplateEngine::new();
    
    let state = Arc::new(AppState {
        queue,
        smtp,
        templates,
    });
    
    // Start email worker in background
    let worker_state = state.clone();
    tokio::spawn(async move {
        email_worker(worker_state).await;
    });
    
    log::info!("🌐 Listening on {}", bind_addr);
    
    let app_state = web::Data::from(state);
    
    HttpServer::new(move || {
        App::new()
            .app_data(app_state.clone())
            .wrap(middleware::Logger::default())
            .route("/health", web::get().to(handlers::health))
            .route("/send/otp", web::post().to(handlers::send_otp))
            .route("/send/otp-2fa", web::post().to(handlers::send_otp_2fa))
            .route("/send", web::post().to(handlers::send_email))
            .route("/stats", web::get().to(handlers::queue_stats))
            .route("/job/{job_id}", web::get().to(handlers::job_status))
    })
    .bind(bind_addr)?
    .run()
    .await
}
