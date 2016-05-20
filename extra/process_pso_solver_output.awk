BEGIN { print "Iteration,Value" }
/> iter*/ { print $3 $NF }
