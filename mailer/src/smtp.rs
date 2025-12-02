use lettre::{
    message::header::ContentType,
    transport::smtp::authentication::Credentials,
    transport::smtp::client::{Tls, TlsParameters},
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
};
use std::time::Duration;

pub struct SmtpClient {
    mailer: AsyncSmtpTransport<Tokio1Executor>,
    from_email: String,
    from_name: String,
}

impl SmtpClient {
    /// Create a new SMTP client
    /// 
    /// # Arguments
    /// * `host` - SMTP server hostname
    /// * `port` - SMTP server port (587 for STARTTLS, 465 for implicit TLS/SMTPS)
    /// * `username` - SMTP username
    /// * `password` - SMTP password
    /// * `secure` - Use TLS (true for secure connections)
    /// * `accept_invalid_certs` - Skip certificate verification (for self-signed certs)
    /// * `implicit_tls` - Use implicit TLS (port 465/SMTPS) instead of STARTTLS (port 587)
    pub fn new(
        host: &str,
        port: u16,
        username: &str,
        password: &str,
        secure: bool,
        accept_invalid_certs: bool,
        implicit_tls: bool,
    ) -> Result<Self, anyhow::Error> {
        let creds = Credentials::new(username.to_string(), password.to_string());
        let timeout = Duration::from_secs(30);

        let mailer = if secure {
            let tls_params = TlsParameters::builder(host.to_string())
                .dangerous_accept_invalid_certs(accept_invalid_certs)
                .build()?;

            if implicit_tls {
                // Implicit TLS (SMTPS) - TLS from the start, typically port 465
                // Use starttls_relay which wraps the connection in TLS immediately when using Tls::Wrapper
                log::info!("Using implicit TLS (SMTPS) mode for {}:{}", host, port);
                AsyncSmtpTransport::<Tokio1Executor>::relay(host)?
                    .port(port)
                    .credentials(creds)
                    .tls(Tls::Wrapper(tls_params))
                    .timeout(Some(timeout))
                    .build()
            } else {
                // STARTTLS - Start plain, upgrade to TLS, typically port 587
                log::info!("Using STARTTLS mode for {}:{}", host, port);
                AsyncSmtpTransport::<Tokio1Executor>::relay(host)?
                    .port(port)
                    .credentials(creds)
                    .tls(Tls::Required(tls_params))
                    .timeout(Some(timeout))
                    .build()
            }
        } else {
            // No TLS - dangerous, only for local testing
            log::warn!("Using insecure SMTP connection (no TLS) for {}:{}", host, port);
            AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(host)
                .port(port)
                .credentials(creds)
                .timeout(Some(timeout))
                .build()
        };

        Ok(Self {
            mailer,
            from_email: username.to_string(),
            from_name: "KillCode".to_string(),
        })
    }

    pub async fn send(&self, to: &str, subject: &str, html_body: &str) -> Result<(), anyhow::Error> {
        let from = format!("{} <{}>", self.from_name, self.from_email);
        
        log::debug!("Building email: from={}, to={}, subject={}", from, to, subject);
        
        let email = Message::builder()
            .from(from.parse()?)
            .to(to.parse()?)
            .subject(subject)
            .header(ContentType::TEXT_HTML)
            .body(html_body.to_string())?;

        log::debug!("Sending email via SMTP...");
        self.mailer.send(email).await?;
        log::debug!("Email sent successfully!");
        
        Ok(())
    }
}
