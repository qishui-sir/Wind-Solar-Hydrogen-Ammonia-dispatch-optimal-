function ensure_directory(path_value)
%ENSURE_DIRECTORY Create a directory when it does not already exist.

if ~isfolder(path_value)
    mkdir(path_value);
end
end
