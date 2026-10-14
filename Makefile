# ─────────────────────────────────────────────────────────────────────────────
# Single entrypoint for the whole pipeline. Run every target from the REPO ROOT
# on the CONTROL NODE. By default each target runs INSIDE the pinned container
# (portable); set RUNNER=local to use locally-installed tools instead.
#
#   make help          list targets
#   make build         build the portable container
#   make shell         open a shell in the container
#   make discover      step 1: VMware/AWS Transform discovery -> raw inventory
#   make normalize     step 2: raw inventory -> spec.yaml
#   make generate      step 3: spec.yaml -> terraform/ + ansible/
#   make deploy        step 4: terraform apply (-> AWS eu-west-2)
#   make configure     step 5: ansible-playbook (-> new EC2 instances)
#   make dms           step 6: run the DMS data migration
#   make validate      step 7: health checks + migration report
#   make destroy       step 8: terraform destroy (clean rerun)
#   make demo-up       steps 1-7 end to end
#   make demo-down     teardown
# ─────────────────────────────────────────────────────────────────────────────

RUNNER ?= docker
IMAGE  ?= vmware2aws
ENVFILE ?= .env

# Wrap a command so it runs inside the container (default) or locally.
ifeq ($(RUNNER),docker)
  RUN = docker run --rm -it --env-file $(ENVFILE) -v "$(CURDIR)":/work -w /work $(IMAGE)
else
  RUN =
endif

.DEFAULT_GOAL := help

.PHONY: help build shell discover normalize generate deploy configure dms validate destroy demo-up demo-down

help:
	@grep -E '^#   make ' $(MAKEFILE_LIST) | sed 's/^#   /  /'

build:
	docker build -t $(IMAGE) .

shell:
	$(RUN) /bin/bash

discover:
	$(RUN) python3 engine/discover.py --config config.yaml

normalize:
	$(RUN) python3 engine/normalize.py --config config.yaml

generate:
	$(RUN) python3 engine/generate.py --config config.yaml --spec sample-inventory/spec.yaml

deploy:
	$(RUN) sh -c 'cd terraform/landing-zone && terraform init && terraform apply -auto-approve'

configure:
	$(RUN) ansible-playbook -i ansible/inventory.ini ansible/site.yml

dms:
	$(RUN) python3 engine/dms_migrate.py --config config.yaml

validate:
	$(RUN) python3 engine/validate.py --config config.yaml

destroy:
	$(RUN) sh -c 'cd terraform/landing-zone && terraform destroy -auto-approve'

demo-up: generate deploy configure dms validate
	@echo "Demo is up. See docs/ for the narrative."

demo-down: destroy
	@echo "Torn down. Safe to rerun."
