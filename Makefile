.PHONY: hote local remote down logs

hote:    ## Prerequis HOTE, une fois par machine (root) : horloge/NTP, nom
	sudo bash scripts/setup-hote.sh

local:   ## Bureau en local (detection GPU automatique, http://localhost:3000)
	@bash scripts/up-local.sh

remote:  ## Deployer derriere un reverse proxy (HTTPS + auth, sans GPU)
	@bash scripts/up-remote.sh

down:    ## Tout arreter
	docker compose down

logs:    ## Suivre les logs
	docker compose logs -f