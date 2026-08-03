.PHONY: local deploy down logs

local:   ## Bureau en local (http://localhost:3000, ne charge pas le VPS)
	docker compose -f docker-compose.yml -f docker-compose.local.yml up -d

deploy:  ## Déployer sur le VPS derrière Traefik (streamé, HTTPS + auth)
	docker compose -f docker-compose.yml -f docker-compose.vps.yml up -d

down:    ## Tout arrêter
	docker compose down

logs:    ## Suivre les logs
	docker compose logs -f
