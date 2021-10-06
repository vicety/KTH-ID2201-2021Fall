srcDir=src
targetDir=output

FUN=gsm1

all: build

clear:
	@rm -f ${targetDir}/*

cp:
	@cp $(srcDir)/*.erl $(targetDir)
	# @cp $(srcDir)/*.data $(targetDir)
	# @cp $(srcDir)/*.hrl $(targetDir)

build: clear cp
	@erlc -pa $(targetDir) -o $(targetDir) $(targetDir)/*.erl
	@echo "compile done"

run:
	@cd $(targetDir); erl -pa $(targetDir) -eval 'worker:$(FUN)()'

run1: build
	@cd $(targetDir); erl -pa $(targetDir) -eval 'node1:test()'
