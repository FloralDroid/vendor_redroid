#!/system/bin/sh

# args: driver
setup_vulkan() {
    echo "setup vulkan for driver: $1"
    case "$1" in
        i915)
            setprop ro.hardware.vulkan intel
            ;;
        amdgpu)
            setprop ro.hardware.vulkan radeon
            ;;
        virtio_gpu)
            setprop ro.hardware.vulkan virtio
            ;;
        v3d|vc4)
            setprop ro.hardware.vulkan broadcom
            ;;
        msm_drm)
            setprop ro.hardware.vulkan freedreno
            ;;
        panfrost)
            setprop ro.hardware.vulkan panfrost
            ;;
        *)
            echo "not supported driver: $1"
            ;;
    esac
}

setup_render_node() {
    node=`getprop ro.boot.floral_gpu_node`
    if [ ! -z "$node" ]; then
        echo "force render node: $node"

        if [ ! -e "$node" ]; then
            echo "render node does not exist: $node"
            return 1
        fi

        setprop gralloc.gbm.device "$node"
        chmod 666 "$node"
        minor="${node##*renderD}"
        if [ -r "/sys/kernel/debug/dri/$minor/name" ]; then
            driver="`cut -d' ' -f1 /sys/kernel/debug/dri/$minor/name`"
            setup_vulkan "$driver"
        fi
        return 0
    fi

    # A render node is sufficient for GBM; debugfs is optional in containers.
    for node in /dev/dri/renderD* ; do
        if [ ! -e "$node" ]; then
            continue
        fi

        minor="${node##*renderD}"
        if [ -r "/sys/kernel/debug/dri/$minor/name" ]; then
            driver="`cut -d' ' -f1 /sys/kernel/debug/dri/$minor/name`"
            echo "DRI node exists, driver: $driver"
            setup_vulkan "$driver"
        fi

        echo "use render node: $node"
        setprop gralloc.gbm.device "$node"
        chmod 666 "$node"
        return 0
    done

    echo "NO qualified render node found"
    return 1
}

gpu_setup_host() {
    echo "use GPU host mode"

    setprop gralloc.gbm.backend drm
    setprop ro.hardware.egl mesa
    setprop ro.hardware.gralloc gbm
    setprop ro.boot.redroid_fps 30
}

gpu_setup_guest() {
    echo "use GPU guest mode"

    local EGL_DIR=/vendor/lib64/egl
    local egl=

    if [ -f $EGL_DIR/libEGL_angle.so ]; then
        egl=angle
    elif [ -f $EGL_DIR/libEGL_swiftshader.so ];then
        egl=swiftshader
    else
        echo "ERROR no SW egl found!!!"
        return 1
    fi

    setprop gralloc.gbm.backend software
    setprop ro.hardware.egl $egl
    setprop ro.hardware.gralloc gbm
    setprop ro.hardware.vulkan pastel
}

gpu_setup() {
    ## mode=(auto, host, guest)
    ## node=(/dev/dri/renderDxxx)

    mode=`getprop ro.boot.floral_gpu_mode auto`
    if [ "$mode" = "host" ]; then
        if ! setup_render_node; then
            echo "ERROR gralloc.gbm DRM backend requires a render node"
            return 1
        fi
        gpu_setup_host
    elif [ "$mode" = "guest" ]; then
        gpu_setup_guest
    elif [ "$mode" = "auto" ]; then
         echo "use GPU auto mode"
         if setup_render_node; then
            gpu_setup_host
         else
            gpu_setup_guest
         fi
    else
        echo "unknown mode: $mode"
    fi
}

gpu_setup
