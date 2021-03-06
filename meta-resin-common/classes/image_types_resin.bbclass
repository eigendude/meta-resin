inherit image_types

#
# Create a raw image that can by written onto a storage device using dd/etcher.
#
# RESIN_IMAGE_BOOTLOADER        - bootloader
# RESIN_BOOT_PARTITION_FILES    - list of items describing files to be deployed
#                                 on boot partition
#                               - items need to be in the 'src:dst' format
#                               - src needs to be relative to DEPLOY_DIR_IMAGE
#                               - dst needs to be an absolute path
#                               - if dst is ommited ('src:' format used),
#                                 absolute path of src will be used as dst
# RESIN_ROOT_FSTYPE             - rootfs image type to be used for integrating
#                                 in the final raw image
# RESIN_BOOT_SIZE               - size of boot partition in KiB
# RESIN_RAW_IMG_COMPRESSION     - define this to compress the final raw image
#                                 with gzip, xz or bzip2
#
# Partition table:
#
#   +-------------------+
#   |                   |  ^
#   | Reserved          |  |RESIN_IMAGE_ALIGNMENT
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Boot partition    |  |RESIN_BOOT_SIZE
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Root partition A  |  |RESIN_ROOTA_SIZE
#   |                   |  v
#   +-------------------+
#   |                   |  ^
#   | Root partition B  |  |RESIN_ROOTB_SIZE
#   |                   |  v
#   +-------------------+
#   |-------------------|
#   ||                 ||  ^
#   || Reserved        ||  |RESIN_IMAGE_ALIGNMENT
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || State partition ||  |RESIN_STATE_SIZE
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || Reserved        ||  |RESIN_IMAGE_ALIGNMENT
#   ||                 ||  v
#   |-------------------|
#   ||                 ||  ^
#   || Data partition  ||  |RESIN_DATA_SIZE
#   ||                 ||  v
#   |-------------------|
#   +-------------------+
#

RESIN_ROOT_FSTYPE ?= "ext4"

python() {
    # Check if we are running on a poky version which deploys to IMGDEPLOYDIR
    # instead of DEPLOY_DIR_IMAGE (poky morty introduced this change)
    if d.getVar('IMGDEPLOYDIR', True):
        d.setVar('RESIN_ROOT_FS', '${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.${RESIN_ROOT_FSTYPE}')
        d.setVar('RESIN_RAW_IMG', '${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.resinos-img')
    else:
        d.setVar('RESIN_ROOT_FS', '${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.${RESIN_ROOT_FSTYPE}')
        d.setVar('RESIN_RAW_IMG', '${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.resinos-img')
}


RESIN_BOOT_FS_LABEL ?= "resin-boot"
RESIN_ROOTA_FS_LABEL ?= "resin-rootA"
RESIN_ROOTB_FS_LABEL ?= "resin-rootB"
RESIN_STATE_FS_LABEL ?= "resin-state"
RESIN_DATA_FS_LABEL ?= "resin-data"

# Sizes in KiB
RESIN_BOOT_SIZE ?= "40960"
RESIN_ROOTB_SIZE ?= ""
RESIN_STATE_SIZE ?= "20480"
RESIN_IMAGE_ALIGNMENT ?= "4096"
IMAGE_ROOTFS_ALIGNMENT = "${RESIN_IMAGE_ALIGNMENT}"

RESIN_FINGERPRINT_EXT ?= "fingerprint"
RESIN_FINGERPRINT_FILENAME ?= "resinos"
RESIN_BOOT_FINGERPRINT_PATH ?= "${WORKDIR}/${RESIN_FINGERPRINT_FILENAME}.${RESIN_FINGERPRINT_EXT}"
RESIN_IMAGE_BOOTLOADER ?= "virtual/bootloader"
RESIN_IMAGEDATESTAMP = "${@time.strftime('%Y.%m.%d',time.gmtime())}"
RESIN_RAW_IMG_COMPRESSION ?= ""
RESIN_DATA_FS = "${DEPLOY_DIR}/images/${MACHINE}/${RESIN_DATA_FS_LABEL}.img"
RESIN_BOOT_FS = "${WORKDIR}/${RESIN_BOOT_FS_LABEL}.img"
RESIN_STATE_FS = "${WORKDIR}/${RESIN_STATE_FS_LABEL}.img"

# resinos-img depends on the rootfs image
IMAGE_TYPEDEP_resinos-img = "${RESIN_ROOT_FSTYPE}"
IMAGE_DEPENDS_resinos-img = " \
    coreutils-native \
    docker-disk \
    dosfstools-native \
    e2fsprogs-native \
    mtools-native \
    parted-native \
    virtual/kernel \
    ${RESIN_IMAGE_BOOTLOADER} \
    "

IMAGE_CMD_resinos-img () {
    #
    # Partition size computation (aligned to RESIN_IMAGE_ALIGNMENT)
    #

    # resin-boot
    RESIN_BOOT_SIZE_ALIGNED=$(expr ${RESIN_BOOT_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} - 1)
    RESIN_BOOT_SIZE_ALIGNED=$(expr ${RESIN_BOOT_SIZE_ALIGNED} \- ${RESIN_BOOT_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})

    # resin-rootA
    RESIN_ROOTA_SIZE=$(du -bks ${RESIN_ROOT_FS} | awk '{print $1}')
    RESIN_ROOTA_SIZE_ALIGNED=$(expr ${RESIN_ROOTA_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} \- 1)
    RESIN_ROOTA_SIZE_ALIGNED=$(expr ${RESIN_ROOTA_SIZE_ALIGNED} \- ${RESIN_ROOTA_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})

    # resin-rootB
    if [ -n "${RESIN_ROOTB_SIZE}" ]; then
        RESIN_ROOTB_SIZE_ALIGNED=$(expr ${RESIN_ROOTB_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} \- 1)
        RESIN_ROOTB_SIZE_ALIGNED=$(expr ${RESIN_ROOTB_SIZE_ALIGNED} \- ${RESIN_ROOTB_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})
    else
        RESIN_ROOTB_SIZE_ALIGNED=${RESIN_ROOTA_SIZE_ALIGNED}
    fi

    # resin-state
    RESIN_STATE_SIZE_ALIGNED=$(expr ${RESIN_STATE_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} \- 1)
    RESIN_STATE_SIZE_ALIGNED=$(expr ${RESIN_STATE_SIZE_ALIGNED} \- ${RESIN_STATE_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})

    # resin-data
    if [ -n "${RESIN_DATA_FS}" ]; then
        RESIN_DATA_SIZE=`du -bks ${RESIN_DATA_FS} | awk '{print $1}'`
        RESIN_DATA_SIZE_ALIGNED=$(expr ${RESIN_DATA_SIZE} \+ ${RESIN_IMAGE_ALIGNMENT} \- 1)
        RESIN_DATA_SIZE_ALIGNED=$(expr ${RESIN_DATA_SIZE_ALIGNED} \- ${RESIN_DATA_SIZE_ALIGNED} \% ${RESIN_IMAGE_ALIGNMENT})
    else
        RESIN_DATA_SIZE_ALIGNED=${RESIN_IMAGE_ALIGNMENT}
    fi

    RESIN_RAW_IMG_SIZE=$(expr \
        ${RESIN_IMAGE_ALIGNMENT} \+ \
        ${RESIN_BOOT_SIZE_ALIGNED} \+ \
        ${RESIN_ROOTA_SIZE_ALIGNED} \+ \
        ${RESIN_ROOTB_SIZE_ALIGNED} \+ \
        ${RESIN_IMAGE_ALIGNMENT} \+ \
        ${RESIN_STATE_SIZE_ALIGNED} \+ \
        ${RESIN_IMAGE_ALIGNMENT} \+ \
        ${RESIN_DATA_SIZE_ALIGNED} \
    )
    echo "Creating raw image as it follow:"
    echo "  Boot partition ${RESIN_BOOT_SIZE_ALIGNED} KiB [$(expr ${RESIN_BOOT_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Root A partition ${RESIN_ROOTA_SIZE_ALIGNED} KiB [$(expr ${RESIN_ROOTA_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Root B partition ${RESIN_ROOTA_SIZE_ALIGNED} KiB [$(expr ${RESIN_ROOTB_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  State partition ${RESIN_STATE_SIZE_ALIGNED} KiB [$(expr ${RESIN_STATE_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "  Data partition ${RESIN_DATA_SIZE_ALIGNED} KiB [$(expr ${RESIN_DATA_SIZE_ALIGNED} \/ 1024) MiB]"
    echo "---"
    echo "Total raw image size ${RESIN_RAW_IMG_SIZE} KiB [$(expr ${RESIN_RAW_IMG_SIZE} \/ 1024) MiB]"

    #
    # Generate the raw image with partition table
    #

    dd if=/dev/zero of=${RESIN_RAW_IMG} bs=1024 count=0 seek=${RESIN_RAW_IMG_SIZE}
    parted -s ${RESIN_RAW_IMG} mklabel msdos

    # resin-boot
    START=${RESIN_IMAGE_ALIGNMENT}
    END=$(expr ${START} \+ ${RESIN_BOOT_SIZE_ALIGNED})
    parted -s ${RESIN_RAW_IMG} unit KiB mkpart primary fat16 ${START} ${END}
    parted -s ${RESIN_RAW_IMG} set 1 boot on

    # resin-rootA
    START=${END}
    END=$(expr ${START} \+ ${RESIN_ROOTA_SIZE_ALIGNED})
    parted -s ${RESIN_RAW_IMG} unit KiB mkpart primary ext4 ${START} ${END}

    # resin-rootB
    START=${END}
    END=$(expr ${START} \+ ${RESIN_ROOTB_SIZE_ALIGNED})
    parted -s ${RESIN_RAW_IMG} unit KiB mkpart primary ext4 ${START} ${END}

    # extended partition
    START=${END}
    parted -s ${RESIN_RAW_IMG} -- unit KiB mkpart extended ${START} -1s

    # resin-state
    START=$(expr ${START} \+ ${RESIN_IMAGE_ALIGNMENT})
    END=$(expr ${START} \+ ${RESIN_STATE_SIZE_ALIGNED})
    parted -s ${RESIN_RAW_IMG} unit KiB mkpart logical ext4 ${START} ${END}

    # resin-data
    START=$(expr ${END} \+ ${RESIN_IMAGE_ALIGNMENT})
    parted -s ${RESIN_RAW_IMG} -- unit KiB mkpart logical ext4 ${START} -1s

    #
    # Generate partitions
    #

    # resin-boot
    RESIN_BOOT_BLOCKS=$(LC_ALL=C parted -s ${RESIN_RAW_IMG} unit b print | awk '/ 1 / { print substr($4, 1, length($4 -1)) / 512 /2 }')
    rm -rf ${RESIN_BOOT_FS}
    mkfs.vfat -n "${RESIN_BOOT_FS_LABEL}" -S 512 -C ${RESIN_BOOT_FS} $RESIN_BOOT_BLOCKS
    echo "Copying files in boot partition..."
    echo -n '' > ${RESIN_BOOT_FINGERPRINT_PATH}
    for RESIN_BOOT_PARTITION_FILE in ${RESIN_BOOT_PARTITION_FILES}; do
        echo "Handling $RESIN_BOOT_PARTITION_FILE ."

        # Check for item format
        case $RESIN_BOOT_PARTITION_FILE in
            *:*) ;;
            *) bbfatal "Some items in RESIN_BOOT_PARTITION_FILES ($RESIN_BOOT_PARTITION_FILE) are not in the 'src:dst' format."
        esac

        # Compute src and dst
        src="$(echo ${RESIN_BOOT_PARTITION_FILE} | awk -F: '{print $1}')"
        dst="$(echo ${RESIN_BOOT_PARTITION_FILE} | awk -F: '{print $2}')"
        if [ -z "${dst}" ]; then
            dst="/${src}" # dst was omitted
        fi
        src="${DEPLOY_DIR_IMAGE}/$src" # src is relative to deploy dir

        # Check that dst is an absolute path and assess if it should be a directory
        case $dst in
            /*)
                # Check if dst is a directory. Directory path ends with '/'.
                case $dst in
                    */) dst_is_dir=true ;;
                     *) dst_is_dir=false ;;
                esac
                ;;
             *) bbfatal "$dst in RESIN_BOOT_PARTITION_FILES is not an absolute path."
        esac

        # Check src type and existence
        if [ -d "$src" ]; then
            if ! $dst_is_dir; then
                bbfatal "You can't copy a directory to a file. You requested to copy $src in $dst."
            fi
            sources="$(find $src -maxdepth 1 -type f)"
        elif [ -f "$src" ]; then
            sources="$src"
        else
            bbfatal "$src is an invalid path referenced in RESIN_BOOT_PARTITION_FILES."
        fi

        # Normalize paths
        dst=$(realpath -ms $dst)
        if $dst_is_dir && [ ! "$dst" = "/" ]; then
            dst="$dst/" # realpath removes last '/' which we need to instruct mcopy that destination is a directory
        fi
        src=$(realpath -m $src)

        for src in $sources; do
            echo "Copying $src -> $dst ..."
            # Create the directories parent directories in dst
            directory=""
            for path_segment in $(echo ${dst} | sed 's|/|\n|g' | head -n -1); do
                if [ -z "$path_segment" ]; then
                    continue
                fi
                directory=$directory/$path_segment
                mmd -D sS -i ${RESIN_BOOT_FS} $directory || true
            done

            mcopy -i ${RESIN_BOOT_FS} -v ${src} ::${dst}
            if $dst_is_dir; then
                md5sum ${src} | awk -v awkdst="$dst$(basename $src)" '{ $2=awkdst; print }' >> ${RESIN_BOOT_FINGERPRINT_PATH}
            else
                md5sum ${src} | awk -v awkdst="$dst" '{ $2=awkdst; print }' >> ${RESIN_BOOT_FINGERPRINT_PATH}
            fi
        done
    done
    echo "${IMAGE_NAME}-${RESIN_IMAGEDATESTAMP}" > ${WORKDIR}/image-version-info
    mcopy -i ${RESIN_BOOT_FS} -v ${WORKDIR}/image-version-info ::
    md5sum ${WORKDIR}/image-version-info | awk -v filepath="/image-version-info" '{ $2=filepath; print }' >> ${RESIN_BOOT_FINGERPRINT_PATH}
    mcopy -i ${RESIN_BOOT_FS} -v ${RESIN_BOOT_FINGERPRINT_PATH} ::
    init_config_json ${WORKDIR}
    mcopy -i ${RESIN_BOOT_FS} -v ${WORKDIR}/config.json ::

    # resin-state
    RESIN_STATE_BLOCKS=$(LC_ALL=C parted -s ${RESIN_RAW_IMG} unit b print | awk '/ 5 / { print substr($4, 1, length($4 -1)) / 512 /2 }')
    rm -rf ${RESIN_STATE_FS}
    dd if=/dev/zero of=${RESIN_STATE_FS} count=${RESIN_STATE_BLOCKS} bs=1024
    mkfs.ext4 -F -L "${RESIN_STATE_FS_LABEL}" ${RESIN_STATE_FS}

    # Label what is not labeled
    e2label ${RESIN_ROOT_FS} ${RESIN_ROOTA_FS_LABEL}
    if [ -n "${RESIN_DATA_FS}" ]; then
        e2label ${RESIN_DATA_FS} ${RESIN_DATA_FS_LABEL}
    fi

    #
    # Burn partitions
    #
    dd if=${RESIN_BOOT_FS} of=${RESIN_RAW_IMG} conv=notrunc,fsync seek=1 bs=$(expr 1024 \* ${RESIN_IMAGE_ALIGNMENT})
    dd if=${RESIN_ROOT_FS} of=${RESIN_RAW_IMG} conv=notrunc,fsync seek=1 bs=$(expr 1024 \* $(expr ${RESIN_IMAGE_ALIGNMENT} \+ ${RESIN_BOOT_SIZE_ALIGNED}))
    dd if=${RESIN_STATE_FS} of=${RESIN_RAW_IMG} conv=notrunc,fsync seek=1 bs=$(expr 1024 \* $(expr ${RESIN_IMAGE_ALIGNMENT} \+ ${RESIN_BOOT_SIZE_ALIGNED} \+ ${RESIN_ROOTA_SIZE_ALIGNED} \+ ${RESIN_ROOTB_SIZE_ALIGNED} \+ ${RESIN_IMAGE_ALIGNMENT}))
    if [ -n "${RESIN_DATA_FS}" ]; then
        dd if=${RESIN_DATA_FS} of=${RESIN_RAW_IMG} conv=notrunc,fsync seek=1 bs=$(expr 1024 \* $(expr ${RESIN_IMAGE_ALIGNMENT} \+ ${RESIN_BOOT_SIZE_ALIGNED} \+ ${RESIN_ROOTA_SIZE_ALIGNED} \+ ${RESIN_ROOTB_SIZE_ALIGNED} \+ ${RESIN_IMAGE_ALIGNMENT} \+ ${RESIN_STATE_SIZE_ALIGNED} \+ ${RESIN_IMAGE_ALIGNMENT}))
    fi
}

resinos_img_compress () {
    # Optionally apply compression
    case "${RESIN_RAW_IMG_COMPRESSION}" in
    "gzip")
        gzip -k9 "${RESIN_RAW_IMG}"
        ;;
    "bzip2")
        bzip2 -k9 "${RESIN_RAW_IMG}"
        ;;
    "xz")
        xz -k "${RESIN_RAW_IMG}"
        ;;
    esac
}

IMAGE_POSTPROCESS_COMMAND += "resinos_img_compress;"

# Make sure we regenerate images if we modify the files that go in the boot
# partition
do_rootfs[vardeps] += "RESIN_BOOT_PARTITION_FILES"
