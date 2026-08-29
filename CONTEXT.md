# Agent Session Browser

The Agent Session Browser organizes resumable conversations across My Files
areas and projects without conflating workflow decisions with runtime status.

## Language

**Conversation**:
A resumable Agent Shell session or Codex task shown in the browser.
_Avoid_: Chat buffer, thread row

**Workflow Stage**:
The user's assessment of a conversation as In Progress, Review, Staged, or
Completed. Every active conversation has exactly one workflow stage.
_Avoid_: Runtime status, chat category

**Active Conversation**:
A conversation that remains visible in Active Conversations and in its workflow
stage.
_Avoid_: Running conversation

**Archived Conversation**:
A conversation removed from Active Conversations and all workflow stages but
retained under Archived.
_Avoid_: Completed conversation, deleted conversation
