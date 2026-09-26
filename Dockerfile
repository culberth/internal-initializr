# internal-initializr as a container image.
#
# Built from an already-packaged jar, not compiled in the image: Maven here resolves through the
# local Nexus configured in Maven's own conf/settings.xml, which a build container cannot see
# (same reason as artemis-browser). scripts/build-image.ps1 builds the jar and copies it to build/.
#
# Upstream compiles for Java 17; a 21 JRE runs it and matches the other images on this cluster.
FROM eclipse-temurin:21-jre-alpine

RUN addgroup -S -g 1000 initializr && adduser -S -u 1000 -G initializr -h /home/initializr initializr

WORKDIR /app
COPY --chown=initializr:initializr build/start-site-exec.jar /app/initializr.jar

USER 1000

# Plain HTTP; TLS, if wanted, is the ingress's job. The site holds no secrets and no sessions.
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/initializr.jar"]
