# Enthroned OS MVP: both applications build against the same Aurora runtime.
# Record the resolved Aurora digest for every real build (ADR-0002).
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM ghcr.io/ublue-os/aurora:stable AS runtime
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/build.sh

# Development tools stay in this stage; DESTDIR contains only our installation.
# Lote 7.1: libplasma-devel + kf6-kcoreaddons-devel build the
# org.enthroned.contextmenu ContainmentActions plugin (desktop-actions/).
FROM runtime AS apps-builder
ARG BUILD_JOBS=4
RUN dnf5 -y install gcc-c++ cmake ninja-build extra-cmake-modules \
      qt6-qtbase-devel qt6-qtdeclarative-devel \
      kf6-kirigami-devel kf6-ki18n-devel kf6-knotifications-devel \
      kf6-kcoreaddons-devel kf6-kconfig-devel libplasma-devel
COPY desktop-actions /src/desktop-actions
COPY settings /src/settings
COPY welcome /src/welcome
RUN cmake -S /src/desktop-actions -B /build/desktop-actions -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
      -DKDE_INSTALL_SYSCONFDIR=/etc && \
    cmake --build /build/desktop-actions --parallel "${BUILD_JOBS}" && \
    DESTDIR=/out cmake --install /build/desktop-actions && \
    cmake -S /src/settings -B /build/settings -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
      -DKDE_INSTALL_SYSCONFDIR=/etc -DBUILD_TESTING=ON && \
    cmake --build /build/settings --parallel "${BUILD_JOBS}" && \
    ctest --test-dir /build/settings --output-on-failure && \
    DESTDIR=/out cmake --install /build/settings && \
    cmake -S /src/welcome -B /build/welcome -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
      -DKDE_INSTALL_SYSCONFDIR=/etc -DBUILD_TESTING=ON && \
    cmake --build /build/welcome --parallel "${BUILD_JOBS}" && \
    ctest --test-dir /build/welcome --output-on-failure && \
    DESTDIR=/out cmake --install /build/welcome

FROM runtime AS final
LABEL org.opencontainers.image.title="enthroned-os" \
      org.opencontainers.image.description="Enthroned OS - MVP candidate derived from Universal Blue Aurora" \
      org.opencontainers.image.vendor="Enthroned OS" \
      org.opencontainers.image.base.name="ghcr.io/ublue-os/aurora:stable" \
      org.opencontainers.image.version="0.1.0-dev"
COPY --from=apps-builder /out/ /
RUN QT_QPA_PLATFORM=offscreen /usr/bin/enthroned-settings --help && \
    QT_QPA_PLATFORM=offscreen /usr/bin/enthroned-welcome --help && \
    test -x /usr/bin/plasma-discover && \
    test -x /usr/bin/dolphin && \
    bootc container lint
