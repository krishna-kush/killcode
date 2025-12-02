pub mod queue;
pub mod smtp;
pub mod templates;
pub mod handlers;
pub mod models;

pub use queue::EmailQueue;
pub use smtp::SmtpClient;
pub use templates::TemplateEngine;
