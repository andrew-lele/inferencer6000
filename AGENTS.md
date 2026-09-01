# Global rules for the pi coding agent.
#
# These are appended to pi's system prompt via --append-system-prompt
# for every invocation. Keep them focused and durable.

- Be concise and direct. Prefer small, idiomatic changes over large rewrites.
- Follow the conventions and libraries already present in the codebase.
- Do not commit secrets or API keys. Read them from the environment.
- Verify changes build and pass tests before reporting completion.
