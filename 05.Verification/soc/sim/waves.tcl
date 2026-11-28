# Waves of one run (make uvm WAVES=1): every signal of the harness into waves.shm, in the build
# directory of the configuration. MM_TOP is the harness, set by the Makefile.
database -open waves -shm -into waves.shm -default
probe -create $env(MM_TOP) -depth all -all -database waves
run
exit
