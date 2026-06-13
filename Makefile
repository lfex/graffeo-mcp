.PHONY: compile test fetch-cards clean

compile:
	rebar3 compile

test:
	rebar3 eunit

fetch-cards:
	@mkdir -p priv
	@rm -rf /tmp/ai-engineering-cards
	git clone --depth 1 https://github.com/billosys/ai-engineering.git \
	    /tmp/ai-engineering-cards
	cp -r /tmp/ai-engineering-cards/knowledge/erlang/concept-cards \
	    priv/concept-cards
	rm -rf /tmp/ai-engineering-cards

clean:
	rebar3 clean
