BEGIN {
	_SPACE = "[ \t\n]+";
	_IDENTIFIER = "[a-zA-Z_][a-zA-Z_0-9]*";
#	_ESCAPABLE = "[\"\\\\]";
	# We don't need word splitting capabilities of AWK here
	FS = "";
	RESULT = "";
}

{
	match($0, _IDENTIFIER);
	if (RSTART == 0)
		next;

	var_name  = substr($0, RSTART, RLENGTH);
	var_value = substr($0, RSTART + RLENGTH);
	match(var_value, "^" _SPACE);
	if (RSTART != 0) {
		var_value = substr(var_value, RSTART + RLENGTH);;
	}
#	gsub(_ESCAPABLE, "\\\\&", var_value);
	RESULT = RESULT var_name "=" var_value ";";
}

END {
	print RESULT;
	fflush();
}
