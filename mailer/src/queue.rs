use std::sync::Arc;
use redis::{AsyncCommands, Client as RedisClient};
use tokio::sync::Mutex;
use chrono::Utc;
use uuid::Uuid;

use crate::models::{EmailJob, EmailStatus, EmailTemplate};

const QUEUE_KEY: &str = "mailer:queue";
const PROCESSING_KEY: &str = "mailer:processing";
const JOBS_KEY: &str = "mailer:jobs";

pub struct EmailQueue {
    redis: Arc<Mutex<redis::aio::MultiplexedConnection>>,
}

impl EmailQueue {
    pub async fn new(redis_url: &str) -> Result<Self, anyhow::Error> {
        let client = RedisClient::open(redis_url)?;
        let conn = client.get_multiplexed_async_connection().await?;
        
        Ok(Self {
            redis: Arc::new(Mutex::new(conn)),
        })
    }

    /// Add a new email job to the queue
    pub async fn enqueue(&self, to: String, subject: String, template: EmailTemplate, data: serde_json::Value) -> Result<String, anyhow::Error> {
        let job_id = Uuid::new_v4().to_string();
        
        let job = EmailJob {
            id: job_id.clone(),
            to,
            subject,
            template,
            data,
            status: EmailStatus::Pending,
            created_at: Utc::now(),
            sent_at: None,
            retries: 0,
            max_retries: 3,
            error: None,
        };

        let job_json = serde_json::to_string(&job)?;
        
        let mut conn = self.redis.lock().await;
        
        // Store job details
        let _: () = conn.hset(JOBS_KEY, &job_id, &job_json).await?;
        
        // Add to queue
        let _: () = conn.rpush(QUEUE_KEY, &job_id).await?;
        
        log::info!("📧 Enqueued email job: {} to {}", job_id, job.to);
        
        Ok(job_id)
    }

    /// Get the next job from the queue
    pub async fn dequeue(&self) -> Result<Option<EmailJob>, anyhow::Error> {
        let mut conn = self.redis.lock().await;
        
        // Move from queue to processing
        let job_id: Option<String> = conn.lpop(QUEUE_KEY, None).await?;
        
        if let Some(id) = job_id {
            // Get job details
            let job_json: Option<String> = conn.hget(JOBS_KEY, &id).await?;
            
            if let Some(json) = job_json {
                let mut job: EmailJob = serde_json::from_str(&json)?;
                job.status = EmailStatus::Processing;
                
                // Update job status
                let _: () = conn.hset(JOBS_KEY, &id, serde_json::to_string(&job)?).await?;
                
                // Add to processing set
                let _: () = conn.sadd(PROCESSING_KEY, &id).await?;
                
                return Ok(Some(job));
            }
        }
        
        Ok(None)
    }

    /// Mark a job as completed
    pub async fn complete(&self, job_id: &str) -> Result<(), anyhow::Error> {
        let mut conn = self.redis.lock().await;
        
        let job_json: Option<String> = conn.hget(JOBS_KEY, job_id).await?;
        
        if let Some(json) = job_json {
            let mut job: EmailJob = serde_json::from_str(&json)?;
            job.status = EmailStatus::Sent;
            job.sent_at = Some(Utc::now());
            
            let _: () = conn.hset(JOBS_KEY, job_id, serde_json::to_string(&job)?).await?;
            let _: () = conn.srem(PROCESSING_KEY, job_id).await?;
            
            log::info!("✅ Email sent successfully: {}", job_id);
        }
        
        Ok(())
    }

    /// Mark a job as failed (will retry if retries < max_retries)
    pub async fn fail(&self, job_id: &str, error: &str) -> Result<bool, anyhow::Error> {
        let mut conn = self.redis.lock().await;
        
        let job_json: Option<String> = conn.hget(JOBS_KEY, job_id).await?;
        
        if let Some(json) = job_json {
            let mut job: EmailJob = serde_json::from_str(&json)?;
            job.retries += 1;
            job.error = Some(error.to_string());
            
            let _: () = conn.srem(PROCESSING_KEY, job_id).await?;
            
            if job.retries < job.max_retries {
                // Re-queue for retry
                job.status = EmailStatus::Pending;
                let _: () = conn.hset(JOBS_KEY, job_id, serde_json::to_string(&job)?).await?;
                let _: () = conn.rpush(QUEUE_KEY, job_id).await?;
                
                log::warn!("⚠️ Email failed, retrying ({}/{}): {} - {}", job.retries, job.max_retries, job_id, error);
                return Ok(true); // Will retry
            } else {
                // Max retries reached
                job.status = EmailStatus::Failed;
                let _: () = conn.hset(JOBS_KEY, job_id, serde_json::to_string(&job)?).await?;
                
                log::error!("❌ Email permanently failed: {} - {}", job_id, error);
                return Ok(false); // No more retries
            }
        }
        
        Ok(false)
    }

    /// Get queue statistics
    pub async fn stats(&self) -> Result<crate::models::QueueStats, anyhow::Error> {
        let mut conn = self.redis.lock().await;
        
        let pending: u64 = conn.llen(QUEUE_KEY).await?;
        let processing: u64 = conn.scard(PROCESSING_KEY).await?;
        
        // Count sent and failed from jobs hash
        let jobs: Vec<String> = conn.hvals(JOBS_KEY).await?;
        let mut sent = 0u64;
        let mut failed = 0u64;
        
        for job_json in jobs {
            if let Ok(job) = serde_json::from_str::<EmailJob>(&job_json) {
                match job.status {
                    EmailStatus::Sent => sent += 1,
                    EmailStatus::Failed => failed += 1,
                    _ => {}
                }
            }
        }
        
        Ok(crate::models::QueueStats {
            pending,
            processing,
            sent,
            failed,
        })
    }

    /// Get a job by ID
    pub async fn get_job(&self, job_id: &str) -> Result<Option<EmailJob>, anyhow::Error> {
        let mut conn = self.redis.lock().await;
        
        let job_json: Option<String> = conn.hget(JOBS_KEY, job_id).await?;
        
        if let Some(json) = job_json {
            let job: EmailJob = serde_json::from_str(&json)?;
            return Ok(Some(job));
        }
        
        Ok(None)
    }
}
