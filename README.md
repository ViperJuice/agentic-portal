# Agentic Portal

A mobile app (iOS + Android) that provides a chat interface for coding agents, starting with Claude Code and extensible to Gemini CLI, OpenAI Codex, Aider, and others.

## Quick Start

### Prerequisites

- Claude Code CLI installed (`claude --version`)
- AgentAPI (included in `bin/`)

### Run AgentAPI with Claude Code

```bash
./bin/agentapi server claude
```

Server starts on `http://localhost:3284`

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/status` | GET | Agent state: `stable` or `running` |
| `/messages` | GET | Full conversation history |
| `/message` | POST | Send message `{"content": "...", "type": "user"}` |
| `/events` | GET | SSE stream for real-time updates |
| `/upload` | POST | File upload (multipart form) |
| `/docs` | GET | Interactive OpenAPI docs |

### Example Usage

```bash
# Check status
curl http://localhost:3284/status

# Send a message
curl -X POST http://localhost:3284/message \
  -H "Content-Type: application/json" \
  -d '{"content": "What files are in this directory?", "type": "user"}'

# Get messages
curl http://localhost:3284/messages

# Stream events (SSE)
curl -N http://localhost:3284/events
```

## Project Structure

```
agentic-portal/
├── bin/
│   └── agentapi         # AgentAPI binary (v0.11.6)
├── specs/
│   └── plain-english-spec.md  # Technical specification
└── README.md
```

## Documentation

See [specs/plain-english-spec.md](specs/plain-english-spec.md) for the complete technical specification including:

- Architecture decisions (Flutter, hybrid local/cloud runtime)
- AgentAPI integration details
- Flutter package recommendations
- Cloud architecture phases
- Authentication, Git integration, push notifications
- Competitive analysis

## Validation Results

AgentAPI v0.11.6 tested successfully with Claude Code v2.0.76:

- Status endpoint: Working
- Messages endpoint: Working
- POST message: Working (Claude responds correctly)
- SSE streaming: Working (real-time event delivery)

## Next Steps

1. Set up Flutter project with Riverpod + EventFlux
2. Implement mDNS discovery + QR code connection flow
3. Build streaming chat UI with markdown/code rendering
4. Test end-to-end local connection
