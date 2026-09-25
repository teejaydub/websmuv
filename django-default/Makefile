.MAKEFLAGS += --no-print-directory

include websmuv/app-Makefile
include websmuv/django-Makefile

# Initial setup for development on a new account, or build with new code.
# Assumes conf.toml is already customized.
dev: django-depends update-dev

# Set up for production use.
install: django-depends django-setup-prod
