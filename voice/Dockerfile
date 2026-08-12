# brain-shim : cerveau vocal = `claude -p` (Max) exposé OpenAI-compat. CPU.
# node:22 (debian) : binaire natif claude-code fiable sur glibc.
FROM node:22

# CLI officiel Claude + curl (le hook brain-context en a besoin).
RUN npm install -g @anthropic-ai/claude-code \
 && apt-get update && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY brain-shim.mjs ./

# Config Claude (hooks + settings) pour l'utilisateur NON-root `node` (uid 1000,
# fourni par l'image). Non-root est OBLIGATOIRE : `claude` refuse
# --permission-mode bypassPermissions en root.
COPY claude-config/ /home/node/.claude/
RUN chmod +x /home/node/.claude/hooks/*.sh \
 && chown -R node:node /home/node/.claude /app

ENV HOME=/home/node \
    CLAUDE_CONFIG_DIR=/home/node/.claude \
    BRAIN_SHIM_PORT=8088
USER node
CMD ["node", "brain-shim.mjs"]
