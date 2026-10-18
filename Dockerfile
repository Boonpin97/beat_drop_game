# Room server image for Cloud Run. Lives at the repo root because the server
# depends on packages/shared; build with the repo root as the context.
FROM dart:stable AS build
WORKDIR /app
COPY packages/shared packages/shared
COPY server/pubspec.* server/
WORKDIR /app/server
RUN dart pub get
COPY server/ .
RUN dart pub get --offline && dart compile exe bin/server.dart -o bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/server /app/bin/server
EXPOSE 8080
CMD ["/app/bin/server"]
