function gsp
    if test -z "$argv[1]"
        echo "Usage: gsp <project_id>"
        return 1
    end

    set project_id $argv[1]

    gcloud config set project $project_id
    gcloud auth application-default set-quota-project $project_id
end
