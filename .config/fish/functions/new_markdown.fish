function note --description 'Creates a new note in the wiki directory'
    argparse n/name -- 'Note name' $argv  # Parse 'name' with short and long flags

    if test -f ~/wiki/$name.md  # Use the parsed 'name' variable
        echo "Note already exists"
    else
        touch ~/wiki/$name.md

        # Use 'set' within a 'begin/end' block for safe appending
        begin
            set -l filename ~/wiki/$name.md  
            echo "# $name" >> $filename         # Use 'name' here as well 
            echo "$(date +'%Y-%m-%d')" >> $filename
            echo -en "\n" >> $filename
            echo -en "\n" >> $filename
            echo -en "\n" >> $filename
            echo "Links:" >> $filename
            echo -en "\n" >> $filename
        end

        nvim -c 'startinsert' ~/wiki/$name.md
    end
end
