# iOS apps

## Circle to Search
Google's Circle to Search experience for iPhone: freeze the screen, then circle, highlight or tap anything to search it, with AI answers, translation, QR codes and web search. See [CircleToSearch/SETUP.md](CircleToSearch/SETUP.md).

**Download:** every push to `main` builds an unsigned `.ipa` and publishes it to the [latest release](../../releases/tag/latest). Install it with [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io), which sign it with your Apple ID.

Pick Claude, ChatGPT, Gemini or Grok and paste its API key in the app's Settings. Optionally, a repository secret named `ANTHROPIC_API_KEY` bakes a Claude key into the build.
