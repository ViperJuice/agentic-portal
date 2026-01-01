# Agentic Portal - Technical Research Specification

## Overview

**Goal**: Build a mobile app (iOS + Android) that provides a chat interface for coding agents, starting with Claude Code and extensible to Gemini CLI, OpenAI Codex, Aider, and others.

**Key Insight**: No mobile SDK exists for Claude Code or similar agents. They are all CLI/TUI tools designed for desktop. This app would be the first mobile interface for coding agents.

---

## 1. Cross-Platform Framework Decision

### Recommendation: Flutter

| Factor | Flutter | React Native |
|--------|---------|--------------|
| Code Sharing | 94% | ~70% |
| Code Syntax Highlighting | Excellent (`flutter_code_view`, 200+ langs) | Good but less mature |
| LLM Streaming | Flutter AI Toolkit (purpose-built) | Requires custom integration |
| Performance | Native ARM compilation | New Architecture approach is comparable |
| Learning Curve | Medium (Dart) | Low (JavaScript) |
| Hiring | Harder | Easier |

**Why Flutter wins for this use case**:
1. Superior code display ecosystem (critical for coding agent output)
2. Flutter AI Toolkit has built-in streaming chat widgets
3. Single codebase, consistent behavior across platforms
4. Compiles to native ARM for smooth streaming performance

---

## 2. Architecture: Hybrid Agent Runtime

```
┌─────────────────────────────────────────────────────────────┐
│                      MOBILE APP (Flutter)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Chat UI     │  │ Agent       │  │ Code Renderer       │  │
│  │ (Streaming) │  │ Switcher    │  │ (Syntax Highlight)  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                           │                                  │
│                    WebSocket/REST                            │
└─────────────────────────────────────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
┌───────────────────────┐       ┌───────────────────────┐
│   LOCAL RUNTIME       │       │   CLOUD RUNTIME       │
│   (User's Machine)    │       │   (Your Servers)      │
│                       │       │                       │
│  ┌─────────────────┐  │       │  ┌─────────────────┐  │
│  │   AgentAPI      │  │       │  │   AgentAPI      │  │
│  │   HTTP Server   │  │       │  │   HTTP Server   │  │
│  └────────┬────────┘  │       │  └────────┬────────┘  │
│           │           │       │           │           │
│  ┌────────▼────────┐  │       │  ┌────────▼────────┐  │
│  │  Claude Code    │  │       │  │  Claude Code    │  │
│  │  Gemini CLI     │  │       │  │  (Sandboxed)    │  │
│  │  Codex CLI      │  │       │  │                 │  │
│  │  Aider          │  │       │  │  Limited tools  │  │
│  └─────────────────┘  │       │  └─────────────────┘  │
│                       │       │                       │
│  Full filesystem      │       │  Workspace-based      │
│  access to projects   │       │  (git clone, sandbox) │
└───────────────────────┘       └───────────────────────┘
```

### Local Runtime (Power Users)
- User runs AgentAPI on their machine (background daemon)
- Full access to local filesystem, git repos, dev environment
- Mobile app connects via local network or tunneling (ngrok, Tailscale)
- All Claude Code capabilities preserved

### Cloud Runtime (Convenience)
- Hosted AgentAPI instances on your infrastructure
- User connects git repos (GitHub, GitLab integration)
- Sandboxed execution environment per user
- Subset of capabilities (no arbitrary bash on user's machine)

---

## 3. AgentAPI - The Backend Abstraction (Deep Dive)

[AgentAPI](https://github.com/coder/agentapi) provides a unified HTTP interface for multiple CLI agents.

### Installation
```bash
# One-liner install
OS=$(uname -s | tr "[:upper:]" "[:lower:]")
ARCH=$(uname -m | sed "s/x86_64/amd64/;s/aarch64/arm64/")
curl -fsSL "https://github.com/coder/agentapi/releases/latest/download/agentapi-${OS}-${ARCH}" -o agentapi && chmod +x agentapi

# Start with Claude Code
agentapi server -- claude
```

### Supported Agents
- Claude Code, Gemini CLI, OpenAI Codex, Aider, Goose, Sourcegraph Amp, GitHub Copilot, OpenCode, Cursor CLI

### Actual API Endpoints (Port 3284)
```
GET  /messages    # Complete conversation history
POST /message     # Send message {"content": "...", "type": "user|raw"}
GET  /status      # Agent state: "stable" or "running"
GET  /events      # SSE stream for real-time updates
POST /upload      # File upload (multipart form)
GET  /docs        # Interactive OpenAPI docs
```

### SSE Streaming Format
- Standard SSE with `data:` prefixed JSON lines
- On connect: Sends all existing messages to reconstruct state
- Then streams only new events as they occur
- Messages include: `id`, `timestamp`, `role` (user/agent), `content`

### Multi-Agent (Separate Ports)
```bash
agentapi server -- claude                    # Port 3284
agentapi server --port 3285 -- aider         # Port 3285
agentapi server --port 3286 --type=gemini -- gemini-cli
```

### Security Configuration
- **Host validation**: Default localhost only. Use `--allowed-hosts` for others
- **CORS**: Default allows localhost:3284, 3000, 3001. Use `--allowed-origins`
- **No built-in auth**: Designed for local/trusted networks

### Key Limitations
- **No session persistence**: Conversations lost on restart (in-memory only)
- **No dynamic agent switching**: Each agent needs separate instance
- **Terminal-coupled**: Parsing depends on agent output format
- **No MCP/A2A yet**: Open issues for protocol support

### Why AgentAPI
1. **Already built** - No custom wrappers needed
2. **SSE streaming** - Works well with mobile
3. **Active development** - v0.11.2, maintained by Coder

---

## 4. Claude Code Integration Strategy (MVP)

### Phase 1: AgentAPI + Claude Code
1. Package AgentAPI for easy local installation (homebrew, npm, etc.)
2. Mobile app connects to AgentAPI endpoint
3. Stream Claude Code responses to Flutter chat UI
4. Render tool outputs (file diffs, command results, code blocks)

### Phase 2: Cloud Option
1. Deploy AgentAPI on cloud infrastructure (AWS/GCP)
2. User authentication and workspace isolation
3. Git integration (clone repos into sandboxed environments)
4. Session persistence across app restarts

### Phase 3: Multi-Agent
1. Agent selector in mobile UI
2. Per-conversation agent configuration
3. Unified message format across agents

---

## 5. Mobile App Architecture (Flutter) - Deep Dive

### Core Packages
```yaml
dependencies:
  # State Management (Riverpod best for streaming)
  flutter_riverpod: ^2.x
  riverpod_annotation: ^2.x

  # SSE Streaming
  eventflux: ^x.x           # SSE with auto-reconnect, parallel connections
  # OR flutter_http_sse     # Exponential backoff reconnection

  # Markdown with Streaming Support
  flutter_smooth_markdown: ^x.x   # AST-based, StreamMarkdown widget, AI plugins
  # OR flutter_streaming_text_markdown  # Direct Stream<String> for LLM

  # Code Display
  flutter_code_view: ^x.x   # 200+ languages, 90+ themes, line numbers

  # Networking
  dio: ^x.x                 # HTTP client

  # Local Discovery
  bonsoir: ^x.x             # mDNS discovery (iOS, Android, desktop)
  mobile_scanner: ^x.x      # QR code scanning
```

### State Management: Riverpod for Streaming
```dart
// StreamNotifier pattern for SSE
@riverpod
class ChatMessages extends _$ChatMessages {
  @override
  Stream<List<Message>> build() async* {
    final eventSource = EventFlux.instance.connect(
      'http://localhost:3284/events',
      onMessage: (event) => /* parse SSE data */,
    );
    ref.onDispose(() => eventSource.disconnect());
    // yield messages as they arrive
  }
}
```

### Performance Optimization
- **ListView.builder** - Only renders visible messages (critical for long chats)
- **const constructors** - Prevent unnecessary rebuilds
- **RepaintBoundary** - Isolate frequently-updating widgets
- **Riverpod selectors** - Only rebuild what changed

### Key Screens
1. **Connection Setup** - QR scan, mDNS discovery, or manual IP entry
2. **Conversation List** - Active sessions (note: in-memory until AgentAPI adds persistence)
3. **Chat View** - Streaming messages with markdown/code rendering
4. **Settings** - API keys (stored in Keychain/Keystore), connection config

### Reference Implementation
- **Kelivo** ([github.com/Chevey339/kelivo](https://github.com/Chevey339/kelivo)) - Production Flutter LLM chat with multi-provider, streaming, markdown, voice

---

## 6. Key Technical Challenges

### Challenge 1: Local Network Discovery (Deep Dive)
**Problem**: How does mobile app find AgentAPI on local network?

**Primary: mDNS/Bonjour** (same WiFi)
- Package: `bonsoir` (best cross-platform support)
- iOS: Requires `NSBonjourServices` + `NSLocalNetworkUsageDescription` in Info.plist
- Android: Works out of the box (NSD API since 4.1)
- Limitation: iOS permission denial is silent (no way to detect)

**Secondary: QR Code**
- Desktop generates QR with `http://192.168.x.x:3284?token=abc`
- Mobile scans with `mobile_scanner` package
- Use short-lived, single-use tokens for security

**Tertiary: Manual Entry**
- Fallback for when discovery fails
- Store recent connections for quick reconnect

**Remote Access (not same network)**
- **Tailscale**: Best option, but no Flutter package (requires native integration)
- **ngrok/cloudflared**: Temporary tunnels for development
- Both require user to set up on desktop side

### Challenge 2: File Operations
**Decision**: Pure chat interface - no file editing in app

**Approach**:
- Display file paths mentioned by agent as tappable links
- Link to GitHub web interface for viewing/editing
- All file operations happen on backend via AgentAPI
- User reviews results in chat, not in a file editor

### Challenge 3: Long-Running Operations
**Problem**: Agent tasks can take minutes (large refactors, builds)
**Solutions**:
- Background execution with push notifications
- Session persistence across app backgrounding
- Progress indicators for tool execution

### Challenge 4: Authentication for Cloud Runtime
**Problem**: Securely connecting to hosted AgentAPI
**Solutions**:
- OAuth with GitHub/Google
- API key per user
- JWT tokens with refresh

---

## 7. Security Considerations

### Local Runtime
- AgentAPI should only listen on localhost by default
- Require explicit user action to expose to network
- Consider mTLS for non-local connections

### Cloud Runtime
- User workspace isolation (containerized)
- Rate limiting on agent calls (API cost control)
- Audit logging for all agent actions
- No persistent storage of API keys (bring your own)

### Mobile App
- Secure storage for connection credentials (Keychain/Keystore)
- Certificate pinning for cloud connections
- No API keys stored in app (passthrough only)

---

## 8. MVP Feature Set

### Must Have
- [ ] Connect to local AgentAPI (mDNS discovery + QR code + manual IP)
- [ ] Chat interface with SSE streaming
- [ ] Markdown rendering with code syntax highlighting
- [ ] Tappable file paths → open in GitHub/external browser
- [ ] Claude Code support (first agent)
- [ ] BYOK: Secure storage for user's API keys (Keychain/Keystore)

### Should Have
- [ ] Cloud runtime option (Phase 2)
- [ ] Multiple agent support (Gemini, Codex, Aider)
- [ ] Dark/light theme
- [ ] Connection reconnection with exponential backoff

### Nice to Have
- [ ] Simple terminal view (if implementation is trivial)
- [ ] Voice input for messages
- [ ] iPad/tablet optimized layout
- [ ] Push notifications for long-running tasks

---

## 9. Decisions Made

| Question | Decision |
|----------|----------|
| API Keys | **BYOK** - Users bring their own keys |
| File Editing | **None** - Chat only, link to GitHub for file ops |
| Agent Runtime | **Hybrid** - Local (power users) + Cloud (convenience) |
| First Agent | **Claude Code** - Design for extensibility |
| Framework | **Flutter** - Best for streaming + code display |

---

## 10. Next Steps

1. **Validate AgentAPI** - Install locally, test with Claude Code, verify SSE streaming
2. **Flutter Scaffold** - Create project with Riverpod, test SSE with EventFlux
3. **Connection Flow** - Implement mDNS + QR + manual entry
4. **Chat UI** - Streaming markdown with `flutter_smooth_markdown`
5. **Claude Code MVP** - End-to-end local connection working
6. **Cloud Architecture** - Design for Phase 2

---

## 11. Cloud Architecture (Deep Dive)

### Recommended Architecture by Phase

**Phase 1: Prototype**
```
Mobile App → Hetzner CX23 (€3.49/mo)
              └─ Docker Compose
                 ├─ AgentAPI container
                 └─ Per-user workspace volumes
```

**Phase 2: Scaling**
```
Mobile App → Load Balancer
              └─ Kubernetes (3 nodes, €30-50/mo)
                 ├─ AgentAPI pods (auto-scale)
                 ├─ gVisor sandboxing
                 └─ PostgreSQL for state
```

**Phase 3: Production**
```
Mobile App → API Gateway
              └─ Firecracker microVMs (E2B or self-hosted)
                 ├─ Hardware-level isolation
                 ├─ Per-user sandboxed environments
                 └─ <125ms startup time
```

### Container Isolation Options

| Option | Startup | Security | Complexity | Best For |
|--------|---------|----------|------------|----------|
| Docker + gVisor | 5s | Good | Low | Prototype |
| Kubernetes + gVisor | 1-5s | Good | Medium | Scale |
| Firecracker microVMs | 125ms | Best | High | Production |

### Session Persistence
- AgentAPI is **in-memory only** - need external state storage
- Pattern: Save state to PostgreSQL before container shutdown
- Per-user database schema partitioning for isolation

---

## 12. Desktop Companion App

### Recommended: Tauri

**Why Tauri over Electron:**
- 10-50MB app size (vs Electron's 150-400MB)
- 30-40MB RAM (vs Electron's 400-500MB)
- Built-in system tray support
- <0.5s startup time

**Features for MVP:**
- Start/stop AgentAPI server
- Generate QR code for mobile connection
- Show connection status in menu bar
- Notification when mobile connects

**Alternative (Lighter):** Go systray + embedded web UI
- Single tiny binary
- `agentapi --gui` opens localhost web interface
- Uses fyne-io/systray for menu bar

**Simplest Path (macOS only):**
- launchd plist for auto-start
- SwiftBar/BitBar script for status

---

## 13. Cloud Provider Pricing

### Prototype Comparison (2 vCPU, 4GB RAM)

| Provider | Monthly | Notes |
|----------|---------|-------|
| **Hetzner CX23** | **€3.49** | Best value, EU focus |
| Fly.io | $5.70 | Fastest startup (125ms) |
| Linode | $5 | Simple, US-friendly |
| DigitalOcean | $24 | More expensive but familiar |
| AWS Fargate | $30-40 | Avoid - 15-30% premium |

### Scaling Comparison (12 vCPU, 24GB total)

| Provider | Monthly | Notes |
|----------|---------|-------|
| **Hetzner 3x CX23** | **€10.47** | Unbeatable |
| Linode 3x 1GB | $15 | Budget option |
| AWS ECS on EC2 | $75-100 | With Reserved Instances |
| DO Kubernetes | $189+ | Simpler but pricier |

### Recommendation
1. **Start**: Hetzner CX23 (€3.49/mo) - Docker Compose
2. **Grow**: Hetzner 3x CX23 (€10/mo) - K3s lightweight K8s
3. **Scale**: Hetzner/DO Kubernetes (€30-50/mo)
4. **Production**: Multi-cloud K8s or Firecracker

### Portability
- Use standard Docker + Kubernetes throughout
- Avoid AWS-specific services (ECS, Fargate lock-in)
- Hetzner → DO → AWS migration is straightforward with K8s

---

## 14. Authentication & Identity

### MVP: Supabase Auth
- GitHub OAuth (developer-focused), Google, Apple (required for iOS)
- `flutter_secure_storage` for JWT/token storage (Keychain/Keystore)
- ~$0-25/month, setup in 1-2 days

### Production: Firebase Auth + Vault
- Firebase with custom claims for agent permissions
- HashiCorp Vault or AWS Secrets Manager for API key storage
- HIPAA/PCI/GDPR ready

### BYOK (Bring Your Own Key) Pattern
- Store user API keys in `flutter_secure_storage` on device
- Server never persistently stores keys
- Per-session encrypted token exchange

---

## 15. Git Integration

### MVP: Fine-Grained GitHub PATs
- User generates token with `Repository contents: Read-only`
- Store in Kubernetes Secret per user
- Clone via `https://token@github.com/owner/repo.git`

### Production: OAuth + Credential Manager
```
User → OAuth consent → Credential Manager (stores refresh token)
                            ↓
Agent Pod → Socket request → Short-lived token (1-8hr) → Clone repo
```
- GitHub Apps for higher rate limits
- GitLab Project Access Tokens
- Bitbucket API Tokens (app passwords deprecated June 2026)

### Container Security
- Docker BuildKit secrets (never in image layers)
- Kubernetes: Mount as file via tmpfs, not env var
- Token per pod, auto-revoke on termination

---

## 16. Push Notifications

### Recommended: Firebase Cloud Messaging (FCM)
- Free, covers both iOS and Android
- Essential packages: `firebase_messaging` + `flutter_local_notifications`

### Backend Flow
1. User starts task → store `{taskId, fcmToken}`
2. Agent completes → Cloud Function triggers FCM
3. Mobile receives notification (foreground/background/terminated)

### iOS Requirements
- APNs certificate (requires Apple dev account $99/yr)
- Xcode: Enable Push Notifications capability
- Test on physical device (simulator won't work)

### Android Requirements
- Notification channels (required Android 8+)
- Android 13+: Runtime permission required
- `onMessageReceived` has 10s limit → use WorkManager for heavy tasks

### Timeline
- MVP: 1-2 days (Firebase console test)
- Production: 1 week (both platforms, backend integration)

---

## 17. Competitive Landscape

### Existing Apps
| App | Code Features | File Editing | Agent Focus |
|-----|---------------|--------------|-------------|
| Claude iOS | Yes, Claude Code native | No | Chat-first |
| ChatGPT | Codex integration (paid) | No | Chat-first |
| GitHub Mobile | Copilot review/assign | No | PR/Issues |
| Gemini | 1M context, Canvas | No | Chat-first |
| Replit Mobile | Full IDE | Yes | Editor-first |
| CodeSandbox iOS | Full IDE | Yes | Editor-first |

### Market Gaps (Our Opportunity)
1. **No agent-first mobile UX** - all are chat-first or editor-first
2. **No local agent connection** - all cloud-only
3. **No multi-agent support** - each app is single-vendor
4. **Poor long output handling** - not designed for streaming agent output
5. **No file awareness without editing** - either full IDE or no files

### Our Advantages
- Agent-first design (not chat-first)
- Local + Cloud runtime support
- Multi-agent (Claude, Gemini, Codex, Aider)
- Pure chat with file awareness (no editing)
- Designed for streaming/long outputs

---

## 18. TUI Fidelity & Session Management

### Core Requirement
Mobile chat must provide **at least as much fidelity** as the terminal TUI, not a dumbed-down experience.

### Verbosity & Display Options
- **Verbosity toggle**: Match agent framework verbosity levels (quiet/normal/verbose/debug)
- **Tool call visibility**: Show/hide tool calls (file reads, bash commands, etc.)
- **Thinking display**: Option to show agent's reasoning/thinking process
- **Streaming control**: Pause/resume streaming, stop generation
- **Output filtering**: Filter by message type (user, agent, tool output, errors)

### Session Persistence (Critical)
**Disconnect ≠ Kill Session**
- User can close app / lose connection without stopping agent
- Agent continues running on backend
- Reconnect and resume from where you left off

**Implementation Pattern**:
```
Mobile App → AgentAPI session with persistent ID
    ↓
Disconnect (app close, network loss)
    ↓
AgentAPI continues running (session stays alive)
    ↓
Reconnect → GET /events sends full history + resumes stream
```

**Technical Requirements**:
- Session IDs persist across connections
- Backend maintains conversation state (note: AgentAPI is in-memory, need external persistence)
- SSE `/events` endpoint already replays history on connect
- Add session timeout (e.g., 8 hours) for cleanup
- Show "Session still running" indicator on reconnect

### Additional TUI Features to Support
- **Agent selection**: Switch between Claude Code, Gemini, Codex, etc.
- **Model selection**: If agent supports multiple models (e.g., Sonnet vs Opus)
- **Temperature/parameters**: Expose tunable settings
- **Context info**: Token usage, context window remaining
- **Interrupt**: Stop agent mid-operation gracefully
- **Retry**: Re-run last request if failed
- **Clear context**: Reset conversation without killing session

### AgentAPI Limitation Note
AgentAPI is currently in-memory only. For true session persistence, we need:
1. External state storage (PostgreSQL, Redis)
2. Save session state on each message
3. Hydrate session on reconnect
4. Or contribute session persistence to AgentAPI upstream

---

## 19. OAuth & Subscription Integration for AI Frameworks

### Overview

To avoid subscribed users paying normal API prices, the portal needs OAuth integration to authenticate users with their existing framework subscriptions. This section details each framework's subscription offerings and OAuth capabilities.

### Framework Comparison Matrix

| Framework | Has Subscription? | Subscription Price | API Separate? | OAuth Support | Integration Strategy |
|-----------|-------------------|-------------------|---------------|---------------|---------------------|
| **Claude Code** | Yes (Pro/Max) | $20/$100/mo | Yes | Third-party only | Unofficial OAuth plugins |
| **Gemini CLI** | Yes (Advanced) | $19.99/mo | Yes | Official OAuth | Native OAuth for API |
| **OpenAI Codex** | Yes (Plus/Pro) | $20/$200/mo | Yes | MCP only | Third-party plugins |
| **GitHub Copilot** | Yes (5 tiers) | $0-$39/mo | No (integrated) | Native OAuth | REST API + Device Flow |
| **Cursor** | Yes (4 tiers) | $20-$200/mo | No (integrated) | MCP OAuth | Native MCP support |
| **Aider** | No | Free (OSS) | N/A | API keys only | No subscription |
| **Goose** | No | Free (OSS) | N/A | Integrates others | No subscription |
| **Sourcegraph Amp** | Yes (Free/Paid) | $0+/mo | No (integrated) | OAuth + SSO | MCP OAuth support |
| **OpenCode** | Optional (Zen) | Pay-as-you-go | Optional | Claude OAuth | Supports subscription OAuth |

---

### 1. Claude Code (Anthropic)

**Subscription Plans:**
- **Pro**: $20/month (or $17/month annual)
- **Max**: $100/month
- **Team**: Custom pricing
- **Enterprise**: Custom pricing

**Key Findings:**
- API pricing is **completely separate** from subscriptions
- Even with Pro/Max, using `ANTHROPIC_API_KEY` triggers API charges
- Pro/Max plans share usage limits between Claude web and Claude Code
- API offers larger context (1M tokens vs 200K for subscriptions)

**OAuth Status:**
- ❌ **No official OAuth** for using subscription credits via API
- ✅ **Third-party implementations** exist (e.g., Roo-Code Issue #4799)
- Some coding tools are implementing OAuth 2.0 to bridge subscriptions to API access

**Implementation Strategy:**
```
Option 1: API Key (Current)
- User provides Anthropic API key
- Pay per token (separate from subscription)

Option 2: OAuth (Future - if Anthropic adds support)
- User authenticates with Claude Pro/Max account
- Portal uses subscription credits instead of API charges
- Requires Anthropic to expose subscription-based API access
```

**Recommendation:**
- **Phase 1**: API key only (current official method)
- **Phase 2**: Monitor for official OAuth support
- **Phase 3**: Consider third-party OAuth plugins (with user consent)

---

### 2. Gemini CLI (Google)

**Subscription Plans:**
- **Free**: $0 (limited usage)
- **Gemini Advanced**: $19.99/month (part of Google One AI Premium)
- **Code Assist (Individual)**: Included in Google AI Pro/Ultra
- **Code Assist (Organization)**: Enterprise licensing

**Key Findings:**
- API pricing is **separate** from Gemini Advanced subscription
- Free tier available with rate limits
- Pay-as-you-go: $0.02-$5.00 per million tokens depending on model
- OAuth designed for model tuning and semantic retrieval features

**OAuth Status:**
- ✅ **Official OAuth support** via Google Cloud
- OAuth scope: `https://www.googleapis.com/auth/generative-language.retriever`
- Recommended to start with API keys, use OAuth for advanced features
- Full documentation at [ai.google.dev/gemini-api/docs/oauth](https://ai.google.dev/gemini-api/docs/oauth)

**Implementation Strategy:**
```
Option 1: API Key (Recommended for MVP)
- Simple setup via Google AI Studio
- Free tier: 15 requests/minute
- Paid tier: Pay-as-you-go billing

Option 2: OAuth (Advanced Features)
- Create OAuth 2.0 Client ID in Google Cloud Console
- Select "Desktop app" application type
- Required for model tuning, semantic retrieval
- May enable subscription-based access in future
```

**Recommendation:**
- **Phase 1**: API key with free tier
- **Phase 2**: OAuth for users with Gemini Advanced subscriptions
- **Phase 3**: Check if Google enables subscription credit passthrough

---

### 3. OpenAI Codex

**Subscription Plans:**
- **ChatGPT Plus**: $20/month (30-150 messages/5hrs)
- **ChatGPT Pro**: $200/month (300-1,500 messages/5hrs)
- **ChatGPT Business**: Custom pricing
- **ChatGPT Enterprise**: Custom pricing

**Key Findings:**
- ChatGPT subscriptions are **completely separate** from OpenAI Platform API
- Two billing systems: chatgpt.com vs platform.openai.com
- Old Codex API deprecated (March 2023), rebuilt into ChatGPT
- New `codex-mini-latest`: $1.50/1M input, $6/1M output tokens
- ChatGPT Plus includes Codex Web and Codex CLI

**OAuth Status:**
- ✅ **Official OAuth** for MCP servers only
- ❌ **No official OAuth** for using ChatGPT Plus credits via API
- ✅ **Third-party plugins** exist (e.g., `opencode-openai-codex-auth`, `ai-sdk-provider-chatgpt-oauth`)
- Community tools enable ChatGPT subscription → API bridge (personal use only)

**Implementation Strategy:**
```
Option 1: OpenAI Platform API Key
- User creates API key at platform.openai.com
- Pay per token (separate from ChatGPT Plus)
- $5 free credits for new accounts

Option 2: Third-Party OAuth (Unofficial)
- Use community plugins (e.g., opencode-openai-codex-auth)
- Authenticate with ChatGPT Plus/Pro account
- Uses OpenAI's OAuth flow (same as official Codex CLI)
- **Risk**: Unofficial, may violate ToS

Option 3: MCP OAuth (Official but limited)
- For MCP server integrations only
- Uses OAuth 2.0 with PKCE
- Doesn't provide API access to Codex
```

**Recommendation:**
- **Phase 1**: OpenAI Platform API key only (official method)
- **Phase 2**: Clearly document that ChatGPT Plus ≠ API access
- **Phase 3**: If third-party OAuth, add disclaimer about unofficial status

---

### 4. GitHub Copilot

**Subscription Plans:**
- **Free**: $0 (limited usage)
- **Pro**: $10/month
- **Pro+**: $39/month
- **Business**: $19/user/month
- **Enterprise**: $39/user/month

**Key Findings:**
- Subscription **includes** API access (not separate billing)
- REST API available for programmatic management
- OAuth device flow for authentication
- Third-party tools can access via `api.githubcopilot.com` (OpenAI-compatible)
- Enhanced MCP OAuth support (Nov 2025) for JetBrains, Eclipse, Xcode

**OAuth Status:**
- ✅ **Full native OAuth support**
- OAuth device flow for CLI tools
- REST API with OAuth app tokens or PATs
- Scopes: `manage_billing:copilot`, `read:org`
- Dynamic Client Registration (DCR) for MCP servers
- Fallback to client-credentials workflow

**Implementation Strategy:**
```
Recommended: OAuth Device Flow
1. User initiates connection in mobile app
2. Portal starts OAuth device flow
3. User authorizes at GitHub
4. Portal receives access token
5. Use token with api.githubcopilot.com

API Access:
- Endpoint: https://api.githubcopilot.com
- OpenAI-compatible format
- Uses GitHub subscription credits
- REST API for seat management
```

**Recommendation:**
- ✅ **Highest priority for OAuth implementation**
- Native support, well-documented, subscription-inclusive
- Use GitHub's official OAuth device flow
- **Best user experience** - one subscription, full access

---

### 5. Cursor

**Subscription Plans:**
- **Hobby**: Free (limited)
- **Pro**: $20/month (500 fast requests)
- **Pro Plus**: $60/month (1,500 fast requests)
- **Ultra**: $200/month (20× Pro usage)
- **Business/Enterprise**: Custom (SAML/SSO)

**Key Findings:**
- Subscription **includes** API access (integrated billing)
- June 2025: Moved from request-based to usage-based pricing
- Native OAuth for MCP server integrations
- No separate API - Cursor is the client

**OAuth Status:**
- ✅ **OAuth for MCP integrations**
- Automatic OAuth handling for MCP servers
- SAML/SSO for Enterprise
- No public API for third-party clients

**Implementation Strategy:**
```
Challenge: Cursor is a client, not an API provider

Option 1: Not Applicable
- Cursor is an IDE, not an agent we can integrate
- Users would use Cursor directly, not through our portal

Option 2: MCP Bridge (Theoretical)
- If Cursor exposes MCP server capabilities
- Portal could connect as MCP client
- Currently not documented
```

**Recommendation:**
- ⚠️ **May not be suitable for portal integration**
- Cursor is an IDE client, not an agent API
- Consider removing from supported agents list
- Keep for reference but focus on API-accessible agents

---

### 6. Aider

**Subscription Plans:**
- **None** - Completely free and open-source

**Key Findings:**
- No subscriptions or licensing fees
- Users pay only for underlying LLM API (OpenAI, Anthropic, DeepSeek, etc.)
- Typical cost: $0.01-$0.10 per feature with GPT-4o
- Supports local models via Ollama (completely free)
- Supports 75+ LLM providers

**OAuth Status:**
- ❌ **No OAuth** (no subscription to authenticate)
- API key configuration for chosen LLM provider
- Supports BYOK (Bring Your Own Key)

**Implementation Strategy:**
```
BYOK Model:
- User provides API key for their chosen LLM
- Options: OpenAI, Anthropic, DeepSeek, local models
- Aider CLI uses the key directly
- No intermediary billing

Portal Integration:
1. User selects Aider agent
2. User chooses LLM provider (Claude, GPT, DeepSeek, etc.)
3. User provides API key for that provider
4. Portal passes key to Aider via environment variable
```

**Recommendation:**
- ✅ **Simple BYOK implementation**
- No OAuth needed - standard API key flow
- Focus on secure storage of user-provided keys
- Use `flutter_secure_storage` for Keychain/Keystore

---

### 7. Goose

**Subscription Plans:**
- **None** - Free and open-source (by Block/Jack Dorsey)

**Key Findings:**
- No native subscription model
- Integrates with existing subscriptions: GitHub Copilot, Cursor, OpenAI, Anthropic
- Can use local models (Ollama, Docker Model Runner) - completely free
- $10 free credits via Tetrate authentication
- Saves developers ~20% of time

**OAuth Status:**
- ⚠️ **Hybrid** - No native OAuth, but supports others' OAuth
- Tetrate auto-authentication
- Can use GitHub Copilot subscription (via GitHub OAuth)
- Can use OpenAI/Anthropic (via API keys)

**Implementation Strategy:**
```
Bring Your Own Subscription:
1. User selects Goose agent
2. User connects existing subscription:
   - GitHub Copilot (OAuth)
   - OpenAI (API key)
   - Anthropic (API key)
   - Cursor (if integrated)
3. Goose uses that provider's credentials

Local Model Option:
- Docker Model Runner (no auth needed)
- Ollama (local, private, free)
```

**Recommendation:**
- ✅ **Flexible integration model**
- Leverage OAuth from connected providers
- Highlight free local model option
- Position as cost-effective alternative

---

### 8. Sourcegraph Amp

**Subscription Plans:**
- **Free**: $0 (ad-supported, usage limits)
- **Paid**: $20+/month (estimated, exact pricing not public)

**Key Findings:**
- Ad-supported free tier (developer attention subsidizes costs)
- Enterprise plans with SSO/SAML/OAuth
- Built-in OAuth for MCP servers
- Available as CLI and VS Code extension

**OAuth Status:**
- ✅ **Full OAuth support**
- OAuth for MCP servers (automatic for Linear, etc.)
- Enterprise SSO: SAML, OpenID Connect, OAuth
- API key for non-interactive environments (`AMP_API_KEY`)

**Implementation Strategy:**
```
Option 1: API Key
- Set AMP_API_KEY environment variable
- For CI/CD, scripts, automation
- Contact amp-devs@ampcode.com for billing

Option 2: OAuth (Recommended)
- OAuth flow for user authentication
- MCP server OAuth for extensions
- Enterprise: SAML/OpenID Connect

Integration Flow:
1. User initiates Amp connection
2. Portal starts OAuth flow
3. User authorizes at ampcode.com
4. Portal receives access token
5. Use token with Amp API
```

**Recommendation:**
- ✅ **Implement OAuth for paid users**
- Support API key for scripting use cases
- Highlight free tier for trial users
- Enterprise: Full SSO integration

---

### 9. OpenCode

**Subscription Plans:**
- **Free**: Open source
- **OpenCode Zen**: Pay-as-you-go (optional curated models)

**Key Findings:**
- Open source AI coding agent
- Optional OpenCode Zen subscription for curated models
- Supports 75+ LLM providers
- Can authenticate with Claude Pro/Max via OAuth
- Third-party ChatGPT subscription OAuth plugins available

**OAuth Status:**
- ✅ **Supports OAuth** for some providers
- Claude Pro/Max: Opens browser for OAuth authentication
- ChatGPT Plus/Pro: Via third-party plugins
- API key authentication for most providers

**Implementation Strategy:**
```
Multi-Provider Approach:

1. OpenCode Zen (Official):
   - User runs /connect → opencode
   - Authenticate at opencode.ai/auth
   - Copy API key to portal
   - Pay-as-you-go billing

2. Claude Pro/Max OAuth:
   - User selects Claude Pro/Max option
   - OpenCode opens browser for OAuth
   - Portal captures authentication
   - Uses subscription credits

3. ChatGPT Subscription (Third-Party):
   - Via opencode-openai-codex-auth plugin
   - OAuth authentication
   - Uses ChatGPT Plus/Pro subscription
   - Personal use only

4. BYOK (Bring Your Own Key):
   - Support 75+ LLM providers
   - User provides API key
   - Standard authentication flow
```

**Recommendation:**
- ✅ **Flexible, multi-option approach**
- Prioritize Claude Pro/Max OAuth (native support)
- OpenCode Zen as premium option
- Third-party ChatGPT OAuth with disclaimers
- BYOK for maximum flexibility

---

### Implementation Priorities

Based on OAuth maturity and subscription integration:

**Tier 1 - Implement First (Native OAuth + Subscriptions):**
1. ✅ **GitHub Copilot** - Full OAuth, integrated billing, best UX
2. ✅ **Sourcegraph Amp** - Full OAuth, MCP support, enterprise-ready
3. ✅ **Gemini CLI** - Official OAuth, good documentation

**Tier 2 - Standard API Key (No OAuth Needed):**
4. ✅ **Aider** - BYOK model, simple integration
5. ✅ **Goose** - Free OSS, integrates other providers
6. ✅ **Claude Code** - API key (wait for official OAuth)

**Tier 3 - Complex/Third-Party OAuth:**
7. ⚠️ **OpenCode** - Multiple auth methods, requires careful implementation
8. ⚠️ **OpenAI Codex** - Third-party OAuth only, ToS concerns

**Tier 4 - Reconsider:**
9. ❌ **Cursor** - IDE client, not suitable for API integration

---

### OAuth Implementation Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MOBILE APP (Flutter)                      │
│  ┌────────────────────────────────────────────────────────┐  │
│  │         OAuth Manager (Riverpod Service)               │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │  │
│  │  │ GitHub   │  │ Google   │  │ Anthropic│  ...       │  │
│  │  │ OAuth    │  │ OAuth    │  │ OAuth    │            │  │
│  │  └──────────┘  └──────────┘  └──────────┘            │  │
│  └────────────────────────────────────────────────────────┘  │
│                           │                                  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │      Secure Token Storage (flutter_secure_storage)     │  │
│  │  - Keychain (iOS) / Keystore (Android)                │  │
│  │  - Encrypted token storage                            │  │
│  │  - Refresh token management                           │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      AgentAPI / Runtime                      │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Agent Runtime with OAuth Token Injection              │  │
│  │  - Receives OAuth tokens from mobile app              │  │
│  │  - Uses tokens for agent authentication               │  │
│  │  - Handles token refresh via callback to app          │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### OAuth Flow Examples

**GitHub Copilot Device Flow:**
```
1. User selects "Connect GitHub Copilot" in mobile app
2. App requests device code from GitHub OAuth
3. Display code + URL to user (e.g., github.com/login/device)
4. User opens URL on any device, enters code
5. App polls GitHub OAuth for authorization
6. Upon success, receive access token
7. Store in flutter_secure_storage
8. Pass to AgentAPI for Copilot calls
```

**Google OAuth (Gemini):**
```
1. User selects "Connect Gemini Advanced"
2. App opens OAuth web view
3. User logs in with Google account
4. Grants scope: generative-language.retriever
5. Google redirects with authorization code
6. App exchanges code for access + refresh tokens
7. Store in flutter_secure_storage
8. Use access token for Gemini API calls
```

**Third-Party OAuth (OpenAI via ChatGPT):**
```
1. User selects "Connect ChatGPT Plus" (if supported)
2. Display warning: "Unofficial integration, personal use only"
3. User confirms understanding
4. App initiates OpenAI OAuth flow
5. User authenticates at OpenAI
6. Receive access token (via third-party plugin)
7. Store with "unofficial" flag
8. Use for Codex API access
```

---

### Security Considerations

**Token Storage:**
- Use `flutter_secure_storage` (Keychain on iOS, Keystore on Android)
- Never store tokens in plain text or shared preferences
- Encrypt tokens at rest
- Implement token rotation

**OAuth Best Practices:**
- Use PKCE (Proof Key for Code Exchange) for all flows
- Implement state parameter to prevent CSRF
- Use short-lived access tokens with refresh tokens
- Validate redirect URIs strictly
- Implement token revocation on logout

**Third-Party OAuth Risks:**
- Clearly label unofficial integrations
- Warn users about potential ToS violations
- Obtain explicit user consent
- Consider liability implications
- Monitor for changes in provider policies

**API Key Security:**
- Store in secure storage, never in code or config
- Implement key rotation capability
- Allow users to revoke/change keys
- Don't log or transmit keys in clear text
- Consider using backend proxy for additional security

---

### User Experience Flow

**Onboarding - Agent Selection:**
```
┌─────────────────────────────────────────┐
│  Select Your Coding Agent               │
├─────────────────────────────────────────┤
│                                         │
│  ✓ GitHub Copilot                       │
│    Already subscribed? Connect now!     │
│    [Connect with GitHub] [Use API Key]  │
│                                         │
│  ○ Claude Code                          │
│    [Connect with API Key]               │
│    (OAuth coming soon)                  │
│                                         │
│  ○ Gemini Advanced                      │
│    [Connect with Google] [Use API Key]  │
│                                         │
│  ○ Aider (Free)                         │
│    Choose your LLM provider...          │
│                                         │
└─────────────────────────────────────────┘
```

**Subscription Detection:**
```
When user connects GitHub Copilot:
┌─────────────────────────────────────────┐
│  GitHub Copilot Connected!              │
├─────────────────────────────────────────┤
│  Plan: Pro ($10/month)                  │
│  Usage: 127 / 500 requests this month   │
│                                         │
│  ✓ Using your subscription              │
│  ✗ No additional API charges            │
│                                         │
│  [View Usage] [Disconnect]              │
└─────────────────────────────────────────┘

When user adds API key:
┌─────────────────────────────────────────┐
│  Claude Code Connected!                 │
├─────────────────────────────────────────┤
│  Authentication: API Key                │
│                                         │
│  ⚠ Pay-per-use billing                  │
│  ⚠ Separate from Claude Pro subscription│
│                                         │
│  Estimated cost: $0.003/request         │
│                                         │
│  [View Pricing] [Disconnect]            │
└─────────────────────────────────────────┘
```

---

### Cost Transparency

**For Users with Subscriptions (OAuth):**
- ✅ Display "Using your [Plan Name] subscription"
- ✅ Show usage against subscription quota
- ✅ Warn when approaching limits
- ✅ Clear "No additional charges" messaging

**For Users with API Keys:**
- ⚠️ Display "Pay-per-use billing"
- ⚠️ Show estimated cost per request
- ⚠️ Link to provider's pricing page
- ⚠️ Monthly cost tracking/alerts

**For Free Tier Users:**
- ℹ️ Display "Free tier - rate limited"
- ℹ️ Show daily/hourly quota remaining
- ℹ️ Offer upgrade path to paid tier

---

### Recommended Flutter Packages

```yaml
dependencies:
  # OAuth & Authentication
  flutter_appauth: ^7.x      # OAuth 2.0 with PKCE support
  oauth2: ^2.x               # OAuth 2.0 client library

  # Secure Storage
  flutter_secure_storage: ^9.x  # Keychain/Keystore integration

  # HTTP & API
  dio: ^5.x                  # HTTP client with interceptors
  http: ^1.x                 # Standard HTTP package

  # State Management
  flutter_riverpod: ^2.x     # For OAuth state management

  # Deep Linking (for OAuth redirects)
  uni_links: ^0.5.x          # Universal/deep link support
  app_links: ^6.x            # App Links (Android) / Universal Links (iOS)
```

---

### Testing Strategy

**OAuth Testing:**
1. **Sandbox Accounts**: Create test accounts with each provider
2. **Mock Servers**: Use mockito to simulate OAuth flows
3. **Integration Tests**: Test full OAuth flow on real devices
4. **Token Refresh**: Test token expiration and refresh
5. **Error Scenarios**: Test network failures, invalid tokens, revoked access

**API Key Testing:**
1. **Invalid Keys**: Test error handling
2. **Rate Limiting**: Test quota enforcement
3. **Key Rotation**: Test changing keys mid-session
4. **Secure Storage**: Verify encryption at rest

**Subscription Detection:**
1. **Plan Detection**: Verify correct plan identification
2. **Quota Tracking**: Test usage counter accuracy
3. **Cost Calculation**: Verify cost estimates
4. **Upgrade Flows**: Test free → paid transitions

---

### Migration Path

**Phase 1: API Keys Only (MVP)**
- Support all agents via API keys
- Implement secure storage
- Basic cost tracking

**Phase 2: GitHub Copilot OAuth**
- Implement OAuth device flow
- Subscription detection
- Usage quota display

**Phase 3: Google/Gemini OAuth**
- Implement Google OAuth
- Support Gemini Advanced subscriptions
- Cross-provider quota management

**Phase 4: Third-Party OAuth**
- OpenCode Claude Pro/Max OAuth
- Sourcegraph Amp OAuth
- Evaluate unofficial ChatGPT OAuth

**Phase 5: Official Anthropic OAuth**
- If/when Anthropic adds subscription OAuth
- Migrate users from API keys
- Unified subscription experience

---

## 20. Open Questions (Remaining)

1. **Monetization**: Will cloud runtime be a paid tier?
2. **Branding**: App name? "Agentic Portal" or something else?

---

## Sources

### Core
- [AgentAPI by Coder](https://github.com/coder/agentapi) - v0.11.2
- [Flutter AI Toolkit](https://docs.flutter.dev/ai-toolkit)
- [Claude Agent SDK](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/agent-sdk)

### Flutter Packages
- [flutter_smooth_markdown](https://pub.dev/packages/flutter_smooth_markdown) - Streaming markdown
- [flutter_code_view](https://pub.dev/packages/flutter_code_view) - Syntax highlighting
- [eventflux](https://pub.dev/packages/eventflux) - SSE client
- [bonsoir](https://pub.dev/packages/bonsoir) - mDNS discovery
- [Riverpod](https://riverpod.dev/) - State management

### Reference Apps
- [Kelivo](https://github.com/Chevey339/kelivo) - Production Flutter LLM chat

### Research
- [Flutter vs React Native 2025](https://www.tirnav.com/blog/google-flutter-vs-react-native-comparison)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Tailscale Docs](https://tailscale.com/kb/)

### Cloud Architecture
- [Firecracker microVMs](https://github.com/firecracker-microvm/firecracker)
- [gVisor Container Security](https://gvisor.dev/)
- [E2B AI Agent Cloud](https://e2b.dev/)
- [Docker Sandboxes for Coding Agents](https://www.docker.com/blog/docker-sandboxes-a-new-approach-for-coding-agent-safety/)

### Desktop Companion
- [Tauri vs Electron](https://www.raftlabs.com/blog/tauri-vs-electron-pros-cons/)
- [Go systray Library](https://github.com/fyne-io/systray)

### Cloud Pricing
- [Hetzner Cloud Pricing](https://www.hetzner.com/cloud/pricing/)
- [Fly.io Pricing](https://fly.io/pricing/)
- [AWS Fargate vs EC2 Comparison](https://www.netcomlearning.com/blog/ecs-vs-ec2)

### OAuth & Subscription Research (Section 19)

**Claude Code (Anthropic):**
- [Anthropic API Pricing: The 2026 Guide](https://www.nops.io/blog/anthropic-api-pricing/)
- [Claude Pricing Explained: Subscription Plans & API Costs](https://intuitionlabs.ai/articles/claude-pricing-plans-api-costs)
- [Using Claude Code with your Pro or Max plan](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan)
- [Support Claude Pro/Max Plans via OAuth Authentication - Roo-Code Issue #4799](https://github.com/RooCodeInc/Roo-Code/issues/4799)
- [Claude Pricing Official](https://claude.com/pricing)

**Gemini CLI (Google):**
- [Authentication with OAuth quickstart - Gemini API](https://ai.google.dev/gemini-api/docs/oauth)
- [Gemini Developer API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Google Gemini Pricing Guide](https://www.cloudeagle.ai/blogs/blogs-google-gemini-pricing-guide)
- [Gemini CLI Authentication Setup](https://geminicli.com/docs/get-started/authentication/)
- [Set up Gemini Code Assist](https://docs.cloud.google.com/gemini/docs/codeassist/set-up-gemini)

**OpenAI Codex:**
- [What is ChatGPT Plus? - OpenAI Help Center](https://help.openai.com/en/articles/6950777-what-is-chatgpt-plus)
- [OpenAI Pricing](https://openai.com/api/pricing/)
- [OpenCode OpenAI Codex Auth Plugin](https://github.com/numman-ali/opencode-openai-codex-auth)
- [Vercel AI SDK ChatGPT OAuth Provider](https://github.com/ben-vargas/ai-sdk-provider-chatgpt-oauth)
- [Authentication - OpenAI Developers](https://developers.openai.com/apps-sdk/build/auth/)

**GitHub Copilot:**
- [REST API endpoints for Copilot - GitHub Docs](https://docs.github.com/en/rest/copilot/copilot-user-management)
- [Plans for GitHub Copilot](https://docs.github.com/en/copilot/get-started/plans)
- [Enhanced MCP OAuth support - GitHub Changelog](https://github.blog/changelog/2025-11-18-enhanced-mcp-oauth-support-for-github-copilot-in-jetbrains-eclipse-and-xcode/)
- [GitHub Copilot Pricing 2026 Guide](https://userjot.com/blog/github-copilot-pricing-guide-2025)
- [Copilot API - Turn GitHub Copilot into OpenAI API](https://github.com/ericc-ch/copilot-api)

**Cursor:**
- [Cursor Pricing](https://cursor.com/pricing)
- [Cursor AI Pricing: 2025 Complete Guide](https://www.cometapi.com/cursor-ai-pricing-2025-complete-guide-analysis/)
- [Cursor APIs Overview](https://cursor.com/docs/api)
- [Using Cursor IDE with cto.new](https://cto.new/blog/using-cursor-ide-with-cto.new-as-your-background-agent)

**Aider:**
- [Aider - AI Pair Programming in Your Terminal](https://aider.chat/)
- [Aider Review: Terminal-Based Code Assistant](https://www.blott.com/blog/post/aider-review-a-developers-month-with-this-terminal-based-code-assistant)
- [Getting Started with Aider](https://blog.openreplay.com/getting-started-aider-ai-coding-terminal/)

**Goose:**
- [GitHub - block/goose](https://github.com/block/goose)
- [GooseAI - NLP Infrastructure](https://goose.ai/)
- [Goose Quickstart](https://block.github.io/goose/docs/quickstart/)
- [Building an AI Assistant with Goose and Docker](https://www.docker.com/blog/building-an-ai-assistant-with-goose-and-docker-model-runner/)

**Sourcegraph Amp:**
- [Amp - Sourcegraph](https://sourcegraph.com/amp)
- [Amp Owner's Manual](https://ampcode.com/manual)
- [Sourcegraph Pricing](https://sourcegraph.com/pricing)
- [Amp's Ad-Supported AI Coding](https://ainativedev.io/news/amp-s-new-business-model-ad-supported-ai-coding)

**OpenCode:**
- [OpenCode - The open source AI coding agent](https://opencode.ai/)
- [GitHub - opencode-ai/opencode](https://github.com/opencode-ai/opencode)
- [OpenCode Providers Documentation](https://opencode.ai/docs/providers/)
- [OpenCode CLI Documentation](https://opencode.ai/docs/cli/)
