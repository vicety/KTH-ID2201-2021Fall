srcDir=src
targetDir=output

FUN=gsm1

all: build

clear:
	@rm -f ${targetDir}/*

cp:
	@cp $(srcDir)/*.erl $(targetDir)

build: clear cp
	@erlc -pa $(targetDir) -o $(targetDir) $(targetDir)/*.erl
	@echo "compile done"

run1: build
	@cd $(targetDir); erl -pa $(targetDir) -eval 'test:node($(MODULE))'

run2: build
	@cd $(targetDir); erl -pa $(targetDir) -eval 'test:node4()'
