#!/usr/bin/env python3
"""Obligation POSITIVE de capitalisation : le tour ne peut pas se terminer si
Jerome a donne une connaissance durable et que rien n'a ete ecrit dans le
second-brain.

Pourquoi ce hook existe (20/08/2026) : la garde `no-local-memory.sh` est une
INTERDICTION — elle empeche la mauvaise destination, elle ne cree pas l'acte.
Jerome l'a pointe : « c'est pas justement produire un comportement obligatoire ?
la tu produis un truc que tu peux contourner ». Un graphe LangGraph produit bien
une obligation (le noeud est une arete, pas un choix) mais seulement dans son
perimetre ; il ne gouverne pas une conversation. Dans une conversation, les deux
seuls mecanismes non contournables sont : refuser un outil (deny) et refuser la
FIN du tour. C'est le second.

Precision volontairement haute, rappel volontairement bas : on ne declenche que
sur des marqueurs explicites. Un faux positif bloque Jerome pour rien, ce qui
serait pire que la fuite qu'on corrige.
"""
import json
import os
import re
import sys

# Marqueurs explicites d'une connaissance durable. Chacun est une formulation par
# laquelle Jerome ETABLIT une regle, corrige un comportement, ou demande une
# memorisation — pas une simple demande de travail.
MARQUEURS = re.compile(
    r"""(
        retiens | rappelle[- ]toi | souviens[- ]toi | note\s+(ca|cela|le)
      | n'?oublie\s+pas | garde\s+en\s+m[ée]moire | m[ée]morise
      | je\s+t'?(ai|avais)\s+(deja\s+)?(dit|demand[ée]|expliqu[ée])
      | ne\s+(re)?fais\s+plus | arr[êe]te\s+de
      | (c'?est|voila)\s+(une\s+)?r[èe]gle | r[èe]gle\s*:
      | (a|à)\s+chaque\s+fois | syst[ée]matiquement
      | encre[rz]?\s | ancre[rz]?\s
    )""",
    re.IGNORECASE | re.VERBOSE,
)

ECRITURES_BRAIN = ("create_memory", "update_memory", "set_user_fact", "update_user_fact")


def transcript_path(payload):
    """Chemin du transcript : fourni par le hook, sinon retrouve par session_id."""
    direct = payload.get("transcript_path")
    if direct and os.path.exists(direct):
        return direct
    sid = payload.get("session_id")
    if not sid:
        return None
    for root, _dirs, files in os.walk("/config/.claude/projects"):
        if f"{sid}.jsonl" in files:
            return os.path.join(root, f"{sid}.jsonl")
    return None


def texte_utilisateur(entry):
    """Texte d'un message utilisateur REEL (on ignore les injections systeme)."""
    msg = entry.get("message") or {}
    if entry.get("type") != "user" or msg.get("role") != "user":
        return None
    if entry.get("isMeta") or entry.get("isCompactSummary"):
        return None
    content = msg.get("content")
    if isinstance(content, str):
        parts = [content]
    elif isinstance(content, list):
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        # Un tool_result n'est pas une parole de Jerome.
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content) and not any(parts):
            return None
    else:
        return None
    texte = "\n".join(parts)
    # Les rappels systeme ne sont pas de la parole utilisateur.
    if "<system-reminder>" in texte and len(texte.strip()) < 400:
        return None
    return texte


def outils_appeles(entry):
    msg = entry.get("message") or {}
    if msg.get("role") != "assistant":
        return []
    content = msg.get("content")
    if not isinstance(content, list):
        return []
    return [b.get("name", "") for b in content if isinstance(b, dict) and b.get("type") == "tool_use"]


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # payload illisible : on ne bloque jamais sur un doute technique

    # Deja bloque une fois sur ce tour : ne pas boucler.
    if payload.get("stop_hook_active"):
        sys.exit(0)

    path = transcript_path(payload)
    if not path:
        sys.exit(0)

    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lignes = [json.loads(l) for l in fh if l.strip().startswith("{")]
    except Exception:
        sys.exit(0)

    # Le tour courant = tout ce qui suit la derniere parole reelle de Jerome.
    dernier = None
    for i, entry in enumerate(lignes):
        if texte_utilisateur(entry) is not None:
            dernier = i
    if dernier is None:
        sys.exit(0)

    parole = texte_utilisateur(lignes[dernier]) or ""
    if not MARQUEURS.search(parole):
        sys.exit(0)  # rien de durable enonce : le tour peut finir

    for entry in lignes[dernier:]:
        if any(o.endswith(ECRITURES_BRAIN) or any(w in o for w in ECRITURES_BRAIN)
               for o in outils_appeles(entry)):
            sys.exit(0)  # capitalise : le tour peut finir

    extrait = " ".join(parole.split())[:180]
    json.dump({
        "decision": "block",
        "reason": (
            "CAPITALISATION OBLIGATOIRE — ce tour ne peut pas se terminer.\n\n"
            f"Jerome a enonce une connaissance durable : « {extrait} »\n\n"
            "Aucune ecriture dans le second-brain n'a eu lieu depuis. Avant de "
            "conclure : appelle mcp__second-brain__recall pour verifier qu'elle "
            "n'existe pas deja, puis mcp__second-brain__create_memory "
            "(type feedback pour une regle de travail, decision pour un choix "
            "technique) ou update_memory si elle existe. Ecris le POURQUOI et le "
            "COMMENT L'APPLIQUER, pas seulement la regle. Interdit : la memoire "
            "locale de Claude, une note dans un fichier, ou repondre sans ecrire."
        ),
    }, sys.stdout)


if __name__ == "__main__":
    main()
