srcDir=src
targetDir=output

all: build

clear:
	@rm -f ${targetDir}/*

cp:
	@cp $(srcDir)/*.erl $(targetDir)
	@cp $(srcDir)/*.hrl $(targetDir)

build: clear cp
	@erlc -pa $(targetDir) -o $(targetDir) $(targetDir)/*.erl
	@echo "compile done"

build-debug: clear cp
	@erlc -Ddebug -pa $(targetDir) -o $(targetDir) $(targetDir)/*.erl
	@echo "compile done"

run-server:
	@erl -noshell -pa $(targetDir) -eval 'main:main(50001), init:stop()'

run-tcp-server:
	@erl -noshell -pa $(targetDir) -eval 'tcp_server:create_tcp_server(50001), init:stop()'

run-tcp-client:
	@erl -noshell -pa $(targetDir) -eval 'tcp_client:start(), init:stop()'

debug:
	@erl -noshell -pa $(targetDir) -eval 'io:format("~p~n", [$(CMD)]), init:stop()'

bench:
	@erl -noshell -pa $(targetDir) -eval 'bench:bench("localhost", 80, $(THREAD), $(REPEAT)), init:stop()'
