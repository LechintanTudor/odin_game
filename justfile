# run the app in debug mode
run:
    odin run src

# start editting the code
edit:
    @ helix --working-dir src src/main.odin && printf '\033[0q'

# format all markdown files
mdformat:
    mdformat --wrap 80 **.md
