.PHONY: local deploy down logs

local:   ## Bureau en local (detection GPU auto, http://localhost:3000)
	@bash scripts/up-local.sh

deploy:  ## Deployer sur le VPS derriere Traefik (streame, HTTPS + auth, sans GPU)
	RENDER_PROFILE=zz-no-gpu docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d

down:    ## Tout arreter
	docker compose down

logs:    ## Suivre les logs
	docker compose logs -f