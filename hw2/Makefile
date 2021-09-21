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





build-debug: clear cp
	@erlc -Ddebug -pa $(targetDir) -o $(targetDir) $(targetDir)/*.erl
	@echo "compile done"

run-server:
	@erl -noshell -pa $(targetDir) -eval 'main:main(50001), init:stop()'

run-tcp-server:
	@erl -noshell -pa $(targetDir) -eval 'tcp_server:create_tcp_server(50001), init:stop()'

run-tcp-client:
	@erl -noshell -pa $(targetDir) -eval 'tcp_client:start(), init:stop()'

