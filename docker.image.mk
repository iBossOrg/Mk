### SHELL ######################################################################

# Replace Debian Almquist Shell with Bash
ifeq ($(realpath $(SHELL)),/bin/dash)
SHELL   		:= /bin/bash
endif

# Exit immediately if a command exits with a non-zero exit status
# TODO: .SHELLFLAGS does not exists on obsoleted macOS X-Code make
# .SHELLFLAGS		= -ec
SHELL			+= -e

### GITHUB #####################################################################

# GitHub repository
# git config --get remote.origin.url
# - https://github.com/sicz/docker-baseimage.git
# - git@github.com:sicz/docker-baseimage.git
GITHUB_URL		?= $(shell \
				git config --get remote.origin.url | \
				sed -E	-e "s|^git@github.com:|https://github.com/|" \
					-e "s|\.git$$||" \
			)
ifeq ($(GITHUB_URL),)
$(error "Not a git repository (or any of the parent directories)")
endif

GITHUB_USER		?= $(notdir $(shell dirname $(GITHUB_URL)))
GITHUB_REPOSITORY	?= $(notdir $(GITHUB_URL))

# All modifications are commited
ifeq ($(shell git status --porcelain),)
GIT_REVISION		?= $(shell git rev-parse --short HEAD)
# Modifications are not commited
else
GIT_REVISION		?= $(shell git rev-parse --short HEAD)-devel
endif

# Build date
BUILD_DATE		?= $(shell date -u "+%Y-%m-%dT%H:%M:%SZ")

### PROJECT_DIRS ###############################################################

# Project directories
PROJECT_DIR		?= $(CURDIR)
BUILD_DIR		?= $(PROJECT_DIR)
TEST_DIR		?= $(BUILD_DIR)
VARIANT_DIR		?= $(BUILD_DIR)
DOCKER_IMAGE_DEPOT	?= $(PROJECT_DIR)

### BASE_IMAGE #################################################################

# Baseimage name
BASE_IMAGE		?= $(BASE_IMAGE_NAME):$(BASE_IMAGE_TAG)

### DOCKER_IMAGE ###############################################################

# Docker image name
DOCKER_VENDOR		?= $(shell echo $(GITHUB_USER) | tr '[:upper:]' '[:lower:]')
DOCKER_NAME		?= $(shell echo $(GITHUB_REPOSITORY) | sed -E -e "s|^docker-||" | tr '[:upper:]' '[:lower:]')
DOCKER_IMAGE_DESC	?= $(GITHUB_USER)/$(GITHUB_REPOSITORY)
DOCKER_IMAGE_TAG	?= latest
DOCKER_IMAGE_URL	?= $(GITHUB_URL)

DOCKER_IMAGE_NAME	?= $(DOCKER_VENDOR)/$(DOCKER_NAME)
DOCKER_IMAGE		?= $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)


### DOCKER_BUILD ###############################################################

# Dockerfile name
DOCKER_FILE		?= Dockerfile
BUILD_DOCKER_FILE	?= $(abspath $(VARIANT_DIR)/$(DOCKER_FILE))

# Build image with tags
BUILD_OPTS		+= --tag $(DOCKER_IMAGE) \
			   $(foreach TAG,$(DOCKER_IMAGE_TAGS),--tag $(DOCKER_IMAGE_NAME):$(TAG)) \
			   --label org.opencontainers.image.title="$(DOCKER_IMAGE_NAME)" \
			   --label org.opencontainers.image.version="$(DOCKER_IMAGE_TAG)" \
			   --label org.opencontainers.image.description="$(DOCKER_IMAGE_DESC)" \
			   --label org.opencontainers.image.url="$(DOCKER_IMAGE_URL)" \
			   --label org.opencontainers.image.source="$(GITHUB_URL)"

# Docker Layer Caching
DOCKER_IMAGE_ID		= $(shell docker inspect --format '{{.Id}}' $(DOCKER_IMAGE) 2> /dev/null)
ifneq ($(DOCKER_IMAGE_ID),)
DOCKER_IMAGE_CREATED	= $(shell docker inspect --format '{{index .Config.Labels "org.opencontainers.image.created"}}' $(DOCKER_IMAGE))
DOCKER_IMAGE_REVISION	= $(shell docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' $(DOCKER_IMAGE))
BUILD_OPTS		+= --cache-from $(DOCKER_IMAGE)
else
DOCKER_IMAGE_CREATED	= $(BUILD_DATE)
DOCKER_IMAGE_REVISION	= $(GIT_REVISION)
endif
BUILD_OPTS		+= --label org.opencontainers.image.created=$(DOCKER_IMAGE_CREATED) \
			   --label org.opencontainers.image.revision=$(DOCKER_IMAGE_REVISION)

# Use http proxy when building the image
ifdef HTTP_PROXY
BUILD_OPTS		+= --build-arg HTTP_PROXY=$(http_proxy)
else ifdef http_proxy
BUILD_OPTS		+= --build-arg HTTP_PROXY=$(HTTP_PROXY)
endif

# Docker image build variables
BUILD_OPTS		+= $(foreach VAR,$(BUILD_VARS),--build-arg "$(VAR)=$($(VAR))")
override BUILD_VARS	+= BASE_IMAGE \
			   BASE_IMAGE_NAME \
			   BASE_IMAGE_TAG \
			   DOCKER_IMAGE \
			   DOCKER_IMAGE_NAME \
			   DOCKER_IMAGE_TAG \
			   DOCKER_NAME \
			   DOCKER_VENDOR \
			   DOCKER_IMAGE_DESC \
			   DOCKER_IMAGE_URL \
			   DOCKER_REGISTRY \
			   GITHUB_REPOSITORY \
			   GITHUB_URL \
			   GITHUB_USER

#### DOCKER_COMPOSE ############################################################

# Hi-level targets for creating and starting containers
CREATE_TARGET		?= create
START_TARGET		?= start
STOP_TARGET		?= stop
RM_TARGET		?= rm

# Unique project id
CONTAINER_ID_FILE	?= .docker-container-id
CONTAINER_ID		?= $(shell \
				if [ -e $(CONTAINER_ID_FILE) ]; then \
					cat $(CONTAINER_ID_FILE); \
				else \
					openssl rand -hex 4; \
				fi \
			   )

# Docker service name
SERVICE_NAME		?= $(shell echo $(DOCKER_NAME) | sed -E -e "s/[^[:alnum:]_]+/_/g")

# Docker Compose project name
COMPOSE_NAME		?= $(CONTAINER_ID)
COMPOSE_PROJECT_NAME	?= $(COMPOSE_NAME)

# Docker Compose service name
COMPOSE_SERVICE_NAME	?= $(SERVICE_NAME)

# Docker container name
CONTAINER_NAME		?= $(CONTAINER_ID)_$(COMPOSE_SERVICE_NAME)_1
TEST_CONTAINER_NAME	?= $(CONTAINER_ID)_$(TEST_SERVICE_NAME)_1

# Support multiple configurations of the Docker Compose
ifneq ($(DOCKER_CONFIGS),)
DOCKER_CONFIG_FILE	?= .docker-config
DOCKER_CONFIG		?= $(shell \
				if [ -e $(DOCKER_CONFIG_FILE) ]; then \
					cat $(DOCKER_CONFIG_FILE); \
				else \
					echo "default"; \
				fi \
			   )
endif

# Docker Compose file
ifeq ($(DOCKER_CONFIG),)
COMPOSE_FILES		?= docker-compose.yml
else
COMPOSE_FILES		?= docker-compose.yml \
			   docker-compose.$(DOCKER_CONFIG).yml
endif
COMPOSE_FILE		?= $(shell echo "$(foreach COMPOSE_FILE,$(COMPOSE_FILES),$(abspath $(PROJECT_DIR)/$(COMPOSE_FILE)))" | tr ' ' ':')

# Variables used in the Docker Compose file
override COMPOSE_VARS	+= $(BUILD_VARS) \
			   COMPOSE_PROJECT_NAME \
			   COMPOSE_FILE \
			   PROJECT_DIR \
			   BUILD_DIR \
			   CURDIR \
			   TEST_CMD \
			   TEST_DIR \
			   TEST_ENV_FILE \
			   TEST_IMAGE \
			   TEST_PROJECT_DIR \
			   VARIANT_DIR

# Docker Compose command
COMPOSE_CMD		?= touch $(TEST_ENV_FILE); \
			   export $(foreach DOCKER_VAR,$(COMPOSE_VARS),$(DOCKER_VAR)="$($(DOCKER_VAR))"); \
			   docker-compose

# Docker Compose create options
COMPOSE_CREATE_OPTS	+= --no-build

# Docker Compose up options
COMPOSE_UP_OPTS		+= -d --remove-orphans $(COMPOSE_CREATE_OPTS)

# Docker Compose down options
COMPOSE_RM_OPTS		+= --remove-orphans -v

### TEST #######################################################################

# Docker test image
TEST_IMAGE_NAME		?= sicz/dockerspec
TEST_IMAGE_TAG		?= latest
TEST_IMAGE		?= $(TEST_IMAGE_NAME):$(TEST_IMAGE_TAG)

# Docker Compose/Swarm test service name
TEST_SERVICE_NAME	?= test

# Variables used in the test conatainer
override TEST_VARS	+= CONTAINER_NAME \
			   SERVICE_NAME \
			   SPEC_OPTS
TEST_CONTAINER_VARS	?= $(BUILD_VARS) \
			   $(TEST_VARS)
TEST_COMPOSE_VARS	?= $(COMPOSE_VARS) \
			   $(TEST_VARS) \
			   TEST_CMD
TEST_STACK_VARS		?= $(STACK_VARS) \
			   $(TEST_VARS) \
			   TEST_CMD

# Classic Docker test container options
TEST_CONTAINER_OPTS	+= --interactive \
			   --tty \
			   --name $(TEST_CONTAINER_NAME) \
			   $(foreach VAR,$(TEST_CONTAINER_VARS),--env "$(VAR)=$($(VAR))") \
			   --volume /var/run/docker.sock:/var/run/docker.sock \
			   --volume $(abspath $(TEST_DIR))/.rspec:/root/.rspec \
			   --volume $(abspath $(TEST_DIR))/spec:/root/spec \
			   --workdir /root/$(TEST_DIR) \
			   --rm

# File containing environment variables
TEST_ENV_FILE		?= $(CURDIR)/.docker-test-env

# Use the project dir as the host volume if Docker host is local
ifeq ($(DOCKER_HOST),)
TEST_PROJECT_DIR	?= $(PROJECT_DIR)
endif

# Test command
TEST_CMD		?= rspec

# Rspec output format
# RSPEC_FORMAT		?= documentation
ifneq ($(RSPEC_FORMAT),)
override SPEC_OPTS	+= --format $(RSPEC_FORMAT)
endif

# Allow RSpec colorized output without allocated tty
ifeq ($(DOCKER_HOST),)
override SPEC_OPTS	+= --tty
endif

# CircleCI configuration file
CIRCLECI_CONFIG_FILE	?= $(PROJECT_DIR)/.circleci/config.yml

### WAIT #######################################################################

# Wait service name
WAIT_SERVICE_NAME	?= wait

### SHELL ######################################################################

# Docker shell options and command
SHELL_OPTS		+= --interactive --tty
SHELL_CMD		?= /docker-entrypoint.sh /bin/sh --login

# Run the shell as an user
ifdef CONTAINER_USER
SHELL_OPTS		+= --user $(CONTAINER_USER)
endif

### DOCKER_REGISTRY ############################################################

# Docker registry
DOCKER_REGISTRY		?= docker.io

# Tags that will be pushed/pulled to/from Docker repository
DOCKER_PUSH_TAGS	?= $(DOCKER_IMAGE_TAG) $(DOCKER_IMAGE_TAGS)
DOCKER_PULL_TAGS	?= $(DOCKER_PUSH_TAGS)

### DOCKER_VERSION #############################################################

# Make targets propagated to all Docker image versions
DOCKER_ALL_VERSIONS_TARGETS += docker-pull \
			   docker-pull-image \
			   docker-pull-dependencies \
			   docker-pull-testimage \
			   docker-push

################################################################################

# Echo with -n support
ECHO			= /bin/echo

################################################################################

# Required variables
ifndef DOCKER_VENDOR
$(error Unable to determine Docker project name. Define DOCKER_VENDOR.)
endif
ifndef DOCKER_NAME
$(error Unable to determine Docker image name. Define DOCKER_NAME.)
endif
ifndef DOCKER_IMAGE_TAG
$(error Unable to determine Docker image tag. Define DOCKER_IMAGE_TAG.)
endif
ifndef BASE_IMAGE_NAME
$(error Unable to determine base image name. Define BASE_IMAGE_NAME.)
endif
ifndef BASE_IMAGE_TAG
$(error Unable to determine base image tag. Define BASE_IMAGE_TAG.)
endif

################################################################################

# Display the make variables
MAKE_VARS		?= GITHUB_MAKE_VARS \
			   BASE_IMAGE_MAKE_VARS \
			   DOCKER_IMAGE_MAKE_VARS \
			   BUILD_MAKE_VARS \
			   EXECUTOR_MAKE_VARS \
			   SHELL_MAKE_VARS \
			   DOCKER_REGISTRY_MAKE_VARS

define GITHUB_MAKE_VARS
GITHUB_URL:		$(GITHUB_URL)
GITHUB_USER:		$(GITHUB_USER)
GITHUB_REPOSITORY:	$(GITHUB_REPOSITORY)

BUILD_DATE:		$(BUILD_DATE)
GIT_REVISION:		$(GIT_REVISION)
endef
export GITHUB_MAKE_VARS

define BASE_IMAGE_MAKE_VARS
BASE_IMAGE_NAME:	$(BASE_IMAGE_NAME)
BASE_IMAGE_TAG:		$(BASE_IMAGE_TAG)
BASE_IMAGE:		$(BASE_IMAGE)
endef
export BASE_IMAGE_MAKE_VARS

define DOCKER_IMAGE_MAKE_VARS
DOCKER_VENDOR:		$(DOCKER_VENDOR)
DOCKER_IMAGE_DESC:	$(DOCKER_IMAGE_DESC)
DOCKER_IMAGE_URL:	$(DOCKER_IMAGE_URL)

DOCKER_NAME:		$(DOCKER_NAME)
DOCKER_IMAGE_TAG:	$(DOCKER_IMAGE_TAG)
DOCKER_IMAGE_TAGS:	$(DOCKER_IMAGE_TAGS)
DOCKER_IMAGE_NAME:	$(DOCKER_IMAGE_NAME)
DOCKER_IMAGE:		$(DOCKER_IMAGE)
endef
export DOCKER_IMAGE_MAKE_VARS

define BUILD_MAKE_VARS
CURDIR:			$(CURDIR)
PROJECT_DIR:		$(PROJECT_DIR)

DOCKER_FILE:		$(DOCKER_FILE)
VARIANT_DIR:		$(VARIANT_DIR)
BUILD_DOCKER_FILE:	$(BUILD_DOCKER_FILE)
BUILD_DIR:		$(BUILD_DIR)
BUILD_VARS:		$(BUILD_VARS)
BUILD_OPTS:		$(BUILD_OPTS)
endef
export BUILD_MAKE_VARS

define EXECUTOR_MAKE_VARS
CONTAINER_ID:		$(CONTAINER_ID)
CONTAINER_ID_FILE:	$(CONTAINER_ID_FILE)

DOCKER_CONFIGS:		$(DOCKER_CONFIGS)
DOCKER_CONFIG:		$(DOCKER_CONFIG)
DOCKER_CONFIG_FILE:	$(DOCKER_CONFIG_FILE)

CREATE_TARGET:		$(CREATE_TARGET)
START_TARGET:		$(START_TARGET)
RM_TARGET:		$(RM_TARGET)

SERVICE_NAME:		$(SERVICE_NAME)
CONTAINER_NAME:		$(CONTAINER_NAME)

COMPOSE_FILES:		$(COMPOSE_FILES)
COMPOSE_FILE:		$(COMPOSE_FILE)
COMPOSE_NAME:		$(COMPOSE_NAME)
COMPOSE_PROJECT_NAME:	$(COMPOSE_PROJECT_NAME)
COMPOSE_SERVICE_NAME:	$(COMPOSE_SERVICE_NAME)
COMPOSE_VARS:		$(COMPOSE_VARS)
COMPOSE_CMD:		$(COMPOSE_CMD)
COMPOSE_CONFIG_OPTS: 	$(COMPOSE_CONFIG_OPTS)
COMPOSE_UP_OPTS:	$(COMPOSE_UP_OPTS)
COMPOSE_PS_OPTS:	$(COMPOSE_PS_OPTS)
COMPOSE_LOGS_OPTS: 	$(COMPOSE_LOGS_OPTS)
COMPOSE_STOP_OPTS: 	$(COMPOSE_STOP_OPTS)
COMPOSE_RM_OPTS:	$(COMPOSE_RM_OPTS)

CIRCLECI:		$(CIRCLECI)
TEST_IMAGE_NAME:	$(TEST_IMAGE_NAME)
TEST_IMAGE_TAG:		$(TEST_IMAGE_TAG)
TEST_IMAGE:		$(TEST_IMAGE)
TEST_DIR:		$(TEST_DIR)
TEST_ENV_FILE:		$(TEST_ENV_FILE)
TEST_SERVICE_NAME:	$(TEST_SERVICE_NAME)
TEST_CONTAINER_NAME:	$(TEST_CONTAINER_NAME)
TEST_VARS:		$(TEST_VARS)
TEST_COMPOSE_VARS:	$(TEST_COMPOSE_VARS)

TEST_CMD:		$(TEST_CMD)
RSPEC_FORMAT:		$(RSPEC_FORMAT)
SPEC_OPTS:		$(SPEC_OPTS)
endef
export EXECUTOR_MAKE_VARS

define SHELL_MAKE_VARS
SHELL_OPTS:		$(SHELL_OPTS)
SHELL_CMD:		$(SHELL_CMD)
endef
export SHELL_MAKE_VARS

define DOCKER_REGISTRY_MAKE_VARS
DOCKER_REGISTRY:	$(DOCKER_REGISTRY)
DOCKER_PUSH_TAGS:	$(DOCKER_PUSH_TAGS)
DOCKER_PULL_TAGS:	$(DOCKER_PULL_TAGS)
DOCKER_IMAGE_DEPENDENCIES: $(DOCKER_IMAGE_DEPENDENCIES)
endef
export DOCKER_REGISTRY_MAKE_VARS

### BUILD_TARGETS ##############################################################

# Build a new image with using the Docker layer caching
.PHONY: docker-build
docker-build:
	@set -eo pipefail; \
	$(ECHO) "Building image $(DOCKER_IMAGE)"; \
	docker build $(BUILD_OPTS) -f $(BUILD_DOCKER_FILE) $(BUILD_DIR); \
	BUILD_ID="`docker inspect --format '{{.Id}}' $(DOCKER_IMAGE)`"; \
	if [ -n "$(DOCKER_IMAGE_ID)" -a "$(DOCKER_IMAGE_ID)" != "$${BUILD_ID}" ]; then \
		$(ECHO) "Image changed, building with current labels"; \
		docker build $(BUILD_OPTS) \
			--label org.opencontainers.image.created=$(BUILD_DATE) \
			--label org.opencontainers.image.revision=$(GIT_REVISION) \
			-f $(BUILD_DOCKER_FILE) $(BUILD_DIR); \
	fi

# Build a new image without using the Docker layer caching
.PHONY: docker-rebuild
docker-rebuild:
	@set -eo pipefail; \
	$(ECHO) "Rebuilding image $(DOCKER_IMAGE)"; \
	docker build $(BUILD_OPTS) \
		--label org.opencontainers.image.created=$(BUILD_DATE) \
		--label org.opencontainers.image.revision=$(GIT_REVISION) \
		-f $(BUILD_DOCKER_FILE) --no-cache $(BUILD_DIR)

# Tag the Docker image
.PHONY: docker-tag
docker-tag:
ifneq ($(DOCKER_IMAGE_TAGS),)
	@$(ECHO) "Tagging image with tags $(DOCKER_IMAGE_TAGS)"
	@$(foreach TAG,$(DOCKER_IMAGE_TAGS), \
		docker tag $(DOCKER_IMAGE) $(DOCKER_IMAGE_NAME):$(TAG); \
	)
endif

### EXECUTOR_TARGETS ###########################################################

# Display the Docker image version
.PHONY: display-version-header
display-version-header:
	@$(ECHO)
	@$(ECHO) "===> $(DOCKER_IMAGE)"
	@$(ECHO)

# Save the Docker executor id
$(CONTAINER_ID_FILE):
	@$(ECHO) $(CONTAINER_ID) > $(CONTAINER_ID_FILE)

# Display the current configuration name
.PHONY: docker-config
docker-config:
ifneq ($(DOCKER_CONFIGS),)
	@$(ECHO) "Using $(DOCKER_CONFIG) configuration"
endif

# Display the configuration file
.PHONY: docker-config-file
docker-config-file: docker-config
	@$(COMPOSE_CMD) config $(COMPOSE_CONFIG_OPTS)

# Display the make variables
.PHONY: docker-makevars
docker-makevars: docker-config
	@set -eo pipefail; \
	 ( \
		$(foreach DOCKER_VAR,$(MAKE_VARS), \
			$(ECHO) "$${$(DOCKER_VAR)}"; \
			$(ECHO); \
		) \
	 ) | sed -E \
		-e $$'s/ +-/\\\n\\\t\\\t\\\t-/g' \
		-e $$'s/ +([A-Z][A-Z]+)/\\\n\\\t\\\t\\\t\\1/g' \
		-e $$'s/(;) */\\1\\\n\\\t\\\t\\\t/g'

# Set the Docker executor configuration
.PHONY: set-docker-config
set-docker-config: $(RM_TARGET)
ifneq ($(DOCKER_CONFIGS),)
ifeq ($(filter $(DOCKER_CONFIG),$(DOCKER_CONFIGS)),)
	$(error Unknown Docker Compose configuration "$(DOCKER_CONFIG)")
endif
	@$(ECHO) $(DOCKER_CONFIG) > $(DOCKER_CONFIG_FILE)
	@$(ECHO) "Setting Docker Compose configuration to $(DOCKER_CONFIG)"
else
	$(error Docker Compose does not support multiple configs)
endif

# Remove the containers and then run them fresh
.PHONY: docker-up
docker-up:
	@$(MAKE) $(RM_TARGET) $(START_TARGET)

# Create the containers
.PHONY: docker-create
docker-create: $(CONTAINER_ID_FILE) docker-config .docker-compose-create
	@true

.docker-compose-create:
	@cd $(PROJECT_DIR) && \
	 $(COMPOSE_CMD) up --no-start $(COMPOSE_CREATE_OPTS) $(COMPOSE_SERVICE_NAME)
	@$(ECHO) $(COMPOSE_SERVICE_NAME) > $@

# Start the containers
.PHONY: docker-start
docker-start: docker-config .docker-compose-start
	@true

.docker-compose-start: $(CREATE_TARGET)
	@$(COMPOSE_CMD) up $(COMPOSE_UP_OPTS) $(COMPOSE_SERVICE_NAME)
	@$(ECHO) $(COMPOSE_SERVICE_NAME) > $@

# Wait for the start of the containers
.PHONY: docker-wait
docker-wait: $(START_TARGET)
	@$(ECHO) "Waiting for container $(CONTAINER_NAME)"
	@set +e; \
	$(COMPOSE_CMD) run --rm $(WAIT_SERVICE_NAME) true; \
	if [ $$? != 0 ]; then \
		$(COMPOSE_CMD) logs $(COMPOSE_LOGS_OPTS); \
		$(ECHO) "ERROR: Timeout has just expired" >&2; \
		exit 1; \
	fi

# Display running containers
.PHONY: docker-ps
docker-ps:
	@$(COMPOSE_CMD) ps $(COMPOSE_PS_OPTS)

# Display the containers logs
.PHONY: docker-logs
docker-logs:
	@if [ -e .docker-compose-start ]; then \
		$(COMPOSE_CMD) logs $(COMPOSE_LOGS_OPTS); \
	fi

# Follow the containers logs
.PHONY: docker-logs-tail
docker-logs-tail:
	@if [ -e .docker-compose-start ]; then \
		$(COMPOSE_CMD) logs --follow $(COMPOSE_LOGS_OPTS); \
	fi

# Run the shell in the running container
.PHONY: docker-shell
docker-shell: $(START_TARGET)
	@set -eo pipefail; \
	docker exec $(SHELL_OPTS) $(CONTAINER_NAME) $(SHELL_CMD)

# Run the tests
.PHONY: docker-test
docker-test: $(START_TARGET) .docker-compose-test
	@$(ECHO) "Running tests in container $(TEST_CONTAINER_NAME)"
	@$(COMPOSE_CMD) run --rm $(TEST_SERVICE_NAME) $(TEST_CMD)

.docker-compose-test:
	@$(ECHO) "Creating container $(TEST_CONTAINER_NAME)"
	@rm -f $(TEST_ENV_FILE)
	@$(foreach VAR,$(TEST_COMPOSE_VARS),echo "$(VAR)=$($(VAR))" >> $(TEST_ENV_FILE);)
	@$(COMPOSE_CMD) up --no-start --no-build $(TEST_SERVICE_NAME)
# Copy the project dir to the test container if the Docker host is remote
ifeq ($(TEST_PROJECT_DIR),)
	@$(ECHO) "Copying project to container $(TEST_CONTAINER_NAME)"
	@docker cp $(PROJECT_DIR) $(TEST_CONTAINER_NAME):$(dir $(PROJECT_DIR))
endif
	@echo $(TEST_SERVICE_NAME) > $@

# Stop the containers
.PHONY: docker-stop
docker-stop:
	@if [ -e .docker-compose-start ]; then \
		$(COMPOSE_CMD) stop $(COMPOSE_STOP_OPTS); \
	fi

# Restart the containers
.PHONY: docker-restart
docker-restart:
	@$(MAKE) $(STOP_TARGET) $(START_TARGET)

# Remove the containers
.PHONY: docker-rm
docker-rm:
	@if [ -e .docker-compose-create ]; then \
		$(COMPOSE_CMD) down $(COMPOSE_RM_OPTS); \
	fi
	@rm -f .docker-compose-*

# Remove all containers and work files
.PHONY: docker-clean
docker-clean: docker-rm
	@rm -f .docker-* $(DOCKER_IMAGE_DEPOT)/$(DOCKER_VENDOR)-$(DOCKER_NAME)-$(DOCKER_IMAGE_TAG).image
	@find . -type f -name '*~' | xargs rm -f

### DOCKER_REGISTRY_TARGETS ####################################################

# Pull all images from the Docker Registry
.PHONY: docker-pull
docker-pull: docker-pull-dependencies docker-pull-image docker-pull-testimage
	@true

# Pull project base image from the Docker registry
.PHONY: docker-pull-baseimage
docker-pull-baseimage:
	@docker pull $(BASE_IMAGE)

# Pull the project image dependencies from the Docker registry
.PHONY: docker-pull-dependencies
docker-pull-dependencies:
	@$(foreach DOCKER_IMAGE,$(DOCKER_IMAGE_DEPENDENCIES),docker pull $(DOCKER_IMAGE);echo;)

# Pull the project image from the Docker registry
.PHONY: docker-pull-image
docker-pull-image:
	@$(foreach TAG,$(DOCKER_PULL_TAGS),docker pull $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG);echo;)

# Pull the test image from the Docker registry
.PHONY: docker-pull-testimage
docker-pull-testimage:
	@docker pull $(TEST_IMAGE)

# Posh the project image to the Docker registry
.PHONY: docker-push
docker-push:
	@$(foreach TAG,$(DOCKER_PUSH_TAGS),docker push $(DOCKER_REGISTRY)/$(DOCKER_IMAGE_NAME):$(TAG);echo;)

# Load the project image from file
.PHONY: docker-load-image
docker-load-image:
	@cat $(DOCKER_IMAGE_DEPOT)/$(DOCKER_VENDOR)-$(DOCKER_NAME)-$(DOCKER_IMAGE_TAG).image | \
	gunzip | docker image load

# Save the project image to file
.PHONY: docker-save-image
docker-save-image:
	@docker image save $(foreach TAG,$(DOCKER_IMAGE_TAG) $(DOCKER_IMAGE_TAGS), $(DOCKER_IMAGE_NAME):$(TAG)) | \
	gzip > $(DOCKER_IMAGE_DEPOT)/$(DOCKER_VENDOR)-$(DOCKER_NAME)-$(DOCKER_IMAGE_TAG).image

################################################################################