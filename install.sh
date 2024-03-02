#!/usr/bin/env bash
# shellcheck disable=SC2034

# Install the scripts for the GNOME Files (Nautilus), Caja and Nemo file managers.

set -eu

# -----------------------------------------------------------------------------
# CONSTANTS
# -----------------------------------------------------------------------------

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
ASSSETS_DIR="$SCRIPT_DIR/.assets"

readonly SCRIPT_DIR ASSSETS_DIR

# -----------------------------------------------------------------------------
# GLOBAL VARIABLES
# -----------------------------------------------------------------------------

ACCELS_FILE=""
FILE_MANAGER=""
INSTALL_DIR=""

# shellcheck disable=SC1091
source "$ASSSETS_DIR/multiselect_menu.sh"

# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------

_main() {
    local categories_defaults=()
    local categories_dirs=()
    local categories_selected=()
    local menu_options=""
    local menu_defaults=()
    local menu_labels=()
    local menu_selected=()

    _check_default_filemanager

    echo "Scripts installer."
    echo
    echo "Select the options (<SPACE> to select, <UP/DOWN> to choose):"

    menu_labels=(
        "Install basic dependencies."
        "Install keyboard shortcuts."
        "Preserve previous scripts (if any)."
        "Close the file manager to reload its configurations."
        "Choose script categories to install."
    )
    menu_defaults=(
        "true"
        "true"
        "true"
        "true"
        "false"
    )

    _multiselect_menu menu_selected menu_labels menu_defaults

    [[ ${menu_selected[0]} == "true" ]] && menu_options+="dependencies,"
    [[ ${menu_selected[1]} == "true" ]] && menu_options+="shortcuts,"
    [[ ${menu_selected[2]} == "true" ]] && [[ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]] && menu_options+="preserve,"
    [[ ${menu_selected[3]} == "true" ]] && menu_options+="reload,"
    [[ ${menu_selected[4]} == "true" ]] && menu_options+="categories,"

    # Get the scripts categories.
    local cat_dirs_find=""
    local dir=""
    cat_dirs_find=$(find -L "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 -type d \
        ! -path "*.git" ! -path "$ASSSETS_DIR" 2>/dev/null | sed "s|^.*/||" | sort --version-sort)

    # Convert the output of 'find' command to an 'array'.
    while IFS= read -d $'\n' -r dir; do
        categories_selected+=("true")
        categories_dirs+=("$dir")
    done <<<"$cat_dirs_find"

    if [[ "$menu_options" == *"categories"* ]]; then
        echo
        echo "Choose the categories (<SPACE> to select, <UP/DOWN> to choose):"
        _multiselect_menu categories_selected categories_dirs categories_defaults
    fi

    echo
    echo "Starting the installation..."

    # Installer steps.
    [[ "$menu_options" == *"dependencies"* ]] && _step_install_dependencies
    [[ "$menu_options" == *"shortcuts"* ]] && _step_install_shortcuts
    _step_install_scripts "$menu_options" categories_selected categories_dirs
    [[ "$menu_options" == *"reload"* ]] && _step_close_filemanager

    echo "Done!"
}

_check_default_filemanager() {
    # Get the default file manager.
    if _command_exists "nautilus"; then
        INSTALL_DIR="$HOME/.local/share/nautilus/scripts"
        ACCELS_FILE="$HOME/.config/nautilus/scripts-accels"
        FILE_MANAGER="nautilus"
    elif _command_exists "nemo"; then
        INSTALL_DIR="$HOME/.local/share/nemo/scripts"
        ACCELS_FILE="$HOME/.gnome2/accels/nemo"
        FILE_MANAGER="nemo"
    elif _command_exists "caja"; then
        INSTALL_DIR="$HOME/.config/caja/scripts"
        ACCELS_FILE="$HOME/.config/caja/accels"
        FILE_MANAGER="caja"
    else
        echo "Error: could not find any compatible file managers!"
        exit 1
    fi
}

_command_exists() {
    local command_check=$1

    if command -v "$command_check" &>/dev/null; then
        return 0
    fi
    return 1
}

# shellcheck disable=SC2086
_step_install_dependencies() {
    echo " > Installing dependencies..."

    local common_names="bzip2 foremost ghostscript gzip jpegoptim lhasa lzip lzop optipng pandoc perl-base qpdf rdfind rhash squashfs-tools tar testdisk unzip wget xclip xorriso zip zstd"
    if _command_exists "sudo"; then
        if _command_exists "apt-get"; then
            # Distro: Ubuntu, Mint, Debian.
            sudo apt-get update || true
            sudo apt-get -y install $common_names imagemagick xz-utils p7zip-full poppler-utils ffmpeg findimagedupes genisoimage
        elif _command_exists "pacman"; then
            # Distro: Manjaro, Arch Linux.
            # Missing packages: findimagedupes.
            sudo pacman -Syy || true
            sudo pacman --noconfirm -S $common_names imagemagick xz p7zip poppler poppler-glib ffmpeg
        elif _command_exists "dnf"; then
            # Distro: Fedora, Red Hat.
            # Missing packages: findimagedupes.
            sudo dnf check-update || true
            sudo dnf -y install $common_names ImageMagick xz p7zip poppler-utils ffmpeg-free genisoimage
        else
            echo "Error: could not find a package manager!"
            exit 1
        fi
    else
        echo "Error: could not run as administrator!"
        exit 1
    fi
}

_step_install_scripts() {
    local menu_options=$1
    local -n _categories_selected=$2
    local -n _categories_dirs=$3
    local tmp_install_dir=""

    # 'Preserve' or 'Remove' previous scripts.
    if [[ "$menu_options" == *"preserve"* ]]; then
        echo " > Preserving previous scripts to a temporary directory..."
        tmp_install_dir=$(mktemp -d)
        mv "$INSTALL_DIR" "$tmp_install_dir" || true
    else
        echo " > Removing previous scripts..."
        rm -rf -- "$INSTALL_DIR"
    fi

    echo " > Installing new scripts..."
    mkdir --parents "$INSTALL_DIR"

    # Copy the script files.
    cp -- "$SCRIPT_DIR/common-functions.sh" "$INSTALL_DIR"
    local i=0
    for i in "${!_categories_dirs[@]}"; do
        if [[ "${_categories_selected[i]}" == "true" ]]; then
            cp -r -- "$SCRIPT_DIR/${_categories_dirs[i]}" "$INSTALL_DIR"
        fi
    done

    # Set file permissions.
    echo " > Setting file permissions..."
    find "$INSTALL_DIR" -mindepth 2 -type f ! -path "*.git/*" -exec chmod +x {} \;

    # Restore previous scripts.
    if [[ "$menu_options" == *"preserve"* ]]; then
        echo " > Restoring previous scripts to the install directory..."
        mv "$tmp_install_dir/scripts" "$INSTALL_DIR/User previous scripts"
    fi
}

_step_install_shortcuts() {
    echo " > Installing the keyboard shortcuts..."

    mkdir --parents "$(dirname -- "$ACCELS_FILE")"
    mv "$ACCELS_FILE" "$ACCELS_FILE.bak" 2>/dev/null || true

    case "$FILE_MANAGER" in
    "nautilus")
        cp -- "$ASSSETS_DIR/scripts-accels" "$ACCELS_FILE"
        ;;
    "nemo")
        cp -- "$ASSSETS_DIR/accels-gtk2" "$ACCELS_FILE"
        sed -i "s|USER|$USER|g" "$ACCELS_FILE"
        sed -i "s|ACCELS_PATH|local\\\\\\\\sshare\\\\\\\\snemo|g" "$ACCELS_FILE"
        ;;
    "caja")
        cp -- "$ASSSETS_DIR/accels-gtk2" "$ACCELS_FILE"
        sed -i "s|USER|$USER|g" "$ACCELS_FILE"
        sed -i "s|ACCELS_PATH|config\\\\\\\\scaja|g" "$ACCELS_FILE"
        ;;
    esac
}

_step_close_filemanager() {
    echo " > Closing the file manager to reload its configurations..."

    eval "$FILE_MANAGER -q &>/dev/null" || true
}

_main "$@"
