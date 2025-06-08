FROM elixir:1.15.0-alpine AS build

# Install dependencies
RUN apk add --no-cache build-base git npm python3

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

FROM alpine:latest
RUN apk add --no-cache openssl ncurses-libs 

WORKDIR /app
RUN chown -R nobody:root /app

ENV MIX_ENV=prod

COPY --from=build --chown=nobody:root /app/_build/${MIX_ENV}/rel/green_elixir ./

USER nobody

CMD ["/app/bin/green_elixir", "start"]