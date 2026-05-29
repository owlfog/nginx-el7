DOCKER ?= docker
IMAGE ?= nginx-rpm-el7:local
VERSION ?= 1.30.2
RELEASE ?= 1
DIST ?= .el7
PAGES_BASE_URL ?=
REPO_DIR ?= dist/repo/el7/x86_64

.PHONY: all image rpm repo pages sign-rpms sign-repo signed-repo smoke clean

all: rpm smoke repo

image:
	$(DOCKER) build -f docker/Dockerfile.el7 -t $(IMAGE) .

rpm: image
	$(DOCKER) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-v "$$(pwd):/work" \
		-w /work \
		-e NGINX_VERSION=$(VERSION) \
		-e NGINX_RELEASE=$(RELEASE) \
		-e DIST=$(DIST) \
		$(IMAGE) ./scripts/build-rpm.sh

repo:
	$(DOCKER) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-v "$$(pwd):/work" \
		-w /work \
		$(IMAGE) ./scripts/create-repo.sh

pages:
	PAGES_BASE_URL="$(PAGES_BASE_URL)" REPO_DIR="$(REPO_DIR)" ./scripts/build-pages.sh

sign-rpms:
	$(DOCKER) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-v "$$(pwd):/work" \
		-w /work \
		-e RPM_GPG_NAME \
		-e RPM_GPG_PRIVATE_KEY_B64 \
		-e RPM_GPG_PRIVATE_KEY_FILE \
		-e RPM_GPG_PUBLIC_KEY_OUT \
		$(IMAGE) ./scripts/sign-rpms.sh

sign-repo:
	$(DOCKER) run --rm \
		--user "$$(id -u):$$(id -g)" \
		-v "$$(pwd):/work" \
		-w /work \
		-e RPM_GPG_NAME \
		-e RPM_GPG_PRIVATE_KEY_B64 \
		-e RPM_GPG_PRIVATE_KEY_FILE \
		-e RPM_GPG_PUBLIC_KEY_OUT \
		$(IMAGE) ./scripts/sign-repo.sh

signed-repo: rpm sign-rpms repo sign-repo pages

smoke:
	$(DOCKER) run --rm \
		-v "$$(pwd):/work:ro" \
		-w /work \
		$(IMAGE) ./scripts/smoke-test-rpm.sh

clean:
	rm -rf build dist
