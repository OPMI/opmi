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


build/opmi_merged.owl: src/ontology/opmi_dev.owl $(IMPORT_FILES) | build/robot.jar build
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
	--reasoner HermiT \
	annotate \
	--ontology-iri "$(OBO)/opmi.owl" \
	--version-iri "$(OBO)/opmi/$(TODAY)/opmi.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output $@

test_report.tsv: build/opmi_merged.owl
	$(ROBOT) report \
	--input $< \
	--fail-on none \
	--output $@


### Test
#
# Run main tests
MERGED_VIOLATION_QUERIES := $(wildcard src/sparql/*-violation.rq)

build/terms-report.csv: build/opmi_merged.owl src/sparql/terms-report.rq | build
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/opmi-previous-release.owl: | build
	curl -L -o $@ "http://purl.obolibrary.org/obo/opmi.owl"

build/released-entities.tsv: build/opmi-previous-release.owl src/sparql/get-opmi-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/current-entities.tsv: build/opmi_merged.owl src/sparql/get-opmi-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/dropped-entities.tsv: build/released-entities.tsv build/current-entities.tsv
	comm -23 $^ > $@

# Run all validation queries and exit on error.
.PHONY: verify
verify: verify-merged verify-entities

# Run validation queries on opmi_merged and exit on error.
.PHONY: verify-merged
verify-merged: build/opmi_merged.owl $(MERGED_VIOLATION_QUERIES) | build/robot.jar
	$(ROBOT) verify --input $< --output-dir build \
	--queries $(MERGED_VIOLATION_QUERIES)

# Check if any entities have been dropped and exit on error.
.PHONY: verify-entities
verify-entities: build/dropped-entities.tsv
	@echo $(shell < $< wc -l) " opmi IRIs have been dropped"
	@! test -s $<

# Run a HermiT reasoner to find inconsistencies
.PHONY: reason
reason: build/opmi_merged.owl | build/robot.jar
	$(ROBOT) reason --input $< --reasoner HermiT

.PHONY: test
test: reason verify


### General
#
# Full build
.PHONY: all
all: imports test opmi.owl build/terms-report.csv

# Remove generated files
.PHONY: clean
clean:
	rm -rf build

# Check for problems such as bad line-endings
.PHONY: check
check:
	src/scripts/check-line-endings.sh tsv

# Fix simple problems such as bad line-endings
.PHONY: fix
fix:
	src/scripts/fix-eol-all.sh