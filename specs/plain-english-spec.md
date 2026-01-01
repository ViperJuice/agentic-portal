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

## 19. Open Questions (Remaining)

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
