# Circle to Search for iPhone

## What you get (matching the Android experience)
| Android Circle to Search | This app |
|---|---|
| Long-press home bar to trigger | Double-tap the back of the phone, the Action Button, Siri ("Circle to Search my screen"), or a Control Center button |
| Screen freezes with a color sweep | Same: the screenshot fills the screen, dims, and a Google-colored shimmer sweeps down |
| Circle anything | Glowing rainbow stroke; the circled area lights up with white corner brackets you can drag to resize |
| Scribble or highlight text | A flat swipe across words highlights them like a highlighter |
| Tap to select | Tapping a word selects it; tapping an object selects the whole object (on-device detection) |
| Results panel slides up | Bottom sheet you can drag up to full screen, while still circling other things above it |
| AI Overview with sources | Claude identifies what you selected, streams an overview word by word, searches the web, and shows source cards |
| "Add to your search" / follow-ups | Ask follow-up questions in the same sheet |
| Copy text, Translate, Search | Copy text, translate the selection, open a Google search, read QR codes, share the crop |
| Translate the whole screen | "Translate" button overlays translated text on every line, on device |
| Ask about the whole screen | "Ask about your screen" bar before you select anything |
| Share an image into it | "Ask About This" in the share sheet of Photos, Safari, etc. |
| Gemini answers | Pick Claude, ChatGPT, Gemini or Grok in Settings |

## Limits Apple imposes (no way around these)
- iOS doesn't let apps draw over other apps, so the overlay works on a screenshot of your screen, not the live app. It looks identical, but the screen behind it doesn't move.
- When you close the overlay, iOS can't jump back to the previous app automatically. Swipe right along the bottom edge of the screen to go straight back.

## 1. Build it
1. On a Mac with Xcode 16+, install XcodeGen: `brew install xcodegen`
2. In this folder run `xcodegen generate`, then open `CircleToSearch.xcodeproj`.
3. Under Signing & Capabilities, pick your team for both targets (CircleToSearch and AskAboutThis). If the bundle ID is taken, change `com.example` in `project.yml` and regenerate.
5. Run it on your iPhone (iOS 18 or later).

## 2. Make the Shortcut
In the Shortcuts app, create a shortcut with two actions:
1. **Take Screenshot**
2. **Circle to Search** (from this app), with Screenshot set to the result of step 1

Name it "Circle to Search".

## 3. Pick your triggers (use as many as you like)
- **Back Tap:** Settings > Accessibility > Touch > Back Tap > Double Tap > Circle to Search
- **Action Button** (iPhone 15 Pro and later): Settings > Action Button > Shortcut > Circle to Search
- **Control Center:** edit Control Center > Add a Control > Shortcut > Circle to Search
- **Siri:** "Circle to Search my screen"

## 4. Using it
- Circle something to search it, swipe across text to highlight it, or tap a word or object.
- Drag the white corners to adjust the selection, and it searches again.
- Drag the results sheet up for more, and type follow-up questions at the bottom.
- Tap Translate at the top to translate everything on screen.

## Choosing the AI (Settings)
Tap the gear on the home screen or in the overlay, then pick **Claude**, **ChatGPT**, **Gemini** or **Grok** and paste that service's API key. Each one keeps its own key and model name, so you can switch any time.

| AI | Get a key | Default model | Web sources |
|---|---|---|---|
| Claude | console.anthropic.com | claude-opus-5-5 | Yes |
| ChatGPT | platform.openai.com/api-keys | gpt-5 | No |
| Gemini | aistudio.google.com/app/apikey (has a free tier) | gemini-2.5-flash | Yes, via Google Search |
| Grok | console.x.ai | grok-4 | No |

- If a provider says the model doesn't exist, type its current model name in Settings.
- Keys only power the AI Overview and follow-ups. Copy text, translation, QR codes, and Google search are free and on device.
- Each service bills per question on your own account, usually around a cent or less.
- Keys are stored on the phone and sent only to the service you picked. For an App Store release, put the keys on your own server instead.

## Files
- `App/`: the app, home screen, and Shortcuts action
- `Shared/`: the overlay, results sheet, on-device detection, translation, and Claude client (used by the app and the share extension)
- `ShareExtension/`: "Ask About This" in the share sheet
- `project.yml`: the Xcode project definition
