srcDir=src
targetDir=output

all: build

build:
	@cp $(srcDir)/*.erl $(targetDir)
	@erlc -pa $(targetDir) -o $(targetDir) $(targetDir)/*.erl
	@echo "compile done"

run-server:
	@erl -noshell -pa $(targetDir) -eval 'tcp_server:init(12345), init:stop()'

run-client:
	@erl -noshell -pa $(targetDir) -eval 'tcp_client:start(), init:stop()'

debug:
	@erl -noshell -pa $(targetDir) -eval 'io:format("~p~n", [$(CMD)]), init:stop()'
