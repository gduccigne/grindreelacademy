#!/bin/bash
#################################################################################################################
# 
# Author  : Glenn Venghaus (apnea@glennvenghaus.com). 
# Version : v2 10-May-2017
# 
# Function 1 : (deep) find Davinci Resolve fusion connect compositions under base path and convert to Nuke scripts
# Function 2 : can be called directly with fusion comp name as parameter from custom automator /Applications/Fusion.app
#              See included screenshot.
#              once created , a call from Resolve to open fusion connect will be redirected to Nuke , using existing 
#              or creating a new .nk file from the .comp 
#
#################################################################################################################

#### USER PARAMETERS #######
# set path to Nuke binary executable  !!!!
nuke_bin="/Applications/Nuke11.3v6/Nuke11.3v6.app/Contents/MacOS/Nuke11.3v6" 
###### END ##########



## input eval
USEAGE="Useage   : $(basename "$0") <comp_search_base_path> "
NUM_PARMS=$#
base_path=`echo "$@" | sed s/\'//g | sed s/\"//g `

# input parsing
if [ $NUM_PARMS -eq 0 ];then
    echo -e $USEAGE
    exit
fi

if [ ${base_path:(-5)} == ".comp" ];then 
    mode="resolve_to_nuke"
    nuke_app=`echo $nuke_bin  | sed 's/\/Contents.*//g'`
else
    mode="convert"
fi

# check nuke executable
if [ ! -f "${nuke_bin}" ];then
    echo "Nuke executable not found at \"${nuke_bin}\". Please set script variable \"nuke_bin\" varable correctly"
    exit 
fi


python_tmp="/tmp/resolve_fc_to_nuke_commands.py"
results_tmp="/tmp/result.out"

# python code to create nuke nodes 
function create_python {

cat > $python_tmp <<EOL
## create a new resolution format ###################################
resolvefusion = '$width $height resolve fusion'
nuke.addFormat( resolvefusion ) 

## set general project session parameters ###################################
root = nuke.root()
root['format'].setValue( 'resolve fusion' ) 
root['fps'].setValue( $framerate ) 
root['first_frame'].setValue( $start + 1001 ) ## First frame plus additional frames
root['last_frame'].setValue( $end + 1001 )    ## Last frame plus additional frames

## Create read node and set values ##################################
r = nuke.nodes.Read(file = "${sourceclip}") 
r['xpos'].setValue(50)
r['ypos'].setValue(0)
r['first'].setValue( $start ) 
r['last'].setValue( $end + 1 )                ## Last frame plus 1 
r['origfirst'].setValue( $start ) 
r['origlast'].setValue( $end ) 

#### Test Frame Mode ####
r['frame_mode'].setValue('start_at')          ## (expression, start_at, offset)
r['frame'].setValue('100')                    ## Frame mode value  

#### Missing Frames ####
## r['on_error'].setValue('nearestframe')     ## Change error display 

r['colorspace'].setValue('gamma2.2')          ## Choose colorspace
r['format'].setValue( 'resolve fusion' ) 

## Create write node and set values #################################
w = nuke.nodes.Write(file = "${targetclip}") 
w.setInput( 0, r ) 
w['xpos'].setValue(800)
w['ypos'].setValue(0)
w['first'].setValue( $start ) 
w['last'].setValue( $end ) 
w['postage_stamp'].setValue( 'true' )

## create some nice backdrops
b1 = nuke.nodes.BackdropNode()
b1['xpos'].setValue(20)
b1['ypos'].setValue(-40)
b1['bdwidth'].setValue(140)
b1['bdheight'].setValue(140)
b1['tile_color'].setValue(5711680)
b1['note_font_color'].setValue(255)
b1['label'].setValue('<center>Fusion Connect Source</center>')

b2 = nuke.nodes.BackdropNode()
b2['xpos'].setValue(770)
b2['ypos'].setValue(-40)
b2['bdwidth'].setValue(140)
b2['bdheight'].setValue(140)
b2['tile_color'].setValue(15280)
b2['note_font_color'].setValue(255)
b2['label'].setValue('<center>Fusion Connect Render</center>')

## Connect viewer  #########################
nuke.toNode("Viewer1").connectInput(0,r)

## create nuke script ###############################################
nuke.scriptSaveAs("${nuke_script}") 
quit() 
EOL

}

# set IFS
IFSOLD=$IFS
IFS=$'\n\b'

if [ $mode == "resolve_to_nuke" ];then
    comp_list=$base_path
else
    comp_list=`find $base_path -name "*.comp" | grep -v "\._"  2>/dev/null `
fi

# find fusion comp file i search path and create nuke file if not exists.
for comp in $comp_list
do
    nuke_script_name=`basename "${comp}" | sed s/.comp/.nk/g`
    nuke_script_path=`dirname "${comp}"| sed 's/fusion*/nuke/g'`
    nuke_script="${nuke_script_path}"/"${nuke_script_name}"

    if [ ! -f "${nuke_script}" ];then

        echo "------- `date` ------------------------------------------------------------------------------------------"
        echo "FOUND  : $comp"
        
        if [ `cat "${comp}" | grep ResolveCompFormatVersion | wc -l` -eq 1 ];then 
            # parsing the fusion composition file 
            sourceclip=`cat "${comp}" | sed -n '/Loader/,/Saver/p' | grep Filename | sed 's/^.*Filename = //g' | sed s/[\",]//g | sed s/_00000000\./_########\./g`
            targetclip=`cat "${comp}" | sed -n '/Saver/,/Views/p' | grep Filename | sed 's/^.*Filename = //g' | sed s/[\",]//g | sed s/_00000000\./_########\./g`
            width=`cat "${comp}" | sed -n '/FrameFormat/,/Views/p' | grep Width | awk '{print $3}' | sed s/[\",]//g`
            height=`cat "${comp}" | sed -n '/FrameFormat/,/Views/p' | grep Height | awk '{print $3}' | sed s/[\",]//g`
            framerate=`cat "${comp}" | sed -n '/FrameFormat/,/Views/p' | grep Rate | awk '{print $3}' | sed s/[\",]//g`
            start=`cat "${comp}" | sed -n '/Loader/,/Saver/p' | grep GlobalStart | awk '{print $3}' | sed s/[\",]//g`
            end=`cat "${comp}" | sed -n '/Loader/,/Saver/p' | grep GlobalEnd | awk '{print $3}' | sed s/[\",]//g`

            # create python code for nuke
            create_python
            
            if [ ! -d "${nuke_script_path}" ];then
                mkdir "${nuke_script_path}"
            fi
            # call nuke to create nuke script
            $nuke_bin -t < $python_tmp  > $results_tmp 2>&1

            if [ `cat $results_tmp | grep Error | wc -l` -eq 0 ];then
                echo "NUKE   : $nuke_script"
            else
                echo "ERROR  : Error(s) creating Nuke script"
                if [ -f "${nuke_script}" ];then
                    rm "${nuke_script}"
                fi
                echo "-----------------------------------DEBUG - COMMANDS --------------------------------------------"
                cat $python_tmp
                echo "-----------------------------------DEBUG - OUTPUT   --------------------------------------------"
                cat $results_tmp
            fi
        else
             echo "NONE   : Not a Davinci Resolve comp. Skipping "
        fi
    fi
done

if [ $mode == "resolve_to_nuke" ];then
    # check if exists
    if [ -f "${nuke_script}" ];then
    # open Nuke
        /usr/bin/open -a $nuke_app "${nuke_script}"
    fi
fi
