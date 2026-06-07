FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /app

# Cache dependency layer — only re-runs when pom.xml changes
COPY pom.xml .
RUN mvn dependency:resolve -DskipTests -q

COPY src ./src
RUN mvn package -DskipTests -q

# ---

FROM eclipse-temurin:21-jre-alpine

RUN apk add --no-cache wget

WORKDIR /app

COPY --from=builder /app/target/*.jar /app/app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
