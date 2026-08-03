# Forgeron APK local SafeDesk : JDK + SDK Android + gradle, en cache.
# Construit une fois, reutilise a chaque forge (~30 s apres chauffage).
#   docker build -t safedesk/android-builder builder/
# ARG WITH_NDK=true pour compiler les clients natifs (fork Moonlight).
FROM eclipse-temurin:17-jdk

ARG WITH_NDK=false
ARG CMDLINE_TOOLS=13114758
ARG GRADLE_VERSION=8.9
ARG PLATFORM=34
ARG BUILD_TOOLS=34.0.0

ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:/opt/gradle/bin

RUN set -eux; \
    apt-get update; apt-get install -y --no-install-recommends unzip curl git; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSLo /tmp/ct.zip "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip"; \
    mkdir -p "$ANDROID_HOME/cmdline-tools"; \
    unzip -q /tmp/ct.zip -d "$ANDROID_HOME/cmdline-tools"; \
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"; \
    rm /tmp/ct.zip; \
    yes | sdkmanager --licenses >/dev/null; \
    sdkmanager "platform-tools" "platforms;android-${PLATFORM}" "build-tools;${BUILD_TOOLS}"; \
    if [ "$WITH_NDK" = "true" ]; then sdkmanager "ndk;26.3.11579264" "cmake;3.22.1"; fi; \
    curl -fsSLo /tmp/gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"; \
    unzip -q /tmp/gradle.zip -d /opt; \
    mv "/opt/gradle-${GRADLE_VERSION}" /opt/gradle; \
    rm /tmp/gradle.zip

WORKDIR /src