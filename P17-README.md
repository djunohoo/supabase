# Phaze17 Supabase Fork

> "We don't just use the platform. We become the platform."

## What This Is

This is the official Phaze17 (P17) fork of the Supabase monorepo. It is not a passive fork. It is a living, breathing customized infrastructure layer built to power the entire P17 ecosystem of applications, tools, and services.

We architect here. We build here. We ship from here.

---

## Branch Strategy

| Branch | Purpose |
|---|---|
| `master` | Upstream sync only. Never build here. |
| `p17-main` | P17 stable base. All ecosystem-wide customizations live here. |
| `p17-<project>` | Per-project radical customizations. Branch from `p17-main`. |

---

## P17 Ecosystem

This fork serves as the backend backbone for:

- **Doc Jock** — AI-powered document ingestion, consolidation, and chat
- **Phaze17.com** — Main platform and SaaS dashboard
- **MetaCrate** — Local file organization and intelligence
- **C17** — Autonomous IT orchestration agent
- ...and whatever we decide to build next

---

## Conventions

- All P17-specific database tables are prefixed per project (e.g. `dj_*` for Doc Jock)
- RLS policies are non-negotiable — every table ships with them
- DEV_MODE auth bypass is allowed in local dev only — never in production
- Docker is a last resort. We don't lead with it.
- Ollama is our local AI layer. Gemini is our cloud fallback.

---

## Staying in Sync with Upstream

Periodically pull upstream Supabase changes into `master`, then merge `master` → `p17-main`. Do this on major upstream releases at minimum. The further we drift without managed merges, the more it hurts later.

---

## Architects

Built and maintained by the P17 team.

*Other dev teams look on in envy. As they should.*
