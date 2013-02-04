.PHONY: all
all:
	./rebar compile

.PHONY: clean
clean:
	./rebar clean

.PHONY: eunit
eunit:
	./rebar eunit skip_deps=true

.PHONY: ct
ct:
	./rebar ct skip_deps=true

.PHONY: test
test: all eunit ct
