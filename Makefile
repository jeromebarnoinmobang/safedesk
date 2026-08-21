.PHONY: hote local remote down logs

hote:    ## Prerequis HOTE, une fois par machine (root) : horloge/NTP, nom
	sudo bash scripts/setup-hote.sh

local:   ## Bureau en local (detection GPU automatique, http://localhost:3000)
	@bash scripts/up-local.sh

remote:  ## Deployer derriere un reverse proxy (HTTPS + auth, sans GPU)
	RENDER_PROFILE=zz-no-gpu docker compose -f docker-compose.yml -f docker-compose.remote.yml up -d

down:    ## Tout arreter
	docker compose down

logs:    ## Suivre les logs
	docker compose logs -f