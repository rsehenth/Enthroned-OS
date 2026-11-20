# Enthroned OS Justfile.
# Adapted from the Universal Blue image-template Justfile (Apache-2.0),
# upstream state recorded in docs/architecture/ADR-0001-upstream-aurora.md.
# Changes vs upstream: ArtifactHub labels removed, REPO_ORGANIZATION gated,
# verification recipes added (doctor / verify-source / verify-image /
# verify-artifacts), chunkah rechunk recipe dropped for F1.

set dotenv-filename := "image-template.env"
set dotenv-load

export image_name := env_var("IMAGE_NAME")
export repo_organization := env_var("REPO_ORGANIZATION")
export image_desc := env_var("IMAGE_DESC")
export image_keywords := env_var("IMAGE_KEYWORDS")
export default_tag := env_var("DEFAULT_TAG")
export bib_image := env_var("BIB_IMAGE")

# Deliberate placeholder that keeps publishing blocked until a real
# GitHub namespace is configured (ADR-0002).

publish_placeholder := "SET_ME_BEFORE_PUBLISH"

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[positional-arguments]
[private]
sudoif command *args:
    #!/usr/bin/env bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif "$@"

# Build the image using the specified parameters

# Example: just build [target_image] [tag]
build $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash

    set -euox pipefail

    BUILD_ARGS=()
    LABELS=()
    if [[ -z "$(git status -s)" ]]; then
        GIT_SHA=$(git rev-parse --short HEAD)
        LABELS+=("--label" "org.opencontainers.image.version={{ default_tag }}.$(date +%Y%m%d)-${GIT_SHA}")
        if [[ "{{ repo_organization }}" != "{{ publish_placeholder }}" ]]; then
            LABELS+=("--label" "org.opencontainers.image.documentation=https://raw.githubusercontent.com/{{ repo_organization }}/{{ image_name }}/${GIT_SHA}/README.md")
            LABELS+=("--label" "org.opencontainers.image.source=https://github.com/{{ repo_organization }}/{{ image_name }}/blob/${GIT_SHA}/Containerfile")
            LABELS+=("--label" "org.opencontainers.image.url=https://github.com/{{ repo_organization }}/{{ image_name }}/tree/${GIT_SHA}")
        else
            echo "REPO_ORGANIZATION is a placeholder; skipping source URL labels (publishing locked, ADR-0002)."
        fi
    fi

    LABELS+=("--label" "org.opencontainers.image.created=$(date -u +%Y\-%m\-%dT%H\:%M\:%S\Z)")
    LABELS+=("--label" "org.opencontainers.image.description={{ image_desc }}")
    LABELS+=("--label" "org.opencontainers.image.title={{ image_name }}")
    LABELS+=("--label" "org.opencontainers.image.vendor=Enthroned OS")

    # This actually builds the image!
    PODMAN_BUILD_ARGS=("${BUILD_ARGS[@]}" "${LABELS[@]}" --network=host --pull=newer --tag "${target_image}:${tag}" --file Containerfile)

    just sudoif podman build --cpuset-cpus=0-3 --cpu-period=100000 --cpu-quota=400000 --memory=10g --memory-swap=10g "${PODMAN_BUILD_ARGS[@]}" .

# Split the image for smaller updates using rpm-ostree (upstream compatible)
ostree-rechunk $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash

    set -xeuo pipefail

    RPM_OSTREE_CHUNKER_IMAGE="localhost/${target_image}:${tag}"

    GRAPHROOT="$(podman info --format '{{ '{{.Store.GraphRoot}}' }}')"

    podman run --rm --pull=never --privileged \
      --mount=type=image,src="${target_image}:${tag}",target=/rpm-ostree \
      --mount=type=bind,src=${GRAPHROOT},target=/run/host-container-storage,rw \
      --mount=type=tmpfs,target=/run/rpm-ostree-storage \
      --entrypoint /usr/bin/rpm-ostree \
      "${RPM_OSTREE_CHUNKER_IMAGE}" \
      compose build-chunked-oci \
      --max-layers 127 \
      --format-version=2 \
      --bootc \
      --rootfs /rpm-ostree \
      --output "containers-storage:[overlay@/run/host-container-storage+/run/rpm-ostree-storage]localhost/${target_image}:${tag}"

# Generate Default Tag
[group('Utility')]
generate-default-tag $tag=default_tag:
    #!/usr/bin/env bash
    set -eoux pipefail

    echo "${tag}"

# Generate Tags
[group('Utility')]
generate-build-tags $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -eoux pipefail

    DATE=$(date +%Y%m%d)
    BUILD_TAGS=()
    if [[ -z "$(git status -s)" ]]; then
        GIT_SHA=$(git rev-parse --short HEAD)
        BUILD_TAGS+=("${tag}-${GIT_SHA}")
        BUILD_TAGS+=("${tag}-${DATE}-${GIT_SHA}")
        BUILD_TAGS+=("${DATE}-${GIT_SHA}")
    fi

    BUILD_TAGS+=("${DATE}")
    BUILD_TAGS+=("${tag}")
    BUILD_TAGS+=("${tag}-${DATE}")

    echo "${BUILD_TAGS[@]}"

# Tag Images
[group('Utility')]
tag-images $target_image=image_name $tag=default_tag tags="":
    #!/usr/bin/env bash
    set -eoux pipefail

    # Get Image, and untag
    IMAGE=$(podman inspect ${target_image}:${tag} | jq -r .[].Id)
    podman untag ${IMAGE}

    # Tag Image
    for tag in {{ tags }}; do
        podman tag $IMAGE "${target_image}:${tag}"
    done

    # Show Images
    podman images

# Image Name
[group('Utility')]
[private]
image_name $target_image=image_name:
    #!/usr/bin/env bash
    set -eoux pipefail

    echo "${image_name}"

# Command: _rootful_load_image

# Loads the user-built image into rootful podman storage or pulls it when absent.
_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -eoux pipefail

    # Use one rootful store for OCI build, inspection and disk generation.
    if ! just sudoif podman image exists "${target_image}:${tag}"; then
        echo "BLOCKED: build the image in rootful storage first: sudo just build" >&2
        exit 2
    fi

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/enthroned-os)
#   tag: The tag of the image to build (ex. f1-dev)
#   type: The type of image to build (ex. qcow2, raw, iso)

# config: The configuration file to use for the build (default: disk_config/disk.toml)
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    # Refuse to bake an unresolvable registry reference into installer media.
    if [[ -f "${config}" ]] && grep -q 'SET_ME_BEFORE_PUBLISH' "${config}"; then
        echo "ERROR: ${config} still contains the SET_ME_BEFORE_PUBLISH placeholder (ADR-0002)." >&2
        echo "Refusing to generate installer media pointing at a non-existent image." >&2
        exit 3
    fi

    case "${type}" in
        qcow2|raw) ;;
        *) echo "BLOCKED: MVP disk route supports qcow2/raw; legacy ISO config needs a separate installer." >&2; exit 2 ;;
    esac
    if [[ ! -r "${config}" ]]; then
        echo "BLOCKED: missing disk blueprint: ${config}" >&2
        exit 2
    fi
    if grep -q 'REPLACE_WITH_LOCAL_HASH' "${config}"; then
        echo "BLOCKED: configure the VM user's password hash first (docs/operations/BUILD.md)." >&2
        exit 2
    fi
    mkdir -p "output/${type}"
    just sudoif podman run --rm --privileged --pull=newer --network=host \
      --cpuset-cpus=0-3 --cpus=4 --memory=10g --memory-swap=10g \
      --security-opt label=type:unconfined_t \
      -v "$(realpath "${config}"):/blueprint.toml:ro" \
      -v "${PWD}/output/${type}:/output" \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "{{ bib_image }}" build \
      --image-size "64 GiB" \
      --blueprint /blueprint.toml --output-dir /output --output-name disk \
      --bootc-ref "${target_image}:${tag}" --bootc-default-fs btrfs "${type}"
    just sudoif chown -R "$(id -u):$(id -g)" "output/${type}"

# Podman builds the image from the Containerfile and creates a bootable image

# Example: just rebuild-qcow2
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image
[group('Build Virtual Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "disk_config/vm.local.toml")

# Build a RAW virtual machine image
[group('Build Virtual Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "raw" "disk_config/vm.local.toml")

# Build an ISO virtual machine image
[group('Build Virtual Machine Image')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "iso" "disk_config/iso.toml")

# Rebuild a QCOW2 virtual machine image
[group('Build Virtual Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "disk_config/vm.local.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtual Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "raw" "disk_config/vm.local.toml")

# Rebuild an ISO virtual machine image
[group('Build Virtual Machine Image')]
rebuild-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/env bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect
    (sleep 30 && xdg-open http://localhost:"$port") &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtual Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "disk_config/vm.local.toml")

# Run a virtual machine from a RAW image
[group('Run Virtual Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "disk_config/vm.local.toml")

# Run a virtual machine from an ISO
[group('Run Virtual Machine')]
run-vm-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine using systemd-vmspawn
[group('Run Virtual Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

# Run environment doctor (read-only checks, no system changes)
[group('Verification')]
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/doctor.sh

# Verify source tree: base image, identity, secrets and workflow policy
[group('Verification')]
verify-source:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/verify-source.sh

# Verify a built image without installing it (default: localhost/<image>:<tag>)
[group('Verification')]
verify-image $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    just sudoif bash scripts/verify-image.sh "localhost/{{ target_image }}:{{ tag }}"

# Verify generated disk artifacts (usage: just verify-artifacts <file> [file...])
[group('Verification')]
verify-artifacts *artifact="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{ artifact }}" ]]; then
        echo "usage: just verify-artifacts <file> [file...]" >&2
        exit 2
    fi
    bash scripts/verify-artifacts.sh {{ artifact }}

# Static validation of the F2 desktop layer (no KDE, no image build required)
[group('Verification')]
verify-desktop:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/validate-desktop.sh

# Static validation of the F3 settings & update center (no Qt/KDE required;

# runs the node logic tests + packaging/safety checks)
[group('Verification')]
verify-settings:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/validate-settings.sh

# Static validation of the F4 applications & welcome phase (no Qt/KDE required;

# runs the node logic tests + packaging/safety/policy checks)
[group('Verification')]
verify-welcome:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/validate-welcome.sh

# Lote 8: read-only audit of the REAL bootc in this system/VM (arguments and
# flows the Update Center relies on). Nothing is staged or mutated.
[group('Verification')]
bootc-capabilities:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/bootc-capabilities.sh

# Lote 8: update pipeline (check-base, build, verify, version, notes; the
# publish phase is gated and never runs implicitly). Extra args pass through:
# just update-pipeline check-base
[group('Utility')]
update-pipeline *args:
    #!/usr/bin/env bash
    set -euo pipefail
    bash scripts/update-pipeline.sh {{ args }}

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Fail on warnings and errors; info and style notes are advisory
    # Run shellcheck on all Bash scripts
    find . -iname "*.sh" -type f -exec shellcheck --severity=warning "{}" ';'
    # Also check shell helpers without a .sh extension
    shellcheck --severity=warning system_files/usr/bin/enthroned-identity system_files/usr/bin/enthroned-diagnostics
    shellcheck --severity=warning system_files/usr/libexec/enthroned-system-update

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
