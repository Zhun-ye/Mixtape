---
allowed-tools: Bash(git:*)
description: Commit changes with auto-generated or custom messages
model: haiku
---

# Commit Command

Commit changes with auto-generated or custom messages

## Usage
```
@commit [message]
```

## Description
This command will:
1. Stage all changes with `git add .`
2. If a message is provided, use it as the commit message
3. If no message is provided, analyze staged changes and generate a one-line commit message
4. Commit the changes without any Claude authorship attribution

## Behavior
- **With message**: `@commit Fix login validation` → Uses the provided message exactly (quotes optional)
- **Without message**: `@commit` → Analyzes changes and generates appropriate message

## Auto-generated Message Requirements
When no message is provided, the generated message will:
- Be one-line only
- Focus on architectural improvements (moving logic from Views to ViewModels)
- Mention elimination of hardcoded values when applicable
- Follow format: "Refactor [component]: move business logic to ViewModels and use dynamic [improvement]"
- No Claude authorship or Co-Authored-By tags
- Professional, clean commit message

## Examples
- `@commit "Add user authentication"` → Uses exact message: "Add user authentication"
- `@commit` → Analyzes changes and generates: "Refactor payment system: move business logic to ViewModels and use dynamic currency"

## Implementation
1. Check if a commit message argument is provided
2. If yes, use the provided message for the commit
3. If no, analyze the current git staged changes and generate a one-line commit message that describes the main architectural improvement, focusing on moving business logic to ViewModels and replacing hardcoded values with dynamic ones
4. Execute `git add .` followed by `git commit -m "[message]"`