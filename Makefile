include .env

default: up

COMPOSER_ROOT ?= /var/www/html
DRUPAL_ROOT ?= /var/www/html/web

## help	:	Print commands help.
.PHONY: help
ifneq (,$(wildcard docker.mk))
help : docker.mk
	@sed -n 's/^##//p' $<
else
help : Makefile
	@sed -n 's/^##//p' $<
endif

## up	:	Start up containers.
.PHONY: up
up:
	@echo "Starting up containers for $(PROJECT_NAME)..."
	docker-compose pull
	docker-compose up -d --remove-orphans

## down	:	Stop containers.
.PHONY: down
down: stop

## start	:	Start containers without updating.
.PHONY: start
start:
	@echo "Starting containers for $(PROJECT_NAME) from where you left off..."
	@docker-compose start

## stop	:	Stop containers.
.PHONY: stop
stop:
	@echo "Stopping containers for $(PROJECT_NAME)..."
	@docker-compose stop

## prune	:	Remove containers and their volumes.
##		You can optionally pass an argument with the service name to prune single container
##		prune mariadb	: Prune `mariadb` container and remove its volumes.
##		prune mariadb solr	: Prune `mariadb` and `solr` containers and remove their volumes.
.PHONY: prune
prune:
	@echo "Removing containers for $(PROJECT_NAME)..."
	@docker-compose down -v $(filter-out $@,$(MAKECMDGOALS))

## ps	:	List running containers.
.PHONY: ps
ps:
	@docker ps --filter name='$(PROJECT_NAME)*'

## shell	:	Access `php` container via shell.
##		You can optionally pass an argument with a service name to open a shell on the specified container
.PHONY: shell
shell:
	@docker exec -i -u wodby -e COLUMNS=$(shell tput cols) -e LINES=$(shell tput lines) $(shell docker ps --filter name='$(PROJECT_NAME)_$(or $(filter-out $@,$(MAKECMDGOALS)), 'php')' --format "{{ .ID }}") sh

## composer	:	Executes `composer` command in a specified `COMPOSER_ROOT` directory (default is `/var/www/html`).
##		To use "--flag" arguments include them in quotation marks.
##		For example: make composer "update drupal/core --with-dependencies"
.PHONY: composer
composer:
	@docker exec -i -u wodby $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") composer --working-dir=$(COMPOSER_ROOT) $(filter-out $@,$(MAKECMDGOALS))

## drupal console
.PHONY: drupal
drupal:
	@docker exec -i -u wodby $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") drupal --root=$(DRUPAL_ROOT) $(filter-out $@,$(MAKECMDGOALS))

## drush	:	Executes `drush` command in a specified `DRUPAL_ROOT` directory (default is `/var/www/html/web`).
##		To use "--flag" arguments include them in quotation marks.
##		For example: make drush "watchdog:show --type=cron"
.PHONY: drush
drush:
	@docker exec -i -u wodby $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) $(filter-out $@,$(MAKECMDGOALS))

## logs	:	View containers logs.
##		You can optinally pass an argument with the service name to limit logs
##		logs php	: View `php` container logs.
##		logs nginx php	: View `nginx` and `php` containers logs.
.PHONY: logs
logs:
	@docker-compose logs -f $(filter-out $@,$(MAKECMDGOALS))

## debug
.PHONY: debug
debug:
	${MAKE} drush ws

## phpcs :	Phpcs.
.PHONY: phpcs
phpcs:
	docker exec -i -u wodby $(PROJECT_NAME)_php sh -c './vendor/bin/phpcs \
                                                          --standard="Drupal,DrupalPractice" -n \
                                                          --extensions="php,module,inc,install,test,profile,theme" \
                                                          web/themes/custom \
                                                          web/modules/custom'

## phpcbf :	Phpcbf.
.PHONY: phpcbf
phpcbf:
	docker exec -i -u wodby $(PROJECT_NAME)_php sh -c './vendor/bin/phpcbf \
                                                          --standard="Drupal,DrupalPractice" -n \
                                                          --extensions="php,module,inc,install,test,profile,theme" \
                                                          web/themes/custom \
                                                          web/modules/custom'

## drupal-check  :	drupal-check analysis.
.PHONY: drupal-check-analysis
drupal-check-analysis:
	docker exec -i -u wodby $(PROJECT_NAME)_php sh -c 'drupal-check -a --drupal-root $(DRUPAL_ROOT) web/modules/custom && drupal-check -a --drupal-root $(DRUPAL_ROOT) web/themes/custom'

## drupal-check  :	drupal-check deprecations.
.PHONY: drupal-check-deprecations
drupal-check-deprecations:
	docker exec -i -u wodby $(PROJECT_NAME)_php sh -c 'drupal-check -d --drupal-root $(DRUPAL_ROOT) web/modules/custom && drupal-check -d --drupal-root $(DRUPAL_ROOT) web/themes/custom'

## init  :	init necessary dependencies
.PHONY: init
init:
	@echo "Initializing .git hooks..."
	git config core.hooksPath .github/hooks
	@echo "Starting containers..."
	${MAKE} start
	@echo "Installing composer dependencies..."
	${MAKE} composer install
	@echo "Installing drupal site..."
	docker exec -i -u wodby $(PROJECT_NAME)_php sh -c 'drush site:install --existing-config --account-name=admin --account-pass=admin standard -y'

## pre-commit  :	pre-commit hook
.PHONY: pre-commit
pre-commit:
	@echo "Exporting configuration files..."
	${MAKE} drush "cex -y"
	@echo "Checking errors..."
	${MAKE} phpcbf

## post-pull  :	post-pull hook
.PHONY: post-pull
post-pull:
	@echo "Installing missing dependencies..."
	${MAKE} composer install
	@echo "Launching updb..."
	${MAKE} drush "updb -y"
	@echo "Importing Configuration files..."
	${MAKE} drush "cim -y"
	@echo "Rebuilding cache..."
	${MAKE} drush cr

# https://stackoverflow.com/a/6273809/1826109
%:
	@:

