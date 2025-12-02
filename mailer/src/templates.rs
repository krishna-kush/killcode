use handlebars::Handlebars;
use serde_json::json;

use crate::models::EmailTemplate;

pub struct TemplateEngine {
    hbs: Handlebars<'static>,
}

impl TemplateEngine {
    pub fn new() -> Self {
        let mut hbs = Handlebars::new();
        
        // Register OTP template (signup)
        hbs.register_template_string("otp", include_str!("../templates/otp.html"))
            .expect("Failed to register OTP template");
        
        // Register 2FA OTP template
        hbs.register_template_string("otp_2fa", include_str!("../templates/otp_2fa.html"))
            .expect("Failed to register 2FA OTP template");
        
        // Register Welcome template
        hbs.register_template_string("welcome", include_str!("../templates/welcome.html"))
            .expect("Failed to register Welcome template");
        
        // Register Password Reset template
        hbs.register_template_string("password_reset", include_str!("../templates/password_reset.html"))
            .expect("Failed to register Password Reset template");
        
        // Register License Created template
        hbs.register_template_string("license_created", include_str!("../templates/license_created.html"))
            .expect("Failed to register License Created template");
        
        Self { hbs }
    }

    pub fn render(&self, template: &EmailTemplate, data: &serde_json::Value) -> Result<String, anyhow::Error> {
        let template_name = match template {
            EmailTemplate::Otp => "otp",
            EmailTemplate::Otp2FA => "otp_2fa",
            EmailTemplate::Welcome => "welcome",
            EmailTemplate::PasswordReset => "password_reset",
            EmailTemplate::LicenseCreated => "license_created",
            EmailTemplate::Custom => {
                // For custom, the data should contain an "html" field
                if let Some(html) = data.get("html").and_then(|v| v.as_str()) {
                    return Ok(html.to_string());
                }
                return Err(anyhow::anyhow!("Custom template requires 'html' field in data"));
            }
        };

        // Merge year into the data object
        let mut render_data = data.clone();
        if let Some(obj) = render_data.as_object_mut() {
            obj.insert("year".to_string(), json!(chrono::Utc::now().format("%Y").to_string()));
        }

        let html = self.hbs.render(template_name, &render_data)?;
        
        Ok(html)
    }
}

impl Default for TemplateEngine {
    fn default() -> Self {
        Self::new()
    }
}
