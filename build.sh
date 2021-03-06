#!/bin/sh
# Creates wheel and Mac OS X installers
# Temporary solution until I get round to writing a makefile

set -e  # Exit on failure

# Icons needs to be frozen before running inselect.py
echo Freeze icons
pyrcc5 icons.qrc > inselect/gui/icons.py

VERSION=`python -m inselect.scripts.inselect --version 2>&1 | sed 's/inselect.py //g'`

echo Building Inselect $VERSION

echo Clean
rm -rf cover build dist
find . -name "*pyc" -print0 | xargs -0 rm -rf
find . -name __pycache__ -print0 | xargs -0 rm -rf

echo Check for presence of barcode engines
python -c "from gouda.engines import ZbarEngine; assert ZbarEngine.available()"
python -c "from gouda.engines import LibDMTXEngine; assert LibDMTXEngine.available()"

echo Report startup time and check for non-essential binary imports
mkdir build
time python -v -m inselect.scripts.inselect --quit &> build/startup_log
for module in cv2 numpy libdmtx scipy sklearn zbar; do
    if grep -q $module build/startup_log; then
        echo Non-essential binary $module imported on startup
        exit 1
    fi
done

echo Tests
PYTHONWARNINGS=module nosetests --with-coverage --cover-html --cover-inclusive --cover-erase --cover-tests --cover-package=inselect inselect

echo Wheel build
./setup.py bdist_wheel
mv dist/inselect-*.whl .

if [[ "$OSTYPE" == "darwin"* ]]; then
    # Modules to be excluded - .spec files read this environment variable
    # See https://github.com/pyinstaller/pyinstaller/wiki/Recipe-remove-tkinter-tcl
    # for details of excluding all of the tcl, tk, tkinter shat
    export EXCLUDE_MODULES="2to3 elementtree FixTk PIL._imagingtk ssl tcl tk _tkinter tkinter Tkinter"

    # Excludes formatted for the pyinstaller command line - for those scripts
    # that do not have their own spec files
    export EXCLUDE_CMD_LINE=`python -c "print(' '.join('--exclude-module {0}'.format(e) for e in '$EXCLUDE_MODULES'.split(' ')))"`

    # 1. The dmg of the Inselect application itself
    # inselect.spec looks at the EXCLUDE_MODULES environment variable
    pyinstaller --clean inselect.spec

    # Remove the directory containing the console app (the windowed app is in inselect.app)
    rm -rf dist/inselect
    rm -rf inselect-$VERSION.dmg

    # Add a few items to the PropertyList file generated by PyInstaller
    python -m bin.plist dist/inselect.app/Contents/Info.plist

    # Example document
    install -c -m 644 examples/Plecoptera_Accession_Drawer_4.jpg dist/
    install -c -m 644 examples/Plecoptera_Accession_Drawer_4.inselect dist/

    # Make the dmg itself
    hdiutil create inselect-$VERSION.dmg -volname inselect-$VERSION -srcfolder dist


    # 2. The dmg of the command-line tools
    # Clean output
    rm -rf build dist

    # read_barcodes.spec looks at the EXCLUDE_MODULES environment variable
    pyinstaller --clean read_barcodes.spec

    # export_metadata uses neither cv2 nor numpy
    pyinstaller --onefile --exclude-module cv2 --exclude-module numpy \
        $EXCLUDE_CMD_LINE inselect/scripts/export_metadata.py

    pyinstaller --onefile $EXCLUDE_CMD_LINE \
        --hidden-import sklearn.neighbors.typedefs \
        --hidden-import sklearn.neighbors.dist_metrics \
        inselect/scripts/segment.py

    # Other scripts
    for script in ingest save_crops; do
        rm -rf $script.spec
        pyinstaller --onefile $EXCLUDE_CMD_LINE inselect/scripts/$script.py
    done

    rm -rf inselect-tools-$VERSION.dmg

    # Make the dmg itself
    hdiutil create inselect-tools-$VERSION.dmg -volname inselect-tools-$VERSION -srcfolder dist
fi
