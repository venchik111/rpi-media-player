# The GitHub tarball of raspberrypi/firmware is several hundred MB and GitHub
# streams it very slowly. scripts/build.sh fetches only boot/ firmware files
# with a sparse, blob-filtered git checkout and Buildroot uses that instead.
RPI_FIRMWARE_OVERRIDE_SRCDIR = $(BR2_DL_DIR)/rpi-firmware-sparse
