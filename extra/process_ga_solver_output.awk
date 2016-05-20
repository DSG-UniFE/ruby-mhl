BEGIN { print "Generation,Value" }
/> gen*/ { print $3 $NF }
