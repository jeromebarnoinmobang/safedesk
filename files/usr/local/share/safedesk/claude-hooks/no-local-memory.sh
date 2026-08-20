#!/bin/bash
# Garde déterministe : la mémoire de Jérôme vit dans le SECOND-BRAIN, jamais sur
# une machine. Toute écriture dans un répertoire `memory/` local de Claude est
# refusée, avec l'outil de remplacement dans le motif du refus.
#
# Pourquoi un hook et pas une consigne : le 17/08/2026 une règle de travail
# (« moins de preuve ») a été écrite en local et est restée invisible pour tous
# les autres brains pendant 3 jours. Une consigne dépend de l'initiative du
# modèle ; un hook n'en dépend pas. Voir la mémoire second-brain
# « garde mémoire locale interdite ».
#
# Entrée : JSON du hook PreToolUse sur stdin. Sortie : rien (autorisé) ou une
# décision `deny` sur stdout.

payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -z "$path" ] && exit 0

case "$path" in
  */.claude/projects/*/memory/*|*/.claude/memory/*|*/.claude/*/MEMORY.md)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "MEMOIRE LOCALE INTERDITE. La memoire de Jerome vit dans le second-brain, pas sur une machine — sinon la connaissance est invisible pour ses autres brains (Claude Desktop, OpenWork, Cowork, orchestrator-brain). Utilise mcp__second-brain__create_memory (ou update_memory apres un recall pour eviter un doublon). Types utiles : feedback (regle de travail), decision, project, observation, reference."
      },
      systemMessage: "Ecriture en memoire locale refusee → a ecrire dans le second-brain."
    }'
    ;;
  *)
    exit 0
    ;;
esac
