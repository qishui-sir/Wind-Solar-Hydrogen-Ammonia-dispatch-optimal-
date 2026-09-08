function value = option_value(options, name, default_value)
%OPTION_VALUE Return a struct option or a default value.

if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = default_value;
end
end
