# run the app in debug mode
run:
    odin run src

# start editting the code
edit:
    @ helix --working-dir src src/main.odin && printf '\033[0q'

# format all markdown files
mdformat:
    mdformat --wrap 80 **.md

# compile all shaders
compile-shaders:
     glslc -fshader-stage=vertex -o build/shape.vert.spv shaders/shape.vert.glsl
     glslc -fshader-stage=fragment -o build/shape.frag.spv shaders/shape.frag.glsl
     glslc -fshader-stage=vertex -o build/sprite.vert.spv shaders/sprite.vert.glsl
     glslc -fshader-stage=fragment -o build/sprite.frag.spv shaders/sprite.frag.glsl
