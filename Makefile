.PHONY: install install-interactive uninstall run

install:
	./install.sh

install-interactive:
	./install.sh --interactive

uninstall:
	./uninstall.sh

# Roda comando shell direto do repo, sem instalar. Ex: make run CMD=devstack-rollout-crash-pods ARGS="-n staging"
run:
	@id="$(CMD)"; \
	if [ -z "$$id" ]; then \
		echo "uso: make run CMD=<id> [ARGS=\"...\"]"; \
		echo ""; \
		echo "ids disponíveis:"; \
		jq -r '.[] | select(.type == "shell") | "  " + .id' catalog.json; \
		exit 1; \
	fi; \
	path="$$(jq -r --arg id "$$id" '.[] | select(.id == $$id) | .path' catalog.json)"; \
	entry="$$(jq -r --arg id "$$id" '.[] | select(.id == $$id) | .entry' catalog.json)"; \
	if [ -z "$$path" ]; then \
		echo "comando '$$id' não encontrado no catalog.json"; \
		echo ""; \
		echo "ids disponíveis:"; \
		jq -r '.[] | select(.type == "shell") | "  " + .id' catalog.json; \
		exit 1; \
	fi; \
	root="$$(pwd)"; \
	bash -c "for f in shell/_lib/*.sh; do source \"\$$f\"; done; source <(sed 's#{{ROOT}}#$$root#g' '$$path'); $$entry $(ARGS)"
