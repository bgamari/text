GHC=../ghc/_build/stage1/bin/ghc 

run() {
    $GHC Hi.hs -isrc -Iinclude cbits/cbits.c \
        -O1 -v0 -fforce-recomp \
        -ddump-simpl -ddump-asm -ddump-cmm -ddump-to-file -dsuppress-uniques \
        $@ \
    && ./Hi
}

run -DGOOD -dumpdir good
run -dumpdir bad
