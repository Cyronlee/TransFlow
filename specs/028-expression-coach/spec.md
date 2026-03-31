# 028 - Expression Coach

## Background

Non-native English speakers often struggle with grammar, word choice, and clarity when speaking English in live conversations. TransFlow already has real-time transcription and speaker diarization capabilities. By integrating a cloud LLM, the app can analyze the user's transcribed speech in real time and offer suggestions for more natural, clearer expression.

Core idea: The AI acts as a personal expression assistant and English tutor, providing up to 3 rephrasing suggestions during a live conversation. The user can review them and then rephrase or clarify their point to the audience.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Target user | Local microphone user only | In app audio mode the user is not speaking; nothing to coach |
| Analysis granularity | Sentence-level | Each `sentenceComplete` event triggers one analysis |
| Diarization dependency | None | Skip diarization wait, use transcription sentences directly to minimize latency |
| LLM approach | Cloud API (BYOK) | Users bring their own API key initially; subscription service planned for the future |
| Supported LLM providers | Google Gemini, OpenAI | Fast models (Gemini Flash Lite, GPT-4o-mini, etc.) for low latency and low cost |
| UI form | Floating panel (NSPanel) | Same interaction model as FloatingPreviewPanel; does not interfere with the main window |
| Max suggestions | 3 per sentence | Avoid information overload |
| Retained entries | Latest 5 | Keep the panel clean; older entries auto-removed |
| Audio source restriction | `.microphone` mode only | Coach feature hidden in app audio / system audio modes |
| Coaching intensity | User-selectable (gentle / moderate / strict) | Default: moderate; configurable in Settings |

## Existing Architecture Overview

### Real-time Transcription Pipeline

```
Microphone audio
    → AudioCaptureService (16kHz mono Float32, ~100ms chunks)
    → Fork: engineStream / levelStream / recordingStream / [diarizationStream]
    → SpeechEngine → TranscriptionEvent (partial / sentenceComplete)
    → TransFlowViewModel updates UI
```

### Floating Panel Pattern (FloatingPreviewPanel)

```
FloatingPreviewPanelManager (NSPanel lifecycle management)
    → NSPanel (draggable, pin/unpin, non-activating panel)
    → FloatingPreviewView (SwiftUI content, hover controls)
    → Reads shared TransFlowViewModel state
```

The coach panel will reuse this architectural pattern.

## Technical Design

### Overall Data Flow

```
sentenceComplete event
    → ExpressionCoachService.analyze(sentence, conversationContext)
    → LLMProvider.sendRequest(prompt)    [Cloud API]
    → CoachSuggestion (original + ≤3 rewrites) or nil (no coaching needed)
    → CoachPanelManager updates floating panel
```

### 1. LLM Service Layer

#### LLMProvider Protocol

```swift
protocol LLMProvider: Sendable {
    var name: String { get }
    func complete(messages: [LLMMessage]) async throws -> String
    func validate() async throws -> Bool
}

struct LLMMessage: Sendable {
    enum Role: String, Sendable { case system, user, assistant }
    let role: Role
    let content: String
}
```

#### Concrete Implementations

| Provider | Class | Endpoint | Recommended Model |
|----------|-------|----------|-------------------|
| Google Gemini | `GeminiProvider` | `generativelanguage.googleapis.com` | gemini-2.0-flash-lite |
| OpenAI | `OpenAIProvider` | `api.openai.com/v1/chat/completions` | gpt-4o-mini |

Both providers use `URLSession` for HTTPS requests with no third-party SDK dependencies.

#### API Key Management

- API keys are stored in the macOS Keychain (`Security.framework`), not in UserDefaults
- `LLMKeyManager` wraps Keychain CRUD operations:
  - `saveKey(_ key: String, for provider: LLMProviderType)`
  - `loadKey(for provider: LLMProviderType) -> String?`
  - `deleteKey(for provider: LLMProviderType)`
- Settings UI provides a secure input field (`SecureField`) with a show/hide toggle
- "Test" button: calls `provider.validate()` to verify the key is valid

### 2. ExpressionCoachService

Core service that coordinates transcription events with LLM analysis.

```swift
@MainActor
@Observable
final class ExpressionCoachService {
    var suggestions: [CoachEntry] = []  // latest 5
    var isAnalyzing: Bool = false

    private let provider: LLMProvider
    private var conversationHistory: [TranscriptionSentence] = []

    func analyze(sentence: TranscriptionSentence) async { ... }
}
```

#### CoachEntry Data Model

```swift
struct CoachEntry: Identifiable, Sendable {
    let id: UUID
    let originalText: String
    let suggestions: [String]     // 1–3 rephrasing suggestions
    let timestamp: Date
    let sentenceId: UUID          // linked TranscriptionSentence.id
}
```

#### System Prompt Design

The system prompt must include:
- Role definition: English expression coach
- Coaching intensity level description
- Output format constraint (JSON for reliable parsing)
- Context note: recent conversation history to understand what the user is responding to

```
You are an English expression coach. The user is a non-native English speaker
having a live conversation. Analyze the user's latest sentence and provide
suggestions for clearer, more natural expression.

Coaching intensity: {gentle|moderate|strict}
- gentle: Only flag genuinely unclear or broken sentences
- moderate: Flag grammar issues and unclear phrasing
- strict: Flag any sentence that could be expressed more naturally

Respond in JSON:
{"needs_coaching": true/false, "suggestions": ["...", "...", "..."]}

If the sentence is fine, return {"needs_coaching": false, "suggestions": []}.
Maximum 3 suggestions. Each suggestion should be a complete rewrite of the
sentence, not a fragment or explanation.

Recent conversation context (for understanding what the user is responding to):
{context}
```

#### Conversation Context Window

- Retain the last 10 completed sentences as context
- Context formatted as `[Speaker X]: sentence text` when diarization info is available
- Without diarization, sentences are passed as plain text
- Estimated token usage: system prompt (~200) + context (~500–800) + sentence (~50) + response (~150) ≈ 900–1200 tokens/request

#### Cost Estimate

| Model | Input Price | Output Price | Per-Request Cost | 1-Hour Meeting (~360 sentences) |
|-------|-------------|--------------|-----------------|--------------------------------|
| Gemini 2.0 Flash Lite | $0.075/1M | $0.30/1M | ~$0.0001 | ~$0.04 |
| GPT-4o-mini | $0.15/1M | $0.60/1M | ~$0.0003 | ~$0.11 |

### 3. Floating Coach Panel

#### CoachPanelManager

Reuses the `FloatingPreviewPanelManager` NSPanel management pattern:

```swift
@MainActor
@Observable
final class CoachPanelManager: NSObject, NSWindowDelegate {
    var isPinned: Bool = false
    var isVisible: Bool = false

    func show(coachService: ExpressionCoachService, locale: Locale, colorScheme: ColorScheme?)
    func close()
    func toggle(...)
    func togglePin()
}
```

NSPanel configuration:
- `styleMask: [.resizable, .nonactivatingPanel]`
- `isMovableByWindowBackground = true`
- `hidesOnDeactivate = false` (does not hide when the app loses focus)
- `backgroundColor = .clear` (for `.glassEffect`)
- `minSize: NSSize(width: 320, height: 120)` (fits exactly 1 entry)
- `setFrameAutosaveName("TransFlow.CoachPanel")` (remembers position and size)

#### CoachPanelView

```
┌──────────────────────────────────────────────────┐
│                                       📌  ✕      │ ← shown on hover
│                                                   │
│  ┌─ Entry ─────────────────────────────────────┐ │
│  │ "I think we should to go with option A"     │ │ ← original (dimmed)
│  │                                              │ │
│  │ 💡 I think we should go with option A    📋 │ │ ← suggestion 1 + copy
│  │ 💡 I'd suggest we go with option A       📋 │ │ ← suggestion 2 + copy
│  │ 💡 My recommendation is option A         📋 │ │ ← suggestion 3 + copy
│  └──────────────────────────────────────────────┘ │
│                                                   │
│  ┌─ Entry ─────────────────────────────────────┐ │
│  │ "The budget is not enough for this..."      │ │
│  │                                              │ │
│  │ 💡 The budget is insufficient for this... 📋 │ │
│  │ 💡 We don't have enough budget for...    📋 │ │
│  └──────────────────────────────────────────────┘ │
│                                                   │
│                    Listening...                    │ ← placeholder when empty
└──────────────────────────────────────────────────┘
```

Design details:

- **Default size**: Just large enough to display 1 entry (~120–160px height)
- **Resizable by dragging**: User can enlarge the panel to see more entries
- **Retains latest 5**: Oldest entry is auto-removed when exceeded
- **Auto-scrolls to newest**: Panel scrolls to bottom when a new suggestion appears
- **Copy button**: Each suggestion has a copy button; click to copy to clipboard
- **Glass effect**: `.glassEffect(.regular, in: .rect(cornerRadius: 14))`
- **Hover controls**: Pin / close, consistent with FloatingPreviewView
- **Empty state**: Displays "Listening..." placeholder text
- **Analyzing state**: Subtle loading indicator while the current sentence is being analyzed

### 4. Settings Changes

#### New Settings Section: Expression Coach

A new section in SettingsView, placed after Diarization Models:

```
┌── EXPRESSION COACH ─────────────────────────────────┐
│ 🧠 LLM Provider                        [Gemini ▾]  │
│ ─────────────────────────────────────────────────── │
│ 🔑 API Key                     [••••••••••] 👁 Test │
│ ─────────────────────────────────────────────────── │
│ 🤖 Model                    [gemini-2.0-flash-lite] │
│ ─────────────────────────────────────────────────── │
│ 📊 Coaching Intensity               [Moderate ▾]   │
└─────────────────────────────────────────────────────┘
```

#### New AppSettings Properties

```swift
// MARK: - Expression Coach Settings

/// Selected LLM provider for expression coaching.
var coachLLMProvider: CoachLLMProviderType  // .gemini | .openai

/// Selected model name (per provider).
var coachModelName: String                  // e.g. "gemini-2.0-flash-lite"

/// Coaching intensity level.
var coachIntensity: CoachIntensity          // .gentle | .moderate | .strict

/// Whether the expression coach feature is enabled.
var coachEnabled: Bool
```

All values persisted via UserDefaults (except API key, which is stored in Keychain).

#### CoachLLMProviderType

```swift
enum CoachLLMProviderType: String, CaseIterable, Identifiable {
    case gemini = "gemini"
    case openai = "openai"

    var id: String { rawValue }

    var displayName: LocalizedStringKey { ... }

    var defaultModel: String {
        switch self {
        case .gemini: "gemini-2.0-flash-lite"
        case .openai: "gpt-4o-mini"
        }
    }

    var availableModels: [String] {
        switch self {
        case .gemini: ["gemini-2.0-flash-lite", "gemini-2.0-flash"]
        case .openai: ["gpt-4o-mini", "gpt-4o"]
        }
    }
}
```

#### CoachIntensity

```swift
enum CoachIntensity: String, CaseIterable, Identifiable {
    case gentle
    case moderate
    case strict

    var id: String { rawValue }
    var displayName: LocalizedStringKey { ... }
    var systemPromptLabel: String { rawValue }
}
```

### 5. ControlBar Changes

Add a coach toggle button in `rightControls`, placed after the diarization toggle:

```swift
// Expression coach toggle
coachToggle
```

Button behavior:
- **Icon**: `text.bubble` (or similar)
- **Active color**: Green (distinct from diarization's orange and translation's blue)
- **Enabled when**: `audioSource == .microphone && coachService.hasValidAPIKey`
- **Disabled state**: Reduced opacity, tooltip shows "API key required" or "Only available in microphone mode"
- **On click**: Toggles `coachEnabled` and opens/closes the coach panel

### 6. ViewModel Integration

In `TransFlowViewModel`:

```swift
// New property
var coachService: ExpressionCoachService

// Inside sentenceComplete handler:
case .sentenceComplete(let sentence):
    sentences.append(sentence)
    // ... existing translation, diarization logic ...

    // Expression coach: only triggers in microphone mode with coach enabled
    if audioSource == .microphone && settings.coachEnabled && coachService.isReady {
        Task {
            await coachService.analyze(sentence: sentence, context: sentences)
        }
    }
```

Key point: coach analysis runs in a separate `Task` and never blocks the main transcription flow.

### 7. Internationalization

New i18n keys (en + zh-Hans):

| Key | en | zh-Hans |
|-----|-----|---------|
| `settings.expression_coach` | Expression Coach | 表达助手 |
| `settings.coach_provider` | LLM Provider | LLM 提供商 |
| `settings.coach_api_key` | API Key | API 密钥 |
| `settings.coach_api_key_test` | Test | 测试 |
| `settings.coach_api_key_valid` | Valid | 有效 |
| `settings.coach_api_key_invalid` | Invalid | 无效 |
| `settings.coach_model` | Model | 模型 |
| `settings.coach_intensity` | Coaching Intensity | 辅导强度 |
| `coach.intensity.gentle` | Gentle | 温和 |
| `coach.intensity.moderate` | Moderate | 适中 |
| `coach.intensity.strict` | Strict | 严格 |
| `control.enable_coach` | Enable Expression Coach | 开启表达助手 |
| `control.disable_coach` | Disable Expression Coach | 关闭表达助手 |
| `control.coach_api_key_required` | API key required — set in Settings | 需要 API 密钥 — 请在设置中配置 |
| `control.coach_mic_only` | Only available in microphone mode | 仅麦克风模式下可用 |
| `coach.listening` | Listening... | 正在聆听... |
| `coach.analyzing` | Analyzing... | 分析中... |
| `coach.copied` | Copied | 已复制 |
| `coach_panel.pin` | Pin on top | 置顶 |
| `coach_panel.unpin` | Unpin | 取消置顶 |
| `coach_panel.close` | Close | 关闭 |

## File Plan

| File | Description | Action |
|------|-------------|--------|
| `Services/LLMProvider.swift` | LLM protocol + message model | New |
| `Services/GeminiProvider.swift` | Google Gemini API implementation | New |
| `Services/OpenAIProvider.swift` | OpenAI API implementation | New |
| `Services/LLMKeyManager.swift` | Keychain API key management | New |
| `Services/ExpressionCoachService.swift` | Coach core service | New |
| `Services/CoachPanelManager.swift` | Floating panel lifecycle management | New |
| `Views/CoachPanelView.swift` | Coach panel SwiftUI view | New |
| `Models/CoachModels.swift` | CoachEntry, CoachIntensity, CoachLLMProviderType | New |
| `Models/AppSettings.swift` | Add coach-related settings properties | Modify |
| `Views/SettingsView.swift` | Add Expression Coach section | Modify |
| `Views/ControlBarView.swift` | Add coach toggle button | Modify |
| `ViewModels/TransFlowViewModel.swift` | Integrate coach analysis trigger | Modify |
| `TransFlowApp.swift` | Inject CoachPanelManager instance | Modify |
| `Localizable.xcstrings` | Add i18n keys | Modify |

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| LLM response latency | Suggestion arrives after the topic has moved on | Use fast models (Flash Lite / 4o-mini); suggestions still have learning value |
| API call failure (network / rate limit) | Missing suggestions | Fail silently without interrupting transcription; optionally retry once |
| LLM returns non-JSON response | Parse failure | Fallback regex extraction of suggestions; ignore unparseable responses |
| Excessive API calls | High cost | Skip analysis for short sentences (<5 words); debounce consecutive sentences |
| API key leakage | Security risk | Keychain storage; never written to UserDefaults / logs / JSONL |
| User enables coach in app audio mode | Feature is meaningless | UI-level restriction: disable button in non-microphone modes |
| LLM produces inappropriate or incorrect suggestions | Misleading the user | Clearly label suggestions as AI-generated; user decides whether to adopt |

## Future Extensions (Out of Scope)

- **Subscription service**: Introduce a TransFlow subscription plan so users can access multiple LLM models without bringing their own API key
- **Dual audio capture**: Capture microphone + app audio simultaneously; app audio provides conversation context while microphone audio is coached
- **Post-session review mode**: After a session ends, AI reviews all of the user's utterances to identify recurring issues and provide learning-focused feedback
- **Custom prompt**: Advanced users can edit the system prompt to customize coaching style
- **Local LLM**: Support llama.cpp / MLX local models for fully offline operation

## Acceptance Criteria

- [ ] Settings allows configuration of LLM provider, API key, model, and coaching intensity
- [ ] API key is stored in Keychain; Test button validates key
- [ ] In microphone mode, Control Bar shows the coach toggle button
- [ ] In non-microphone modes, the coach button is disabled or hidden
- [ ] Enabling the coach opens the floating coach panel
- [ ] Each sentenceComplete triggers LLM analysis (microphone mode only)
- [ ] Sentences that need no coaching produce no coach entry
- [ ] When suggestions exist, the panel displays the original sentence + up to 3 suggestions
- [ ] The panel retains the latest 5 entries
- [ ] Default panel size shows 1 entry; resizable by dragging
- [ ] Each suggestion has a copy button that copies to clipboard
- [ ] Panel supports pin/unpin, close, and drag-to-move
- [ ] Panel position and size are remembered across sessions (autosave frame)
- [ ] LLM call failures are handled silently without affecting transcription
- [ ] App builds successfully (xcodebuild)
