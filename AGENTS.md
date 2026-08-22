## Communication & Documentation

- Lead with the most important relevant information and omit anything unnecessary or repeated.
- Use clear structure, familiar words, and concise sentences.
- Explain the main idea simply before adding necessary detail.
- Keep information accurate.
- Make documented rules specific and verifiable.
- In documentation, put each prose sentence on its own source line.
- Draw diagrams using Mermaid syntax.

## 語言與在地化

- 所有檔案均使用正體中文。
- 應用程式介面使用正體中文。
- 用詞以台灣慣用詞為主。

## 紫微斗數流派

- 以三合派為主，中州派為輔。

## 設計風格

- 應用程式採用極簡風格（Minimalist Style）。

## Code Style

- Follow KISS (Keep It Simple) and YAGNI (You Aren't Gonna Need It).
- Prefer simple, minimal solutions over unnecessary complexity.
- Split source files over 1,000 lines along clear responsibility boundaries, or document why they must remain intact.

## Execution

- Ask at most one clarifying question per turn, and present options as a numbered list.

## Git & GitHub

- Format branch names as `narumi/<type>/<short-description>` using lowercase kebab-case.
- Do not use blanket staging such as `git add -A`; stage only intended paths.
- Format commit message subjects as Conventional Commits: `<type>[(<scope>)][!]: <description>`.
- Never change Git `user.name` or `user.email` unless explicitly requested.
- Do not add `Co-Authored-By` trailers (or any other agent-attribution trailer) to commit messages unless the user explicitly asks for one. This overrides per-project guidelines that default-include such a trailer.
- Always sign commits.
- Format pull request titles as `<type>[(<scope>)][!]: <description>` and summarize the pull request's overall outcome.
