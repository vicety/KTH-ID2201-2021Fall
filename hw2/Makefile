srcDir=src
targetDir=output

all: build

clear:
	@rm -f ${targetDir}/*

cp:
	@cp $(srcDir)/*.erl $(targetDir)
	@cp $(srcDir)/*.data $(targetDir)
	# @cp $(srcDir)/*.hrl $(targetDir)

build: clear cp
	@erlc -pa $(targetDir) -o $(targetDir) $(targetDir)/*.erl
	@echo "compile done"

dij:
	@erl -noshell -pa $(targetDir) -eval 'dij:test(), init:stop()'

run:
	@cd $(targetDir); erl -sname $(NAME) -connect_all false -pa $(targetDir) -eval 'routy:start($(NAME))'
