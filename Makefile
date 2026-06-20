# OPMI ontology Makefile
# Jie Zheng
#
# This Makefile is used to build artifacts
# for the OPMI: Ontology of Precision Medicine and Investigation
#

### Configuration
#
# prologue:
# <http://clarkgrubb.com/makefile-style-guide#toc2>

MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

### Definitions

SHELL   := /bin/bash
OBO     := http://purl.obolibrary.org/obo
OPMI    := $(OBO)/OPMI_
TODAY   := $(shell date +%Y-%m-%d)

### Directories
#
# This is a temporary place to put things.
build:
	mkdir -p $@


### ROBOT
#
# We use the latest official release version of ROBOT
build/robot.jar: | build
	curl -L -o $@ "https://github.com/ontodev/robot/releases/latest/download/robot.jar"

ROBOT := java -jar build/robot.jar


### Imports
#
# Use Ontofox to import various modules.
ONTOFOX_INPUT_DIR := src/ontology/Ontofox_inputs
IMPORT_DIR        := src/ontology/imports

ONTOFOX_INPUTS := $(wildcard $(ONTOFOX_INPUT_DIR)/*_imports_input.txt)
IMPORT_NAMES   := $(patsubst $(ONTOFOX_INPUT_DIR)/%_imports_input.txt,%,$(ONTOFOX_INPUTS))
IMPORT_FILES   := $(addprefix $(IMPORT_DIR)/,$(addsuffix _imports.owl,$(IMPORT_NAMES)))

$(IMPORT_DIR)/%_imports.owl: $(ONTOFOX_INPUT_DIR)/%_imports_input.txt | $(IMPORT_DIR)
	curl -s -F file=@$< -o $@ https://ontofox.hegroup.org/service.php

.PHONY: imports
imports: $(IMPORT_FILES)


build/opmi_merged.owl: src/ontology/opmi-edit.owl $(IMPORT_FILES) | build/robot.jar build
	$(ROBOT) merge \
	--input $< \
	annotate \
	--ontology-iri "$(OBO)/opmi/opmi_merged.owl" \
	--version-iri "$(OBO)/opmi/$(TODAY)/opmi_merged.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output build/opmi_merged.tmp.owl
	sed '/<owl:imports/d' build/opmi_merged.tmp.owl > $@
	rm build/opmi_merged.tmp.owl

opmi.owl: build/opmi_merged.owl
	$(ROBOT) reason \
	--input $< \
	--reasoner ELK \
	annotate \
	--ontology-iri "$(OBO)/opmi.owl" \
	--version-iri "$(OBO)/opmi/releases/$(TODAY)/opmi.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output $@

robot_report.tsv: build/opmi_merged.owl
	$(ROBOT) report \
	--input $< \
	--fail-on none \
	--output $@

### General
#
# Full build
.PHONY: all
all: opmi.owl robot_report.tsv

# Remove generated files
.PHONY: clean
clean:
	rm -rf build