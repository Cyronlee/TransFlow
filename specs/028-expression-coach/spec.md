# 028 - Expression Coach

## Background

Non-native English speakers often struggle with grammar, word choice, and clarity when speaking English in live conversations. TransFlow already has real-time transcription and speaker diarization capabilities. By integrating a cloud LLM, the app can analyze the user's transcribed speech in real time and offer suggestions for more natural, clearer expression.

Core idea: The AI acts as a personal expression assistant and English tutor, providing up to 3 rephrasing suggestions during a live conversation. The user can review them and then rephrase or clarify their point to the audience.

V1 scope: coach only runs for English transcription sessions (`en-*` locales) using the local microphone. It does not attempt multilingual coaching in this version.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Target user | Local microphone user speaking English | V1 is an English-speaking coach, not a general multilingual assistant |
| Language scope | English transcription locales only (`en-*`) | Avoid coaching non-English sessions in v1 |
| Analysis granularity | Sentence-level | Completed sentences are the unit of analysis |
| Scheduling policy | Single-flight, latest-wins | Prevent request backlog and stale suggestions during fast speech |
| Diarization dependency | None | Skip diarization wait, use transcription sentences directly to minimize latency |
| Conversation context scope | Recent local utterance history only | Dual capture is deferred; remote speaker audio is unavailable in v1 |
| LLM approach | Cloud API (BYOK) | Users bring their own API key initially; subscription service planned for the future |
| Supported LLM providers | Google Gemini, OpenAI | Fast models (Gemini Flash Lite, GPT-4o-mini, etc.) for low latency and low cost |
| UI form | Floating panel (NSPanel) | Same interaction model as FloatingPreviewPanel; does not interfere with the main window |
| Max suggestions | 3 per sentence | Avoid information overload |
| Retained entries | Latest 5 | Keep the panel clean; older entries auto-removed |
| Audio source restriction | `.microphone` mode only | Coach button stays visible but disabled in app audio / system audio modes |
| Coaching intensity | User-selectable (gentle / moderate / strict) | Default: moderate; configurable in Settings |
| Config application | Apply after restarting listening | Avoid hot-swapping provider/model/intensity mid-session |
| Privacy disclosure | Clear Settings note | Users should know recent utterances are sent to the selected cloud provider |

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
eligible `sentenceComplete` event
    → ExpressionCoachService.handleCompletedSentence(sentence)
    → Single-flight scheduler (1 in-flight, latest pending sentence only)
    → LLMProvider.complete(messages)    [Cloud API]
    → CoachEntry (original + ≤3 rewrites) or nil (no coaching needed)
    → CoachPanelManager / CoachPanelView updates
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

#### Privacy Disclosure

- Expression Coach settings show a clear note explaining that recent spoken English utterances are sent to the selected LLM provider for analysis
- The feature remains opt-in and is disabled by default

### 2. ExpressionCoachService

Core service that coordinates transcription events with LLM analysis.

```swift
@MainActor
@Observable
final class ExpressionCoachService {
    var entries: [CoachEntry] = []  // latest 5
    var isAnalyzing: Bool = false
    var isEnabled: Bool = false

    private var runtimeConfig: CoachRuntimeConfig?
    private var provider: LLMProvider?
    private var inFlightTask: Task<Void, Never>?
    private var pendingSentence: TranscriptionSentence?
    private var conversationHistory: [TranscriptionSentence] = []

    func beginListeningSession(config: CoachRuntimeConfig?)
    func endListeningSession()
    func setCoachingEnabled(_ enabled: Bool)
    func handleCompletedSentence(_ sentence: TranscriptionSentence)
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

#### CoachRuntimeConfig

```swift
struct CoachRuntimeConfig: Sendable {
    let providerType: CoachLLMProviderType
    let modelName: String
    let intensity: CoachIntensity
}
```

`CoachRuntimeConfig` is snapshotted when listening starts. Changing provider, model, or intensity while listening is active updates persisted settings only; the active listening session keeps using its existing runtime config until listening restarts.

#### Sentence Eligibility

A sentence is eligible for coaching only when all of the following are true:
- Current audio source is `.microphone`
- Selected transcription language is English (`en-*`)
- Coaching is enabled (`coachEnabled == true`)
- A valid API key exists for the selected provider
- Sentence contains at least 5 words after trimming

#### Scheduling Policy

The service uses a single-flight, latest-wins scheduler:
- At most one LLM request may be in flight at a time
- If a new eligible sentence arrives while a request is running, store only the latest pending sentence and discard any older pending sentence
- When the in-flight request finishes, immediately analyze the latest pending sentence if coaching is still enabled
- Disabling coaching, closing the panel, switching to an ineligible mode/language, or stopping listening cancels in-flight work and clears pending work
- `isAnalyzing` represents that the service currently has in-flight or pending analysis work

#### System Prompt Design

The system prompt must include:
- Role definition: English expression coach
- Coaching intensity level description
- Output format constraint (JSON for reliable parsing)
- Context note: recent local utterance history for same-speaker continuity

```
You are an English expression coach. The user is a non-native English speaker
having a live conversation. All input below comes from the same local speaker.
Analyze the user's latest English sentence and provide suggestions for clearer,
more natural expression.

Coaching intensity: {gentle|moderate|strict}
- gentle: Only flag genuinely unclear or broken sentences
- moderate: Flag grammar issues and unclear phrasing
- strict: Flag any sentence that could be expressed more naturally

Respond in JSON:
{"needs_coaching": true/false, "suggestions": ["...", "...", "..."]}

If the sentence is fine, return {"needs_coaching": false, "suggestions": []}.
Maximum 3 suggestions. Each suggestion should be a complete rewrite of the
sentence, not a fragment or explanation.

Recent local utterance history from the same speaker (for context only):
{context}
```

#### Conversation Context Window

- Retain the last 10 completed local microphone sentences from the same listening session as context
- Context contains only the user's own local utterance history in v1
- Remote speaker / app audio / system audio is not included; dual capture is future work
- Context is passed as plain text in chronological order
- Estimated token usage: system prompt (~200) + context (~500–800) + sentence (~50) + response (~150) ≈ 900–1200 tokens/request; actual cost is often lower because short sentences are skipped and the scheduler keeps only the latest pending sentence

#### Cost Estimate

| Model | Input Price | Output Price | Per-Request Cost | 1-Hour Meeting (upper bound ~360 analyzed sentences) |
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

Closing the panel is not a purely visual action in v1. It disables coaching for the current listening session, cancels in-flight/pending analysis, and leaves transcription running.

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
- **Close behavior**: Closing the panel disables coaching for the current listening session; transcription keeps running

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
│ ─────────────────────────────────────────────────── │
│ ℹ Sends recent spoken English utterances to your   │
│   selected LLM provider for analysis               │
│ ℹ Changes apply next time you start listening      │
└─────────────────────────────────────────────────────┘
```

The section includes a privacy disclosure note and a secondary note explaining that provider/model/intensity changes apply only to the next listening session.

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
/// Closing the panel sets this to false, but transcription keeps running.
var coachEnabled: Bool
```

All values are persisted via UserDefaults (except API key, which is stored in Keychain). Active listening sessions use a `CoachRuntimeConfig` snapshot captured when listening starts, so changing provider/model/intensity in Settings does not affect the current session.

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
- **Enabled when**: `audioSource == .microphone && selectedLanguage is English && coachService.hasValidAPIKey`
- **Disabled state**: Reduced opacity, tooltip shows "API key required", "Only available in microphone mode", or "English only in v1"
- **On click when off**: Sets `coachEnabled = true` and opens the coach panel
- **On click when on**: Sets `coachEnabled = false`, closes the panel, and cancels in-flight/pending analysis
- **Panel close button**: Performs the same disable flow, but transcription continues

### 6. ViewModel Integration

In `TransFlowViewModel`:

```swift
// New property
var coachService: ExpressionCoachService

// When listening starts, snapshot the coach runtime config for this session
let coachRuntimeConfig =
    audioSource == .microphone && selectedLanguage.identifier.hasPrefix("en")
    ? CoachRuntimeConfig(
        providerType: settings.coachLLMProvider,
        modelName: settings.coachModelName,
        intensity: settings.coachIntensity
    )
    : nil

coachService.beginListeningSession(config: coachRuntimeConfig)

// Inside sentenceComplete handler:
case .sentenceComplete(let sentence):
    sentences.append(sentence)
    // ... existing translation, diarization logic ...

    coachService.handleCompletedSentence(sentence)

// When listening stops:
coachService.endListeningSession()
```

Key points:
- `beginListeningSession` snapshots provider/model/intensity for the full listening session
- `handleCompletedSentence` updates local utterance history and, when coaching is enabled, submits eligible sentences to the single-flight scheduler
- Closing the coach panel calls `coachService.setCoachingEnabled(false)` and does not stop transcription
- Coach analysis runs in a separate task and never blocks the main transcription flow

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
| `settings.coach_privacy_note` | Sends recent spoken English utterances to your selected LLM provider for analysis | 会将最近说出的英语内容发送给你选择的 LLM 提供商进行分析 |
| `settings.coach_restart_required` | Changes apply next time you start listening | 更改将在下次开始收听时生效 |
| `coach.intensity.gentle` | Gentle | 温和 |
| `coach.intensity.moderate` | Moderate | 适中 |
| `coach.intensity.strict` | Strict | 严格 |
| `control.enable_coach` | Enable Expression Coach | 开启表达助手 |
| `control.disable_coach` | Disable Expression Coach | 关闭表达助手 |
| `control.coach_api_key_required` | API key required — set in Settings | 需要 API 密钥 — 请在设置中配置 |
| `control.coach_mic_only` | Only available in microphone mode | 仅麦克风模式下可用 |
| `control.coach_english_only` | English only in v1 | v1 仅支持英语 |
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
| `Services/ExpressionCoachService.swift` | Coach core service + single-flight scheduler | New |
| `Services/CoachPanelManager.swift` | Floating panel lifecycle management | New |
| `Views/CoachPanelView.swift` | Coach panel SwiftUI view | New |
| `Models/CoachModels.swift` | CoachEntry, CoachRuntimeConfig, CoachIntensity, CoachLLMProviderType | New |
| `Models/AppSettings.swift` | Add coach-related settings properties | Modify |
| `Views/SettingsView.swift` | Add Expression Coach section + privacy / restart notes | Modify |
| `Views/ControlBarView.swift` | Add coach toggle button | Modify |
| `ViewModels/TransFlowViewModel.swift` | Manage coach session lifecycle and sentence submission | Modify |
| `TransFlowApp.swift` | Inject CoachPanelManager instance | Modify |
| `Localizable.xcstrings` | Add i18n keys | Modify |

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| LLM response latency | Suggestion arrives after the topic has moved on | Use fast models and single-flight latest-wins scheduling so backlog never grows beyond one pending sentence |
| API call failure (network / rate limit) | Missing suggestions | Fail silently without interrupting transcription; optionally retry once |
| LLM returns non-JSON response | Parse failure | Fallback regex extraction of suggestions; ignore unparseable responses |
| Excessive API calls | High cost | Skip analysis for short sentences (<5 words); keep only one in-flight request and one latest pending sentence |
| Settings changed mid-session | User expects immediate behavior change | Snapshot runtime config at listening start; show restart note in Settings |
| API key leakage | Security risk | Keychain storage; never written to UserDefaults / logs / JSONL |
| Cloud processing surprises users | Privacy concern | Clear Settings disclosure that recent spoken English utterances are sent to the selected provider |
| User enables coach in unsupported state | Feature is meaningless | Disable button in non-microphone modes and non-English sessions |
| LLM produces inappropriate or incorrect suggestions | Misleading the user | Clearly label suggestions as AI-generated; user decides whether to adopt |

## Future Extensions (Out of Scope)

- **Subscription service**: Introduce a TransFlow subscription plan so users can access multiple LLM models without bringing their own API key
- **Dual audio capture**: Capture microphone + app/system audio simultaneously using two parallel transcription streams; app/system audio provides remote-side context while microphone audio remains the coached source
- **Post-session review mode**: After a session ends, AI reviews all of the user's utterances to identify recurring issues and provide learning-focused feedback
- **Custom prompt**: Advanced users can edit the system prompt to customize coaching style
- **Local LLM**: Support llama.cpp / MLX local models for fully offline operation

## Acceptance Criteria

- [ ] Settings allows configuration of LLM provider, API key, model, and coaching intensity, and shows privacy / restart notes
- [ ] API key is stored in Keychain; Test button validates key
- [ ] The coach control is enabled only when microphone mode, English transcription, and a valid API key are all true
- [ ] In unsupported states (non-microphone mode, non-English language, or missing API key), the coach button remains visible but disabled with an explanatory tooltip
- [ ] Enabling the coach opens the floating coach panel
- [ ] Closing the panel disables coaching and cancels in-flight/pending analysis without stopping transcription
- [ ] Eligible `sentenceComplete` events are analyzed only for English microphone sessions
- [ ] The service uses single-flight, latest-wins scheduling (at most one in-flight request and one latest pending sentence)
- [ ] Changing provider/model/intensity during active listening takes effect after listening restarts
- [ ] Sentences that need no coaching produce no coach entry
- [ ] When suggestions exist, the panel displays the original sentence + up to 3 suggestions
- [ ] The panel retains the latest 5 entries
- [ ] Default panel size shows 1 entry; resizable by dragging
- [ ] Each suggestion has a copy button that copies to clipboard
- [ ] Panel supports pin/unpin, close, and drag-to-move
- [ ] Panel position and size are remembered across sessions (autosave frame)
- [ ] LLM call failures are handled silently without affecting transcription
- [ ] App builds successfully (xcodebuild)
