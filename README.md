# Killcode

**Binary Licensing & Protection Platform**

Protect your software with hardware-locked licenses, continuous verification, and self-destruct capabilities.

---

## What is Killcode?

Killcode is a comprehensive binary licensing and protection system that allows software vendors to distribute executables with built-in license enforcement. Upload your binary, create a license with custom policies, and deliver a protected version that automatically verifies authorization before and during execution. Revoke licenses at anytime. 🔒

### The Problem We Solve

**Traditional software licensing is broken:**
- License keys can be shared freely
- Cracked versions bypass payment entirely  
- No way to revoke access after distribution
- Hardware upgrades break legitimate licenses
- Offline usage can't be monitored or controlled

**Killcode provides:**
- **Hardware-locked licenses** - Binaries only run on authorized machines
- **Continuous verification** - Real-time license checking during execution
- **Remote revocation** - Instantly disable licenses for any reason
- **Grace periods** - Network tolerance for offline usage
- **Self-destruct** - Automatic binary deletion on unauthorized access
- **Analytics** - Track usage, executions, and violations

---

## Core Features

### 🔐 License Enforcement
- **Patchable licenses** - Update settings remotely (grace period, failure thresholds)
- **Read-only licenses** - Immutable, baked-in at creation
- **Sync mode** - Verify before execution (strict)
- **Async mode** - Verify during execution (user-friendly)
- **Expiration dates** - Time-limited access
- **Execution limits** - Max runs per license
- **Machine fingerprinting** - CPU, RAM, MAC address binding

### 🛡️ Protection Mechanisms
- **Embedded verification** - No external config files to tamper with
- **HMAC authentication** - Cryptographically signed API calls
- **Network failure tolerance** - Configurable grace periods
- **Kill methods** - Shred (secure delete) or simple deletion
- **Anti-tampering** - Detects binary modification attempts
- **Revocation** - Instant license disabling

### 📊 Monitoring & Analytics
- **Real-time telemetry** - Execution tracking per machine
- **Verification history** - Success/failure logs with timestamps
- **Geographic analytics** - See where your software runs (GeoIP)
- **Unique computers** - Track distinct hardware installations
- **Execution counts** - Monitor usage patterns
- **Dashboard** - Comprehensive analytics and insights

### 🌍 Multi-Platform Support
- **Linux**: x86_64, x86, ARM64, ARMv7
- **Windows**: x86_64, x86
- **Auto-detection** - Matches license enforcement to binary architecture

---

## How It Works

### 1. Upload Your Binary
Upload any Linux or Windows executable through the web UI or API.

### 2. Create a License
Configure license policies:
- **Type**: Patchable (editable) or Read-only (immutable)
- **Mode**: Sync (verify first) or Async (verify during)
- **Limits**: Expiration date, max executions
- **Tolerance**: Grace period, network failure threshold
- **Security**: Kill method on unauthorized access

### 3. Download Protected Binary
Receive a single merged executable with embedded license enforcement. No additional files needed.

### 4. Distribute to Customers
Your protected binary automatically:
- Verifies license on startup (sync) or during execution (async)
- Checks hardware fingerprint against license
- Respects grace periods for offline usage
- Reports telemetry back to your server
- Self-destructs if unauthorized or revoked

### 5. Monitor & Control
- View real-time analytics and usage patterns
- Revoke licenses instantly if needed
- Update patchable license settings remotely
- Track verification attempts and failures

---

## Use Cases

### 🎮 Software Vendors
Protect commercial applications from piracy while allowing legitimate offline usage with grace periods.

### 🏢 Enterprise Software
Deploy internal tools with hardware-locked licenses, automatic expiration, and centralized control.

### 🔬 Research & Academia
Distribute proprietary tools with execution limits, ensuring compliance with licensing agreements.

### 🛠️ SaaS On-Premise
Offer self-hosted versions of SaaS products with built-in subscription validation and remote kill switches.

### 🎓 Educational Software
Provide time-limited access to educational tools with automatic expiration for semester-based licensing.

---

## Key Concepts

### License Types

**Patchable License:**
- Update grace period, failure thresholds, and other dynamic settings after creation
- Useful for adjusting policies based on customer feedback
- Changes apply immediately to existing installations

**Read-Only License:**
- All settings permanently baked in at creation
- Cannot be modified once generated
- Maximum security - no chance of post-distribution tampering

### Verification Modes

**Sync Mode (Recommended for Critical Apps):**
```
1. Start protected binary
2. Verify license with server
3. If authorized → Execute your app
4. If unauthorized → Self-destruct
```

**Async Mode (Better User Experience):**
```
1. Start your app immediately
2. Verify license in background
3. If unauthorized → Kill app + self-destruct
```

### Grace Periods

**Network tolerance for offline usage:**
- Set grace period to 300 seconds (5 minutes)
- User can run app offline for up to 5 minutes
- After grace period expires → verification required
- If verification fails → binary self-destructs

**Network failure threshold:**
- Allow N consecutive network failures before killing
- Example: 5 failures = ~25 minutes offline (5 sec checks)
- Prevents legitimate users from being locked out due to poor connectivity

### Self-Destruct

**Secure deletion on unauthorized access:**
- **Shred method**: Overwrite binary with random data before deletion (secure)
- **Simple method**: Standard file deletion (fast)
- Triggered on: License revoked, expired, tampered, or max failures exceeded

---

## Architecture

Killcode consists of four main components:

### Server
Central API for license management, binary uploads, and verification requests.  
*See [server/README.md](server/README.md) for details.*

### Weaver
Binary merging microservice that combines your executable with license enforcement code.  
*See [weaver/README.md](weaver/README.md) for details.*

### killer
Cross-platform license verification binary built for 6 architectures.  
*See [killer/README.md](killer/README.md) for details.*

### UI
Web interface for managing binaries, licenses, and analytics.  
*See [ui/README.md](ui/README.md) for details.*

---

## Security Considerations

### What Killcode Protects
✅ License validation and enforcement  
✅ Hardware fingerprinting  
✅ Remote revocation  
✅ Execution monitoring  
✅ Time-based expiration  
✅ Offline usage control  

### What Killcode Doesn't Protect
❌ Runtime binary modification (use additional obfuscation)  
❌ Memory dumping (use anti-debug features)  
❌ Reverse engineering (combine with code obfuscation)  
❌ Determined attackers with unlimited time  

### Best Practices
- Use **sync mode** for critical applications
- Enable **self-destruct** in production
- Set reasonable **grace periods** (5-15 minutes)
- Monitor **verification failures** for abuse patterns
- Rotate **shared secrets** periodically
- Combine with **code obfuscation** for maximum protection

---

## Quick Start

### Prerequisites
- Docker & Docker Compose
- 4GB+ RAM
- 10GB+ disk space
- Git (for submodule support)

### Run the Platform

```bash
# Clone repository with submodules
git clone --recurse-submodules https://github.com/yourusername/killcode.git
cd killcode

# Or if already cloned, initialize submodules
git submodule update --init --recursive

# Start all services
docker compose up -d

# Access web UI
open http://localhost:5173
```

**Note:** This project uses Git submodules for `server`, `weaver`, `killer`, and `ui` components. Make sure to clone with `--recurse-submodules` or run `git submodule update --init --recursive` after cloning.

### Your First Protected Binary

1. **Login** - Create account at `http://localhost:5173`
2. **Upload** - Upload your binary (Linux/Windows executable)
3. **Create License** - Configure policies (sync mode, 300s grace period)
4. **Download** - Get protected binary
5. **Test** - Run protected binary (will verify with your local server)
6. **Monitor** - View analytics and telemetry in dashboard

---

## Project Structure

```
killcode/
├── server/          # License management API (Rust) [submodule]
├── weaver/          # Binary merging service (Rust) [submodule]
├── killer/          # License verification binary (Rust) [submodule]
├── ui/              # Web interface (Next.js) [submodule]
├── scripts/         # Deployment & testing scripts
├── docker-compose.yml
└── .gitmodules      # Submodule configuration
```

**Submodules:**
Each core component is maintained as a separate Git submodule for independent versioning and development.

---

## Technology Stack

- **Backend**: Rust (Actix-Web, Tokio)
- **Database**: MongoDB
- **Cache/Queue**: Redis
- **Frontend**: Next.js 16, React 19, Tailwind CSS
- **Binary Analysis**: Goblin, objcopy
- **Cross-compilation**: GCC toolchains (x86, ARM, MinGW)
- **GeoIP**: MaxMind GeoLite2

---

## Status

**Beta** - Production-ready core features with ongoing development for advanced weaving capabilities.

---

## License

Proprietary - Part of the Killcode binary protection system.

**No Commercial Use Allowed** - This software is provided for personal, educational, and evaluation purposes only. Commercial use, redistribution, or resale is strictly prohibited without explicit written permission from the copyright holder.

See [LICENSE](LICENSE) for full terms.

---

## Support

For technical documentation, see individual component READMEs:
- [Server](server/README.md) - API, storage, architecture
- [Weaver](weaver/README.md) - Binary merging internals
- [Killer](killer/README.md) - License enforcement code
- [UI](ui/README.md) - Web interface tech stack
